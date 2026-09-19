import Foundation

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
    var direction: String?
    var note: String?
}

struct RecommendRequest: Encodable {
    var message: String
    var favorites: [String]
    var image: String?
}
