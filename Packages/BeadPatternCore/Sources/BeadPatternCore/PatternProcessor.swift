import Foundation

public actor PatternProcessor {
    public typealias ProgressHandler = @Sendable (Double) async -> Void

    public init() {}

    public func process(
        raster: RasterImage,
        settings: PatternSettings,
        palette: [PaletteColor],
        progress: ProgressHandler? = nil
    ) async throws -> PatternGrid {
        guard (10...300).contains(settings.columns) else {
            throw PatternCoreError.invalidColumns
        }
        guard !palette.isEmpty else { throw PatternCoreError.emptyPalette }

        let columns = settings.columns
        let rows = max(1, Int((Double(columns) * Double(raster.height) / Double(raster.width)).rounded()))
        let cellCount = columns * rows
        guard cellCount <= 300_000 else { throw PatternCoreError.tooManyCells(cellCount) }

        var cells = Array(repeating: PatternCell.transparent, count: cellCount)
        let matcher = try PaletteMatcher(palette: palette)
        var matchCache: [RGBColor: PaletteColor] = [:]
        for row in 0..<rows {
            try Task.checkCancellation()
            for column in 0..<columns {
                if let rgb = representativeColor(
                    raster: raster,
                    row: row,
                    column: column,
                    rows: rows,
                    columns: columns,
                    mode: settings.pixelationMode
                ) {
                    let nearest: PaletteColor
                    if let cached = matchCache[rgb] {
                        nearest = cached
                    } else {
                        nearest = try matcher.closest(to: rgb)
                        matchCache[rgb] = nearest
                    }
                    cells[row * columns + column] = PatternCell(hex: nearest.hex)
                }
            }
            if row.isMultiple(of: max(1, rows / 100)) {
                await progress?(Double(row + 1) / Double(rows) * 0.8)
            }
        }

        let initial = PatternGrid(columns: columns, rows: rows, cells: cells)
        let merged = try mergeSimilarColors(
            grid: initial,
            palette: palette,
            threshold: settings.mergeThreshold
        )
        await progress?(1)
        return merged
    }

    private func representativeColor(
        raster: RasterImage,
        row: Int,
        column: Int,
        rows: Int,
        columns: Int,
        mode: PixelationMode
    ) -> RGBColor? {
        let startX = Int(floor(Double(column * raster.width) / Double(columns)))
        let endX = min(raster.width, Int(ceil(Double((column + 1) * raster.width) / Double(columns))))
        let startY = Int(floor(Double(row * raster.height) / Double(rows)))
        let endY = min(raster.height, Int(ceil(Double((row + 1) * raster.height) / Double(rows))))

        var count = 0
        var redSum = 0
        var greenSum = 0
        var blueSum = 0
        var frequencies: [UInt32: Int] = [:]
        var dominant: UInt32 = 0
        var dominantCount = 0

        for y in startY..<max(startY + 1, endY) {
            for x in startX..<max(startX + 1, endX) {
                let offset = (y * raster.width + x) * 4
                guard raster.rgba[offset + 3] >= 128 else { continue }
                let red = raster.rgba[offset]
                let green = raster.rgba[offset + 1]
                let blue = raster.rgba[offset + 2]
                count += 1
                if mode == .average {
                    redSum += Int(red)
                    greenSum += Int(green)
                    blueSum += Int(blue)
                } else {
                    let packed = UInt32(red) << 16 | UInt32(green) << 8 | UInt32(blue)
                    let newCount = frequencies[packed, default: 0] + 1
                    frequencies[packed] = newCount
                    if newCount > dominantCount {
                        dominant = packed
                        dominantCount = newCount
                    }
                }
            }
        }

        guard count > 0 else { return nil }
        if mode == .average {
            return RGBColor(
                red: UInt8((Double(redSum) / Double(count)).rounded()),
                green: UInt8((Double(greenSum) / Double(count)).rounded()),
                blue: UInt8((Double(blueSum) / Double(count)).rounded())
            )
        }
        return RGBColor(
            red: UInt8((dominant >> 16) & 0xff),
            green: UInt8((dominant >> 8) & 0xff),
            blue: UInt8(dominant & 0xff)
        )
    }

    private func mergeSimilarColors(
        grid: PatternGrid,
        palette: [PaletteColor],
        threshold: Double
    ) throws -> PatternGrid {
        guard threshold > 0 else { return grid }
        let lookup = Dictionary(uniqueKeysWithValues: palette.map { ($0.hex, $0) })
        var counts: [String: Int] = [:]
        var firstSeen: [String] = []
        for cell in grid.cells where !cell.isExternal {
            if counts[cell.hex] == nil { firstSeen.append(cell.hex) }
            counts[cell.hex, default: 0] += 1
        }
        let encounterOrder = Dictionary(uniqueKeysWithValues: firstSeen.enumerated().map { ($0.element, $0.offset) })
        let ordered = firstSeen.sorted {
            let lhs = counts[$0, default: 0]
            let rhs = counts[$1, default: 0]
            return lhs == rhs ? encounterOrder[$0, default: 0] < encounterOrder[$1, default: 0] : lhs > rhs
        }

        var replacements: [String: String] = [:]
        var replaced = Set<String>()
        for index in ordered.indices {
            let frequentHex = ordered[index]
            guard !replaced.contains(frequentHex), let frequent = lookup[frequentHex] else { continue }
            for otherIndex in ordered.index(after: index)..<ordered.endIndex {
                let rareHex = ordered[otherIndex]
                guard !replaced.contains(rareHex), let rare = lookup[rareHex] else { continue }
                if ColorDistance.oklab(frequent.rgb, rare.rgb) < threshold {
                    replaced.insert(rareHex)
                    replacements[rareHex] = frequentHex
                }
            }
        }

        var result = grid
        for index in result.cells.indices where !result.cells[index].isExternal {
            if let replacement = replacements[result.cells[index].hex] {
                result.cells[index].hex = replacement
            }
        }
        return result
    }
}
