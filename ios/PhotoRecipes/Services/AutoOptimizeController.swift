import Foundation
import UIKit
import Combine

/// Sense → Reason → Apply → Verify (soft) → Ready
@MainActor
final class AutoOptimizeController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case sensing(String)
        case reasoning(String)
        case applying(String)
        case verifying(String)
        case ready
        case error(String)

        var statusCopy: String {
            switch self {
            case .idle: return ""
            case .sensing(let s): return s
            case .reasoning(let s): return s
            case .applying(let s): return s
            case .verifying(let s): return s
            case .ready: return "Ready to capture"
            case .error(let s): return s
            }
        }

        var isRunning: Bool {
            switch self {
            case .sensing, .reasoning, .applying, .verifying: return true
            default: return false
            }
        }
    }

    struct SettingsSnapshot: Equatable {
        var mode: String
        var aperture: String?
        var shutter: String
        var iso: String
        var ev: String
        var wb: String
        var focus: String
    }

    struct DiffLine: Equatable, Identifiable {
        var id: String { label }
        var label: String
        var before: String
        var after: String
        var clamped: Bool
        /// Tier: core (always chips) vs advanced (Teach / More changes)
        var tier: Tier = .core
        enum Tier: String, Equatable { case core, advanced }
    }

    @Published var phase: Phase = .idle
    @Published var beforeSnapshot: SettingsSnapshot?
    @Published var afterSnapshot: SettingsSnapshot?
    @Published var diffs: [DiffLine] = []
    @Published var advancedDiffs: [DiffLine] = []
    @Published var reasonNote: String?
    @Published var tips: [String] = []
    @Published var chosenRecipeId: String?
    @Published var chosenRecipeTitle: String?
    @Published var verifyWarning: String?
    @Published var agentBaseline: SettingsSnapshot?
    @Published var isDirtyOverride = false
    @Published var teachWhy: String?
    @Published var coachOnly: CoachOnly?
    @Published var panCue: PanCue?
    @Published var senseSummary: String?
    /// Suggested look from Auto Optimize — never silent apply (Apply / Dismiss chip).
    @Published var suggestedLook: CreativeLook?

    var teachOneLiner: String? {
        let tw = teachWhy?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !tw.isEmpty { return tw }
        return reasonNote
    }

    /// Status for AgentStatusPill (Ready · look suggested when chip pending).
    var pillStatus: String {
        if let verifyWarning, !verifyWarning.isEmpty { return verifyWarning }
        if case .ready = phase, suggestedLook != nil { return "Ready · look suggested" }
        return phase.statusCopy
    }

    var coreDiffs: [DiffLine] { diffs.filter { $0.tier == .core } }

    private let api: APIClient
    private let freeKey = "autoOptimize.freeUses.day"
    private let freeDateKey = "autoOptimize.freeUses.date"
    static let freeDailyLimit = 1

    init(api: APIClient = .shared) { self.api = api }

    var freeRemainingToday: Int {
        refreshDay()
        return max(0, Self.freeDailyLimit - UserDefaults.standard.integer(forKey: freeKey))
    }

    func canRun(isPro: Bool) -> Bool { isPro || freeRemainingToday > 0 }

    private func consumeFree(isPro: Bool) {
        guard !isPro else { return }
        refreshDay()
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: freeKey) + 1, forKey: freeKey)
        objectWillChange.send()
    }

    private func refreshDay() {
        let f = DateFormatter(); f.calendar = Calendar.current; f.dateFormat = "yyyy-MM-dd"
        let today = f.string(from: Date())
        if UserDefaults.standard.string(forKey: freeDateKey) != today {
            UserDefaults.standard.set(today, forKey: freeDateKey)
            UserDefaults.standard.set(0, forKey: freeKey)
        }
    }

    func resetToAgent(session: CameraSession) {
        guard agentBaseline != nil else { return }
        if let id = chosenRecipeId, let recipe = BundledPresets.recipe(id: id) {
            _ = session.apply(recipe: recipe, asPro: true)
        }
        afterSnapshot = agentBaseline
        isDirtyOverride = false
        phase = .ready
    }

    func markDirty() { isDirtyOverride = true }

    func dismissSuggestedLook() { suggestedLook = nil }

    func applySuggestedLook(session: CameraSession) {
        guard let look = suggestedLook else { return }
        session.setActiveLook(look)
        suggestedLook = nil
        phase = .ready
    }

    func clear() {
        phase = .idle
        beforeSnapshot = nil; afterSnapshot = nil; diffs = []; advancedDiffs = []
        reasonNote = nil; tips = []; chosenRecipeId = nil; chosenRecipeTitle = nil
        verifyWarning = nil; agentBaseline = nil; isDirtyOverride = false
        teachWhy = nil; coachOnly = nil; panCue = nil; senseSummary = nil
        suggestedLook = nil
    }

    func run(session: CameraSession, entitlements: EntitlementsStore, preferStagedRecipeId: String?, sceneNote: String = "") async {
        guard !phase.isRunning else { return }
        guard canRun(isPro: entitlements.isPro) else {
            phase = .error("Free Peek limit reached — upgrade for unlimited Auto Optimize")
            entitlements.showPaywall = true
            return
        }

        PushAnalytics.shared.track(.autoOptimizeStarted)
        verifyWarning = nil; diffs = []; advancedDiffs = []; reasonNote = nil; tips = []; isDirtyOverride = false
        teachWhy = nil; coachOnly = nil; panCue = nil; senseSummary = nil
        suggestedLook = nil
        beforeSnapshot = snap(session)
        phase = .sensing("Reading light…")
        try? await Task.sleep(nanoseconds: 350_000_000)
        phase = .sensing("Finding subject…")

        let probe: Data
        do {
            let raw = try await session.captureProbeFrame()
            if let img = UIImage(data: raw), let c = APIClient.compressForVision(img) { probe = c }
            else { probe = raw }
        } catch {
            phase = .error(error.localizedDescription); return
        }

        phase = .reasoning("Matching a recipe…")
        let message = """
        Auto Optimize for live capture. Prefer a field recipe from the book presets.         Respond with the best preset for this scene and a short reason.         Focus on exposure triangle and technique — no beauty filters or sky replacement.
        """
        let note = sceneNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let messageWithNote = note.isEmpty ? message : message + "\nPhotographer scene note: \(note)"

        let response: RecommendResponse
        do {
            response = try await api.recommend(
                message: messageWithNote,
                favorites: Array(entitlements.favoriteIds),
                imageJPEGData: probe
            )
        } catch let APIError.paywall(p) {
            phase = .error(p.error ?? "Free Peek limit reached")
            entitlements.showPaywall = true
            return
        } catch {
            phase = .error(error.localizedDescription); return
        }

        consumeFree(isPro: entitlements.isPro)

        var recipe: Recipe?
        if let preferred = preferStagedRecipeId.flatMap({ BundledPresets.recipe(id: $0) }) {
            recipe = preferred
            phase = .reasoning("Using \(preferred.title)…")
        }
        if recipe == nil {
            recipe = response.preset ?? response.presetId.flatMap { BundledPresets.recipe(id: $0) }
        }
        guard let recipe else {
            phase = .error("Couldn’t match a recipe — try again"); return
        }

        chosenRecipeId = recipe.id
        chosenRecipeTitle = recipe.title
        reasonNote = response.reason
        tips = response.tips ?? recipe.tips

        phase = .applying("Applying shutter & ISO…")
        try? await Task.sleep(nanoseconds: 280_000_000)

        teachWhy = response.teachWhy
        coachOnly = response.coachOnly
        panCue = response.panCue
        senseSummary = response.senseSummary

        let notesBefore = session.applyNotes
        let applied = session.apply(recipe: recipe, asPro: entitlements.isPro)
        // Same apply path for button + Camera voice: overlay agentic phoneTargets when present.
        if let targets = response.phoneTargets {
            _ = session.applyPhoneTargets(targets, asPro: entitlements.isPro)
            // Suggest look — never silent apply (chip Apply / Dismiss).
            if let look = targets.creativeLook, !look.id.isEmpty, CreativeLookCatalog.isKnown(look.id) {
                var suggested = look
                if suggested.intensity == nil {
                    suggested.intensity = CreativeLookCatalog.defaultIntensity
                }
                phase = .applying("Suggesting look: \(suggested.displayName)…")
                try? await Task.sleep(nanoseconds: 220_000_000)
                suggestedLook = suggested
            }
        }
        session.optimizeReason = teachOneLiner ?? reasonNote

        advancedDiffs = buildAdvancedDiffs(beforeNotes: notesBefore, afterNotes: session.applyNotes, session: session)

        if !applied && !entitlements.isPro {
            afterSnapshot = recommended(recipe, session)
            diffs = buildDiffs(beforeSnapshot, afterSnapshot, session.clampMessages)
            agentBaseline = afterSnapshot
            phase = .ready
            PushNotificationManager.shared.noteFirstSuccessfulAutoOptimize()
            return
        }

        session.refreshReadouts()
        afterSnapshot = snap(session)
        diffs = buildDiffs(beforeSnapshot, afterSnapshot, session.clampMessages)
        agentBaseline = afterSnapshot

        phase = .verifying("Checking exposure…")
        try? await Task.sleep(nanoseconds: 300_000_000)
        if let shutter = afterSnapshot?.shutter, let sec = RecipeCameraMapper.parseShutter(shutter), sec >= 1.0/60.0 {
            verifyWarning = "Ready · watch handshake at \(shutter)"
            phase = .verifying("Motion risk — holding shutter speed")
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        // Clear motion verifyWarning so look-suggested ready status can show; keep handshake in tips if needed.
        if suggestedLook != nil { verifyWarning = nil }
        phase = .ready
        PushNotificationManager.shared.noteFirstSuccessfulAutoOptimize()
    }

    private func snap(_ session: CameraSession) -> SettingsSnapshot {
        SettingsSnapshot(
            mode: session.captureMode.shortLabel,
            aperture: session.apertureGuidance,
            shutter: RecipeCameraMapper.formatShutter(session.exposureSeconds),
            iso: "\(Int(session.iso.rounded()))",
            ev: String(format: "%+.1f", session.evBias),
            wb: session.whiteBalanceLocked ? "Locked" : "Auto",
            focus: session.focusLocked ? "Locked" : "Cont."
        )
    }

    private func recommended(_ recipe: Recipe, _ session: CameraSession) -> SettingsSnapshot {
        let m = RecipeCameraMapper.map(dials: recipe.dials, capabilities: session.capabilities)
        return SettingsSnapshot(
            mode: session.captureMode.shortLabel,
            aperture: m.apertureGuidance ?? recipe.dials.aperture,
            shutter: m.shutterSeconds.map { RecipeCameraMapper.formatShutter($0) } ?? (recipe.dials.shutter ?? "—"),
            iso: m.iso.map { "\(Int($0))" } ?? (recipe.dials.iso ?? "—"),
            ev: String(format: "%+.1f", session.evBias),
            wb: session.whiteBalanceLocked ? "Locked" : "Auto",
            focus: session.focusLocked ? "Locked" : "Cont."
        )
    }

    private func buildDiffs(_ before: SettingsSnapshot?, _ after: SettingsSnapshot?, _ clamps: [String]) -> [DiffLine] {
        guard let before, let after else { return [] }
        var lines: [DiffLine] = []
        func add(_ label: String, _ b: String, _ a: String, clampedHint: String? = nil) {
            guard b != a else { return }
            let clamped = clampedHint.map { h in clamps.contains { $0.lowercased().contains(h) } } ?? false
            lines.append(.init(label: label, before: b, after: a, clamped: clamped, tier: .core))
        }
        add("MODE", before.mode, after.mode)
        add("f", before.aperture ?? "—", after.aperture ?? "—", clampedHint: "aperture")
        add("Shutter", before.shutter, after.shutter, clampedHint: "shutter")
        add("ISO", before.iso, after.iso, clampedHint: "iso")
        add("EV", before.ev, after.ev)
        add("WB", before.wb, after.wb)
        add("Focus", before.focus, after.focus)
        return lines
    }

    private func buildAdvancedDiffs(beforeNotes: [String], afterNotes: [String], session: CameraSession) -> [DiffLine] {
        let added = afterNotes.filter { !beforeNotes.contains($0) }
        var lines: [DiffLine] = []
        for note in added {
            let lower = note.lowercased()
            if lower.contains("look") { continue } // Look has its own Teach section
            let label: String = {
                if lower.contains("torch") { return "Torch" }
                if lower.contains("flash") { return "Flash" }
                if lower.contains("low-light") || lower.contains("low light") { return "Low-light" }
                if lower.contains("hdr") { return "Video HDR" }
                if lower.contains("zoom") { return "Zoom" }
                if lower.contains("lens") { return "Lens" }
                if lower.contains("bracket") { return "Bracket" }
                if lower.contains("frame") || lower.contains("fps") { return "FPS" }
                if lower.contains("wb") || lower.contains("white") { return "WB" }
                return "Advanced"
            }()
            lines.append(.init(label: label, before: "—", after: note, clamped: false, tier: .advanced))
        }
        if session.torchOn {
            lines.append(.init(label: "Torch", before: "Off", after: "On", clamped: false, tier: .advanced))
        }
        if session.lowLightBoostOn {
            lines.append(.init(label: "Low-light", before: "Off", after: "On", clamped: false, tier: .advanced))
        }
        // Dedupe by label keeping last
        var seen = Set<String>()
        return lines.reversed().filter { seen.insert($0.label).inserted }.reversed()
    }
}
