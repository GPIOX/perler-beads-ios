import BeadPatternCore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceView: View {
    @ObservedObject private var document: PatternDocument
    @StateObject private var model: WorkspaceModel
    @Environment(\.undoManager) private var undoManager
    @State private var photoItem: PhotosPickerItem?
    @State private var showsFileImporter = false
    @State private var showsCamera = false
    @State private var showsAbout = false

    init(document: PatternDocument) {
        self.document = document
        _model = StateObject(wrappedValue: WorkspaceModel(document: document))
    }

    var body: some View {
        NavigationSplitView {
            settingsSidebar
                .navigationTitle("拼豆图纸")
        } detail: {
            VStack(spacing: 0) {
                Picker("工作模式", selection: $model.mode) {
                    ForEach(WorkspaceMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                if model.isProcessing {
                    processingView
                } else if let grid = model.grid {
                    switch model.mode {
                    case .preview:
                        PreviewModeView(model: model, grid: grid)
                    case .edit:
                        EditModeView(model: model, grid: grid, undoManager: undoManager)
                    case .focus:
                        FocusModeView(model: model, grid: grid)
                    }
                } else {
                    ContentUnavailableView(
                        "导入第一张图片",
                        systemImage: "square.grid.3x3.fill",
                        description: Text("从照片、文件或相机导入，也可以打开 Web 版导出的 CSV。")
                    )
                }
            }
            .navigationTitle(document.project.title)
            .toolbar { workspaceToolbar }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    model.importImage(data: data, filename: "source.image")
                }
                photoItem = nil
            }
        }
        .fileImporter(
            isPresented: $showsFileImporter,
            allowedContentTypes: [.image, .commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            importFile(result)
        }
        .sheet(isPresented: $showsCamera) {
            CameraPicker { data in
                model.importImage(data: data, filename: "source.jpg")
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $model.showsPalette) {
            PaletteManagerView(model: model)
        }
        .sheet(isPresented: $model.showsReplaceSheet) {
            ColorReplaceView(model: model, undoManager: undoManager)
        }
        .sheet(isPresented: $model.showsShareSheet) {
            ShareSheet(items: model.shareItems)
        }
        .sheet(isPresented: $showsAbout) {
            AboutView()
        }
        .alert("操作失败", isPresented: errorBinding) {
            Button("好") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .alert("导入提示", isPresented: warningBinding) {
            Button("好") { model.warningMessage = nil }
        } message: {
            Text(model.warningMessage ?? "")
        }
    }

    private var settingsSidebar: some View {
        Form {
            Section("导入") {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("从照片选择", systemImage: "photo.on.rectangle")
                }
                Button { showsFileImporter = true } label: {
                    Label("从文件或 CSV 导入", systemImage: "folder")
                }
                Button { showsCamera = true } label: {
                    Label("拍摄照片", systemImage: "camera")
                }
            }

            Section("图像处理") {
                Stepper(value: columnsBinding, in: 10...300, step: 10) {
                    LabeledContent("横向格数", value: "\(document.project.settings.columns)")
                }
                VStack(alignment: .leading) {
                    LabeledContent("颜色合并阈值", value: "\(Int(document.project.settings.mergeThreshold))")
                    Slider(value: thresholdBinding, in: 0...100, step: 1)
                }
                Picker("处理模式", selection: pixelationModeBinding) {
                    Text("卡通（主色）").tag(PixelationMode.dominant)
                    Text("真实（平均）").tag(PixelationMode.average)
                }
                Picker("色号系统", selection: colorSystemBinding) {
                    ForEach(ColorSystem.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Button { model.showsPalette = true } label: {
                    Label("管理色板", systemImage: "paintpalette")
                }
                Button(action: model.regenerate) {
                    Label("生成 / 重新生成", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .disabled(document.sourceData == nil)
            }

            if let grid = model.grid {
                Section("图纸信息") {
                    LabeledContent("尺寸", value: "\(grid.columns) × \(grid.rows)")
                    LabeledContent("颜色", value: "\(model.statistics.count) 种")
                    LabeledContent("总量", value: "\(model.totalBeads) 颗")
                    Button { model.removeBackground(undoManager: undoManager) } label: {
                        Label("一键去背景", systemImage: "eraser.line.dashed")
                    }
                    Button { model.exportPNG() } label: {
                        Label("导出 PNG 图纸", systemImage: "square.and.arrow.up")
                    }
                    Button { model.exportCSV() } label: {
                        Label("导出 CSV 源数据", systemImage: "tablecells")
                    }
                }
            }

            Section {
                Button { showsAbout = true } label: {
                    Label("关于与开源许可", systemImage: "info.circle")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var processingView: some View {
        VStack(spacing: 18) {
            ProgressView(value: model.processingProgress)
                .frame(maxWidth: 320)
            Text("正在本机生成图纸… \(Int(model.processingProgress * 100))%")
            Button("取消", role: .cancel, action: model.cancelProcessing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    @ToolbarContentBuilder
    private var workspaceToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { undoManager?.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!(undoManager?.canUndo ?? false))
            Button { undoManager?.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!(undoManager?.canRedo ?? false))
        }
    }

    private func importFile(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            if url.pathExtension.lowercased() == "csv" {
                model.importCSV(data)
            } else {
                model.importImage(data: data, filename: RasterDecoder.preferredFilename(for: url))
            }
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private var columnsBinding: Binding<Int> { settingBinding(\.columns) }
    private var thresholdBinding: Binding<Double> { settingBinding(\.mergeThreshold) }
    private var pixelationModeBinding: Binding<PixelationMode> { settingBinding(\.pixelationMode) }
    private var colorSystemBinding: Binding<ColorSystem> { settingBinding(\.colorSystem) }

    private func settingBinding<Value>(_ keyPath: WritableKeyPath<PatternSettings, Value>) -> Binding<Value> {
        Binding {
            document.project.settings[keyPath: keyPath]
        } set: { value in
            document.objectWillChange.send()
            document.project.settings[keyPath: keyPath] = value
            document.project.modifiedAt = .now
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }

    private var warningBinding: Binding<Bool> {
        Binding(get: { model.warningMessage != nil }, set: { if !$0 { model.warningMessage = nil } })
    }
}
