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
    }

    struct DiffLine: Equatable, Identifiable {
        var id: String { label }
        var label: String
        var before: String
        var after: String
        var clamped: Bool
    }

    @Published var phase: Phase = .idle
    @Published var beforeSnapshot: SettingsSnapshot?
    @Published var afterSnapshot: SettingsSnapshot?
    @Published var diffs: [DiffLine] = []
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

    var teachOneLiner: String? {
        let tw = teachWhy?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !tw.isEmpty { return tw }
        return reasonNote
    }

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

    func clear() {
        phase = .idle
        beforeSnapshot = nil; afterSnapshot = nil; diffs = []
        reasonNote = nil; tips = []; chosenRecipeId = nil; chosenRecipeTitle = nil
        verifyWarning = nil; agentBaseline = nil; isDirtyOverride = false
        teachWhy = nil; coachOnly = nil; panCue = nil; senseSummary = nil
    }

    func run(session: CameraSession, entitlements: EntitlementsStore, preferStagedRecipeId: String?, sceneNote: String = "") async {
        guard !phase.isRunning else { return }
        guard canRun(isPro: entitlements.isPro) else {
            phase = .error("Free Peek limit reached — upgrade for unlimited Auto Optimize")
            entitlements.showPaywall = true
            return
        }

        verifyWarning = nil; diffs = []; reasonNote = nil; tips = []; isDirtyOverride = false
        teachWhy = nil; coachOnly = nil; panCue = nil; senseSummary = nil
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

        phase = .applying("Applying \(recipe.title)…")
        try? await Task.sleep(nanoseconds: 280_000_000)

        teachWhy = response.teachWhy
        coachOnly = response.coachOnly
        panCue = response.panCue
        senseSummary = response.senseSummary

        let applied = session.apply(recipe: recipe, asPro: entitlements.isPro)
        // Same apply path for button + Camera voice: overlay agentic phoneTargets when present.
        if let targets = response.phoneTargets {
            _ = session.applyPhoneTargets(targets, asPro: entitlements.isPro)
        }
        session.optimizeReason = teachOneLiner ?? reasonNote

        if !applied && !entitlements.isPro {
            afterSnapshot = recommended(recipe, session)
            diffs = buildDiffs(beforeSnapshot, afterSnapshot, session.clampMessages)
            agentBaseline = afterSnapshot
            phase = .ready
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
        phase = .ready
    }

    private func snap(_ session: CameraSession) -> SettingsSnapshot {
        SettingsSnapshot(
            mode: session.captureMode.shortLabel,
            aperture: session.apertureGuidance,
            shutter: RecipeCameraMapper.formatShutter(session.exposureSeconds),
            iso: "\(Int(session.iso.rounded()))"
        )
    }

    private func recommended(_ recipe: Recipe, _ session: CameraSession) -> SettingsSnapshot {
        let m = RecipeCameraMapper.map(dials: recipe.dials, capabilities: session.capabilities)
        return SettingsSnapshot(
            mode: session.captureMode.shortLabel,
            aperture: m.apertureGuidance ?? recipe.dials.aperture,
            shutter: m.shutterSeconds.map { RecipeCameraMapper.formatShutter($0) } ?? (recipe.dials.shutter ?? "—"),
            iso: m.iso.map { "\(Int($0))" } ?? (recipe.dials.iso ?? "—")
        )
    }

    private func buildDiffs(_ before: SettingsSnapshot?, _ after: SettingsSnapshot?, _ clamps: [String]) -> [DiffLine] {
        guard let before, let after else { return [] }
        var lines: [DiffLine] = []
        if before.mode != after.mode {
            lines.append(.init(label: "MODE", before: before.mode, after: after.mode, clamped: false))
        }
        let ba = before.aperture ?? "—"; let aa = after.aperture ?? "—"
        if ba != aa {
            lines.append(.init(label: "f", before: ba, after: aa, clamped: clamps.contains { $0.lowercased().contains("aperture") }))
        }
        if before.shutter != after.shutter {
            lines.append(.init(label: "S", before: before.shutter, after: after.shutter, clamped: clamps.contains { $0.lowercased().contains("shutter") }))
        }
        if before.iso != after.iso {
            lines.append(.init(label: "ISO", before: before.iso, after: after.iso, clamped: clamps.contains { $0.lowercased().contains("iso") }))
        }
        return lines
    }
}
