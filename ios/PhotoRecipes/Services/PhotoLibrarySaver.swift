import Foundation
import Photos
import UIKit

enum PhotoLibrarySaver {
    enum SaveError: LocalizedError {
        case denied, failed
        var errorDescription: String? {
            switch self {
            case .denied: return "Photo Library access is off. Enable it in Settings to save captures."
            case .failed: return "Could not save photo to Camera Roll."
            }
        }
    }

    static func requestAddOnly() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited: return true
        case .notDetermined:
            let s = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            return s == .authorized || s == .limited
        default: return false
        }
    }

    static func saveJPEG(_ data: Data) async throws {
        guard await requestAddOnly() else { throw SaveError.denied }
        try await PHPhotoLibrary.shared().performChanges {
            let req = PHAssetCreationRequest.forAsset()
            req.addResource(with: .photo, data: data, options: nil)
        }
    }
}
