import Foundation
import AVFoundation

/// Parses recipe dial strings (e.g. `1/30s`, `f/11`, `ISO 400`) into device-ready values
/// with graceful fallbacks when the phone cannot honor a setting.
struct RecipeCameraMapper {

    struct MappedSettings: Equatable {
        var shutterSeconds: Double?
        var iso: Float?
        var evCompensation: Float?
        var apertureGuidance: String?
        var whiteBalanceTempKelvin: Float?
        var focusMode: FocusIntent
        var notes: [String]
        var unsupported: [String]

        enum FocusIntent: Equatable {
            case continuous
            case locked
            case hyperfocalHint
        }
    }

    static func map(dials: DialSettings, capabilities: DeviceCapabilities) -> MappedSettings {
        var notes: [String] = []
        var unsupported: [String] = []

        // Aperture — always guidance-only on fixed phone lenses
        var apertureGuidance: String?
        if let aperture = dials.aperture, !aperture.isEmpty, aperture.lowercased() != "auto" {
            apertureGuidance = aperture
            notes.append("Aperture \(aperture) is guidance-only — phone lenses are fixed; use DoF with subject distance instead.")
        }

        // Shutter
        var shutter: Double?
        if let raw = dials.shutter {
            if let parsed = parseShutter(raw) {
                if capabilities.supportsCustomExposure {
                    let clamped = clamp(parsed, min: capabilities.minExposureSeconds, max: capabilities.maxExposureSeconds)
                    if clamped != parsed {
                        notes.append("Shutter \(formatShutter(parsed)) clamped to device range \(formatShutter(clamped)).")
                    }
                    shutter = clamped
                } else {
                    unsupported.append("Custom shutter (\(raw)) — format locks exposure; showing guidance only.")
                }
            } else if raw.lowercased().contains("auto") {
                notes.append("Recipe shutter is auto — leaving continuous exposure.")
            } else {
                notes.append("Could not parse shutter “\(raw)” — left unchanged.")
            }
        }

        // ISO
        var iso: Float?
        if let raw = dials.iso {
            if let parsed = parseISO(raw) {
                if capabilities.supportsCustomExposure {
                    let clamped = clamp(parsed, min: capabilities.minISO, max: capabilities.maxISO)
                    if clamped != parsed {
                        notes.append("ISO \(Int(parsed)) clamped to \(Int(clamped)).")
                    }
                    iso = clamped
                } else {
                    unsupported.append("Custom ISO (\(raw)) — not available on this format.")
                }
            } else if raw.lowercased().contains("as needed") || raw.lowercased() == "low" || raw.lowercased() == "auto" {
                notes.append("ISO “\(raw)” treated as auto / keep low — continuous exposure.")
            } else {
                notes.append("Could not parse ISO “\(raw)”.")
            }
        }

        // EV
        var ev: Float?
        if let raw = dials.evBracket {
            if let parsed = parseEV(raw) {
                if capabilities.supportsExposureTargetBias {
                    ev = clamp(parsed, min: capabilities.minEV, max: capabilities.maxEV)
                } else {
                    unsupported.append("EV compensation not available.")
                }
            }
        }

        // Focus intent from mode / notes
        var focus: MappedSettings.FocusIntent = .continuous
        let blob = ((dials.notes ?? "") + " " + dials.mode.rawValue).lowercased()
        if blob.contains("hyperfocal") || blob.contains("one third") || blob.contains("⅓") {
            focus = .hyperfocalHint
            notes.append("Hyperfocal tip: tap-focus ~⅓ into the frame, then lock focus (Pro).")
        }

        // Mode-driven notes
        switch dials.mode {
        case .shutterPriority:
            notes.append("Recipe wants shutter priority — phone applies fixed shutter + ISO when custom exposure is supported.")
        case .aperturePriority:
            notes.append("Aperture priority mapped to guidance + auto/custom exposure (no f-stop control).")
        case .manual:
            notes.append("Manual recipe — applying shutter/ISO when device allows.")
        case .phoneHdr:
            notes.append("Phone HDR — capture with system processing; manual locks may be limited.")
            unsupported.append("True multi-frame HDR bracket is OS-controlled.")
        case .auto:
            break
        }

        if !capabilities.supportsCustomExposure {
            notes.append("This camera format does not allow locked exposure (common on ultra-wide / some virtual devices).")
        }

        return MappedSettings(
            shutterSeconds: shutter,
            iso: iso,
            evCompensation: ev,
            apertureGuidance: apertureGuidance,
            whiteBalanceTempKelvin: nil,
            focusMode: focus,
            notes: notes,
            unsupported: unsupported
        )
    }

