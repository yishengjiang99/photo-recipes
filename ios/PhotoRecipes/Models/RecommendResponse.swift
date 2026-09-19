import Foundation
import CoreGraphics

struct RecommendResponse: Codable, Hashable {
    var presetId: String?
    var reason: String?
    var tips: [String]?
    var preset: Recipe?
    var model: String?
    var vision: Bool?
    var error: String?
    var code: String?

    // Agentic Auto Optimize (PR #7) — optional; shared apply path consumes phoneTargets.
    var teachWhy: String?
    var phoneTargets: PhoneTargets?
    var coachOnly: CoachOnly?
    var panCue: PanCue?
    var senseSummary: String?
}

/// Phone-settable targets from select_preset (AVFoundation-applicable).
struct PhoneTargets: Codable, Hashable {
    var shutter: String?
    var iso: String?
    /// Exposure compensation, e.g. "+0.7", "0", "-1"
    var ev: String?
    var whiteBalance: String?
    var focusMode: String?
    /// `videoZoomFactor` (1 = 1×). Server may send number or `"2x"` string.
    var zoom: Double?
    /// Normalized focus POI 0…1; omit to use focusMode only.
    var focusPoint: FocusPointNorm?

    enum CodingKeys: String, CodingKey {
        case shutter, iso, ev, whiteBalance, focusMode, zoom, focusPoint
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shutter = try c.decodeIfPresent(String.self, forKey: .shutter)
        iso = try c.decodeIfPresent(String.self, forKey: .iso)
        ev = try c.decodeIfPresent(String.self, forKey: .ev)
        whiteBalance = try c.decodeIfPresent(String.self, forKey: .whiteBalance)
        focusMode = try c.decodeIfPresent(String.self, forKey: .focusMode)
        focusPoint = try c.decodeIfPresent(FocusPointNorm.self, forKey: .focusPoint)
        zoom = Self.decodeZoom(c)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(shutter, forKey: .shutter)
        try c.encodeIfPresent(iso, forKey: .iso)
        try c.encodeIfPresent(ev, forKey: .ev)
        try c.encodeIfPresent(whiteBalance, forKey: .whiteBalance)
        try c.encodeIfPresent(focusMode, forKey: .focusMode)
        try c.encodeIfPresent(zoom, forKey: .zoom)
        try c.encodeIfPresent(focusPoint, forKey: .focusPoint)
    }

    private static func decodeZoom(_ c: KeyedDecodingContainer<CodingKeys>) -> Double? {
        if let d = try? c.decodeIfPresent(Double.self, forKey: .zoom) { return d }
        if let i = try? c.decodeIfPresent(Int.self, forKey: .zoom) { return Double(i) }
        if let s = try? c.decodeIfPresent(String.self, forKey: .zoom) {
            let cleaned = s.lowercased()
                .replacingOccurrences(of: "×", with: "")
                .replacingOccurrences(of: "x", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return Double(cleaned)
        }
        return nil
    }
}

struct FocusPointNorm: Codable, Hashable {
    var x: Double
    var y: Double

    var cgPoint: CGPoint {
        CGPoint(
            x: min(max(x, 0), 1),
            y: min(max(y, 0), 1)
        )
    }
}

/// Coach guidance the device does not auto-apply.
struct CoachOnly: Codable, Hashable {
    var aperture: String?
    var nd: String?
    var tripod: Bool?
    var notes: String?
}

/// Optional pan direction when a motion/panning recipe fits.
struct PanCue: Codable, Hashable {
    /// `left` | `right` | `either`
    var direction: String?
    var note: String?
}

struct RecommendRequest: Encodable {
    var message: String
    var favorites: [String]
    var image: String?
}
