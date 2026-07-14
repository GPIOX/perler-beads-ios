import BeadPatternCore
import Foundation
import SwiftUI

enum WorkspaceMode: String, CaseIterable, Identifiable {
    case preview = "预览"
    case edit = "编辑"
    case focus = "专心"
    var id: Self { self }
}

enum EditorTool: String, CaseIterable, Identifiable {
    case paint = "画笔"
    case erase = "橡皮擦"
    case floodErase = "区域擦除"
    var id: Self { self }
}

@MainActor
final class WorkspaceModel: ObservableObject {
    @Published var mode: WorkspaceMode = .preview
    @Published var editorTool: EditorTool = .paint
    @Published var selectedPaintHex: String?
    @Published var processingProgress: Double = 0
    @Published var isProcessing = false
    @Published var errorMessage: String?
    @Published var warningMessage: String?
    @Published var shareItems: [Any] = []
    @Published var showsShareSheet = false
    @Published var showsPalette = false
    @Published var showsReplaceSheet = false

    let document: PatternDocument
    let colorStore: ColorMappingStore
    private let processor = PatternProcessor()
    private var processingTask: Task<Void, Never>?
    private static let globalPaletteDefaultsKey = "globalPaletteHexColors"

    init(document: PatternDocument) {
        self.document = document
        let store = try! ColorMappingStore.bundled()
        colorStore = store
        if document.project.settings.selectedHexColors.isEmpty {
            let saved = UserDefaults.standard.stringArray(forKey: Self.globalPaletteDefaultsKey) ?? []
            let known = Set(store.palette.map(\.hex))
            let validSaved = Set(saved.map { $0.uppercased() }).intersection(known)
            document.project.settings.selectedHexColors = validSaved.isEmpty ? known : validSaved
        }
        selectedPaintHex = document.project.grid.flatMap { PatternEditing.statistics(for: $0).first?.hex }
    }

    var grid: PatternGrid? { document.project.grid }
    var statistics: [ColorCount] { grid.map(PatternEditing.statistics) ?? [] }
    var totalBeads: Int { statistics.reduce(0) { $0 + $1.count } }

    func saveGlobalPaletteDefault() {
        UserDefaults.standard.set(
            document.project.settings.selectedHexColors.sorted(),
            forKey: Self.globalPaletteDefaultsKey
        )
    }

    func importImage(data: Data, filename: String) {
        document.sourceData = data
        document.sourceFilename = filename
        document.project.sourceFilename = filename
        document.project.title = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        regenerate()
    }

