import Foundation
import ImageIO

enum ThumbnailPreviewLocator {
    static func validPreviewURL(in projectURL: URL) -> URL? {
        let previewURL = projectURL.appendingPathComponent("preview.png", isDirectory: false)
        guard FileManager.default.fileExists(atPath: previewURL.path),
              let source = CGImageSourceCreateWithURL(previewURL as CFURL, nil),
              CGImageSourceGetCount(source) > 0
        else {
            return nil
        }
        return previewURL
    }
}
