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

    /// Deterministic B&W → monoInk (mirrors server BW_LOOK_RE / #119).
    /// Used client-side so spoken B&W still bakes if SSE omits or wrong-looks.
    static func isBlackAndWhite(_ raw: String) -> Bool {
        let t = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !t.isEmpty else { return false }
        if t.contains("black and white") || t.contains("black & white") { return true }
        if t.contains("b&w") || t.contains("b & w") || t.contains("b and w") { return true }
        if t.contains("monochrome") { return true }
        let tokens = t
            .split(whereSeparator: { !$0.isLetter && $0 != "&" })
            .map(String.init)
        if tokens.contains("bw") || tokens.contains("mono") || tokens.contains("b&w") { return true }
        if t == "bw" || t == "mono" || t == "b&w" { return true }
        return false
    }

    /// Force look when utterance is B&W (replaces prior/wrong look).
    static func forcedLook(for message: String) -> CreativeLook? {
        guard isBlackAndWhite(message) else { return nil }
        return CreativeLook(id: "monoInk", intensity: CreativeLookCatalog.defaultIntensity)
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

    static let missingLookMessage =
        "No look returned — try again (server should send a creativeLook)"
}
