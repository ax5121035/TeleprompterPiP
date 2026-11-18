import SwiftUI

struct ContentView: View {
    @StateObject private var store = ScriptStore()
    @ObservedObject private var engine = PiPEngine.shared

    @State private var draftTitle = ""
    @State private var draftText = ""
    @State private var showTemplates = false
    @State private var showSaveAlert = false
    @State private var showLibrary = false
    @AppStorage("teleprompter.firstLaunch") private var firstLaunch = true

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 顶部状态条
                statusBar

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        previewCard
                        textEditorCard
                        controlCard
                        actionButtons
                        templateHint
                    }
                    .padding()
                }
            }
            .navigationTitle("悬浮提词器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("模板") { showTemplates = true }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button("稿件") { showLibrary = true }
                        Button("保存") { showSaveAlert = true }
                    }
                }
            }
            .sheet(isPresented: $showTemplates) {
                TemplateSheet { text in
                    draftText = text
                    draftTitle = ""
                }
            }
            .sheet(isPresented: $showLibrary) {
                LibraryView(store: store) { item in
                    draftText = item.text
                    draftTitle = item.title
                }
            }
            .alert("保存稿件", isPresented: $showSaveAlert) {
                TextField("标题（可留空）", text: $draftTitle)
                Button("保存") {
                    store.addScript(title: draftTitle, text: draftText)
                    draftTitle = ""
                }
                Button("取消", role: .cancel) {}
            }
            .onAppear {
                syncEngine()
                if firstLaunch {
                    draftText = ScriptTemplate.layout.sample
                    firstLaunch = false
                }
            }
            .onChange(of: draftText) { _ in syncEngine() }
            .onChange(of: store.config) { _ in syncEngine(); store.saveConfig() }
        }
    }

    private func syncEngine() {
        engine.update(text: draftText, config: store.config)
    }

    // MARK: - 状态条

    private var statusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(engine.isPiPActive ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            Text(engine.isPiPActive
                 ? "悬浮中 · 第 \(engine.currentLine + 1)/\(engine.totalLines) 行"
                 : (PiPEngine.isSupported ? "就绪" : "设备不支持画中画"))
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            if engine.isPiPActive {
                Text(engine.isPlaying ? "播放中" : "已暂停")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.15))
                    .cornerRadius(6)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(.systemGray6))
    }

    // MARK: - 预览

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("悬浮窗预览", systemImage: "rectangle.on.rectangle")
                    .font(.headline)
                Spacer()
                Text("16:9")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            DisplayHostingView()
                .frame(height: 150)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
            Text("启动后切到相机 App，提词窗会悬浮在取景画面上。预览仅作参考。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - 文案编辑

    private var textEditorCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("口播文案", systemImage: "text.alignleft")
                .font(.headline)
            TextEditor(text: $draftText)
                .frame(minHeight: 160)
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
            HStack {
                Button("智能断句") {
                    draftText = TextTools.withPauses(draftText)
                }
                .buttonStyle(.bordered)
                Button("清空") { draftText = "" }
                .buttonStyle(.bordered)
                Spacer()
                Text("\(draftText.count) 字")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - 控制面板

    private var controlCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("提词设置", systemImage: "slider.horizontal.3")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("字号").font(.subheadline)
                    Spacer()
                    Text("\(Int(store.config.fontSize))").font(.caption).foregroundColor(.secondary)
                }
                Slider(value: $store.config.fontSize, in: 40...160, step: 2)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("速度").font(.subheadline)
                    Spacer()
                    Text("\(Int(store.config.speed))").font(.caption).foregroundColor(.secondary)
                }
                Slider(value: $store.config.speed, in: 20...260, step: 5)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("行距").font(.subheadline)
                    Spacer()
                    Text(String(format: "%.1f", store.config.lineSpacing))
                        .font(.caption).foregroundColor(.secondary)
                }
                Slider(value: $store.config.lineSpacing, in: 1.0...2.2, step: 0.1)
            }

            Toggle("镜像模式（外接分光镜用）", isOn: $store.config.mirrored)

            HStack(spacing: 20) {
                ColorPicker("文字颜色", selection: colorBinding(for: \.foregroundHex))
                ColorPicker("背景颜色", selection: colorBinding(for: \.backgroundHex))
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func colorBinding(for key: WritableKeyPath<PrompterConfig, String>) -> Binding<Color> {
        Binding(
            get: { Color(uiColor: UIColor(hex: store.config[keyPath: key]) ?? .white) },
            set: { color in
                store.config[keyPath: key] = UIColor(color).hexString()
            }
        )
    }

    // MARK: - 操作按钮

    private var actionButtons: some View {
        VStack(spacing: 10) {
            if engine.isPiPActive {
                HStack(spacing: 12) {
                    Button {
                        engine.togglePlay()
                    } label: {
                        Label(engine.isPlaying ? "暂停" : "继续",
                              systemImage: engine.isPlaying ? "pause.fill" : "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button { engine.jump(-1) } label: {
                        Label("上一句", systemImage: "backward.fill")
                    }
                    .buttonStyle(.bordered)

                    Button { engine.jump(1) } label: {
                        Label("下一句", systemImage: "forward.fill")
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    engine.reset()
                } label: {
                    Label("回到开头", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    engine.stop()
                } label: {
                    Label("关闭悬浮窗", systemImage: "xmark.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    syncEngine()
                    engine.start()
                } label: {
                    HStack {
                        Image(systemName: "rectangle.on.rectangle.angled")
                        Text("启动悬浮提词")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let error = engine.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private var templateHint: some View {
        Text("提示：悬浮窗内可直接用系统自带的播放/暂停、快进按钮控制；改字号和速度需切回本 App 调整，悬浮窗会实时更新。")
            .font(.caption)
            .foregroundColor(.secondary)
    }
}

// MARK: - 模板选择

struct TemplateSheet: View {
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                ForEach(ScriptTemplate.allCases) { tpl in
                    Button {
                        onPick(tpl.sample)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(tpl.rawValue).font(.headline)
                            Text(tpl.sample.components(separatedBy: .newlines).first ?? "")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("测评模板")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 稿件库

struct LibraryView: View {
    @ObservedObject var store: ScriptStore
    let onPick: (ScriptItem) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Group {
                if store.scripts.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 44))
                            .foregroundColor(.secondary)
                        Text("还没有稿件")
                            .font(.headline)
                        Text("在主编页点「保存」把当前文案存成稿件")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(store.scripts) { item in
                            HStack {
                                Button {
                                    onPick(item)
                                    dismiss()
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title).font(.headline)
                                        Text(item.text.components(separatedBy: .newlines).first ?? "")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    store.deleteScript(item)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
            .navigationTitle("我的稿件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
