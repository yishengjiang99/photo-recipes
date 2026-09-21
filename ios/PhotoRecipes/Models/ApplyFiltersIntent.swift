import Foundation

/// Client-side matcher for APPLY-FILTERS utterances (agentic contract § Apply-filters).
/// Typed Scene/Ask text and STT transcripts use the normal Recommend `message` — no extra flag.
/// If this matches but the Recommend payload has no creativeLook → visible error (server bug).
///
/// Build 25: Camera intent matching uses the **last endpointed utterance only**
/// (not the full accumulated Scene note). Short look tokens like "warm" / "moody"
/// match so a later utterance can replace the prior look.
enum ApplyFiltersIntent {
    /// True when the user is asking to apply a bakeable look/filter/grade now.
    static func matches(_ raw: String) -> Bool {
        let t = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !t.isEmpty else { return false }

        // Explicit apply / grade commands
        let phrases = [
            "apply filters", "apply filter", "add a filter", "add filter",
            "put a filter", "use a filter", "use filter",
            "apply a look", "add a look", "give it a look", "apply look",
            "grade this", "color grade", "colour grade",
            "apply a grade", "add a grade",
        ]
        if phrases.contains(where: { t.contains($0) }) { return true }

        // "make it …" look adjectives
        if t.contains("make it") {
            let looks = [
                "cinematic", "moody", "warm", "cool", "dreamy", "vintage",
                "grainy", "filmic", "film look", "b&w", "bw", "black and white",
                "black & white", "mono", "teal", "golden", "orange",
            ]
            if looks.contains(where: { t.contains($0) }) { return true }
        }

        // Named look / grade shortcuts (with or without "make it")
        let named = [
            "cinematic", "moody film", "warm film", "warm glow", "golden hour look",
            "black and white", "black & white", "b&w", "b and w",
            "teal and orange", "teal orange", "teal & orange",
            "add grain", "film grain", "soft dream", "dreamy look",
            "cool blue", "night grade", "crisp cool", "blockbuster",
            "lo-fi", "lofi", "editorial red", "soft vintage", "mono ink",
        ]
        if named.contains(where: { t.contains($0) }) { return true }

        // Bare look tokens — for short endpointed utterances ("warm", "moody").
        // Prefer whole-utterance / word-boundary so "warming up" in a long note
        // is less likely to false-positive when callers pass full scene text.
        let shortLooks = [
            "warm", "cool", "moody", "cinematic", "grain", "grainy",
            "mono", "vintage", "dreamy", "filmic", "golden",
        ]
        let tokens = t
            .split(whereSeparator: { !$0.isLetter && $0 != "&" })
            .map(String.init)
        if shortLooks.contains(where: { tokens.contains($0) }) { return true }
        // Exact short utterance
        if shortLooks.contains(t) { return true }

        return false
    }

    /// Deterministic B&W → monoInk (mirrors server CREATIVE_LOOK_OVERRIDE_RULES / #119).
    /// Used client-side so spoken B&W still bakes if SSE omits or wrong-looks.
    static func isBlackAndWhite(_ raw: String) -> Bool {
        let t = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !t.isEmpty else { return false }
        if t.contains("black and white") || t.contains("black & white") { return true }
        if t.contains("monochrome") || t.contains("mono ink") { return true }
        // Tokenize so "grab and walk" does not false-positive on "b and w".
        let tokens = t
            .split(whereSeparator: { !$0.isLetter && $0 != "&" })
            .map(String.init)
        if tokens.contains("b&w") || tokens.contains("bw") || tokens.contains("mono") { return true }
        // "b and w" / "b & w" as three tokens
        for i in 0..<tokens.count {
            if tokens[i] == "b" {
                if i + 1 < tokens.count, tokens[i + 1] == "and" || tokens[i + 1] == "&",
                   i + 2 < tokens.count, tokens[i + 2] == "w" {
                    return true
                }
            }
        }
        if t == "bw" || t == "mono" || t == "b&w" { return true }
        return false
    }

