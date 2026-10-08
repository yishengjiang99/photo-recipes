import CoreGraphics
import AVFoundation

/// Explicit coordinate spaces used across the camera pipeline.
///
/// - **Vision**: normalized 0…1, origin **bottom-left** (what `VNImageRequestHandler` returns).
/// - **UI**: normalized 0…1, origin **top-left** (SwiftUI layout space; what the reticle draws in).
/// - **Device**: `AVCaptureDevice` point of interest 0…1 in sensor space
///   (what `focusPointOfInterest` / `exposurePointOfInterest` take).
///
/// Mixing these spaces was a real defect: tap-to-focus passed UI coordinates
/// straight in as device points, and Vision ran on sideways (sensor-native)
/// frames. Every conversion below is named; raw `CGPoint` math across spaces
/// should go through these helpers so the spaces stay visible at call sites.
enum CoordinateSpaces {

    /// Vision (bottom-left origin) → UI (top-left origin). Both normalized 0…1.
    /// Only valid when the frame handed to Vision is upright (see
    /// `CameraSession.updateVideoOutputOrientation()`).
    static func visionToUI(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x, y: 1 - p.y)
    }

    /// Vision rect (bottom-left origin) → UI rect (top-left origin). Both normalized.
    static func visionRectToUI(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height)
    }

    /// UI normalized point → point in a layer/view of `size` (points, top-left origin).
    static func uiToLayerPoint(_ p: CGPoint, layerSize: CGSize) -> CGPoint {
        CGPoint(x: p.x * layerSize.width, y: p.y * layerSize.height)
    }

    /// Clamp a normalized point into 0…1.
    static func clamp01(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 0), 1), y: min(max(p.y, 0), 1))
    }
}

/// Converts UI-normalized points (top-left origin) to `AVCaptureDevice` points
/// of interest (sensor space). Inject a mock in tests; production uses the live
/// preview layer via `PreviewLayerDevicePointConverter`.
protocol DevicePointConverter: AnyObject {
    func devicePoint(uiNormalized: CGPoint) -> CGPoint
}

/// Production converter backed by the live `AVCaptureVideoPreviewLayer`.
/// Uses `captureDevicePointConverted(fromLayerPoint:)` so mirroring, rotation,
/// and `.resizeAspectFill` crop are all honored.
final class PreviewLayerDevicePointConverter: DevicePointConverter {
    weak var layer: AVCaptureVideoPreviewLayer?

    init(layer: AVCaptureVideoPreviewLayer?) {
        self.layer = layer
    }

    func devicePoint(uiNormalized: CGPoint) -> CGPoint {
        let p = CoordinateSpaces.clamp01(uiNormalized)
        guard let layer else { return p }
        let size = layer.bounds.size
        guard size.width > 0, size.height > 0 else { return p }
        let layerPoint = CoordinateSpaces.uiToLayerPoint(p, layerSize: size)
        return layer.captureDevicePointConverted(fromLayerPoint: layerPoint)
    }
}
