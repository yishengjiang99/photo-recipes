import Foundation
import UIKit
import Combine

/// Sense → Reason → Apply → Verify (soft) → Ready
/// Build 3 hybrid:
///   Pass 1 — local (AVFoundation metering + Vision + heuristics) → apply → Ready (no VLM).
///   Pass 2 — optional non-blocking `/api/recommend` refine within the chosen recipe (never blocks shutter).
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

    /// Pass 2 cloud refine — Settings can disable. Default ON (hybrid). Never blocks AO / shutter.
    static let cloudRefineDefaultsKey = "autoOptimize.cloudRefineEnabled"
    /// Back-compat alias for Settings binding.
    static let deepCoachDefaultsKey = cloudRefineDefaultsKey
    static var cloudRefineEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: cloudRefineDefaultsKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: cloudRefineDefaultsKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: cloudRefineDefaultsKey) }
    }
    static var deepCoachEnabled: Bool {
        get { cloudRefineEnabled }
        set { cloudRefineEnabled = newValue }
    }

    /// Pass 2 in flight — pill shows “Ready · refining…”; shutter stays enabled.
    @Published var isCloudRefining = false

    /// Monotonic run id so late Pass 2 responses cannot clobber a newer Optimize.
    private var runGeneration = 0
    private var cloudRefineTask: Task<Void, Never>?

    var teachOneLiner: String? {
        let tw = teachWhy?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !tw.isEmpty { return tw }
        return reasonNote
    }

    /// Status for AgentStatusPill (Ready · look suggested when chip pending).
    var pillStatus: String {
        if let verifyWarning, !verifyWarning.isEmpty { return verifyWarning }
        if case .ready = phase, isCloudRefining { return "Ready · refining…" }
        if case .ready = phase, suggestedLook != nil { return "Ready · look suggested" }
        return phase.statusCopy
    }

    var coreDiffs: [DiffLine] { diffs.filter { $0.tier == .core } }

    private let api: APIClient
    /// Legacy local counter keys (unused for gating Pass 1). Pass 2 consumes server Ask quota.
    private let freeKey = "autoOptimize.freeUses.day"
    private let freeDateKey = "autoOptimize.freeUses.date"
    static let freeDailyLimit = 1

    init(api: APIClient = .shared) { self.api = api }

    /// Pass 1 is local and never quota-gated. Kept for UI badges that still read remaining.
    var freeRemainingToday: Int {
        // Surface server Ask remaining when known; else show local leftover (compat).
        refreshDay()
        return max(0, Self.freeDailyLimit - UserDefaults.standard.integer(forKey: freeKey))
    }

    /// Pass 1 always allowed. Pro still gates *writing* dials via `asPro` in apply paths.
    func canRun(isPro: Bool) -> Bool {
        _ = isPro
        return true
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

    func dismissSuggestedLook() {
        if let look = suggestedLook {
            Analytics.shared.track("look_dismissed", props: ["look_id": look.id, "source": "suggested"])
        }
        suggestedLook = nil
    }

    func applySuggestedLook(session: CameraSession) {
        guard let look = suggestedLook else { return }
        Analytics.shared.track("look_applied", props: ["look_id": look.id, "source": "suggested"])
        session.setActiveLook(look)
        suggestedLook = nil
        phase = .ready
    }

    func clear() {
        cloudRefineTask?.cancel()
        cloudRefineTask = nil
        isCloudRefining = false
        runGeneration &+= 1
        phase = .idle
        beforeSnapshot = nil; afterSnapshot = nil; diffs = []; advancedDiffs = []
        reasonNote = nil; tips = []; chosenRecipeId = nil; chosenRecipeTitle = nil
        verifyWarning = nil; agentBaseline = nil; isDirtyOverride = false
        teachWhy = nil; coachOnly = nil; panCue = nil; senseSummary = nil
        suggestedLook = nil
    }

    /// Local-first Auto Optimize. Happy path never calls the network or a VLM.
    func run(
        session: CameraSession,
        entitlements: EntitlementsStore,
        preferStagedRecipeId: String?,
        sceneNote: String = "",
        devicePitchDegrees: Double? = nil
    ) async {
        guard !phase.isRunning else { return }

        cloudRefineTask?.cancel()
        isCloudRefining = false
        runGeneration &+= 1
        let generation = runGeneration

        PushAnalytics.shared.track(.autoOptimizeStarted)
        Analytics.shared.track("auto_optimize_start", props: ["source": "ios_hybrid_pass1"])
        verifyWarning = nil; diffs = []; advancedDiffs = []; reasonNote = nil; tips = []; isDirtyOverride = false
        teachWhy = nil; coachOnly = nil; panCue = nil; senseSummary = nil
        suggestedLook = nil
        beforeSnapshot = snap(session)
        phase = .sensing("Reading light…")
        try? await Task.sleep(nanoseconds: 120_000_000)

        // Metering first (instant) — no network.
        session.refreshReadouts()
        phase = .sensing("Finding subject…")

        // Optional probe for Vision faces / saliency / histogram — stays on-device.
        var probe: Data?
        do {
            let raw = try await session.captureProbeFrame()
            if let img = UIImage(data: raw), let c = APIClient.compressForVision(img) {
                probe = c
            } else {
                probe = raw
            }
        } catch {
            // Soft-fail: continue with metering-only heuristics.
            probe = nil
            Analytics.shared.track("auto_optimize_probe_soft_fail", props: ["error": error.localizedDescription])
        }

        let signals = await LocalSceneAnalyzer.analyze(
            session: session,
            probeJPEG: probe,
            sceneNote: sceneNote,
            pitchDegrees: devicePitchDegrees
        )
        senseSummary = signals.senseSummary

        phase = .reasoning("Matching a recipe…")
        try? await Task.sleep(nanoseconds: 80_000_000)

        let local = LocalAutoOptimizeEngine.recommend(
            signals: signals,
            preferRecipeId: preferStagedRecipeId,
            capabilities: session.capabilities
        )

        guard let recipe = BundledPresets.recipe(id: local.recipeId) else {
            Analytics.shared.track("auto_optimize_fail", props: ["error_code": "no_recipe", "path": "local"])
            phase = .error("Couldn’t match a recipe — try again")
            return
        }

        chosenRecipeId = recipe.id
        chosenRecipeTitle = recipe.title
        reasonNote = local.reason
        tips = local.tips
        teachWhy = local.teachWhy
        coachOnly = local.coachOnly
        panCue = local.panCue

        phase = .applying("Applying shutter & ISO…")
        try? await Task.sleep(nanoseconds: 120_000_000)

        let notesBefore = session.applyNotes
        let applied = session.apply(recipe: recipe, asPro: entitlements.isPro)
        // Same apply path for button + Camera voice: overlay local phoneTargets.
        _ = session.applyPhoneTargets(local.phoneTargets, asPro: entitlements.isPro)

        if let look = local.suggestedLook, !look.id.isEmpty, CreativeLookCatalog.isKnown(look.id) {
            var suggested = look
            if suggested.intensity == nil {
                suggested.intensity = CreativeLookCatalog.defaultIntensity
            }
            phase = .applying("Suggesting look: \(suggested.displayName)…")
            try? await Task.sleep(nanoseconds: 100_000_000)
            suggestedLook = suggested
            Analytics.shared.track("look_suggested", props: ["look_id": suggested.id, "source": "local"])
        }

        session.optimizeReason = teachOneLiner ?? reasonNote
        advancedDiffs = buildAdvancedDiffs(beforeNotes: notesBefore, afterNotes: session.applyNotes, session: session)

        if !applied && !entitlements.isPro {
            afterSnapshot = recommended(recipe, session)
            diffs = buildDiffs(beforeSnapshot, afterSnapshot, session.clampMessages)
            agentBaseline = afterSnapshot
            phase = .ready
            Analytics.shared.track("auto_optimize_success", props: [
                "recipe_id": recipe.id,
                "coach_only": "true",
                "path": "local",
            ])
            PushNotificationManager.shared.noteFirstSuccessfulAutoOptimize()
            schedulePass2CloudRefine(
                session: session,
                entitlements: entitlements,
                recipe: recipe,
                sceneNote: sceneNote,
                probeJPEG: probe,
                generation: generation,
                wroteDials: false
            )
            return
        }

        session.refreshReadouts()
        afterSnapshot = snap(session)
        diffs = buildDiffs(beforeSnapshot, afterSnapshot, session.clampMessages)
        agentBaseline = afterSnapshot

        phase = .verifying("Checking exposure…")
        try? await Task.sleep(nanoseconds: 150_000_000)
        if let shutter = afterSnapshot?.shutter, let sec = RecipeCameraMapper.parseShutter(shutter), sec >= 1.0 / 60.0 {
            verifyWarning = "Ready · watch handshake at \(shutter)"
            phase = .verifying("Motion risk — holding shutter speed")
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        if suggestedLook != nil { verifyWarning = nil }
        phase = .ready
        Analytics.shared.track("auto_optimize_success", props: [
            "recipe_id": recipe.id,
            "path": "local",
        ])
        PushNotificationManager.shared.noteFirstSuccessfulAutoOptimize()
        schedulePass2CloudRefine(
            session: session,
            entitlements: entitlements,
            recipe: recipe,
            sceneNote: sceneNote,
            probeJPEG: probe,
            generation: generation,
            wroteDials: true
        )
    }

    // MARK: - Pass 2 (cloud refine, non-blocking)

    /// After Pass 1 Ready: optionally call `/api/recommend` to refine dials **within** the chosen recipe.
    /// Never blocks shutter. Soft-fails offline / 402 / errors. Applies only if still same generation + recipe.
    private func schedulePass2CloudRefine(
        session: CameraSession,
        entitlements: EntitlementsStore,
        recipe: Recipe,
        sceneNote: String,
        probeJPEG: Data?,
        generation: Int,
        wroteDials: Bool
    ) {
        guard Self.cloudRefineEnabled else {
            Analytics.shared.track("cloud_refine_skipped", props: ["reason": "disabled", "recipe_id": recipe.id])
            return
        }
        cloudRefineTask?.cancel()
        let recipeId = recipe.id
        let recipeTitle = recipe.title
        let note = sceneNote
        let probe = probeJPEG
        let favorites = Array(entitlements.favoriteIds)
        let isPro = entitlements.isPro

        cloudRefineTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.isCloudRefining = true
            defer {
                if self.runGeneration == generation {
                    self.isCloudRefining = false
                }
            }

            let message = """
            Pass-2 refine for Photo Recipes Auto Optimize.
            Locked recipe: "\(recipeTitle)" (id: \(recipeId)).
            Stay on this preset — refine phoneTargets (shutter/ISO/EV/WB/focus/torch/look intensity) within its dial space and coaching only. Do not switch to a different presetId.
            Sense (on-device): \(self.senseSummary ?? "n/a")
            Photographer note: \(note.isEmpty ? "(none)" : note)
            Focus on exposure triangle and technique — no beauty filters or sky replacement.
            """

            let response: RecommendResponse
            do {
                response = try await self.api.recommend(
                    message: message,
                    favorites: favorites,
                    imageJPEGData: probe
                )
            } catch is CancellationError {
                return
            } catch let APIError.paywall(_) {
                Analytics.shared.track("cloud_refine_skipped", props: [
                    "reason": "quota",
                    "recipe_id": recipeId,
                ])
                return
            } catch {
                Analytics.shared.track("cloud_refine_fail", props: [
                    "error": error.localizedDescription,
                    "recipe_id": recipeId,
                ])
                return
            }

            guard !Task.isCancelled else { return }
            guard self.runGeneration == generation else { return }
            guard self.chosenRecipeId == recipeId else { return }
            guard case .ready = self.phase else { return }

            // Prefer staying on Pass 1 recipe; ignore cloud preset switches.
            let cloudPresetId = response.presetId ?? response.preset?.id
            if let cloudPresetId, cloudPresetId != recipeId {
                Analytics.shared.track("cloud_refine_preset_ignored", props: [
                    "local": recipeId,
                    "cloud": cloudPresetId,
                ])
            }

            if let tw = response.teachWhy?.trimmingCharacters(in: .whitespacesAndNewlines), !tw.isEmpty {
                self.teachWhy = tw
            }
            if let reason = response.reason?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty {
                self.reasonNote = reason
            }
            if let tips = response.tips, !tips.isEmpty {
                self.tips = tips
            }
            if let coach = response.coachOnly {
                self.coachOnly = coach
            }
            if let pan = response.panCue {
                self.panCue = pan
            }
            if let sense = response.senseSummary, !sense.isEmpty {
                self.senseSummary = sense
            }

            if let targets = response.phoneTargets {
                let notesBefore = session.applyNotes
                if wroteDials || isPro {
                    _ = session.applyPhoneTargets(targets, asPro: isPro)
                }
                // Look chip: recipes remain source of truth; look is optional intensity on phoneTargets.
                if let look = targets.creativeLook, !look.id.isEmpty, CreativeLookCatalog.isKnown(look.id) {
                    var suggested = look
                    if suggested.intensity == nil {
                        suggested.intensity = CreativeLookCatalog.defaultIntensity
                    }
                    self.suggestedLook = suggested
                    Analytics.shared.track("look_suggested", props: ["look_id": suggested.id, "source": "cloud_refine"])
                }
                session.optimizeReason = self.teachOneLiner ?? self.reasonNote
                self.advancedDiffs = self.buildAdvancedDiffs(
                    beforeNotes: notesBefore,
                    afterNotes: session.applyNotes,
                    session: session
                )
                if isPro {
                    session.refreshReadouts()
                    self.afterSnapshot = self.snap(session)
                    self.diffs = self.buildDiffs(self.beforeSnapshot, self.afterSnapshot, session.clampMessages)
                    self.agentBaseline = self.afterSnapshot
                }
            }

            Analytics.shared.track("cloud_refine_success", props: [
                "recipe_id": recipeId,
                "wrote": (wroteDials || isPro) ? "true" : "false",
            ])
        }
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