    func importCSV(_ data: Data) {
        do {
            guard let text = String(data: data, encoding: .utf8) else {
                throw PatternCoreError.invalidCSV("文件不是 UTF-8 编码")
            }
            let result = try PatternCSV.decode(text, knownHexColors: Set(colorStore.palette.map(\.hex)))
            document.project.grid = result.grid
            document.previewData = PatternExporter.renderPreview(grid: result.grid)
            document.project.settings.columns = min(300, max(10, result.grid.columns))
            document.project.modifiedAt = .now
            selectedPaintHex = PatternEditing.statistics(for: result.grid).first?.hex
            if !result.unmappedHexColors.isEmpty {
                warningMessage = "已导入，但有 \(result.unmappedHexColors.count) 种颜色没有品牌色号。"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func regenerate() {
        guard let sourceData = document.sourceData else {
            errorMessage = "请先导入图片。"
            return
        }
        processingTask?.cancel()
        do {
            let raster = try RasterDecoder.decode(data: sourceData)
            let settings = document.project.settings
            let palette = try colorStore.activePalette(settings: settings)
            isProcessing = true
            processingProgress = 0
            errorMessage = nil
            processingTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let result = try await processor.process(
                        raster: raster,
                        settings: settings,
                        palette: palette
                    ) { [weak self] value in
                        await MainActor.run { self?.processingProgress = value }
                    }
                    guard !Task.isCancelled else { return }
                    document.project.grid = result
                    document.previewData = PatternExporter.renderPreview(grid: result)
                    document.project.focusProgress = FocusProgress()
                    document.project.modifiedAt = .now
                    selectedPaintHex = PatternEditing.statistics(for: result).first?.hex
                } catch is CancellationError {
                    // A cancelled operation never replaces the current document grid.
                } catch {
                    errorMessage = error.localizedDescription
                }
                isProcessing = false
            }
        } catch {
            isProcessing = false
            errorMessage = error.localizedDescription
        }
    }

    func cancelProcessing() {
        processingTask?.cancel()
        processingTask = nil
        isProcessing = false
    }

    func editCell(row: Int, column: Int, undoManager: UndoManager?) {
        guard let grid else { return }
        do {
            let updated: PatternGrid
            switch editorTool {
            case .paint:
                guard let selectedPaintHex else { return }
                updated = try PatternEditing.paint(grid: grid, row: row, column: column, hex: selectedPaintHex)
            case .erase:
                updated = try PatternEditing.paint(grid: grid, row: row, column: column, hex: nil)
            case .floodErase:
                updated = try PatternEditing.floodErase(grid: grid, row: row, column: column)
            }
            setGrid(updated, replacing: grid, undoManager: undoManager, actionName: editorTool.rawValue)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeBackground(undoManager: UndoManager?) {
        guard let grid else { return }
        do {
            let updated = try PatternEditing.autoRemoveBackground(grid: grid)
            setGrid(updated, replacing: grid, undoManager: undoManager, actionName: "去背景")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func replaceColor(sourceHex: String, targetHex: String, undoManager: UndoManager?) {
        guard let grid else { return }
        do {
            let updated = try PatternEditing.replaceColor(grid: grid, sourceHex: sourceHex, targetHex: targetHex)
            setGrid(updated, replacing: grid, undoManager: undoManager, actionName: "替换颜色")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleExcluded(_ hex: String, undoManager: UndoManager?) {
        let normalized = hex.uppercased()
        if document.project.settings.excludedHexColors.contains(normalized) {
            document.project.settings.excludedHexColors.remove(normalized)
            regenerate()
            return
        }
        guard let grid else { return }
        var nextSettings = document.project.settings
        nextSettings.excludedHexColors.insert(normalized)
        do {
            let candidateHex = Set(grid.cells.filter { !$0.isExternal }.map(\.hex))
                .subtracting(nextSettings.excludedHexColors)
            let candidates = colorStore.palette.filter { candidateHex.contains($0.hex) }
            guard !candidates.isEmpty else { throw PatternCoreError.emptyPalette }
            let updated = try PatternEditing.remapExcludedColor(
                grid: grid,
                excludedHex: normalized,
                candidates: candidates
            )
            document.project.settings = nextSettings
            setGrid(updated, replacing: grid, undoManager: undoManager, actionName: "排除颜色")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleFocusRegion(row: Int, column: Int) {
        guard let grid, row >= 0, row < grid.rows, column >= 0, column < grid.columns else { return }
        let cell = grid[row, column]
        guard !cell.isExternal, cell.hex == document.project.focusProgress.currentColorHex else { return }
        guard let region = try? PatternEditing.connectedRegion(grid: grid, row: row, column: column) else { return }
        if region.isSubset(of: document.project.focusProgress.completedCellIndices) {
            document.project.focusProgress.completedCellIndices.subtract(region)
        } else {
            document.project.focusProgress.completedCellIndices.formUnion(region)
        }
        document.project.modifiedAt = .now
        document.objectWillChange.send()
    }

    func tickFocusTimer() {
        guard !document.project.focusProgress.isPaused else { return }
        document.project.focusProgress.elapsedSeconds += 1
        document.objectWillChange.send()
    }

    func setGrid(_ newGrid: PatternGrid, replacing oldGrid: PatternGrid, undoManager: UndoManager?, actionName: String) {
        document.project.grid = newGrid
        document.previewData = PatternExporter.renderPreview(grid: newGrid)
        document.project.modifiedAt = .now
        selectedPaintHex = selectedPaintHex ?? PatternEditing.statistics(for: newGrid).first?.hex
        undoManager?.registerUndo(withTarget: self) { target in
            target.setGrid(oldGrid, replacing: newGrid, undoManager: undoManager, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
    }

    func exportPNG() {
        guard let grid else { return }
        do {
            let data = try PatternExporter.renderPNG(
                grid: grid,
                statistics: statistics,
                colorStore: colorStore,
                colorSystem: document.project.settings.colorSystem
            )
            let url = try temporaryURL(extension: "png")
            try data.write(to: url, options: .atomic)
            shareItems = [url]
            showsShareSheet = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportCSV() {
        guard let grid else { return }
        do {
            let csv = try PatternCSV.encode(grid)
            let url = try temporaryURL(extension: "csv")
            try Data(csv.utf8).write(to: url, options: .atomic)
            shareItems = [url]
            showsShareSheet = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func temporaryURL(extension fileExtension: String) throws -> URL {
        let safeTitle = document.project.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeadPatternExports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("\(safeTitle)-\(grid?.columns ?? 0)x\(grid?.rows ?? 0).\(fileExtension)")
    }
}