    // MARK: - Parsers

    /// Accepts `1/30`, `1/30s`, `1/200 of a second`, `0.5`, `1/2s`, `20s`, `20 sec`, ranges like `1/2s (day)`.
    static func parseShutter(_ raw: String) -> Double? {
        let s = raw.lowercased()
            .replacingOccurrences(of: "of a second", with: "")
            .replacingOccurrences(of: "seconds", with: "s")
            .replacingOccurrences(of: "second", with: "s")
            .replacingOccurrences(of: "sec", with: "s")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Prefer first fractional or numeric token (handles "1/2s (day) · 20s (night)")
        if let frac = firstMatch(in: s, pattern: #"(\d+)\s*/\s*(\d+)"#) {
            let num = Double(frac[1]) ?? 0
            let den = Double(frac[2]) ?? 1
            guard den != 0 else { return nil }
            return num / den
        }
        if let dec = firstMatch(in: s, pattern: #"(\d+(?:\.\d+)?)\s*s?"#) {
            return Double(dec[1])
        }
        return nil
    }

    static func parseISO(_ raw: String) -> Float? {
        let s = raw.lowercased()
        if s.contains("as needed") || s == "low" || s == "auto" { return nil }
        if let m = firstMatch(in: s, pattern: #"(\d{2,6})"#) {
            return Float(m[1])
        }
        return nil
    }

    static func parseEV(_ raw: String) -> Float? {
        // e.g. "±2 EV", "-1", "+0.7", "0 / ±1 / ±2"
        let s = raw.replacingOccurrences(of: "ev", with: "", options: .caseInsensitive)
        if let m = firstMatch(in: s, pattern: #"([+-]?\d+(?:\.\d+)?)"#) {
            return Float(m[1])
        }
        return nil
    }

    static func parseAperture(_ raw: String) -> Double? {
        let s = raw.lowercased()
        if let m = firstMatch(in: s, pattern: #"f\s*/?\s*(\d+(?:\.\d+)?)"#) {
            return Double(m[1])
        }
        return nil
    }

    static func formatShutter(_ seconds: Double) -> String {
        if seconds >= 1 {
            return String(format: "%.1fs", seconds)
        }
        let denom = max(1, Int((1.0 / seconds).rounded()))
        return "1/\(denom)s"
    }

    private static func clamp<T: Comparable>(_ v: T, min: T, max: T) -> T {
        Swift.min(Swift.max(v, min), max)
    }

    private static func firstMatch(in text: String, pattern: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, options: [], range: range) else { return nil }
        var parts: [String] = []
        for i in 0..<m.numberOfRanges {
            guard let r = Range(m.range(at: i), in: text) else { parts.append(""); continue }
            parts.append(String(text[r]))
        }
        return parts
    }
}

/// Snapshot of what the active AVCaptureDevice can do.
struct DeviceCapabilities: Equatable {
    var supportsCustomExposure: Bool
    var supportsExposureTargetBias: Bool
    var supportsWhiteBalanceLock: Bool
    var supportsFocusLock: Bool
    var minExposureSeconds: Double
    var maxExposureSeconds: Double
    var minISO: Float
    var maxISO: Float
    var minEV: Float
    var maxEV: Float
    var deviceTypeName: String

    static let unknown = DeviceCapabilities(
        supportsCustomExposure: false,
        supportsExposureTargetBias: false,
        supportsWhiteBalanceLock: false,
        supportsFocusLock: false,
        minExposureSeconds: 1.0 / 1000,
        maxExposureSeconds: 1,
        minISO: 50,
        maxISO: 1600,
        minEV: -2,
        maxEV: 2,
        deviceTypeName: "unknown"
    )
}
