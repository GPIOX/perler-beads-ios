import QuickLookThumbnailing
import UIKit

final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        if let previewURL = ThumbnailPreviewLocator.validPreviewURL(in: request.fileURL) {
            let reply = QLThumbnailReply(imageFileURL: previewURL)
            reply.extensionBadge = "BEAD"
            handler(reply, nil)
            return
        }

        let size = request.maximumSize
        let reply = QLThumbnailReply(contextSize: size, currentContextDrawing: {
            let background = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.width * 0.16)
            UIColor(red: 0.04, green: 0.12, blue: 0.24, alpha: 1).setFill()
            background.fill()

            let colors: [UIColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .systemPurple]
            let count = 3
            let gap = min(size.width, size.height) * 0.055
            let diameter = min(size.width, size.height) * 0.18
            let total = diameter * CGFloat(count) + gap * CGFloat(count - 1)
            let origin = CGPoint(x: (size.width - total) / 2, y: (size.height - total) / 2)
            for row in 0..<count {
                for column in 0..<count {
                    let rect = CGRect(
                        x: origin.x + CGFloat(column) * (diameter + gap),
                        y: origin.y + CGFloat(row) * (diameter + gap),
                        width: diameter,
                        height: diameter
                    )
                    colors[(row * count + column) % colors.count].setFill()
                    UIBezierPath(ovalIn: rect).fill()
                    UIColor.white.withAlphaComponent(0.7).setStroke()
                    let ring = UIBezierPath(ovalIn: rect.insetBy(dx: diameter * 0.28, dy: diameter * 0.28))
                    ring.lineWidth = max(1, diameter * 0.08)
                    ring.stroke()
                }
            }
            return true
        })
        reply.extensionBadge = "BEAD"
        handler(reply, nil)
    }
}
