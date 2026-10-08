import Foundation
import Combine
import os
import os.log
import UIKit

// MARK: - os_signpost latency instrumentation (tap → applied)
//
// PENDING device numbers: measure in Instruments with the os_signpost
// instrument on the "AutoOptimize" category. The interval
// `auto_optimize` spans from the Auto Optimize tap (`begin`) to the moment
// the controller reaches Ready or Error (`end`, with the outcome attached).
// The wall-clock tap→ready number is ALSO attached to the
// `auto_optimize_success` analytics event as `latency_ms` so it can be read
// from telemetry without a device in hand.

enum AOPerf {
    private static let log = OSLog(subsystem: "com.ragnus.mvp", category: "AutoOptimize")

    /// Begin the tap→applied interval. Returns an opaque id for `end(_:outcome:)`.
    static func begin(runId: String) -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "auto_optimize", signpostID: id,
                    "tap-to-applied run %{public}s", runId)
        return id
    }

    static func end(_ id: OSSignpostID, outcome: String) {
        os_signpost(.end, log: log, name: "auto_optimize", signpostID: id,
                    "outcome %{public}s", outcome)
    }
}

@MainActor
final class AutoOptimizeController: ObservableObject {
    enum Phase {
        case idle
        case sensing(String)
        case reasoning(String)
        case applying(String)
        case verifying(String)
        case ready
        case error(String)

        var isRunning: Bool {
            switch self {
            case .sensing, .reasoning, .applying, .verifying: true
            case .idle, .ready, .error: false
            }
        }

        var statusCopy: String {
            switch self {
            case .idle: return "Auto Optimize"
            case .sensing(let s): return s
            case .reasoning(let s): return s
            case .applying(let s): return s
            case .verifying(let s): return s
            case .ready: return "Ready"
            case .error(let msg): return msg
            }
        }
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
    /// Bumps when Pass 1 / Pass 2 successfully writes dials — CameraView shows on-finder apply burst.
    @Published var applyFeedbackToken: Int = 0
    /// Look id auto-applied by the last run (for look_undone telemetry).
    @Published var autoAppliedLookId: String?
    /// Runner-up chip: one-tap switch when the top recipe is uncertain.
    @Published var alsoTryRecipeId: String?
    @Published var alsoTryRecipeTitle: String?
    @Published var alsoTryProbability: Double?
    /// Set when the scene materially changed after Ready — UI shows
    /// "Scene changed — re-optimize?". Never triggers a silent re-run.
    @Published var sceneChangedSuggestion: String?
    /// Monotonic id of the last run (ties outcome telemetry to the run).
    private(set) var lastRunId: String?
    /// When the last run finished — photo-captured outcomes count within 30 s.
    private(set) var lastRunDate: Date?
    /// Trigger of the last run: manual / auto_first_capture / subject_change / voice / deep_link / teach.
    private(set) var lastTrigger: String = "manual"
    /// Run id for which a manual dial override was already tracked (one per run).
    private var overrideTrackedForRun: String?

    /// Set when the user undoes an Auto Optimize — never auto-run again for this install.
    static let userUndidKey = "autoOptimize.userUndid"

    private let log = Logger(subsystem: "com.ragnus.mvp", category: "AutoOptimize")

