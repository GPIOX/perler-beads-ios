import BeadPatternCore
import Testing
import UIKit
@testable import BeadPatternApp

@Test func rasterDecoderReadsPNG() throws {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 1))
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

@Test func previewRendererProducesPNG() throws {
    let grid = PatternGrid(columns: 2, rows: 1, cells: [
        PatternCell(hex: "#FF0000"), PatternCell(hex: "#0000FF"),
    ])
    #expect(PatternExporter.renderPreview(grid: grid) != nil)
}
