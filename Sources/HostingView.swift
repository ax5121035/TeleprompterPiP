import SwiftUI
import AVFoundation

/// 承载 AVSampleBufferDisplayLayer 的 UIView。
/// PiP 要求内容 layer 必须在 App 的视图层级里，否则无法启动。
struct DisplayHostingView: UIViewRepresentable {
    let engine = PiPEngine.shared

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        engine.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        engine.updateDisplayFrame(uiView.bounds)
    }
}