    /// Pass 2 cloud refine — Settings can disable. Default OFF (local-first).
    static let cloudRefineDefaultsKey = "autoOptimize.cloudRefineEnabled"
    /// Back-compat alias for Settings binding.
    static let deepCoachDefaultsKey = cloudRefineDefaultsKey
    static var cloudRefineEnabled: Bool {
        get {
            // Local-first: Pass 1 on-device is the happy path. Pass 2 cloud refine opt-in.
            if UserDefaults.standard.object(forKey: cloudRefineDefaultsKey) == nil { return false }
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
    private var sceneWatchTask: Task<Void, Never>?
    /// The scorer behind Pass 1 (JSON v1 default; Core ML opt-in via Settings).
    private let scorer: RecipeScoring = RecipeScorerSelector.scorer()

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
    /// Fallback when subscription-status has not loaded (matches server FREE_DAILY_LIMIT default from #71).
    static let freeDailyLimit = FreeOptimizeQuota.defaultDailyLimit

    init(api: APIClient = .shared) { self.api = api }

    /// Successful-output quota (welcome window: 10 in first 24h, then daily limit).
    var quota: FreeOptimizeQuota { FreeOptimizeQuota() }

    var freeRemainingToday: Int {
        quota.remaining(serverDailyLimit: nil)
    }

    /// Local AO quota counts successful optimizes on device (local AO never hits the server,
    /// so server `asksRemaining` — the Ask/Recommend pool — is not used here).
    func freeRemainingToday(entitlements: EntitlementsStore) -> Int {
        quota.remaining(serverDailyLimit: entitlements.status.freeDailyLimit)
    }

    func canRun(isPro: Bool) -> Bool {
        isPro || freeRemainingToday > 0
    }

    /// Pro / unlimited allowlist / asksLimit == nil → unlimited. Else free successful-output pool.
    func canRun(entitlements: EntitlementsStore) -> Bool {
        if isUnlimitedAsk(entitlements) { return true }
        return freeRemainingToday(entitlements: entitlements) > 0
    }

    /// Called only on optimize success — failures, timeouts and cancels never consume.
    private func consumeSharedFreeIfNeeded(_ entitlements: EntitlementsStore) {
        quota.recordSuccess(countsAgainstFree: !isUnlimitedAsk(entitlements))
        objectWillChange.send()
    }

    /// Server Ask identity is unlimited when asksLimit is nil (Pro or allowlists from #71).
    private func isUnlimitedAsk(_ entitlements: EntitlementsStore) -> Bool {
        entitlements.isPro
            || entitlements.status.unlimited == true
            || entitlements.status.asksLimit == nil
    }

    func resetToAgent(session: CameraSession) {
        guard agentBaseline != nil else { return }
        if let id = chosenRecipeId, let recipe = BundledPresets.recipe(id: id) {
            _ = session.apply(recipe: recipe)
        }
        afterSnapshot = agentBaseline
        isDirtyOverride = false
        phase = .ready
    }

    func markDirty() {
        isDirtyOverride = true
        // Manual dial override after an optimize — outcome of that run, once per run.
        if let runId = lastRunId, overrideTrackedForRun != runId {
            overrideTrackedForRun = runId
            Analytics.shared.track("optimize_dial_override", props: [
                "recipe_id": chosenRecipeId ?? "",
                "trigger": lastTrigger,
                "run_id": runId,
            ])
        }
    }

    func dismissSuggestedLook() {
        if let look = suggestedLook {
            Analytics.shared.track("look_dismissed", props: ["look_id": look.id, "source": "suggested"])
        }
        suggestedLook = nil
    }

    /// Persistent Undo: restore the pre-optimize camera (auto exposure / focus, no look / LUT).
    func undo(session: CameraSession) {
        let lookId = session.activeCreativeLook?.id
        Analytics.shared.track("optimize_undone", props: [
            "recipe_id": chosenRecipeId ?? "",
            "trigger": lastTrigger,
            "had_look": lookId == nil ? "0" : "1",
            "run_id": lastRunId ?? "",
        ])
        if let lookId, lookId == autoAppliedLookId {
            Analytics.shared.track("look_undone", props: [
                "look_id": lookId,
                "auto_applied": "1",
                "rank": "1",
                "source": "undo",
            ])
        }
        UserDefaults.standard.set(true, forKey: Self.userUndidKey)
        session.clearRecipe()
        clear()
    }

    func applySuggestedLook(session: CameraSession) {
        guard let look = suggestedLook else { return }
        Analytics.shared.track("look_applied", props: ["look_id": look.id, "source": "suggested", "rank": "1", "auto_applied": "0"])
        session.setActiveLook(look)
        suggestedLook = nil
        phase = .ready
    }

    func clear() {
        cloudRefineTask?.cancel()
        cloudRefineTask = nil
        sceneWatchTask?.cancel()
        sceneWatchTask = nil
        isCloudRefining = false
        runGeneration &+= 1
        phase = .idle
        beforeSnapshot = nil; afterSnapshot = nil; diffs = []; advancedDiffs = []
        reasonNote = nil; tips = []; chosenRecipeId = nil; chosenRecipeTitle = nil
        verifyWarning = nil; agentBaseline = nil; isDirtyOverride = false
        teachWhy = nil; coachOnly = nil; panCue = nil; senseSummary = nil
        suggestedLook = nil
        autoAppliedLookId = nil
        alsoTryRecipeId = nil; alsoTryRecipeTitle = nil; alsoTryProbability = nil
        sceneChangedSuggestion = nil
        applyFeedbackToken = 0
    }

    // MARK: - Pass 1 (on-device ML loop: features → score → solve → apply → verify)

    /// Local-first Auto Optimize. The happy path never calls the network.
    ///
    /// 1. Features: the `SceneSensor` snapshot (refreshed synchronously on tap
    ///    when stale > 1 s).
    /// 2. Score: `RecipeScorer` over all ten bundled recipes (the reference
    ///    card is never a candidate); a staged recipe skips scoring.
    /// 3. Solve: `SettingsSolver` turns the recipe + features into dial targets.
    /// 4. Apply: `applyPhoneTargets` — never `setEV` after custom exposure.
    /// 5. Verify: 300 ms settle + read-back; one ISO nudge when the exposure
    ///    offset is > 1 stop off; diff chips show read-back values.
    func run(
        session: CameraSession,
        entitlements: EntitlementsStore,
        preferStagedRecipeId: String?,
        sceneNote: String = "",
        elevationDegrees: Double? = nil,
        handShake: Double? = nil,
        trigger: String = "manual",
        parentRunId: String? = nil
    ) async {
        guard !phase.isRunning else {
            log.info("run skipped — already running")
            return
        }
        guard canRun(entitlements: entitlements) else {
            phase = .error("Free Peek limit reached — try again tomorrow or go Pro")
            Analytics.shared.track("auto_optimize_fail", props: ["error_code": "quota", "error_class": "quota", "path": "local", "trigger": trigger])
            log.info("run blocked — quota")
            return
        }

        cloudRefineTask?.cancel()
        isCloudRefining = false
        sceneWatchTask?.cancel()
        runGeneration &+= 1
        let generation = runGeneration
        lastTrigger = trigger
        let startedAt = Date()
        let runId = UUID().uuidString
        lastRunId = runId
        lastRunDate = Date()
        let perfId = AOPerf.begin(runId: runId)
        let isFirstSuccessPending = !UserDefaults.standard.bool(
            forKey: PushNotificationManager.hasCompletedFirstAutoOptimizeKey
        )
        let allowCloudRefine = isFirstSuccessPending || Self.cloudRefineEnabled

        func wasCancelled(stage: String) -> Bool {
            guard runGeneration != generation else { return false }
            Analytics.shared.track("auto_optimize_cancel", props: [
                "latency_ms": "\(Int(Date().timeIntervalSince(startedAt) * 1000))",
                "stage": stage,
            ])
            AOPerf.end(perfId, outcome: "cancelled")
            return true
        }

        // --- 1. Features -----------------------------------------------------
        phase = .sensing("Reading scene…")
        let metering = session.meteringSample()
        await SceneSensor.shared.updateMetering(metering)
        if let elevationDegrees, let handShake {
            await SceneSensor.shared.updatePose(elevationDegrees: elevationDegrees, handShakeRadPerSec: handShake)
        }

        let features: SceneFeatures
        do {
            var snapshot = await SceneSensor.shared.current()
            if snapshot.age > 1.0 {
                // Snapshot older than 1 s — one synchronous full pass before scoring.
                phase = .sensing("Reading light…")
                guard let fresh = await SceneSensor.shared.refreshNow(metering: metering, note: sceneNote) else {
                    phase = .error("Camera not ready — try again")
                    Analytics.shared.track("auto_optimize_fail", props: [
                        "error_code": "no_frame", "error_class": "no_frame",
                        "path": "local", "trigger": trigger,
                    ])
                    AOPerf.end(perfId, outcome: "no-frame")
                    return
                }
                snapshot = fresh
            }
            var f = snapshot.features
            // Stamp tap-time state: the note (intent) the user typed, the live
            // metering, and the pose from this exact tap.
            f.recipeIntent = IntentMatcher.match(note: sceneNote)
            f.meteredExposureSeconds = metering.exposureSeconds
            f.meteredISO = metering.iso
            f.exposureTargetOffset = metering.exposureTargetOffset
            f.exposureWasCustom = metering.exposureWasCustom
            if let elevationDegrees { f.cameraElevationDegrees = Float(elevationDegrees) }
            if let handShake { f.handShakeRadPerSec = Float(handShake) }
            features = f
        }

        // --- 2. Score ---------------------------------------------------------
        if wasCancelled(stage: "sense") { return }
        phase = .reasoning("Matching a recipe…")
        let scores = scorer.score(features)
        guard let decision = RecipeDecider.decide(
            scores: scores,
            features: features,
            stagedRecipeId: preferStagedRecipeId
        ) else {
            phase = .error("No recipe matched the scene — try again")
            Analytics.shared.track("auto_optimize_fail", props: [
                "error_code": "no_recipe", "error_class": "no_recipe",
                "path": "local", "trigger": trigger,
            ])
            AOPerf.end(perfId, outcome: "no-recipe")
            return
        }

        guard let recipe = BundledPresets.recipe(id: decision.recipeId) else {
            phase = .error("Unknown recipe — try again")
            AOPerf.end(perfId, outcome: "unknown-recipe")
            return
        }

        // --- 3. Solve ----------------------------------------------------------
        let solveContext = SettingsSolver.SolveContext(
            frameWidthPx: session.videoFrameWidth ?? 1920,
            fieldOfViewDegrees: session.activeFieldOfViewDegrees() ?? 70,
            currentWBGains: session.currentWhiteBalanceGains()
        )
        let solution = SettingsSolver.solve(
            recipeId: recipe.id,
            features: features,
            capabilities: session.capabilities,
            context: solveContext
        )

        // --- 4. Apply ----------------------------------------------------------
        if wasCancelled(stage: "apply") { return }
        phase = .applying("Applying \(decision.recipeTitle)…")
        beforeSnapshot = snap(session)
        var wroteTargets = false
        if entitlements.canApplyDials {
            wroteTargets = session.applyPhoneTargets(solution.phoneTargets)
        }
        session.clampMessages.append(contentsOf: solution.clampMessages)

        // Coach-only path (free tier: dials locked) — show the solved values.
        if !entitlements.canApplyDials {
            afterSnapshot = recommendedSnapshot(from: solution, session: session)
            agentBaseline = afterSnapshot
            diffs = buildDiffs(beforeSnapshot, afterSnapshot, session.clampMessages)
            publishDecision(decision, recipe: recipe, features: features, solution: solution, session: session)
            phase = .ready
            applyFeedbackToken &+= 1
            let latencyMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            log.info("ready (coach-only) recipe=\(recipe.id, privacy: .public) latency=\(latencyMs)ms")
            Analytics.shared.track("auto_optimize_success", props: [
                "recipe_id": recipe.id,
                "latency_ms": "\(latencyMs)",
                "path": "local",
                "coach_only": "1",
                "run_id": runId,
                "parent_run_id": parentRunId ?? "",
                "features_v": "\(SceneFeatures.currentSchemaVersion)",
                "feature_vector": Self.quantizedVector(features),
                "top3": Self.top3Scores(scores),
            ])
            AOPerf.end(perfId, outcome: "ready-coach-only")
            consumeSharedFreeIfNeeded(entitlements)
            return
        }

        // --- 5. Verify: settle + read-back -------------------------------------
        phase = .verifying("Checking exposure…")
        try? await Task.sleep(nanoseconds: 300_000_000) // let hardware settle
        if wasCancelled(stage: "verify") { return }
        session.refreshReadouts()
        let readback = session.readbackState()
        var verifyNotes: [String] = []

        if solution.phoneTargets.exposureDurationSec != nil {
            if readback.exposureMode != "custom" {
                verifyNotes.append("Custom exposure not held (\(readback.exposureMode)) — values below are guidance.")
            } else if let want = solution.phoneTargets.exposureDurationSec, want > 0 {
                let drift = abs(readback.exposureDuration - want) / want
                if drift > 0.15 {
                    verifyNotes.append("Shutter read back \(RecipeCameraMapper.formatShutter(readback.exposureDuration)) vs solved \(RecipeCameraMapper.formatShutter(want)).")
                }
            }
        }
        if let wantISO = solution.phoneTargets.iso.flatMap({ Float($0) }), wantISO > 0 {
            let drift = abs(readback.iso - wantISO) / wantISO
            if drift > 0.15 {
                verifyNotes.append("ISO read back \(Int(readback.iso.rounded())) vs solved \(Int(wantISO.rounded())).")
            }
        }

        // Exposure-offset nudge: > 1 stop off after the solve → nudge ISO once.
        // (setISO keeps the solved shutter — never touches EV after custom exposure.)
        if abs(readback.exposureTargetOffset) > 1.0, entitlements.canApplyDials {
            let nudgedISO = readback.iso / Float(pow(2.0, Double(readback.exposureTargetOffset)))
            session.setISO(nudgedISO)
            verifyNotes.append("Exposure was \(String(format: "%+.1f", readback.exposureTargetOffset)) stops off — nudged ISO once.")
            try? await Task.sleep(nanoseconds: 150_000_000)
            session.refreshReadouts()
        }
        session.clampMessages.append(contentsOf: verifyNotes)
        verifyWarning = verifyNotes.isEmpty ? nil : verifyNotes.joined(separator: " ")

        // Diff chips show the values READ BACK from the device, not the targets.
        afterSnapshot = snap(session)
        agentBaseline = afterSnapshot
        diffs = buildDiffs(beforeSnapshot, afterSnapshot, session.clampMessages)
        advancedDiffs = buildAdvancedDiffs(session: session)

        publishDecision(decision, recipe: recipe, features: features, solution: solution, session: session)

        if suggestedLook != nil { verifyWarning = nil }
        phase = .ready
        applyFeedbackToken &+= 1
        let latencyMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        log.info("ready recipe=\(recipe.id, privacy: .public) diffs=\(self.coreDiffs.count) wroteTargets=\(wroteTargets) latency=\(latencyMs)ms")
        Analytics.shared.track("auto_optimize_success", props: [
            "recipe_id": recipe.id,
            "latency_ms": "\(latencyMs)",
            "path": "local",
            "trigger": trigger,
            "run_id": runId,
            "parent_run_id": parentRunId ?? "",
            "features_v": "\(SceneFeatures.currentSchemaVersion)",
            "feature_vector": Self.quantizedVector(features),
            "top3": Self.top3Scores(scores),
        ])
        AOPerf.end(perfId, outcome: "ready")
        consumeSharedFreeIfNeeded(entitlements)
        PushNotificationManager.shared.noteFirstSuccessfulAutoOptimize()

        // Pass 2: refine the LOCKED recipe with one still JPEG (never pixels for Pass 1).
        guard allowCloudRefine else {
            Analytics.shared.track("cloud_refine_skipped", props: ["reason": "first_win_local", "recipe_id": recipe.id])
            return
        }
        let probe = await SceneSensor.shared.latestJPEG()
        startSceneChangeWatch(session: session, recipeId: recipe.id, baselineEV: features.sceneEV100, generation: generation)
        schedulePass2CloudRefine(
            session: session,
            entitlements: entitlements,
            recipe: recipe,
            sceneNote: sceneNote,
            probeJPEG: probe,
            generation: generation,
            wroteDials: entitlements.canApplyDials
        )
    }

    /// Publishes the scored decision to the UI-facing state.
    private func publishDecision(
        _ decision: RecipeDecision,
        recipe: Recipe,
        features: SceneFeatures,
        solution: SettingsSolver.Solution,
        session: CameraSession
    ) {
        chosenRecipeId = decision.recipeId
        chosenRecipeTitle = decision.recipeTitle
        reasonNote = decision.reason
        teachWhy = decision.teachWhy
        senseSummary = decision.senseSummary
        tips = recipe.tips + solution.extraTips
        coachOnly = solution.coachOnly
        panCue = solution.panCue
        session.apertureGuidance = solution.apertureGuidance
        session.appliedRecipeId = recipe.id
        session.appliedRecipeTitle = decision.recipeTitle
        if decision.showAlsoTry, let runner = decision.runnerUp {
            alsoTryRecipeId = runner.recipeId
            alsoTryRecipeTitle = BundledPresets.recipe(id: runner.recipeId)?.title ?? runner.recipeId
            alsoTryProbability = runner.probability
        } else {
            alsoTryRecipeId = nil; alsoTryRecipeTitle = nil; alsoTryProbability = nil
        }

        // Look: ported heuristic — auto-apply ≥ 0.6 confidence, else a chip.
        autoAppliedLookId = nil
        if let suggested = LookSuggester.suggest(features: features) {
            if suggested.confidence >= LookSuggester.autoApplyThreshold {
                session.setActiveLook(suggested.look)
                autoAppliedLookId = suggested.look.id
                Analytics.shared.track("look_applied", props: [
                    "look_id": suggested.look.id,
                    "source": "auto",
                    "rank": "1",
                    "auto_applied": "1",
                    "confidence": String(format: "%.2f", suggested.confidence),
                ])
            } else {
                suggestedLook = suggested.look
            }
        }
    }

    // MARK: - Outcome telemetry (same run id)

    /// The 45-dim feature vector quantized to 2 decimals for telemetry.
    /// Numeric features only — Pass 1 telemetry never carries pixels.
    static func quantizedVector(_ features: SceneFeatures) -> String {
        features.featureVector().map { String(format: "%.2f", $0) }.joined(separator: ",")
    }

    static func top3Scores(_ scores: [RecipeScore]) -> String {
        scores.prefix(3)
            .map { "\($0.recipeId):\(String(format: "%.2f", $0.probability))" }
            .joined(separator: ",")
    }

    /// Returns the last run id when a photo is captured within 30 s of a
    /// successful optimize (consumed — one capture per run).
    func takeRecentRunIdForCapture() -> String? {
        guard let id = lastRunId, let at = lastRunDate,
              Date().timeIntervalSince(at) <= 30 else { return nil }
        lastRunId = nil
        return id
    }

    // MARK: - Scene-change watch (never a silent re-run)

    /// After Ready, polls the sensor every 2 s. When a *different* recipe
    /// scores ≥ 0.75 twice in a row, or the scene EV shifted by > 1.5 stops,
    /// shows "Scene changed — re-optimize?" — the user taps to re-run.
    private func startSceneChangeWatch(session: CameraSession, recipeId: String, baselineEV: Float?, generation: Int) {
        sceneWatchTask?.cancel()
        sceneWatchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var streak = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                guard self.runGeneration == generation, case .ready = self.phase else { return }
                let snapshot = await SceneSensor.shared.current()
                guard snapshot.age <= 2.0 else { continue }
                var features = snapshot.features
                features.recipeIntent = nil // scene change is about the scene, not the note
                let scores = self.scorer.score(features)
                if let top = scores.first, top.recipeId != recipeId, top.probability >= 0.75 {
                    streak += 1
                } else {
                    streak = 0
                }
                let evShift: Bool = {
                    guard let a = baselineEV, let b = features.sceneEV100 else { return false }
                    return abs(a - b) > 1.5
                }()
                if streak >= 2 || evShift {
                    self.sceneChangedSuggestion = "Scene changed — re-optimize?"
                    Analytics.shared.track("scene_changed_suggest", props: ["recipe_id": recipeId])
                    return
                }
            }
        }
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
        // Pass 1 already consumed the shared Free Peek unit for this tap — do not double-charge.
        // Soft-skip only on hard server 402 below; allow refine attempt after a paid Pass 1.
        cloudRefineTask?.cancel()
        let recipeId = recipe.id
        let recipeTitle = recipe.title
        let note = sceneNote
        let probe = probeJPEG
        let favorites = Array(entitlements.favoriteIds)

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
                // Refine dials when server allows free phoneTargets (or Pro).
                if entitlements.canApplyDials {
                    _ = session.applyPhoneTargets(targets)
                }
                // Look: auto-apply when Pass 1 left none; otherwise keep Pass 1 look.
                if session.activeCreativeLook == nil,
                   let look = targets.creativeLook, !look.id.isEmpty, CreativeLookCatalog.isKnown(look.id) {
                    var applied = look
                    if applied.intensity == nil {
                        applied.intensity = CreativeLookCatalog.defaultIntensity
                    }
                    session.setActiveLook(applied)
                    self.suggestedLook = nil
                    Analytics.shared.track("look_applied", props: ["look_id": applied.id, "source": "cloud_refine_auto"])
                }
                session.optimizeReason = self.teachOneLiner ?? self.reasonNote
                self.advancedDiffs = self.buildAdvancedDiffs(beforeNotes: notesBefore, afterNotes: session.applyNotes, session: session)
                // Free Peek + Pro both write dials — always refresh diffs for on-finder apply burst.
                session.refreshReadouts()
                self.afterSnapshot = self.snap(session)
                self.diffs = self.buildDiffs(self.beforeSnapshot, self.afterSnapshot, session.clampMessages)
                self.agentBaseline = self.afterSnapshot
                if !self.coreDiffs.isEmpty {
                    self.applyFeedbackToken &+= 1
                }
            }

