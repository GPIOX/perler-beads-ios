import BeadPatternCore
import SwiftUI
import UniformTypeIdentifiers

struct ImportSourceDocument: FileDocument, Sendable {
    enum Kind: Sendable {
        case image
        case csv
    }

    static let readableContentTypes: [UTType] = [.png, .jpeg, .heic, .gif, .commaSeparatedText]
    static let writableContentTypes: [UTType] = []

    let data: Data
    let filename: String
    let kind: Kind

    init(data: Data, filename: String, kind: Kind) {
        self.data = data
        self.filename = filename
        self.kind = kind
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
        filename = configuration.file.preferredFilename ?? "导入文件"
        kind = configuration.contentType.conforms(to: .commaSeparatedText) ? .csv : .image
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        throw CocoaError(.fileWriteUnsupportedScheme)
    }
}

actor ProjectImportCoordinator {
    private let destinationDirectory: URL?

    init(destinationDirectory: URL? = nil) {
        self.destinationDirectory = destinationDirectory
    }

    func createProject(from source: ImportSourceDocument, settings initialSettings: PatternSettings) async throws -> URL {
        let store = try ColorMappingStore.bundled()
        var settings = initialSettings
        if settings.selectedHexColors.isEmpty {
            settings.selectedHexColors = Set(store.palette.map(\.hex))
        }

        let baseName = sanitizedBaseName(source.filename)
        let sourceFilename: String?
        let sourceData: Data?
        let grid: PatternGrid

        switch source.kind {
        case .image:
            let raster = try RasterDecoder.decode(data: source.data)
            let palette = try store.activePalette(settings: settings)
            grid = try await PatternProcessor().process(raster: raster, settings: settings, palette: palette)
            sourceFilename = RasterDecoder.preferredFilename(for: URL(fileURLWithPath: source.filename))
            sourceData = source.data
        case .csv:
            guard let text = String(data: source.data, encoding: .utf8) else {
                throw PatternCoreError.invalidCSV("文件不是 UTF-8 编码")
            }
            grid = try PatternCSV.decode(text, knownHexColors: Set(store.palette.map(\.hex))).grid
            settings.columns = min(300, max(10, grid.columns))
            sourceFilename = nil
            sourceData = nil
        }

        let project = PatternProject(
            title: baseName,
            sourceFilename: sourceFilename,
            settings: settings,
            grid: grid
        )
        let preview = await MainActor.run { PatternExporter.renderPreview(grid: grid) }
        let snapshot = PatternDocument.Snapshot(
            project: project,
            sourceData: sourceData,
            sourceFilename: sourceFilename,
            previewData: preview
        )
        let wrapper = try PatternDocument.makeFileWrapper(snapshot: snapshot)
        let destination = try uniqueDestination(named: baseName)
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).beadpattern", isDirectory: true)

        do {
            try wrapper.write(to: temporary, options: .atomic, originalContentsURL: nil)
            try FileManager.default.moveItem(at: temporary, to: destination)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    private func uniqueDestination(named baseName: String) throws -> URL {
        let directory: URL
        if let destinationDirectory {
            directory = destinationDirectory
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } else {
            directory = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        }
        var suffix = 1
        while true {
            let filename = suffix == 1 ? baseName : "\(baseName) \(suffix)"
            let candidate = directory
                .appendingPathComponent(filename)
                .appendingPathExtension("beadpattern")
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            suffix += 1
        }
    }

    private func sanitizedBaseName(_ filename: String) -> String {
        let value = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "导入图纸" : value
    }
}

struct ImportSourceView: View {
    let source: ImportSourceDocument

    @Environment(\.openURL) private var openURL
    @State private var errorMessage: String?
    @State private var hasStarted = false
    private let coordinator = ProjectImportCoordinator()

    var body: some View {
        VStack(spacing: 18) {
            if let errorMessage {
                ContentUnavailableView(
                    "导入失败",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else {
                ProgressView()
                Text(source.kind == .image ? "正在创建并生成图纸…" : "正在创建图纸…")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .navigationTitle(source.filename)
        .task {
            guard !hasStarted else { return }
            hasStarted = true
            do {
                let store = try ColorMappingStore.bundled()
                let settings = WorkspaceModel.defaultSettings(colorStore: store)
                let url = try await coordinator.createProject(from: source, settings: settings)
                openURL(url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
