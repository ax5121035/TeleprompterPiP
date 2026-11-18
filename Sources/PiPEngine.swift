import AVFoundation
import AVKit
import CoreMedia
import CoreVideo
import QuartzCore
import UIKit
import Combine

/// 画中画提词引擎：把文字逐帧渲染成 CVPixelBuffer，
/// 通过 AVSampleBufferDisplayLayer 喂给系统 PiP，实现悬浮在任意 App 之上。
final class PiPEngine: NSObject, ObservableObject {

    static let shared = PiPEngine()

    // MARK: - 渲染常量
    private let width = 1280
    private let height = 720
    private let timescale: Int32 = 600
    private let fps: Int32 = 30

    // MARK: - 状态
    @Published var isPiPActive = false
    @Published var isPlaying = true
    @Published var errorMessage: String?
    @Published var currentLine = 0
    @Published var totalLines = 0

    // MARK: - 配置（主线程读写）
    private var text: String = ""
    private var lines: [String] = []
    private var config = PrompterConfig()

    // MARK: - PiP 组件
    private let displayLayer = AVSampleBufferDisplayLayer()
    private var pipController: AVPictureInPictureController?
    private var source: AVPictureInPictureController.ContentSource?

    // MARK: - 渲染循环
    private var renderTimer: Timer?
    private var heartbeatTimer: Timer?
    // 三块缓冲轮转：单块缓冲会被「正在显示」和「正在绘制」同时占用，画面会撕裂/闪烁
    private var pixelBuffers: [CVPixelBuffer] = []
    private var bufferIndex = 0
    private var formatDescription: CMVideoFormatDescription?
    private var pts: CMTime = .zero
    private var lastRenderTime: CFTimeInterval = 0
    private var scrollOffset: CGFloat = 0
    private var lineHeight: CGFloat = 0

    // 静音音频保活：切到相机后系统倾向于挂起 App，持续输出静音可提高后台存活率
    private var audioEngine: AVAudioEngine?
    private var silentPlayer: AVAudioPlayerNode?

    // 确保 PiP 源图层在视图层级中（系统要求 layer 必须渲染在屏幕上）
    private var hostingView: UIView?

    private override init() {
        super.init()
        setupDisplayLayer()
    }

    // MARK: - 公开 API

    static var isSupported: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    /// 把显示层挂到视图层级上（App 启动时调用一次）
    func attach(to view: UIView) {
        displayLayer.frame = view.bounds
        displayLayer.videoGravity = .resizeAspect
        if displayLayer.superlayer == nil {
            view.layer.addSublayer(displayLayer)
        }
        hostingView = view
    }

    /// 视图尺寸变化时同步显示层 frame
    func updateDisplayFrame(_ bounds: CGRect) {
        displayLayer.frame = bounds
    }

    /// 更新文案与配置；PiP 运行中调用会实时生效
    func update(text: String, config: PrompterConfig) {
        let linesChanged = text != self.text ||
            config.fontSize != self.config.fontSize ||
            config.lineSpacing != self.config.lineSpacing

        self.text = text
        self.config = config

        if linesChanged {
            let maxChars = TextTools.suggestedMaxChars(fontSize: config.fontSize)
            self.lines = TextTools.wrap(text, maxChars: maxChars)
            self.lineHeight = config.fontSize * config.lineSpacing
            DispatchQueue.main.async {
                self.totalLines = self.lines.count
                self.currentLine = 0
            }
        }
    }