            Analytics.shared.track("cloud_refine_success", props: [
                "recipe_id": recipeId,
                "wrote": wroteDials ? "true" : "false",
            ])
        }
    }

    /// Manual Pass 2 trigger (Teach sheet). Locked to the chosen recipe.
    func runCloudRefine(session: CameraSession, entitlements: EntitlementsStore) {
        guard case .ready = phase, let id = chosenRecipeId, let recipe = BundledPresets.recipe(id: id) else { return }
        Task {
            let probe = await SceneSensor.shared.latestJPEG()
            schedulePass2CloudRefine(
                session: session,
                entitlements: entitlements,
                recipe: recipe,
                sceneNote: "",
                probeJPEG: probe,
                generation: runGeneration,
                wroteDials: entitlements.canApplyDials
            )
        }
    }

    func cancelPass2CloudRefine() {
        cloudRefineTask?.cancel()
        cloudRefineTask = nil
        isCloudRefining = false
    }

    // MARK: - Snapshots & diffs

    /// Snapshot of the CURRENT device readouts (post-verify read-back).
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

    /// Coach-only snapshot: what the solver WOULD apply (free tier, dials locked).
    private func recommendedSnapshot(from solution: SettingsSolver.Solution, session: CameraSession) -> SettingsSnapshot {
        let t = solution.phoneTargets
        let shutter = t.exposureDurationSec.map { RecipeCameraMapper.formatShutter($0) } ?? t.shutter ?? "—"
        let focus: String = {
            switch t.focusMode {
            case "locked"?: return "Locked"
            case "continuous"?: return "Cont."
            default: return "Auto"
            }
        }()
        return SettingsSnapshot(
            mode: session.captureMode.shortLabel,
            aperture: solution.apertureGuidance ?? session.apertureGuidance,
            shutter: shutter,
            iso: t.iso ?? "—",
            ev: t.ev ?? "0",
            wb: session.whiteBalanceLocked ? "Locked" : "Auto",
            focus: focus
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
        var deduped: [DiffLine] = []
        for line in lines.reversed() {
            if seen.insert(line.label).inserted { deduped.append(line) }
        }
        return deduped.reversed()
    }

    /// Read-back-based advanced diffs (Pass 1): torch / low-light boost / HDR / zoom actually on.
    private func buildAdvancedDiffs(session: CameraSession) -> [DiffLine] {
        var lines: [DiffLine] = []
        if session.torchOn {
            lines.append(.init(label: "Torch", before: "Off", after: "On", clamped: false, tier: .advanced))
        }
        if session.lowLightBoostOn {
            lines.append(.init(label: "Low-light", before: "Off", after: "On", clamped: false, tier: .advanced))
        }
        if session.videoHDROn {
            lines.append(.init(label: "Video HDR", before: "Off", after: "On", clamped: false, tier: .advanced))
        }
        return lines
    }

    // MARK: - Nested types

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
}