    /// Ordered named-look phrases → CreativeLook id (mirrors server CREATIVE_LOOK_OVERRIDE_RULES).
    /// More specific phrases first; first match wins. "apply filters" alone does not force.
    private static let namedLookPhrases: [(phrases: [String], id: String)] = [
        // Short "b and w" / "b&w" / "bw" / "mono" go through isBlackAndWhite (token-safe).
        (["apply black and white filter", "black and white", "black & white",
          "monochrome", "mono ink", "make it black and white"], "monoInk"),
        (["warm pop"], "warmPop"),
        (["crisp cool"], "crispCool"),
        (["editorial red"], "editorialRed"),
        (["soft vintage", "vintage look", "vintage"], "softVintage"),
        (["golden hour"], "goldenHour"),
        (["lo-fi", "lofi", "lo fi punch", "lo fi"], "loFiPunch"),
        (["teal and orange", "teal orange", "teal & orange"], "tealOrange"),
        (["blockbuster", "cinematic"], "blockbuster"),
        (["moody film", "moody"], "moodyFilm"),
        (["cool blue", "night grade"], "coolBlue"),
        (["soft dream", "dreamy"], "softDream"),
        (["film grain", "grainy", "add grain"], "filmGrain"),
        (["warm glow", "warm film", "warm look", "warm"], "warmGlow"),
    ]

    /// Force look for named utterances (B&W + full V1 map). Replaces prior/wrong look.
    static func forcedLook(for message: String) -> CreativeLook? {
        let t = message
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !t.isEmpty else { return nil }

        // Token-level short forms for B&W (bw / mono) — same as isBlackAndWhite.
        if isBlackAndWhite(t) {
            return CreativeLook(id: "monoInk", intensity: CreativeLookCatalog.defaultIntensity)
        }

        for entry in namedLookPhrases {
            if entry.phrases.contains(where: { t.contains($0) || t == $0 }) {
                return CreativeLook(id: entry.id, intensity: CreativeLookCatalog.defaultIntensity)
            }
        }

        // Bare short tokens that are whole utterances / word tokens
        let tokens = t
            .split(whereSeparator: { !$0.isLetter && $0 != "&" && $0 != "-" })
            .map(String.init)
        let bare: [(String, String)] = [
            ("warm", "warmGlow"), ("moody", "moodyFilm"), ("cinematic", "blockbuster"),
            ("vintage", "softVintage"), ("dreamy", "softDream"), ("grainy", "filmGrain"),
            ("lofi", "loFiPunch"),
        ]
        for (token, id) in bare {
            if tokens.contains(token) || t == token {
                return CreativeLook(id: id, intensity: CreativeLookCatalog.defaultIntensity)
            }
        }
        return nil
    }

    /// Prefer nested phoneTargets.creativeLook; accept top-level fallback.
    static func resolvedLook(from response: RecommendResponse) -> CreativeLook? {
        if let look = response.phoneTargets?.creativeLook, !look.id.isEmpty {
            return look
        }
        if let look = response.creativeLook, !look.id.isEmpty {
            return look
        }
        return nil
    }

    /// Merge phoneTargets.creativeLook ← top-level ← forced named look (parity with server overrides).
    /// Nested `phoneTargets.creativeLook` wins over top-level when both are set;
    /// top-level alone still populates targets; forcedLook (B&W / named) always wins last.
    static func mergeCreativeLook(response: RecommendResponse?, message: String?) -> PhoneTargets? {
        var targets = response?.phoneTargets
        if var t = targets {
            if t.creativeLook == nil, let top = response?.creativeLook {
                t.creativeLook = top
                targets = t
            }
        } else if let top = response?.creativeLook {
            var t = PhoneTargets()
            t.creativeLook = top
            targets = t
        }
        if let forced = forcedLook(for: message ?? "") {
            var t = targets ?? PhoneTargets()
            t.creativeLook = forced
            targets = t
        }
        return targets
    }

    /// Camera voice final routing (last endpointed utterance only).
    /// APPLY-FILTERS → Recommend SSE with messageOverride; else Auto Optimize.
    /// Non-empty utterance always cancels in-flight Recommend/AO first (looks don't stack).
    enum VoiceEndpointAction: Equatable {
        case none
        /// Stream recommend with this utterance as `message` (not the full Scene note).
        case recommend(messageOverride: String)
        case optimize
    }

    struct VoiceEndpointPlan: Equatable {
        var cancelInFlight: Bool
        var action: VoiceEndpointAction
    }

    static func planVoiceEndpoint(_ raw: String) -> VoiceEndpointPlan {
        let utterance = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !utterance.isEmpty else {
            return VoiceEndpointPlan(cancelInFlight: false, action: .none)
        }
        if matches(utterance) {
            return VoiceEndpointPlan(
                cancelInFlight: true,
                action: .recommend(messageOverride: utterance)
            )
        }
        return VoiceEndpointPlan(cancelInFlight: true, action: .optimize)
    }

    static let missingLookMessage =
        "No look returned — try again (server should send a creativeLook)"
}
