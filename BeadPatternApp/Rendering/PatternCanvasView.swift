import BeadPatternCore
import SwiftUI
import UIKit

struct PatternCanvasRepresentable: UIViewRepresentable {
    let grid: PatternGrid
    let colorStore: ColorMappingStore
    let colorSystem: ColorSystem
    var drawingEnabled = false
    var focusHex: String?
    var completed: Set<Int> = []
    var highlighted: Set<Int> = []
    let onCell: (Int, Int) -> Void

    func makeUIView(context: Context) -> PatternCanvasView {
        let view = PatternCanvasView()
        update(view)
        return view
    }

    func updateUIView(_ uiView: PatternCanvasView, context: Context) {
        update(uiView)
    }

    private func update(_ view: PatternCanvasView) {
        view.update(
            grid: grid,
            colorStore: colorStore,
            colorSystem: colorSystem,
            drawingEnabled: drawingEnabled,
            focusHex: focusHex,
            completed: completed,
            highlighted: highlighted,
            onCell: onCell
        )
    }
}

final class PatternCanvasView: UIView, UIGestureRecognizerDelegate {
    private var grid = PatternGrid(columns: 1, rows: 1, cells: [.transparent])
    private var colorStore: ColorMappingStore?
    private var colorSystem: ColorSystem = .mard
    private var drawingEnabled = false
    private var focusHex: String?
    private var completed = Set<Int>()
    private var highlighted = Set<Int>()
    private var onCell: ((Int, Int) -> Void)?
    private var canvasScale: CGFloat = 1
    private var canvasOffset = CGPoint(x: 20, y: 20)
    private var lastGridSize = ""
    private var lastDrawnCell: Int?
    private let cellSize: CGFloat = 24

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        backgroundColor = .secondarySystemBackground
        isAccessibilityElement = true
        accessibilityLabel = "拼豆图纸画布"

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        addGestureRecognizer(pinch)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        pan.delegate = self
        addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.delegate = self
        addGestureRecognizer(tap)

        let draw = UILongPressGestureRecognizer(target: self, action: #selector(handleDraw(_:)))
        draw.minimumPressDuration = 0
        draw.allowableMovement = .greatestFiniteMagnitude
        draw.delegate = self
        addGestureRecognizer(draw)
    }

    required init?(coder: NSCoder) { nil }

    func update(
        grid: PatternGrid,
        colorStore: ColorMappingStore,
        colorSystem: ColorSystem,
        drawingEnabled: Bool,
        focusHex: String?,
        completed: Set<Int>,
        highlighted: Set<Int>,
        onCell: @escaping (Int, Int) -> Void
    ) {
        let sizeKey = "\(grid.columns)x\(grid.rows)"
        if sizeKey != lastGridSize {
            lastGridSize = sizeKey
            canvasScale = 1
            canvasOffset = CGPoint(x: 20, y: 20)
        }
        self.grid = grid
        self.colorStore = colorStore
        self.colorSystem = colorSystem
        self.drawingEnabled = drawingEnabled
        self.focusHex = focusHex?.uppercased()
        self.completed = completed
        self.highlighted = highlighted
        self.onCell = onCell
        setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard canvasScale == 1, canvasOffset == CGPoint(x: 20, y: 20), bounds.width > 0 else { return }
        let width = CGFloat(grid.columns) * cellSize
        let height = CGFloat(grid.rows) * cellSize
        canvasScale = min(1, max(0.08, min((bounds.width - 40) / width, (bounds.height - 40) / height)))
        canvasOffset = CGPoint(
            x: max(20, (bounds.width - width * canvasScale) / 2),
            y: max(20, (bounds.height - height * canvasScale) / 2)
        )
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), grid.isValid else { return }
        UIColor.secondarySystemBackground.setFill()
        context.fill(bounds)
        context.saveGState()
        context.translateBy(x: canvasOffset.x, y: canvasOffset.y)
        context.scaleBy(x: canvasScale, y: canvasScale)

        let visible = CGRect(
            x: (bounds.minX - canvasOffset.x) / canvasScale,
            y: (bounds.minY - canvasOffset.y) / canvasScale,
            width: bounds.width / canvasScale,
            height: bounds.height / canvasScale
        )
        let firstColumn = max(0, Int(floor(visible.minX / cellSize)))
        let lastColumn = min(grid.columns - 1, Int(ceil(visible.maxX / cellSize)))
        let firstRow = max(0, Int(floor(visible.minY / cellSize)))
        let lastRow = min(grid.rows - 1, Int(ceil(visible.maxY / cellSize)))

