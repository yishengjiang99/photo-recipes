import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    /// Preview-only LUT id from phoneTargets.previewLUT — never applied to captured JPEG.
    var previewLUTId: String? = nil

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.applyPreviewLUT(previewLUTId)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer.session = session
        uiView.applyPreviewLUT(previewLUTId)
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        private var lutOverlay: CALayer?

        /// Thin preview-only hook. Does NOT mutate capture pipeline / JPEG (not a filter app).
        func applyPreviewLUT(_ id: String?) {
            lutOverlay?.removeFromSuperlayer()
            lutOverlay = nil
            guard let id, !id.isEmpty else { return }
            // Placeholder tint keyed by id — real LUT CIFilter wiring can land later.
            let overlay = CALayer()
            overlay.frame = bounds
            overlay.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            overlay.opacity = 0.12
            overlay.backgroundColor = Self.tint(for: id).cgColor
            overlay.name = "previewLUT"
            layer.addSublayer(overlay)
            lutOverlay = overlay
        }

        private static func tint(for id: String) -> UIColor {
            switch id.lowercased() {
            case "warm", "golden": return UIColor(red: 1.0, green: 0.75, blue: 0.4, alpha: 1)
            case "cool", "blue": return UIColor(red: 0.45, green: 0.65, blue: 1.0, alpha: 1)
            case "contrast", "punch": return UIColor(white: 0.2, alpha: 1)
            default: return UIColor(white: 0.5, alpha: 1)
            }
        }
    }
}
