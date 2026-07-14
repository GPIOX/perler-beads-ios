import Foundation

public enum PixelationMode: String, Codable, CaseIterable, Sendable {
    case dominant
    case average
}

public enum ColorSystem: String, Codable, CaseIterable, Sendable {
    case mard = "MARD"
    case coco = "COCO"
    case manman = "漫漫"
    case panpan = "盼盼"
    case mixiaowo = "咪小窝"
}

public enum GuidanceMode: String, Codable, CaseIterable, Sendable {
    case nearest
    case largest
    case edgeFirst
}

public struct PatternSettings: Codable, Equatable, Sendable {
    public var columns: Int
    public var mergeThreshold: Double
    public var pixelationMode: PixelationMode
    public var colorSystem: ColorSystem
    public var selectedHexColors: Set<String>
    public var excludedHexColors: Set<String>

    public init(
        columns: Int = 100,
        mergeThreshold: Double = 30,
        pixelationMode: PixelationMode = .dominant,
        colorSystem: ColorSystem = .mard,
        selectedHexColors: Set<String> = [],
        excludedHexColors: Set<String> = []
    ) {
        self.columns = columns
        self.mergeThreshold = mergeThreshold
        self.pixelationMode = pixelationMode
        self.colorSystem = colorSystem
        self.selectedHexColors = selectedHexColors
        self.excludedHexColors = excludedHexColors
    }
}

public struct PatternCell: Codable, Hashable, Sendable {
    public var hex: String
    public var isExternal: Bool

    public init(hex: String, isExternal: Bool = false) {
        self.hex = hex.uppercased()
        self.isExternal = isExternal
    }

    public static let transparent = PatternCell(hex: "#FFFFFF", isExternal: true)
}

public struct PatternGrid: Codable, Equatable, Sendable {
    public var columns: Int
    public var rows: Int
    public var cells: [PatternCell]

    public init(columns: Int, rows: Int, cells: [PatternCell]) {
        self.columns = columns
        self.rows = rows
        self.cells = cells
    }

    public var isValid: Bool {
        columns > 0 && rows > 0 && cells.count == columns * rows
    }

    public subscript(row: Int, column: Int) -> PatternCell {
        get { cells[row * columns + column] }
        set { cells[row * columns + column] = newValue }
    }
}

public struct ColorCount: Codable, Equatable, Identifiable, Sendable {
    public var hex: String
    public var count: Int
    public var id: String { hex }

    public init(hex: String, count: Int) {
        self.hex = hex.uppercased()
        self.count = count
    }
}

public struct FocusProgress: Codable, Equatable, Sendable {
    public var completedCellIndices: Set<Int>
    public var currentColorHex: String?
    public var elapsedSeconds: Int
    public var isPaused: Bool
    public var guidanceMode: GuidanceMode

    public init(
        completedCellIndices: Set<Int> = [],
        currentColorHex: String? = nil,
        elapsedSeconds: Int = 0,
        isPaused: Bool = true,
        guidanceMode: GuidanceMode = .nearest
    ) {
        self.completedCellIndices = completedCellIndices
        self.currentColorHex = currentColorHex
        self.elapsedSeconds = elapsedSeconds
        self.isPaused = isPaused
        self.guidanceMode = guidanceMode
    }
}

public struct PatternProject: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var modifiedAt: Date
    public var sourceFilename: String?
    public var settings: PatternSettings
    public var grid: PatternGrid?
    public var focusProgress: FocusProgress

    public init(
        schemaVersion: Int = currentSchemaVersion,
        id: UUID = UUID(),
        title: String = "未命名图纸",
        createdAt: Date = .now,
        modifiedAt: Date = .now,
        sourceFilename: String? = nil,
        settings: PatternSettings = .init(),
        grid: PatternGrid? = nil,
        focusProgress: FocusProgress = .init()
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.sourceFilename = sourceFilename
        self.settings = settings
        self.grid = grid
        self.focusProgress = focusProgress
    }
}

public struct RasterImage: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let rgba: [UInt8]

    public init(width: Int, height: Int, rgba: [UInt8]) throws {
        guard width > 0, height > 0, rgba.count == width * height * 4 else {
            throw PatternCoreError.invalidRaster
        }
        self.width = width
        self.height = height
        self.rgba = rgba
    }
}

public enum PatternCoreError: LocalizedError, Equatable, Sendable {
    case invalidRaster
    case invalidGrid
    case invalidColumns
    case tooManyCells(Int)
    case emptyPalette
    case invalidHex(String)
    case invalidCSV(String)
    case unsupportedSchema(Int)
    case invalidColorMapping(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRaster: "图片像素数据无效。"
        case .invalidGrid: "图纸网格数据无效。"
        case .invalidColumns: "横向格子数必须在 10 到 300 之间。"
        case let .tooManyCells(count): "图纸共有 \(count) 格，超过 300,000 格限制。"
        case .emptyPalette: "当前没有可用颜色。"
        case let .invalidHex(value): "无效颜色：\(value)"
        case let .invalidCSV(reason): "CSV 无效：\(reason)"
        case let .unsupportedSchema(version): "不支持项目文件版本 \(version)。"
        case let .invalidColorMapping(reason): "色号映射无效：\(reason)"
        }
    }
}
