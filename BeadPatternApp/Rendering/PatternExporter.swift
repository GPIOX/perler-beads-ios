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

        let axis: CGFloat = 34
        let titleHeight: CGFloat = 68
        let statsColumns = max(1, min(4, grid.columns * Int(cellSize) / 250))
        let statsRows = Int(ceil(Double(statistics.count) / Double(statsColumns)))
        let statsHeight = CGFloat(54 + statsRows * 28 + 42)
        let width = axis + CGFloat(grid.columns) * cellSize + 20
        let height = titleHeight + axis + CGFloat(grid.rows) * cellSize + statsHeight

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

            UIColor.darkGray.setStroke()
            context.setLineWidth(1.5)
            context.stroke(CGRect(
                x: origin.x,
                y: origin.y,
                width: CGFloat(grid.columns) * cellSize,
                height: CGFloat(grid.rows) * cellSize
            ))
            for value in stride(from: 10, to: grid.columns, by: 10) {
                let x = origin.x + CGFloat(value) * cellSize
                context.move(to: CGPoint(x: x, y: origin.y))
                context.addLine(to: CGPoint(x: x, y: origin.y + CGFloat(grid.rows) * cellSize))
                context.strokePath()
            }
            for value in stride(from: 10, to: grid.rows, by: 10) {
                let y = origin.y + CGFloat(value) * cellSize
                context.move(to: CGPoint(x: origin.x, y: y))
                context.addLine(to: CGPoint(x: origin.x + CGFloat(grid.columns) * cellSize, y: y))
                context.strokePath()
            }
            for value in stride(from: 0, through: grid.columns, by: 10) {
                drawCentered(
                    "\(value)",
                    in: CGRect(x: origin.x + CGFloat(value) * cellSize - 20, y: titleHeight, width: 40, height: axis),
                    font: .systemFont(ofSize: 11),
                    color: .darkGray
                )
            }
            for value in stride(from: 0, through: grid.rows, by: 10) {
                drawCentered(
                    "\(value)",
                    in: CGRect(x: 0, y: origin.y + CGFloat(value) * cellSize - 10, width: axis, height: 20),
                    font: .systemFont(ofSize: 11),
                    color: .darkGray
                )
            }

            let statsTop = origin.y + CGFloat(grid.rows) * cellSize + 28
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
        (text as NSString).draw(
            in: rect,
            withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
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
