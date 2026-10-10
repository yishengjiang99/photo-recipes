import SwiftUI
import AVFoundation
import UIKit

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    /// Preview-only LUT id from phoneTargets.previewLUT — never applied to captured JPEG.
    var previewLUTId: String? = nil
    /// Active Creative Look — tint overlay approximates bake until Metal live pipeline.
    var creativeLook: CreativeLook? = nil
    /// Called once with the live preview layer so the session can convert
    /// UI points → device points of interest (tap-to-focus, AO focus).
    var onPreviewLayer: ((AVCaptureVideoPreviewLayer) -> Void)? = nil

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.applyPreviewLUT(previewLUTId)
        view.applyCreativeLook(creativeLook)
        onPreviewLayer?(view.videoPreviewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer.session = session
        uiView.applyPreviewLUT(previewLUTId)
        uiView.applyCreativeLook(creativeLook)
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        private var lutOverlay: CALayer?
        private var lookOverlay: CALayer?

        override func layoutSubviews() {
            super.layoutSubviews()
            lutOverlay?.frame = bounds
            lookOverlay?.frame = bounds
        }


        /// Thin preview-only LUT hook. Does NOT mutate capture pipeline / JPEG.
        func applyPreviewLUT(_ id: String?) {
            lutOverlay?.removeFromSuperlayer()
            lutOverlay = nil
            guard let id, !id.isEmpty else { return }
            let overlay = CALayer()
            overlay.frame = bounds
            overlay.opacity = 0.12
            overlay.backgroundColor = Self.lutTint(for: id).cgColor
            overlay.name = "previewLUT"
            layer.addSublayer(overlay)
            lutOverlay = overlay
        }

        /// Live look grade hint on the finder (still bake happens in CreativeLookEngine).
        /// monoInk uses colorBlendMode + white so the finder reads as B&W (not a gray wash).
        func applyCreativeLook(_ look: CreativeLook?) {
            lookOverlay?.removeFromSuperlayer()
            lookOverlay = nil
            guard let look, look.resolvedIntensity > 0, CreativeLookCatalog.isKnown(look.id) else { return }
            let overlay = CALayer()
            overlay.frame = bounds
            let intensity = CGFloat(look.resolvedIntensity)
            overlay.name = "creativeLook"
            if look.id == "monoInk" {
                // color blend with white → desaturate preview (matches still monoInk bake).
                overlay.backgroundColor = UIColor.white.cgColor
                overlay.compositingFilter = "colorBlendMode"
                overlay.opacity = Float(min(1, 0.55 + 0.45 * intensity))
            } else {
                overlay.opacity = Float(0.08 + 0.22 * intensity)
                overlay.backgroundColor = Self.lookTint(for: look.id).cgColor
            }
            layer.addSublayer(overlay)
            lookOverlay = overlay
        }

        private static func lutTint(for id: String) -> UIColor {
            switch id.lowercased() {
            case "warm", "golden": return UIColor(red: 1.0, green: 0.75, blue: 0.4, alpha: 1)
            case "cool", "blue": return UIColor(red: 0.45, green: 0.65, blue: 1.0, alpha: 1)
            case "contrast", "punch": return UIColor(white: 0.2, alpha: 1)
            default: return UIColor(white: 0.5, alpha: 1)
            }
        }

        private static func lookTint(for id: String) -> UIColor {
            switch id {
            case "crispCool", "coolBlue": return UIColor(red: 0.45, green: 0.65, blue: 1.0, alpha: 1)
            case "warmGlow", "warmPop", "goldenHour": return UIColor(red: 1.0, green: 0.7, blue: 0.35, alpha: 1)
            case "editorialRed": return UIColor(red: 0.85, green: 0.25, blue: 0.3, alpha: 1)
            case "softVintage", "softDream": return UIColor(red: 0.9, green: 0.8, blue: 0.65, alpha: 1)
            case "monoInk", "filmGrain", "moodyFilm": return UIColor(white: 0.25, alpha: 1)
            case "tealOrange", "blockbuster": return UIColor(red: 0.2, green: 0.55, blue: 0.55, alpha: 1)
            case "loFiPunch": return UIColor(red: 0.7, green: 0.35, blue: 0.2, alpha: 1)
            // Selfie pack: neutral warm hint only — the retouch is still-only (no live retouch).
            case "selfieNatural", "selfieGlow", "selfieStudio", "selfieLowLight", "selfiePortrait":
                return UIColor(red: 1.0, green: 0.86, blue: 0.74, alpha: 1)
            default: return UIColor(white: 0.4, alpha: 1)
            }
        }
    }
}
