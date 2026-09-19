import Foundation

/// Capture grade (V1 look pack). Baked into preview + still when intensity > 0 — not a beauty filter.
struct CreativeLook: Codable, Hashable, Identifiable {
    var id: String
    /// Blend 0…1 (0 = identity, 1 = full look). Default when agent omits: 0.55.
    var intensity: Double?

    enum CodingKeys: String, CodingKey { case id, intensity }

    init(id: String, intensity: Double? = nil) {
        self.id = id
        if let intensity {
            self.intensity = min(max(intensity, 0), 1)
        } else {
            self.intensity = nil
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        if let d = try? c.decodeIfPresent(Double.self, forKey: .intensity) {
            intensity = min(max(d, 0), 1)
        } else if let i = try? c.decodeIfPresent(Int.self, forKey: .intensity) {
            intensity = min(max(Double(i), 0), 1)
        } else {
            intensity = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(intensity, forKey: .intensity)
    }

    /// Resolved intensity for UI / preview (agent default ~0.55).
    var resolvedIntensity: Double { intensity ?? CreativeLookCatalog.defaultIntensity }

    var displayName: String { CreativeLookCatalog.displayName(for: id) }
    var craftSentence: String { CreativeLookCatalog.craftSentence(for: id) }
}

enum CreativeLookCatalog {
    static let defaultIntensity: Double = 0.55

    /// Exact V1 ids from server `CREATIVE_LOOK_IDS` / design-handoff-capabilities-comms-v1.
    static let allIds: [String] = [
        "crispCool", "warmGlow", "warmPop", "editorialRed", "softVintage", "monoInk",
        "goldenHour", "loFiPunch", "tealOrange", "blockbuster", "moodyFilm", "coolBlue",
        "softDream", "filmGrain",
    ]

    static let displayNames: [String: String] = [
        "crispCool": "Crisp Cool",
        "warmGlow": "Warm Glow",
        "warmPop": "Warm Pop",
        "editorialRed": "Editorial Red",
        "softVintage": "Soft Vintage",
        "monoInk": "Mono Ink",
        "goldenHour": "Golden Hour",
        "loFiPunch": "Lo-Fi Punch",
        "tealOrange": "Teal & Orange",
        "blockbuster": "Blockbuster",
        "moodyFilm": "Moody Film",
        "coolBlue": "Cool Blue",
        "softDream": "Soft Dream",
        "filmGrain": "Film Grain",
    ]

    /// One craft sentence for Teach — capture grade language, never “filter” / beauty.
    static let craftSentences: [String: String] = [
        "crispCool": "Cool contrast for overcast steel and clean edges.",
        "warmGlow": "Gentle warmth that lifts midtones without washing skin.",
        "warmPop": "Punchy warm grade for golden subjects and street color.",
        "editorialRed": "Editorial red bias for fashion / product stills.",
        "softVintage": "Soft faded curve — quiet nostalgia, not a beauty pass.",
        "monoInk": "High-contrast monochrome ink for graphic silhouettes.",
        "goldenHour": "Golden warmth with a soft sky lift for late light.",
        "loFiPunch": "Lo-fi contrast punch with a quiet edge vignette feel.",
        "tealOrange": "Complementary teal shadows / orange midtones — cinema grade.",
        "blockbuster": "Wide cinematic contrast with cool shadow hold.",
        "moodyFilm": "Lower mid key, filmic curve, restrained chroma.",
        "coolBlue": "Cool blue cast with crisp shadow separation.",
        "softDream": "Soft lift and dreamy low contrast for haze / mist.",
        "filmGrain": "Subtle grain texture plus a mild film curve.",
    ]

    static func displayName(for id: String) -> String {
        displayNames[id] ?? id
    }

    static func craftSentence(for id: String) -> String {
        craftSentences[id] ?? "Capture grade for this light — intensity blends the look into preview and still."
    }

    static func isKnown(_ id: String) -> Bool {
        allIds.contains(id)
    }

    static var catalog: [CreativeLook] {
        allIds.map { CreativeLook(id: $0, intensity: defaultIntensity) }
    }
}