    /// 启动悬浮提词
    func start() {
        guard Self.isSupported else {
            errorMessage = "当前设备或系统版本不支持画中画（需 iOS 15+，且 iPhone 支持）"
            return
        }
        guard !lines.isEmpty else {
            errorMessage = "请先输入或粘贴口播文案"
            return
        }

        errorMessage = nil
        setupControllerIfNeeded()
        activateAudioSession()

        // 重置播放位置
        scrollOffset = 0
        pts = .zero
        lastRenderTime = 0
        isPlaying = true
        renderFirstFrame()

        guard let controller = pipController else { return }
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
        } else {
            controller.startPictureInPicture()
        }
    }

    /// 关闭悬浮窗
    func stop() {
        pipController?.stopPictureInPicture()
        stopSilentAudio()
    }

    func togglePlay() {
        isPlaying.toggle()
    }

    /// 跳到上一句 / 下一句
    func jump(_ direction: Int) {
        guard lineHeight > 0 else { return }
        scrollOffset += CGFloat(direction) * lineHeight
        clampOffset()
    }

    /// 回到开头
    func reset() {
        scrollOffset = 0
        currentLine = 0
    }

    // MARK: - 初始化

    private func setupDisplayLayer() {
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = UIColor.black.cgColor

        let attributes: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:],
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue as Any,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue as Any
        ]

        // 预分配 3 块缓冲轮转使用
        for _ in 0..<3 {
            var buffer: CVPixelBuffer?
            let status = CVPixelBufferCreate(
                kCFAllocatorDefault, width, height,
                kCVPixelFormatType_32BGRA,
                attributes as CFDictionary, &buffer
            )
            if status == kCVReturnSuccess, let buffer = buffer {
                pixelBuffers.append(buffer)
            }
        }

        guard let first = pixelBuffers.first else { return }
        var desc: CMVideoFormatDescription?
        let descStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: first,
            formatDescriptionOut: &desc
        )
        if descStatus == noErr { formatDescription = desc }
    }

    private func setupControllerIfNeeded() {
        guard pipController == nil else { return }
        let contentSource = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: displayLayer,
            playbackDelegate: self
        )
        let controller = AVPictureInPictureController(contentSource: contentSource)
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        source = contentSource
        pipController = controller
    }

    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        // 用 playback 类别 + mixWithOthers，保证切到相机 App 后本 App 仍可后台推帧
        try? session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        try? session.setActive(true)
        startSilentAudio()
    }

    /// 持续输出静音，让 App 在切到相机后不被立刻挂起（画面才不会冻住）
    private func startSilentAudio() {
        guard audioEngine == nil else { return }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2) else { return }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0

        do {
            try engine.start()
        } catch {
            return
        }

        let frames: AVAudioFrameCount = 4_410
        guard let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            engine.stop()
            return
        }
        silence.frameLength = frames
        player.scheduleBuffer(silence, at: nil, options: .loops, completionHandler: nil)
        player.play()

        audioEngine = engine
        silentPlayer = player
    }

    private func stopSilentAudio() {
        silentPlayer?.stop()
        audioEngine?.stop()
        silentPlayer = nil
        audioEngine = nil
    }

    // MARK: - 渲染循环

    private func renderFirstFrame() {
        enqueueFrame(at: pts)
    }

    private func startRendering() {
        stopRendering()
        lastRenderTime = CACurrentMediaTime()
        // 用 Timer 而非 CADisplayLink：Timer 在 App 退到后台（切到相机）后仍能触发，
        // CADisplayLink 依赖屏幕刷新，后台会停止回调。
        renderTimer = Timer.scheduledTimer(
            timeInterval: 1.0 / Double(fps),
            target: self,
            selector: #selector(tick),
            userInfo: nil,
            repeats: true
        )
        renderTimer?.tolerance = 0.005
        RunLoop.main.add(renderTimer!, forMode: .common)

        // 心跳：即使暂停或帧供给被节流，也维持 PiP 不被系统判定为结束而自动消失
        heartbeatTimer = Timer.scheduledTimer(
            timeInterval: 0.5,
            target: self,
            selector: #selector(heartbeat),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(heartbeatTimer!, forMode: .common)
    }

    private func stopRendering() {
        renderTimer?.invalidate()
        renderTimer = nil
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    @objc private func tick() {
        guard isPlaying, isPiPActive else { return }

        let now = CACurrentMediaTime()
        var delta = now - lastRenderTime
        lastRenderTime = now
        // 后台被节流时单帧 delta 可能很大，限制上限避免文字瞬间跳一大截
        if delta > 0.2 { delta = 1.0 / Double(fps) }

        // 按时间推进滚动，速度单位：点/秒
        scrollOffset += CGFloat(delta) * config.speed
        clampOffset()

        enqueueFrame(at: pts)
        pts = pts + CMTime(value: 1, timescale: fps)
    }

    /// 保活：后台节流导致渲染队列断流时，重发当前帧，防止 PiP 自动 dismissal
    @objc private func heartbeat() {
        guard isPiPActive else { return }
        enqueueFrame(at: pts)
        pts = pts + CMTime(value: 1, timescale: fps)
    }

    private func clampOffset() {
        guard lineHeight > 0, !lines.isEmpty else { return }
        let contentHeight = CGFloat(lines.count) * lineHeight
        let maxOffset = contentHeight + CGFloat(height) / 2
        if scrollOffset > maxOffset {
            scrollOffset = 0
            DispatchQueue.main.async { self.currentLine = 0 }
        } else if scrollOffset < 0 {
            scrollOffset = 0
        }

        let idx = Int(scrollOffset / lineHeight)
        if idx != currentLine {
            DispatchQueue.main.async { self.currentLine = min(idx, self.lines.count - 1) }
        }
    }

    private func enqueueFrame(at time: CMTime) {
        guard !pixelBuffers.isEmpty, let format = formatDescription else { return }
        let buffer = pixelBuffers[bufferIndex % pixelBuffers.count]
        bufferIndex = (bufferIndex + 1) % pixelBuffers.count

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)

        let bitmapInfo = CGBitmapInfo(rawValue:
            CGImageAlphaInfo.premultipliedFirst.rawValue |
            CGBitmapInfo.byteOrder32Little.rawValue
        )
        guard let context = CGContext(
            data: base,
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo.rawValue
        ) else { return }

        // 背景
        context.setFillColor(config.background.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // 关键：NSString.draw 是 UIKit 方法，依赖 UIGraphicsGetCurrentContext()。
        // 必须把自建 CGContext push 成当前上下文，否则后台推帧时文字画不出来（黑屏）。
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }

        // CoreGraphics 原点在左下；翻转成左上的 UIKit 坐标系来画字
        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        if config.mirrored {
            context.translateBy(x: CGFloat(width), y: 0)
            context.scaleBy(x: -1, y: 1)
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byClipping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: config.fontSize),
            .foregroundColor: config.foreground,
            .paragraphStyle: paragraph
        ]

        let centerY = CGFloat(height) / 2 - lineHeight / 2
        for (index, line) in lines.enumerated() {
            let y = centerY + CGFloat(index) * lineHeight - scrollOffset
            if y > -lineHeight * 2 && y < CGFloat(height) + lineHeight {
                let rect = CGRect(x: 20, y: y, width: CGFloat(width) - 40, height: lineHeight)
                (line as NSString).draw(in: rect, withAttributes: attributes)
            }
        }
        context.restoreGState()

        // 包装成 CMSampleBuffer
        // 时间基准：每帧 1/fps 秒（30fps）。之前用 1/timescale 会让时间流速失真，
        // displayLayer 可能判定播放结束而自动收起悬浮窗。
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: fps),
            presentationTimeStamp: time,
            decodeTimeStamp: .invalid
        )
        var sample: CMSampleBuffer?
        let status = CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: buffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: format,
            sampleTiming: &timing,
            sampleBufferOut: &sample
        )
        if status == noErr, let sample = sample {
            displayLayer.enqueue(sample)
        }
    }
}

