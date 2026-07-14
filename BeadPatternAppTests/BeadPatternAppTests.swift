import BeadPatternCore
import Testing
import UIKit
@testable import BeadPatternApp

@Test func rasterDecoderReadsPNG() throws {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 1), format: format)
    let image = renderer.image { context in
        UIColor.red.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        UIColor.blue.setFill()
        context.fill(CGRect(x: 1, y: 0, width: 1, height: 1))
    }
    let raster = try RasterDecoder.decode(data: #require(image.pngData()))
    #expect(raster.width == 2)
    #expect(raster.height == 1)
    #expect(raster.rgba.count == 8)
}

@Test func importSourceRegistersOnlySupportedImageAndCSVTypes() {
    let identifiers = Set(ImportSourceDocument.readableContentTypes.map(\.identifier))
    #expect(identifiers == [
        "public.png",
        "public.jpeg",
        "public.heic",
        "com.compuserve.gif",
        "public.comma-separated-values-text",
    ])
}

@Test func previewRendererProducesPNG() throws {
    let grid = PatternGrid(columns: 2, rows: 1, cells: [
        PatternCell(hex: "#FF0000"), PatternCell(hex: "#0000FF"),
    ])
    #expect(PatternExporter.renderPreview(grid: grid) != nil)
}

@Test func boardBoundariesFollowTwentyNineByTwentyNineBoards() {
    #expect(PatternChartStyle.boardBoundaryIndices(for: 29) == [0, 29])
    #expect(PatternChartStyle.boardBoundaryIndices(for: 67) == [0, 29, 58, 67])
}

@Test func exportedChartIncludesCoordinatesOnAllFourSides() throws {
    let grid = PatternGrid(
        columns: 30,
        rows: 31,
        cells: Array(repeating: .transparent, count: 30 * 31)
    )
    let colorStore = try ColorMappingStore.bundled()
    let data = try PatternExporter.renderPNG(
        grid: grid,
        statistics: [],
        colorStore: colorStore,
        colorSystem: .mard
    )
    let image = try #require(UIImage(data: data))

    // 30 px 单格 + 左右各 34 px 坐标轴。
    #expect(image.size.width == 968)
    // 68 px 标题 + 上下各 34 px 坐标轴 + 统计区。
    #expect(image.size.height == 1_162)
}

@Test @MainActor func canvasRendersCoordinateBoardStyle() throws {
    let grid = PatternGrid(
        columns: 30,
        rows: 30,
        cells: (0..<(30 * 30)).map { index in
            PatternCell(hex: index.isMultiple(of: 2) ? "#F4B6C2" : "#4A5568")
        }
    )
    let colorStore = try ColorMappingStore.bundled()
    let canvas = PatternCanvasView(frame: CGRect(x: 0, y: 0, width: 390, height: 500))
    canvas.update(
        grid: grid,
        colorStore: colorStore,
        colorSystem: .mard,
        drawingEnabled: false,
        focusHex: nil,
        completed: [],
        highlighted: [],
        onCell: { _, _ in }
    )
    canvas.layoutIfNeeded()
    let image = UIGraphicsImageRenderer(bounds: canvas.bounds).image { _ in
        canvas.draw(canvas.bounds)
    }

    #expect(try #require(image.pngData()).count > 10_000)
}

@Test func newDocumentContainsImmediatePreview() throws {
    let document = PatternDocument()
    let snapshot = try document.snapshot(contentType: .beadPatternProject)
    let wrapper = try PatternDocument.makeFileWrapper(snapshot: snapshot)
    let preview = wrapper.fileWrappers?["preview.png"]?.regularFileContents

    #expect(preview?.starts(with: [0x89, 0x50, 0x4E, 0x47]) == true)
}

@Test func directCSVImportCreatesUniqueProjectsWithoutChangingSource() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let projects = root.appendingPathComponent("Projects", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let csv = "#FF0000,#00FF00\nTRANSPARENT,#0000FF"
    let sourceURL = root.appendingPathComponent("测试.csv")
    let sourceData = Data(csv.utf8)
    try sourceData.write(to: sourceURL)
    let source = ImportSourceDocument(data: sourceData, filename: "测试.csv", kind: .csv)
    let coordinator = ProjectImportCoordinator(destinationDirectory: projects)

    let first = try await coordinator.createProject(from: source, settings: PatternSettings())
    let second = try await coordinator.createProject(from: source, settings: PatternSettings())

    #expect(first.lastPathComponent == "测试.beadpattern")
    #expect(second.lastPathComponent == "测试 2.beadpattern")
    #expect(try Data(contentsOf: sourceURL) == sourceData)
    let manifest = try Data(contentsOf: first.appendingPathComponent("manifest.json"))
    let project = try JSONDecoder.projectDecoder.decode(PatternProject.self, from: manifest)
    #expect(project.grid?.columns == 2)
    #expect(project.grid?.rows == 2)
    #expect(FileManager.default.fileExists(atPath: first.appendingPathComponent("preview.png").path))
}

@Test func directImageImportCreatesProjectAndKeepsOriginalBytes() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let projects = root.appendingPathComponent("Projects", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 12), format: format).image { context in
        UIColor.systemYellow.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 10, height: 12))
        UIColor.systemPurple.setFill()
        context.fill(CGRect(x: 10, y: 0, width: 10, height: 12))
    }
    let sourceData = try #require(image.pngData())
    let sourceURL = root.appendingPathComponent("示例.png")
    try sourceData.write(to: sourceURL)
    let source = ImportSourceDocument(data: sourceData, filename: sourceURL.lastPathComponent, kind: .image)
    let coordinator = ProjectImportCoordinator(destinationDirectory: projects)

    let destination = try await coordinator.createProject(from: source, settings: PatternSettings(columns: 10))

    #expect(try Data(contentsOf: sourceURL) == sourceData)
    #expect(try Data(contentsOf: destination.appendingPathComponent("source.png")) == sourceData)
    let manifest = try Data(contentsOf: destination.appendingPathComponent("manifest.json"))
    let project = try JSONDecoder.projectDecoder.decode(PatternProject.self, from: manifest)
    #expect(project.title == "示例")
    #expect(project.grid?.columns == 10)
    #expect(project.grid?.rows == 6)
    #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("preview.png").path))
}

