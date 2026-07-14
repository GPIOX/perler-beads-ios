import Foundation

public enum PatternEditing {
    public static func statistics(for grid: PatternGrid) -> [ColorCount] {
        var counts: [String: Int] = [:]
        for cell in grid.cells where !cell.isExternal {
            counts[cell.hex, default: 0] += 1
        }
        return counts.map(ColorCount.init).sorted {
            $0.count == $1.count ? $0.hex < $1.hex : $0.count > $1.count
        }
    }

    public static func paint(grid: PatternGrid, row: Int, column: Int, hex: String?) throws -> PatternGrid {
        guard grid.isValid, row >= 0, row < grid.rows, column >= 0, column < grid.columns else {
            throw PatternCoreError.invalidGrid
        }
        var result = grid
        if let hex {
            _ = try RGBColor(hex: hex)
            result[row, column] = PatternCell(hex: hex)
        } else {
            result[row, column] = .transparent
        }
        return result
    }

    public static func replaceColor(grid: PatternGrid, sourceHex: String, targetHex: String) throws -> PatternGrid {
        _ = try RGBColor(hex: targetHex)
        var result = grid
        let source = sourceHex.uppercased()
        for index in result.cells.indices where !result.cells[index].isExternal {
            if result.cells[index].hex == source {
                result.cells[index] = PatternCell(hex: targetHex)
            }
        }
        return result
    }

    public static func floodErase(grid: PatternGrid, row: Int, column: Int) throws -> PatternGrid {
        let region = try connectedRegion(grid: grid, row: row, column: column)
        var result = grid
        for index in region { result.cells[index] = .transparent }
        return result
    }

    public static func autoRemoveBackground(grid: PatternGrid) throws -> PatternGrid {
        guard grid.isValid else { throw PatternCoreError.invalidGrid }
        var borderCounts: [String: Int] = [:]
        var borderOrder: [String] = []
        for column in 0..<grid.columns {
            addBorderColor(grid[0, column], to: &borderCounts, order: &borderOrder)
            if grid.rows > 1 { addBorderColor(grid[grid.rows - 1, column], to: &borderCounts, order: &borderOrder) }
        }
        if grid.rows > 2 {
            for row in 1..<(grid.rows - 1) {
                addBorderColor(grid[row, 0], to: &borderCounts, order: &borderOrder)
                if grid.columns > 1 { addBorderColor(grid[row, grid.columns - 1], to: &borderCounts, order: &borderOrder) }
            }
        }
        guard var target = borderOrder.first else { return grid }
        var maximum = borderCounts[target, default: 0]
        for color in borderOrder.dropFirst() {
            let count = borderCounts[color, default: 0]
            if count > maximum {
                target = color
                maximum = count
            }
        }

        var result = grid
        var visited = Set<Int>()
        var stack: [Int] = []
        func append(_ row: Int, _ column: Int) {
            guard row >= 0, row < grid.rows, column >= 0, column < grid.columns else { return }
            let index = row * grid.columns + column
            guard !visited.contains(index), !result.cells[index].isExternal, result.cells[index].hex == target else { return }
            visited.insert(index)
            stack.append(index)
        }
        for column in 0..<grid.columns {
            append(0, column)
            append(grid.rows - 1, column)
        }
        for row in 0..<grid.rows {
            append(row, 0)
            append(row, grid.columns - 1)
        }
        while let index = stack.popLast() {
            result.cells[index] = .transparent
            let row = index / grid.columns
            let column = index % grid.columns
            append(row - 1, column)
            append(row + 1, column)
            append(row, column - 1)
            append(row, column + 1)
        }
        return result
    }

    public static func remapExcludedColor(
        grid: PatternGrid,
        excludedHex: String,
        candidates: [PaletteColor]
    ) throws -> PatternGrid {
        let source = try RGBColor(hex: excludedHex)
        let replacement = try ColorDistance.closest(to: source, in: candidates)
        return try replaceColor(grid: grid, sourceHex: excludedHex, targetHex: replacement.hex)
    }

    public static func connectedRegion(grid: PatternGrid, row: Int, column: Int) throws -> Set<Int> {
        guard grid.isValid, row >= 0, row < grid.rows, column >= 0, column < grid.columns else {
            throw PatternCoreError.invalidGrid
        }
        let start = row * grid.columns + column
        let target = grid.cells[start]
        guard !target.isExternal else { return [] }
        var visited = Set<Int>()
        var stack = [start]
        while let index = stack.popLast() {
            guard !visited.contains(index), !grid.cells[index].isExternal, grid.cells[index].hex == target.hex else { continue }
            visited.insert(index)
            let currentRow = index / grid.columns
            let currentColumn = index % grid.columns
            if currentRow > 0 { stack.append(index - grid.columns) }
            if currentRow + 1 < grid.rows { stack.append(index + grid.columns) }
            if currentColumn > 0 { stack.append(index - 1) }
            if currentColumn + 1 < grid.columns { stack.append(index + 1) }
        }
        return visited
    }

    public static func regions(grid: PatternGrid, hex: String) -> [Set<Int>] {
        let target = hex.uppercased()
        var unseen = Set(grid.cells.indices.filter { !grid.cells[$0].isExternal && grid.cells[$0].hex == target })
        var output: [Set<Int>] = []
        while let start = unseen.first {
            let row = start / grid.columns
            let column = start % grid.columns
            guard let region = try? connectedRegion(grid: grid, row: row, column: column) else { break }
            output.append(region)
            unseen.subtract(region)
        }
        return output
    }

    public static func recommendedRegion(
        grid: PatternGrid,
        hex: String,
        completed: Set<Int>,
        mode: GuidanceMode,
        reference: Int? = nil
    ) -> Set<Int>? {
        let incomplete = regions(grid: grid, hex: hex).filter { !$0.isSubset(of: completed) }
        guard !incomplete.isEmpty else { return nil }
        switch mode {
        case .largest:
            return incomplete.max { $0.count < $1.count }
        case .edgeFirst:
            return incomplete.first { region in
                region.contains { index in
                    let row = index / grid.columns
                    let column = index % grid.columns
                    return row == 0 || column == 0 || row == grid.rows - 1 || column == grid.columns - 1
                }
            } ?? incomplete[0]
        case .nearest:
            let referenceIndex = reference ?? (grid.rows / 2 * grid.columns + grid.columns / 2)
            let referenceRow = referenceIndex / grid.columns
            let referenceColumn = referenceIndex % grid.columns
            return incomplete.min { lhs, rhs in
                distance(of: lhs, fromRow: referenceRow, column: referenceColumn, columns: grid.columns)
                    < distance(of: rhs, fromRow: referenceRow, column: referenceColumn, columns: grid.columns)
            }
        }
    }

    private static func addBorderColor(
        _ cell: PatternCell,
        to counts: inout [String: Int],
        order: inout [String]
    ) {
        guard !cell.isExternal else { return }
        if counts[cell.hex] == nil { order.append(cell.hex) }
        counts[cell.hex, default: 0] += 1
    }

    private static func distance(of region: Set<Int>, fromRow row: Int, column: Int, columns: Int) -> Int {
        guard !region.isEmpty else { return .max }
        let averageRow = region.reduce(0) { $0 + $1 / columns } / region.count
        let averageColumn = region.reduce(0) { $0 + $1 % columns } / region.count
        return abs(averageRow - row) + abs(averageColumn - column)
    }
}
