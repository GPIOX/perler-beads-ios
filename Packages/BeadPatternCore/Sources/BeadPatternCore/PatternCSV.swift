import Foundation

public enum PatternCSV {
    public struct ImportResult: Equatable, Sendable {
        public let grid: PatternGrid
        public let unmappedHexColors: Set<String>

        public init(grid: PatternGrid, unmappedHexColors: Set<String>) {
            self.grid = grid
            self.unmappedHexColors = unmappedHexColors
        }
    }

    public static func encode(_ grid: PatternGrid) throws -> String {
        guard grid.isValid else { throw PatternCoreError.invalidGrid }
        return (0..<grid.rows).map { row in
            (0..<grid.columns).map { column in
                let cell = grid[row, column]
                return cell.isExternal ? "TRANSPARENT" : cell.hex
            }.joined(separator: ",")
        }.joined(separator: "\n")
    }

    public static func decode(_ text: String, knownHexColors: Set<String> = []) throws -> ImportResult {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        guard let first = lines.first, !first.isEmpty else {
            throw PatternCoreError.invalidCSV("文件为空")
        }
        let columns = first.split(separator: ",", omittingEmptySubsequences: false).count
        guard columns > 0 else { throw PatternCoreError.invalidCSV("没有列") }

        let known = Set(knownHexColors.map { $0.uppercased() })
        var cells: [PatternCell] = []
        var unmapped = Set<String>()
        for (rowIndex, line) in lines.enumerated() {
            let values = line.split(separator: ",", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard values.count == columns else {
                throw PatternCoreError.invalidCSV("第 \(rowIndex + 1) 行列数不一致")
            }
            for value in values {
                if value.isEmpty || value.uppercased() == "TRANSPARENT" {
                    cells.append(.transparent)
                } else {
                    let normalized = value.uppercased()
                    _ = try RGBColor(hex: normalized)
                    cells.append(PatternCell(hex: normalized))
                    if !known.isEmpty && !known.contains(normalized) { unmapped.insert(normalized) }
                }
            }
        }
        return ImportResult(
            grid: PatternGrid(columns: columns, rows: lines.count, cells: cells),
            unmappedHexColors: unmapped
        )
    }
}
