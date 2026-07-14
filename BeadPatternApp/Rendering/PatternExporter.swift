import BeadPatternCore
import Foundation
import UIKit

enum PatternExportError: LocalizedError {
    case imageTooLarge
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .imageTooLarge: "图纸过大，无法在保证色号可读的同时导出。请降低横向格数。"
        case .encodingFailed: "PNG 编码失败。"
        }
    }
}

enum PatternExporter {
    private static let maximumPixels: CGFloat = 64_000_000

    static func renderPNG(
        grid: PatternGrid,
        statistics: [ColorCount],
        colorStore: ColorMappingStore,
        colorSystem: ColorSystem
    ) throws -> Data {
        let rawCellSize = floor(sqrt(maximumPixels / CGFloat(max(1, grid.columns * grid.rows))))
        let cellSize = min(30, rawCellSize)
        guard cellSize >= 16 else { throw PatternExportError.imageTooLarge }

        let axis: CGFloat = max(28, cellSize + 4)
        let titleHeight: CGFloat = 68
        let statsColumns = max(1, min(4, grid.columns * Int(cellSize) / 250))
        let statsRows = Int(ceil(Double(statistics.count) / Double(statsColumns)))
        let statsHeight = CGFloat(54 + statsRows * 28 + 42)
        let gridWidth = CGFloat(grid.columns) * cellSize
        let gridHeight = CGFloat(grid.rows) * cellSize
        let width = axis * 2 + gridWidth
        let height = titleHeight + axis * 2 + gridHeight + statsHeight

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        let image = renderer.image { output in
            let context = output.cgContext
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: CGSize(width: width, height: height)))

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            ("拼豆图纸  \(grid.columns) × \(grid.rows)" as NSString).draw(
                in: CGRect(x: 0, y: 18, width: width, height: 30),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 22, weight: .bold),
                    .foregroundColor: UIColor.label,
                    .paragraphStyle: paragraph,
                ]
            )

            let origin = CGPoint(x: axis, y: titleHeight + axis)
            drawCoordinateAxes(
                context: context,
                origin: origin,
                grid: grid,
                cellSize: cellSize,
                axisSize: axis
            )
            for row in 0..<grid.rows {
                for column in 0..<grid.columns {
                    let cell = grid[row, column]
                    let frame = CGRect(
                        x: origin.x + CGFloat(column) * cellSize,
                        y: origin.y + CGFloat(row) * cellSize,
                        width: cellSize,
                        height: cellSize
                    )
                    (cell.isExternal ? UIColor.systemGray6 : UIColor(hexString: cell.hex)).setFill()
                    context.fill(frame)
                    UIColor(white: 0.72, alpha: 1).setStroke()
                    context.setLineWidth(0.5)
                    context.stroke(frame)
                    if !cell.isExternal {
                        let code = colorStore.code(for: cell.hex, system: colorSystem) ?? "?"
                        drawCentered(
                            code,
                            in: frame,
                            font: .monospacedSystemFont(ofSize: max(7, cellSize * 0.29), weight: .medium),
                            color: UIColor(hexString: cell.hex).isLightColor ? .black : .white
                        )
                    }
                }
            }

            UIColor.black.setStroke()
            context.setLineWidth(2.5)
            context.setLineCap(.butt)
            for value in PatternChartStyle.boardBoundaryIndices(for: grid.columns) {
                let x = origin.x + CGFloat(value) * cellSize
                context.move(to: CGPoint(x: x, y: origin.y))
                context.addLine(to: CGPoint(x: x, y: origin.y + gridHeight))
            }
            for value in PatternChartStyle.boardBoundaryIndices(for: grid.rows) {
                let y = origin.y + CGFloat(value) * cellSize
                context.move(to: CGPoint(x: origin.x, y: y))
                context.addLine(to: CGPoint(x: origin.x + gridWidth, y: y))
            }
            context.strokePath()

            let statsTop = origin.y + gridHeight + axis + 28
            ("颜色用量" as NSString).draw(
                at: CGPoint(x: 24, y: statsTop),
                withAttributes: [.font: UIFont.systemFont(ofSize: 18, weight: .bold), .foregroundColor: UIColor.label]
            )
            let columnWidth = (width - 48) / CGFloat(statsColumns)
            for (index, item) in statistics.enumerated() {
                let column = index % statsColumns
                let row = index / statsColumns
                let x = 24 + CGFloat(column) * columnWidth
                let y = statsTop + 34 + CGFloat(row) * 28
                UIColor(hexString: item.hex).setFill()
                context.fill(CGRect(x: x, y: y, width: 18, height: 18))
                let code = colorStore.code(for: item.hex, system: colorSystem) ?? "?"
                ("\(code)  \(item.count) 颗" as NSString).draw(
                    at: CGPoint(x: x + 25, y: y),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: UIColor.label]
                )
            }
            let total = statistics.reduce(0) { $0 + $1.count }
            ("总计 \(total) 颗  ·  开源项目 perler-beads-ios" as NSString).draw(
                at: CGPoint(x: 24, y: height - 34),
                withAttributes: [.font: UIFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: UIColor.darkGray]
            )
        }
        guard let data = image.pngData() else { throw PatternExportError.encodingFailed }
        return data
    }

    private static func drawCoordinateAxes(
        context: CGContext,
        origin: CGPoint,
        grid: PatternGrid,
        cellSize: CGFloat,
        axisSize: CGFloat
    ) {
        let gridWidth = CGFloat(grid.columns) * cellSize
        let gridHeight = CGFloat(grid.rows) * cellSize
        let topY = origin.y - axisSize
        let bottomY = origin.y + gridHeight
        let leftX = origin.x - axisSize
        let rightX = origin.x + gridWidth

        UIColor(white: 0.92, alpha: 1).setFill()
        context.fill(CGRect(x: origin.x, y: topY, width: gridWidth, height: axisSize))
        context.fill(CGRect(x: origin.x, y: bottomY, width: gridWidth, height: axisSize))
        context.fill(CGRect(x: leftX, y: origin.y, width: axisSize, height: gridHeight))
        context.fill(CGRect(x: rightX, y: origin.y, width: axisSize, height: gridHeight))

        UIColor(white: 0.84, alpha: 1).setFill()
        context.fill(CGRect(x: leftX, y: topY, width: axisSize, height: axisSize))
        context.fill(CGRect(x: rightX, y: topY, width: axisSize, height: axisSize))
        context.fill(CGRect(x: leftX, y: bottomY, width: axisSize, height: axisSize))
        context.fill(CGRect(x: rightX, y: bottomY, width: axisSize, height: axisSize))

        UIColor(white: 0.68, alpha: 1).setStroke()
        context.setLineWidth(0.5)
        let font = UIFont.monospacedDigitSystemFont(
            ofSize: min(9, max(6, cellSize * 0.32)),
            weight: .regular
        )
        for column in 0..<grid.columns {
            let x = origin.x + CGFloat(column) * cellSize
            let top = CGRect(x: x, y: topY, width: cellSize, height: axisSize)
            let bottom = CGRect(x: x, y: bottomY, width: cellSize, height: axisSize)
            context.stroke(top)
            context.stroke(bottom)
            let value = "\(column + 1)"
            drawCentered(value, in: top, font: font, color: .darkGray)
            drawCentered(value, in: bottom, font: font, color: .darkGray)
        }
        for row in 0..<grid.rows {
            let y = origin.y + CGFloat(row) * cellSize
            let left = CGRect(x: leftX, y: y, width: axisSize, height: cellSize)
            let right = CGRect(x: rightX, y: y, width: axisSize, height: cellSize)
            context.stroke(left)
            context.stroke(right)
            let value = "\(row + 1)"
            drawCentered(value, in: left, font: font, color: .darkGray)
            drawCentered(value, in: right, font: font, color: .darkGray)
        }
    }

    static func renderPreview(grid: PatternGrid, maximumDimension: CGFloat = 600) -> Data? {
        let cellSize = min(maximumDimension / CGFloat(grid.columns), maximumDimension / CGFloat(grid.rows))
        let size = CGSize(width: CGFloat(grid.columns) * cellSize, height: CGFloat(grid.rows) * cellSize)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { output in
            UIColor.systemGray6.setFill()
            output.cgContext.fill(CGRect(origin: .zero, size: size))
            for row in 0..<grid.rows {
                for column in 0..<grid.columns {
                    let cell = grid[row, column]
                    guard !cell.isExternal else { continue }
                    UIColor(hexString: cell.hex).setFill()
                    output.cgContext.fill(CGRect(
                        x: CGFloat(column) * cellSize,
                        y: CGFloat(row) * cellSize,
                        width: cellSize + 0.5,
                        height: cellSize + 0.5
                    ))
                }
            }
        }.pngData()
    }

    private static func drawCentered(_ text: String, in rect: CGRect, font: UIFont, color: UIColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byClipping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        let value = text as NSString
        let textHeight = ceil(value.size(withAttributes: attributes).height)
        value.draw(
            in: CGRect(x: rect.minX, y: rect.midY - textHeight / 2, width: rect.width, height: textHeight),
            withAttributes: attributes
        )
    }
}

private extension UIColor {
    convenience init(hexString: String) {
        let value = UInt64(hexString.dropFirst(), radix: 16) ?? 0
        self.init(
            red: CGFloat((value >> 16) & 0xff) / 255,
            green: CGFloat((value >> 8) & 0xff) / 255,
            blue: CGFloat(value & 0xff) / 255,
            alpha: 1
        )
    }

    var isLightColor: Bool {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: nil)
        return red * 0.2126 + green * 0.7152 + blue * 0.0722 > 0.55
    }
}