// MARK: - PiP 播放代理

extension PiPEngine: AVPictureInPictureSampleBufferPlaybackDelegate {

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        setPlaying playing: Bool
    ) {
        isPlaying = playing
    }

    func pictureInPictureControllerTimeRangeForPlayback(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> CMTimeRange {
        // 无限时长（直播语义）：提词是连续流，没有终点。
        // 避免有限区间走到头后 PiP 自动退出。
        CMTimeRange(start: .zero, duration: .positiveInfinity)
    }

    func pictureInPictureControllerIsPlaybackPaused(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> Bool {
        !isPlaying
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        let seconds = skipInterval.seconds
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.lineHeight > 0 else {
                completionHandler()
                return
            }
            self.scrollOffset += CGFloat(seconds) * self.config.speed
            self.clampOffset()
            completionHandler()
        }
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {
        // 固定 16:9 渲染，resizeAspect 会自动适配
    }
}

// MARK: - PiP 生命周期代理

extension PiPEngine: AVPictureInPictureControllerDelegate {

    func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        isPiPActive = true
        errorMessage = nil
        startRendering()
    }

    func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        isPiPActive = false
        isPlaying = false
        stopRendering()
        stopSilentAudio()
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        errorMessage = "悬浮窗启动失败：\(error.localizedDescription)"
        isPiPActive = false
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }
}
