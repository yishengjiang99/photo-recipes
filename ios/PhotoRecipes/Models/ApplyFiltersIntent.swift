import Foundation

/// Client-side matcher for APPLY-FILTERS utterances (agentic contract § Apply-filters).
/// Typed Scene/Ask text and STT transcripts use the normal Recommend `message` — no extra flag.
/// If this matches but the Recommend payload has no creativeLook → visible error (server bug).
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
                "black & white", "mono", "teal", "golden",
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

        return false
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