@Test func failedDirectImportLeavesNoPartialProject() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = ImportSourceDocument(data: Data("bad,csv\nrow".utf8), filename: "坏文件.csv", kind: .csv)
    let coordinator = ProjectImportCoordinator(destinationDirectory: directory)

    await #expect(throws: PatternCoreError.self) {
        _ = try await coordinator.createProject(from: source, settings: PatternSettings())
    }
    let contents = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    #expect(contents.isEmpty)
}

@Test @MainActor func csvImportMovesWorkspaceToPreview() throws {
    let document = PatternDocument()
    let model = WorkspaceModel(document: document, photoLibrarySaver: MockPhotoLibrarySaver())
    model.importCSV(Data("#FF0000,#00FF00".utf8))
    #expect(model.phase == .result)
    #expect(model.mode == .preview)
    #expect(model.grid != nil)
}

@Test @MainActor func firstImageGenerationMovesWorkspaceToPreview() async throws {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 12), format: format).image { context in
        UIColor.red.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 10, height: 12))
        UIColor.blue.setFill()
        context.fill(CGRect(x: 10, y: 0, width: 10, height: 12))
    }
    let document = PatternDocument(sourceData: image.pngData(), sourceFilename: "测试.png")
    document.project.settings.columns = 10
    let model = WorkspaceModel(document: document, photoLibrarySaver: MockPhotoLibrarySaver())

    model.regenerate()
    #expect(model.phase == .processing)
    while model.isProcessing {
        try await Task.sleep(for: .milliseconds(20))
    }

    #expect(model.phase == .result)
    #expect(model.mode == .preview)
    #expect(model.grid?.columns == 10)
}

@Test @MainActor func pngCanBeSentToPhotoLibraryService() async throws {
    let grid = PatternGrid(columns: 2, rows: 1, cells: [
        PatternCell(hex: "#FF0000"), PatternCell(hex: "#0000FF"),
    ])
    let document = PatternDocument(project: PatternProject(grid: grid))
    let saver = MockPhotoLibrarySaver()
    let model = WorkspaceModel(document: document, photoLibrarySaver: saver)

    model.savePNGToPhotos()
    while model.isExporting {
        try await Task.sleep(for: .milliseconds(20))
    }

    #expect(saver.savedData?.starts(with: [0x89, 0x50, 0x4E, 0x47]) == true)
    #expect(model.successMessage == "PNG 已保存到照片。")
}

@Test @MainActor func deniedPhotoPermissionOffersSystemSettings() async throws {
    let grid = PatternGrid(columns: 1, rows: 1, cells: [PatternCell(hex: "#FF0000")])
    let document = PatternDocument(project: PatternProject(grid: grid))
    let model = WorkspaceModel(document: document, photoLibrarySaver: DeniedPhotoLibrarySaver())

    model.savePNGToPhotos()
    while model.isExporting {
        try await Task.sleep(for: .milliseconds(20))
    }

    #expect(model.offersSettingsForError)
    #expect(model.errorMessage == PhotoLibrarySaveError.permissionDenied.localizedDescription)
}

@Test @MainActor func restrictedPhotoLibraryShowsExplicitErrorWithoutSettingsLink() async throws {
    let grid = PatternGrid(columns: 1, rows: 1, cells: [PatternCell(hex: "#FF0000")])
    let document = PatternDocument(project: PatternProject(grid: grid))
    let model = WorkspaceModel(document: document, photoLibrarySaver: FailingPhotoLibrarySaver(error: .restricted))

    model.savePNGToPhotos()
    while model.isExporting {
        try await Task.sleep(for: .milliseconds(20))
    }

    #expect(!model.offersSettingsForError)
    #expect(model.errorMessage == PhotoLibrarySaveError.restricted.localizedDescription)
}

@Test @MainActor func photoLibraryWriteFailureShowsExplicitError() async throws {
    let grid = PatternGrid(columns: 1, rows: 1, cells: [PatternCell(hex: "#FF0000")])
    let document = PatternDocument(project: PatternProject(grid: grid))
    let model = WorkspaceModel(document: document, photoLibrarySaver: FailingPhotoLibrarySaver(error: .saveFailed))

    model.savePNGToPhotos()
    while model.isExporting {
        try await Task.sleep(for: .milliseconds(20))
    }

    #expect(model.errorMessage == PhotoLibrarySaveError.saveFailed.localizedDescription)
}

@MainActor
private final class MockPhotoLibrarySaver: PhotoLibrarySaving {
    var savedData: Data?

    func savePNG(_ data: Data) async throws {
        savedData = data
    }
}

@MainActor
private final class DeniedPhotoLibrarySaver: PhotoLibrarySaving {
    func savePNG(_ data: Data) async throws {
        throw PhotoLibrarySaveError.permissionDenied
    }
}

@MainActor
private final class FailingPhotoLibrarySaver: PhotoLibrarySaving {
    let error: PhotoLibrarySaveError

    init(error: PhotoLibrarySaveError) {
        self.error = error
    }

    func savePNG(_ data: Data) async throws {
        throw error
    }
}
