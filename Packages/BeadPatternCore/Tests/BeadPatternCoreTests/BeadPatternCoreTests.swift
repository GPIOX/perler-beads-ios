import Testing
import Foundation
@testable import BeadPatternCore

@Test func bundledPaletteIsComplete() throws {
    let store = try ColorMappingStore.bundled()
    #expect(store.palette.count == 291)
    #expect(store.code(for: "#FAF4C8", system: .mard) == "A01")
    #expect(store.code(for: "#FAF4C8", system: .coco) == "E02")
}

@Test func exactColorHasZeroDistance() throws {
    let red = try RGBColor(hex: "#FF0000")
    #expect(ColorDistance.oklab(red, red) == 0)
    let palette = [try PaletteColor(hex: "#000000"), try PaletteColor(hex: "#FF0000")]
    #expect(try ColorDistance.closest(to: red, in: palette).hex == "#FF0000")
}

@Test func processorMapsDominantAndTransparentCells() async throws {
    let bytes: [UInt8] = [
        255, 0, 0, 255, 255, 0, 0, 255,
        0, 0, 255, 0, 0, 0, 255, 0,
    ]
    let raster = try RasterImage(width: 2, height: 2, rgba: bytes)
    let red = try PaletteColor(hex: "#FF0000")
    var settings = PatternSettings(columns: 10, mergeThreshold: 0)
    // A 2x2 raster still expands to a valid 10x10 bead grid.
    settings.pixelationMode = .dominant
    let grid = try await PatternProcessor().process(raster: raster, settings: settings, palette: [red])
    #expect(grid.columns == 10)
    #expect(grid.rows == 10)
    #expect(grid.cells.contains { !$0.isExternal })
    #expect(grid.cells.contains { $0.isExternal })
}

@Test func csvRoundTripPreservesGrid() throws {
    let grid = PatternGrid(columns: 2, rows: 2, cells: [
        PatternCell(hex: "#FF0000"), .transparent,
        PatternCell(hex: "#00FF00"), PatternCell(hex: "#0000FF"),
    ])
    let encoded = try PatternCSV.encode(grid)
    let result = try PatternCSV.decode(encoded)
    #expect(result.grid == grid)
}

@Test func csvRejectsRaggedRows() {
    #expect(throws: PatternCoreError.self) {
        try PatternCSV.decode("#FFFFFF,#000000\n#FFFFFF")
    }
}

@Test func backgroundRemovalOnlyErasesBorderConnectedColor() throws {
    let white = PatternCell(hex: "#FFFFFF")
    let black = PatternCell(hex: "#000000")
    let grid = PatternGrid(columns: 3, rows: 3, cells: [
        white, white, white,
        white, black, white,
        white, white, white,
    ])
    let result = try PatternEditing.autoRemoveBackground(grid: grid)
    #expect(result.cells.filter(\.isExternal).count == 8)
    #expect(result[1, 1] == black)
}

@Test func connectedRegionDoesNotCrossOtherColors() throws {
    let red = PatternCell(hex: "#FF0000")
    let blue = PatternCell(hex: "#0000FF")
    let grid = PatternGrid(columns: 3, rows: 2, cells: [red, red, blue, red, blue, blue])
    let region = try PatternEditing.connectedRegion(grid: grid, row: 0, column: 0)
    #expect(region == Set([0, 1, 3]))
}

@Test func webBaselineFixtureMatchesCellForCell() async throws {
    struct Fixture: Decodable {
        let width: Int
        let height: Int
        let columns: Int
        let mergeThreshold: Double
        let mode: PixelationMode
        let rgba: [UInt8]
        let expectedHex: [String]
    }
    let url = try #require(Bundle.module.url(forResource: "web-baseline-2efee730", withExtension: "json"))
    let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    let store = try ColorMappingStore.bundled()
    let raster = try RasterImage(width: fixture.width, height: fixture.height, rgba: fixture.rgba)
    let settings = PatternSettings(
        columns: fixture.columns,
        mergeThreshold: fixture.mergeThreshold,
        pixelationMode: fixture.mode,
        selectedHexColors: Set(fixture.expectedHex)
    )
    let grid = try await PatternProcessor().process(
        raster: raster,
        settings: settings,
        palette: try store.activePalette(settings: settings)
    )
    #expect(grid.rows == 1)
    #expect(grid.cells.map(\.hex) == fixture.expectedHex)
}

@Test func maximumSquareGridProcessesWithoutChangingDimensions() async throws {
    let pixel = [UInt8](arrayLiteral: 250, 244, 200, 255)
    let raster = try RasterImage(width: 300, height: 300, rgba: Array(repeating: pixel, count: 90_000).flatMap { $0 })
    let palette = [try PaletteColor(hex: "#FAF4C8")]
    let settings = PatternSettings(columns: 300, mergeThreshold: 0, pixelationMode: .dominant)
    let grid = try await PatternProcessor().process(raster: raster, settings: settings, palette: palette)
    #expect(grid.columns == 300)
    #expect(grid.rows == 300)
    #expect(grid.cells.count == 90_000)
}