        guard firstColumn <= lastColumn, firstRow <= lastRow else {
            context.restoreGState()
            return
        }

        for row in firstRow...lastRow {
            for column in firstColumn...lastColumn {
                let index = row * grid.columns + column
                let cell = grid.cells[index]
                let frame = CGRect(
                    x: CGFloat(column) * cellSize,
                    y: CGFloat(row) * cellSize,
                    width: cellSize,
                    height: cellSize
                )
                if cell.isExternal {
                    UIColor.systemGray5.setFill()
                } else {
                    let alpha: CGFloat = focusHex == nil || focusHex == cell.hex ? 1 : 0.16
                    UIColor(hex: cell.hex).withAlphaComponent(alpha).setFill()
                }
                context.fill(frame)

                UIColor.separator.setStroke()
                context.setLineWidth(0.5 / canvasScale)
                context.stroke(frame)

                if completed.contains(index) {
                    UIColor.systemGreen.withAlphaComponent(0.55).setFill()
                    context.fill(frame.insetBy(dx: 3, dy: 3))
                }
                if highlighted.contains(index) {
                    UIColor.systemOrange.setStroke()
                    context.setLineWidth(3 / canvasScale)
                    context.stroke(frame.insetBy(dx: 1.5, dy: 1.5))
                }

                if !cell.isExternal, canvasScale * cellSize >= 18 {
                    let code = colorStore?.code(for: cell.hex, system: colorSystem) ?? "?"
                    let color = UIColor(hex: cell.hex).isLight ? UIColor.black : UIColor.white
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: UIFont.monospacedSystemFont(ofSize: 7, weight: .medium),
                        .foregroundColor: color,
                    ]
                    let text = code as NSString
                    let size = text.size(withAttributes: attributes)
                    text.draw(
                        at: CGPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2),
                        withAttributes: attributes
                    )
                }
            }
        }
        context.restoreGState()
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        guard recognizer.state == .began || recognizer.state == .changed else { return }
        let location = recognizer.location(in: self)
        let oldScale = canvasScale
        canvasScale = min(8, max(0.05, canvasScale * recognizer.scale))
        let ratio = canvasScale / oldScale
        canvasOffset = CGPoint(
            x: location.x - (location.x - canvasOffset.x) * ratio,
            y: location.y - (location.y - canvasOffset.y) * ratio
        )
        recognizer.scale = 1
        setNeedsDisplay()
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: self)
        canvasOffset.x += translation.x
        canvasOffset.y += translation.y
        recognizer.setTranslation(.zero, in: self)
        setNeedsDisplay()
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard !drawingEnabled, recognizer.state == .ended else { return }
        dispatchCell(at: recognizer.location(in: self))
    }

    @objc private func handleDraw(_ recognizer: UILongPressGestureRecognizer) {
        guard drawingEnabled else { return }
        if recognizer.state == .ended || recognizer.state == .cancelled {
            lastDrawnCell = nil
            return
        }
        guard recognizer.state == .began || recognizer.state == .changed else { return }
        dispatchCell(at: recognizer.location(in: self), avoidsDuplicate: true)
    }

    private func dispatchCell(at location: CGPoint, avoidsDuplicate: Bool = false) {
        let x = (location.x - canvasOffset.x) / canvasScale
        let y = (location.y - canvasOffset.y) / canvasScale
        let column = Int(floor(x / cellSize))
        let row = Int(floor(y / cellSize))
        guard row >= 0, row < grid.rows, column >= 0, column < grid.columns else { return }
        let index = row * grid.columns + column
        guard !avoidsDuplicate || lastDrawnCell != index else { return }
        lastDrawnCell = index
        onCell?(row, column)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

private extension UIColor {
    convenience init(hex: String) {
        let value = UInt64(hex.dropFirst(), radix: 16) ?? 0
        self.init(
            red: CGFloat((value >> 16) & 0xff) / 255,
            green: CGFloat((value >> 8) & 0xff) / 255,
            blue: CGFloat(value & 0xff) / 255,
            alpha: 1
        )
    }

    var isLight: Bool {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: nil)
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue > 0.55
    }
}
