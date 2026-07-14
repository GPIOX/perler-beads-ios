import Foundation
import Photos

enum PhotoLibrarySaveError: LocalizedError, Equatable {
    case permissionDenied
    case restricted
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "没有添加到照片图库的权限。请在系统设置中允许“拼豆图纸”添加照片。"
        case .restricted: "照片图库访问受到系统限制，无法保存 PNG。"
        case .saveFailed: "无法将 PNG 保存到照片图库。"
        }
    }
}

@MainActor
protocol PhotoLibrarySaving: AnyObject {
    func savePNG(_ data: Data) async throws
}

@MainActor
final class PhotoLibrarySaver: PhotoLibrarySaving {
    func savePNG(_ data: Data) async throws {
        var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            status = await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                    continuation.resume(returning: newStatus)
                }
            }
        }
        switch status {
        case .authorized, .limited:
            break
        case .restricted:
            throw PhotoLibrarySaveError.restricted
        default:
            throw PhotoLibrarySaveError.permissionDenied
        }

        try await Self.writePNGToPhotoLibrary(data)
    }

    /// Photos executes its change block on a private queue. Keeping this helper
    /// nonisolated prevents Swift 6 from attaching MainActor isolation to that block.
    private nonisolated static func writePNGToPhotoLibrary(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.uniformTypeIdentifier = "public.png"
                request.addResource(with: .photo, data: data, options: options)
            } completionHandler: { success, error in
                if success && error == nil {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: PhotoLibrarySaveError.saveFailed)
                }
            }
        }
    }
}
