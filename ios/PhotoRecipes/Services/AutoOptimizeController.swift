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

    /// Per-analysis frame-stats timing (Phase 2). `gpuMs` comes from the
    /// command buffer's `gpuStartTime`/`gpuEndTime`; nil on the CPU fallback
    /// or when the device reports no timestamps. `wallMs` is the end-to-end
    /// `analyze` time. Target <2 ms GPU time on A15 — **device measurement
    /// pending** (no GPU on the build VM; CI macOS runners have no usable
    /// GPU either, so the Metal path is exercised on-device only).
    static func recordFrameStats(wallMs: Double, gpuMs: Double?, source: String) {
        let gpuStr = gpuMs.map { String(format: "%.3f", $0) } ?? "n/a"
        os_signpost(.event, log: log, name: "gpu_frame_stats",
                    "wall_ms %f gpu_ms %{public}s source %{public}s",
                    wallMs, gpuStr, source)
    }
}

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
    /// Numeric dial state at AO Ready (post-verify read-back) — the baseline
    /// for override deltas in `optimize_dial_override`.
    private var appliedDialsAtReady: AppliedDials?
    /// Run id whose dial-override label is armed but not yet recorded — the
    /// label fires at the user's capture or after dial inactivity (Section D).
    private var pendingOverrideRunId: String?
    /// 3 s dial-inactivity task for the pending override label.
    private var overrideInactivityTask: Task<Void, Never>?
    /// Weak session for the inactivity path (markDirty may be called without one).
    private weak var pendingOverrideSession: CameraSession?
    /// Test seam: override-label events go here instead of Analytics.
    var overrideLabelSink: (([String: String]) -> Void)?
    /// Test seam: dial-inactivity delay before the deferred override label fires.
    static var overrideLabelInactivityDelayNanoseconds: UInt64 = 3_000_000_000
    /// Set by the camera view while the user's own capture is in flight — the
    /// armed opt-in bracket yields to it (Section D).
    var isUserCaptureInFlight = false
    /// 30 s capture-window task: fires `optimize_capture_abandoned` when the
    /// window closes without a capture.
    private var captureWindowTask: Task<Void, Never>?

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
            Task { _ = await session.apply(recipe: recipe) }
        }
        afterSnapshot = agentBaseline
        isDirtyOverride = false
        phase = .ready
    }

    /// Manual dial touch after an optimize. Arms the deferred
    /// `optimize_dial_override` label — the event records the FINAL dial
    /// state at the user's capture or after 3 s of dial inactivity, whichever
    /// comes first, compared against the applied-at-Ready state. The first
    /// touch's tiny partial delta is NOT the training signal (Section D).
    func markDirty(session: CameraSession? = nil) {
        isDirtyOverride = true
        guard let runId = lastRunId, overrideTrackedForRun != runId else { return }
        if let session { pendingOverrideSession = session }
        pendingOverrideRunId = runId
        scheduleOverrideInactivityLabel()
    }

    /// Record the deferred `optimize_dial_override` label: the FINAL dial
    /// state (at capture or after 3 s of dial inactivity) vs the
    /// applied-at-Ready state. Once per run; no-ops when no override is armed
    /// or the run moved on. Called from the capture-completion path and the
    /// inactivity timer.
    func recordPendingOverrideLabel() {
        overrideInactivityTask?.cancel()
        overrideInactivityTask = nil
        guard let runId = pendingOverrideRunId, runId == lastRunId else {
            pendingOverrideRunId = nil
            return
        }
        pendingOverrideRunId = nil
        overrideTrackedForRun = runId
        let session = pendingOverrideSession
        pendingOverrideSession = nil
        var props: [String: String] = [
            "recipe_id": chosenRecipeId ?? "",
            "trigger": lastTrigger,
            "run_id": runId,
        ]
        if let session, let applied = appliedDialsAtReady {
            let current = AppliedDials(
                shutterSec: session.exposureSeconds,
                iso: session.iso,
                ev: session.evBias,
                wbKelvin: session.currentWhiteBalanceKelvin(),
                recipeId: chosenRecipeId ?? "")
            props.merge(Self.overrideLabelProps(
                applied: applied,
                current: current,
                inAutoExposure: session.isAutoExposure)) { _, new in new }
        }
        if let sink = overrideLabelSink {
            sink(props)
        } else {
            Analytics.shared.track("optimize_dial_override", props: props)
        }
    }

    /// (Re)start the 3 s dial-inactivity timer for the pending override label.
    private func scheduleOverrideInactivityLabel() {
        overrideInactivityTask?.cancel()
        overrideInactivityTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.overrideLabelInactivityDelayNanoseconds)
            guard let self, !Task.isCancelled else { return }
            self.recordPendingOverrideLabel()
        }
    }

    /// Test seam: seeds the "current run" (run id + applied-at-Ready dials)
    /// without running the pipeline.
    func seedCurrentRunForTests(runId: String, appliedDials: AppliedDials) {
        lastRunId = runId
        lastRunDate = Date()
        appliedDialsAtReady = appliedDials
        overrideTrackedForRun = nil
        pendingOverrideRunId = nil
    }

    /// The single training target for ExposureOffsetNet: the total exposure
    /// change the user's override made, in stops — log2 of the (t·ISO) ratio
    /// plus the EV-bias delta. The EV delta is included only in auto
    /// exposure; in custom exposure the EV dial is a no-op. Nil on
    /// degenerate dials. Pure and nonisolated — unit-tested.
    nonisolated static func exposureDeltaStops(
        applied: AppliedDials,
        current: AppliedDials,
        inAutoExposure: Bool
    ) -> Double? {
        guard applied.shutterSec > 0, applied.iso > 0,
              current.shutterSec > 0, current.iso > 0 else { return nil }
        let ratio = (current.shutterSec * Double(current.iso))
            / (applied.shutterSec * Double(applied.iso))
        var stops = log2(ratio)
        if inAutoExposure { stops += Double(current.ev - applied.ev) }
        return stops
    }

    /// Deferred override-label props: the per-dial deltas plus the single
    /// `exposure_delta_stops` training target. Pure and nonisolated —
    /// unit-tested.
    nonisolated static func overrideLabelProps(
        applied: AppliedDials,
        current: AppliedDials,
        inAutoExposure: Bool
    ) -> [String: String] {
        var props = dialDeltaProps(applied: applied, current: current)
        if let stops = exposureDeltaStops(applied: applied, current: current, inAutoExposure: inAutoExposure) {
            props["exposure_delta_stops"] = String(format: "%+.2f", stops)
        }
        return props
    }

    /// Numeric dial state (Phase 3 outcome telemetry).
    struct AppliedDials: Equatable {
        var shutterSec: Double
        var iso: Float
        var ev: Float
        var wbKelvin: Float?
        var recipeId: String
    }

    /// Snapshot the post-verify dial state at Ready (call after read-backs refresh).
    private func captureAppliedDials(session: CameraSession, recipeId: String) {
        appliedDialsAtReady = AppliedDials(
            shutterSec: session.exposureSeconds,
            iso: session.iso,
            ev: session.evBias,
            wbKelvin: session.currentWhiteBalanceKelvin(),
            recipeId: recipeId)
    }

    /// Deltas between the AO-applied dials and the user's override.
    /// Pure and nonisolated — unit-tested.
    nonisolated static func dialDeltaProps(applied: AppliedDials, current: AppliedDials) -> [String: String] {
        var p: [String: String] = [:]
        p["ev_delta"] = String(format: "%+.1f", current.ev - applied.ev)
        if applied.shutterSec > 0, current.shutterSec > 0 {
            p["shutter_delta_stops"] = String(format: "%+.2f", log2(current.shutterSec / applied.shutterSec))
        }
        if applied.iso > 0, current.iso > 0 {
            p["iso_delta_stops"] = String(format: "%+.2f", log2(Double(current.iso / applied.iso)))
        }
        if let a = applied.wbKelvin, let c = current.wbKelvin, a > 0, c > 0 {
            p["wb_kelvin_delta"] = String(format: "%+.0f", c - a)
        }
        p["recipe_unchanged"] = (applied.recipeId == current.recipeId) ? "1" : "0"
        return p
    }

    func dismissSuggestedLook() {
        if let look = suggestedLook {
            Analytics.shared.track("look_dismissed", props: [
                "look_id": look.id,
                "source": "suggested",
                "run_id": lastRunId ?? "",
            ])
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
                "run_id": lastRunId ?? "",
            ])
        }
        UserDefaults.standard.set(true, forKey: Self.userUndidKey)
        session.clearRecipe()
        clear()
    }

    func applySuggestedLook(session: CameraSession) {
        guard let look = suggestedLook else { return }
        Analytics.shared.track("look_applied", props: [
            "look_id": look.id,
            "source": "suggested",
            "rank": "1",
            "auto_applied": "0",
            "run_id": lastRunId ?? "",
        ])
        session.setActiveLook(look)
        suggestedLook = nil
        phase = .ready
    }

    func clear() {
        cloudRefineTask?.cancel()
        cloudRefineTask = nil
        sceneWatchTask?.cancel()
        sceneWatchTask = nil
        captureWindowTask?.cancel()
        captureWindowTask = nil
        overrideInactivityTask?.cancel()
        overrideInactivityTask = nil
        pendingOverrideRunId = nil
        pendingOverrideSession = nil
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

    // MARK: - Staged recipe pinning

    /// Which recipe, if any, pins the run and skips scoring. Only a recipe
    /// the *user* picked may pin: AO's own previous pick is also written to
    /// `session.appliedRecipeId`, and feeding that back as "staged" skipped
    /// scoring forever — one Panning pick then stuck across every scene,
    /// re-run and camera flip.
    static func pinnedRecipeId(staged: String?, applied: String?, aoChosen: String?) -> String? {
        if let staged { return staged }
        guard let applied else { return nil }
        return applied == aoChosen ? nil : applied
    }

    // MARK: - Pass 1 (on-device ML loop: features → score → solve → apply → verify)

    /// Local-first Auto Optimize. The happy path never calls the network.
    ///
    /// 0. Converge: AE to a converged auto state first — clears any stale
    ///    custom-exposure lock and anchors E_auto to the metered light level.
    /// 1. Features: the `SceneSensor` snapshot (refreshed synchronously on tap
    ///    when stale > 1 s).
    /// 2. Score: `RecipeScorer` over all ten bundled recipes (the reference
    ///    card is never a candidate); a staged recipe skips scoring.
    /// 3. Solve: `SettingsSolver` + `ExposurePlanner` turn the recipe +
    ///    features into dial targets from the converged E_auto.
    /// 4. Apply: `applyPhoneTargets` — never `setEV` after custom exposure.
    /// 5. Verify: closed-loop settle + read-back; ≤2 ISO corrections while
    ///    |offset − targetEV| > 0.3 EV; diff chips show read-back values.
    func run(
        session: CameraSession,
        entitlements: EntitlementsStore,
        preferStagedRecipeId: String?,
        sceneNote: String = "",
        elevationDegrees: Double? = nil,
        handShake: Double? = nil,
        isTripodSteady: Bool? = nil,
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
        captureWindowTask?.cancel()
        captureWindowTask = nil
        runGeneration &+= 1
        let generation = runGeneration
        lastTrigger = trigger
        let startedAt = Date()
        let runId = UUID().uuidString
        lastRunId = runId
        lastRunDate = Date()
        // A new run drops any armed override label from the previous run.
        pendingOverrideRunId = nil
        overrideInactivityTask?.cancel()
        overrideInactivityTask = nil
        pendingOverrideSession = nil
        let perfId = AOPerf.begin(runId: runId)
        let isFirstSuccessPending = !UserDefaults.standard.bool(
            forKey: PushNotificationManager.hasCompletedFirstAutoOptimizeKey
        )

        func wasCancelled(stage: String) -> Bool {
            guard runGeneration != generation else { return false }
            Analytics.shared.track("auto_optimize_cancel", props: [
                "latency_ms": "\(Int(Date().timeIntervalSince(startedAt) * 1000))",
                "stage": stage,
            ])
            AOPerf.end(perfId, outcome: "cancelled")
            return true
        }

        // --- 0. AE converge ----------------------------------------------------
        // Meter from a converged auto state: continuous AE at zero bias clears
        // any stale custom-exposure lock from a previous run, and the snapshot
        // anchors E_auto to the metered light level — not the tone-mapped
        // probe brightness the system AE already normalized.
        // Thermal .critical: rules scorer + system auto exposure (no custom).
        let thermalCritical = ProcessInfo.processInfo.thermalState == .critical
        phase = .sensing("Reading light…")
        // Hoisted: the snapshot's frame timestamp must postdate convergence
        // (A5) — frames exposed under a previous run's custom exposure would
        // anchor E_auto to the wrong light level.
        var convergedAt = Date.distantPast
        // Hoisted: the run's metered anchor, carried into the Pass 2 context so
        // the server's absolute shutter/ISO are re-planned from it (Section B).
        var convergedEAuto = 0.0
        do {
            let converge = try await session.convergeAutoExposure()
            convergedAt = converge.convergedAt
            convergedEAuto = converge.eAuto
            if converge.timedOut {
                Analytics.shared.track("ae_converge_timeout", props: [
                    "run_id": runId,
                    "trigger": trigger,
                ])
            }
        } catch {
            if wasCancelled(stage: "converge") { return }
            // Task cancelled without a generation bump — stop quietly.
            AOPerf.end(perfId, outcome: "cancelled")
            return
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
            // A5: the snapshot must postdate AE convergence — a 1 Hz tick
            // that ran during convergence saw frames exposed under the
            // previous run's custom exposure. refreshNow is already budgeted.
            if snapshot.age > 1.0 || snapshot.predatesConvergence(convergedAt) {
                // Snapshot older than 1 s or predating convergence — one
                // synchronous full pass before scoring.
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
                snapshot = SceneSnapshot(features: fresh, age: 0, frameAt: Date())
            }
            var f = snapshot.features
            // Stamp tap-time state: the note (intent) the user typed, the live
            // metering, and the pose from this exact tap.
            f.recipeIntent = IntentMatcher.match(note: sceneNote)
            f.meteredExposureSeconds = metering.exposureSeconds
            f.meteredISO = metering.iso
            f.exposureTargetOffset = metering.exposureTargetOffset
            f.exposureWasCustom = metering.wasCustom
            if let elevationDegrees { f.cameraElevationDegrees = Float(elevationDegrees) }
            if let handShake { f.handShakeRadPerSec = Float(handShake) }
            if let isTripodSteady { f.isTripodSteady = isTripodSteady }
            features = f
        }

        // --- 2. Score ---------------------------------------------------------
        if wasCancelled(stage: "sense") { return }
        phase = .reasoning("Matching a recipe…")
        // Thermal .critical falls back to the rules scorer (never Core ML).
        let runScorer: RecipeScoring = thermalCritical ? JSONRecipeScorer() : scorer
        let scores = runScorer.score(features)
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
            context: solveContext,
            forceSystemAutoExposure: thermalCritical
        )

        // --- 4. Apply ----------------------------------------------------------
        if wasCancelled(stage: "apply") { return }
        phase = .applying("Applying \(decision.recipeTitle)…")
        beforeSnapshot = snap(session)
        var wroteTargets = false
        if entitlements.canApplyDials {
            wroteTargets = await session.applyPhoneTargets(solution.phoneTargets)
        }
        session.clampMessages.append(contentsOf: solution.clampMessages)

        // Coach-only path (free tier: dials locked) — show the solved values.
        if !entitlements.canApplyDials {
            afterSnapshot = recommendedSnapshot(from: solution, session: session)
            agentBaseline = afterSnapshot
            diffs = buildDiffs(beforeSnapshot, afterSnapshot, session.clampMessages)
            publishDecision(decision, recipe: recipe, features: features, solution: solution, session: session, runId: runId)
            phase = .ready
            applyFeedbackToken &+= 1
            captureAppliedDials(session: session, recipeId: recipe.id)
            let latencyMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            log.info("ready (coach-only) recipe=\(recipe.id, privacy: .public) latency=\(latencyMs)ms")
            var successProps: [String: String] = [
                "recipe_id": recipe.id,
                "latency_ms": "\(latencyMs)",
                "path": "local",
                "coach_only": "1",
                "run_id": runId,
                "parent_run_id": parentRunId ?? "",
                "features_v": "\(SceneFeatures.currentSchemaVersion)",
                "feature_vector": Self.quantizedVector(features),
                "top3": Self.top3Scores(scores),
                "thermal_state": Self.thermalStateName,
                "gpu_stats": Self.gpuStatsProvenance(features),
                "scene_label_top": features.sceneLabels?.first?.identifier ?? "",
            ]
            successProps.merge(Self.telemetryV2Props(
                features: features,
                solution: solution,
                residualEV: nil,
                verifyIterations: 0,
                lensDeviceType: session.readbackState().lensDeviceType
            )) { _, new in new }
            Analytics.shared.track("auto_optimize_success", props: successProps)
            AOPerf.end(perfId, outcome: "ready-coach-only")
            consumeSharedFreeIfNeeded(entitlements)
            scheduleCaptureWindowCheck(runId: runId, recipeId: recipe.id)
            maybeCaptureOptInBracket(session: session, runId: runId, recipeId: recipe.id,
                                     features: features, coachOnly: true,
                                     solution: solution, verifyResidualEV: nil,
                                     lensDeviceType: session.readbackState().lensDeviceType)
            return
        }

        // --- 5. Verify: closed-loop settle + read-back + correct ---------------
        phase = .verifying("Checking exposure…")
        var verifyNotes: [String] = []

        // Closed-loop correction against the planner's targetEV: wait for the
        // write to land (completion + ~2 frames), compare exposureTargetOffset,
        // correct ISO while |offset − targetEV| > 0.3 EV (≤2 iterations).
        // Replaces the old single >1-stop nudge.
        // The residual is hoisted into the AO Ready telemetry (Phase 3).
        var verifyResidualEV: Double? = nil
        var verifyIterations = 0
        if let targetEV = solution.targetEV,
           solution.phoneTargets.exposureDurationSec != nil,
           entitlements.canApplyDials {
            let v = await session.verifyExposure(
                targetEV: targetEV,
                priority: solution.priority,
                shutterCapSeconds: solution.shutterCapSeconds)
            verifyIterations = v.iterations
            if v.verified {
                verifyResidualEV = v.residualEV
                if v.iterations > 0 {
                    // Human-readable, not technical. "Brightened 2 stops, still a bit dark"
                    // beats "Exposure was -2.1 EV off target — corrected in 2 iteration(s)".
                    let stops = abs(v.initialError)
                    let stopsText = String(format: "%.0f", stops) + (stops == 1 ? " stop" : " stops")
                    let direction = v.initialError < 0 ? "Brightened" : "Darkened"
                    if abs(v.residualEV) > 0.3 {
                        let still = v.residualEV < 0 ? "still a bit dark" : "still a bit bright"
                        verifyNotes.append("\(direction) \(stopsText), \(still)")
                    } else {
                        verifyNotes.append("\(direction) \(stopsText)")
                    }
                } else if abs(v.residualEV) > 0.3 {
                    let still = v.residualEV < 0 ? "A bit dark" : "A bit bright"
                    verifyNotes.append(still)
                }
                Analytics.shared.track("auto_optimize_verify", props: [
                    "run_id": runId,
                    "recipe_id": recipe.id,
                    "residual_ev": String(format: "%.2f", v.residualEV),
                    "iterations": "\(v.iterations)",
                    "clamped": v.clamped ? "1" : "0",
                ])
            }
        } else {
            try? await Task.sleep(nanoseconds: 300_000_000) // let hardware settle
        }
        if wasCancelled(stage: "verify") { return }
        session.refreshReadouts()
        let readback = session.readbackState()

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

        // Single status surface: verify notes go only to verifyWarning (AgentStatusPill).
        // Do NOT also append to session.clampMessages — that draws a duplicate banner.
        verifyWarning = verifyNotes.isEmpty ? nil : verifyNotes.joined(separator: " ")

        // Diff chips show the values READ BACK from the device, not the targets.
        afterSnapshot = snap(session)
        agentBaseline = afterSnapshot
        diffs = buildDiffs(beforeSnapshot, afterSnapshot, session.clampMessages)
        advancedDiffs = buildAdvancedDiffs(session: session)

        publishDecision(decision, recipe: recipe, features: features, solution: solution, session: session, runId: runId)

        if suggestedLook != nil { verifyWarning = nil }
        phase = .ready
        applyFeedbackToken &+= 1
        captureAppliedDials(session: session, recipeId: recipe.id)
        let latencyMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        log.info("ready recipe=\(recipe.id, privacy: .public) diffs=\(self.coreDiffs.count) wroteTargets=\(wroteTargets) latency=\(latencyMs)ms")
        var successProps: [String: String] = [
            "recipe_id": recipe.id,
            "latency_ms": "\(latencyMs)",
            "path": "local",
            "trigger": trigger,
            "run_id": runId,
            "parent_run_id": parentRunId ?? "",
            "features_v": "\(SceneFeatures.currentSchemaVersion)",
            "feature_vector": Self.quantizedVector(features),
            "top3": Self.top3Scores(scores),
            "thermal_state": Self.thermalStateName,
            "gpu_stats": Self.gpuStatsProvenance(features),
            "scene_label_top": features.sceneLabels?.first?.identifier ?? "",
        ]
        successProps.merge(Self.telemetryV2Props(
            features: features,
            solution: solution,
            residualEV: verifyResidualEV,
            verifyIterations: verifyIterations,
            lensDeviceType: readback.lensDeviceType
        )) { _, new in new }
        Analytics.shared.track("auto_optimize_success", props: successProps)
        AOPerf.end(perfId, outcome: "ready")
        consumeSharedFreeIfNeeded(entitlements)
        PushNotificationManager.shared.noteFirstSuccessfulAutoOptimize()
        scheduleCaptureWindowCheck(runId: runId, recipeId: recipe.id)
        maybeCaptureOptInBracket(session: session, runId: runId, recipeId: recipe.id,
                                 features: features, coachOnly: false,
                                 solution: solution, verifyResidualEV: verifyResidualEV,
                                 lensDeviceType: readback.lensDeviceType)

        // Pass 2: refine the LOCKED recipe with one still JPEG (never pixels for Pass 1).
        // Gate: the first successful optimize stays local-only, the toggle
        // gates the rest, and auto_first_capture never triggers a cloud call.
        // Each skip reason fires only when actually true (Section B).
        switch Self.cloudRefineGate(
            isFirstSuccessPending: isFirstSuccessPending,
            cloudRefineEnabled: Self.cloudRefineEnabled,
            trigger: trigger
        ) {
        case .allow:
            break
        case .skip(let reason):
            Analytics.shared.track("cloud_refine_skipped", props: ["reason": reason, "recipe_id": recipe.id])
            return
        }

        // Exposure anchor for Pass 2: re-plan the server's exposure from the
        // same metered E_auto with the recipe's priority/cap. Nil when Pass 1
        // wrote no custom exposure (HDR / system-auto / metering-missing /
        // thermal fallback) — Pass 2 then refines intent only, never exposure.
        let pass2Anchor: Pass2ExposureAnchor? = {
            guard convergedEAuto > 0, solution.phoneTargets.exposureDurationSec != nil else { return nil }
            let motion = ExposurePlanner.MotionContext(
                handShakeRadPerSec: Double(features.handShakeRadPerSec),
                frameWidthPx: solveContext.frameWidthPx,
                fieldOfViewDegrees: solveContext.fieldOfViewDegrees,
                isTripodSteady: features.isTripodSteady)
            let limits = ExposurePlanner.DeviceLimits(
                minShutterSeconds: session.capabilities.minExposureSeconds,
                maxShutterSeconds: session.capabilities.maxExposureSeconds,
                minISO: session.capabilities.minISO,
                maxISO: session.capabilities.maxISO)
            return Pass2ExposureAnchor(
                eAuto: convergedEAuto,
                priority: solution.priority,
                motion: motion,
                limits: limits)
        }()

        let probe = await SceneSensor.shared.latestJPEG()
        startSceneChangeWatch(session: session, recipeId: recipe.id, baselineEV: features.sceneEV100, generation: generation)
        schedulePass2CloudRefine(
            session: session,
            entitlements: entitlements,
            recipe: recipe,
            sceneNote: sceneNote,
            probeJPEG: probe,
            generation: generation,
            wroteDials: entitlements.canApplyDials,
            pass2Anchor: pass2Anchor
        )
    }

    /// Publishes the scored decision to the UI-facing state.
    private func publishDecision(
        _ decision: RecipeDecision,
        recipe: Recipe,
        features: SceneFeatures,
        solution: SettingsSolver.Solution,
        session: CameraSession,
        runId: String
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
                    "run_id": runId,
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

    /// Thermal state at run time (additive telemetry only).
    static var thermalStateName: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    /// GPU stats provenance for the run: "metal", "cpu", or "none".
    static func gpuStatsProvenance(_ features: SceneFeatures) -> String {
        features.gpuStatsFresh ? (features.gpuStatsSource ?? "unknown") : "none"
    }

    /// Phase 3 telemetry props for `auto_optimize_success` (additive — the
    /// caller keeps every existing key). Numeric only, never pixels; the
    /// 45-dim `featureVector()` contract is untouched.
    static func telemetryV2Props(
        features: SceneFeatures,
        solution: SettingsSolver.Solution,
        residualEV: Double?,
        verifyIterations: Int,
        lensDeviceType: String
    ) -> [String: String] {
        AOTelemetrySerializer.readyProps(
            features: features,
            planShutterSec: solution.phoneTargets.exposureDurationSec,
            planISO: solution.phoneTargets.iso,
            planTargetEV: solution.targetEV,
            planResidualEV: solution.residualEV,
            residualEV: residualEV,
            verifyIterations: verifyIterations,
            lensDeviceType: lensDeviceType
        )
    }

    /// After Ready, wait out the 30 s capture window: when it closes with no
    /// capture (the run id was never consumed by `takeRecentRunIdForCapture`),
    /// log `optimize_capture_abandoned` — the capture-vs-abandon outcome label.
    /// Cancelled by a newer run, `clear()`, or undo.
    private func scheduleCaptureWindowCheck(runId: String, recipeId: String) {
        captureWindowTask?.cancel()
        captureWindowTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 31_000_000_000)
            guard let self, !Task.isCancelled else { return }
            guard self.lastRunId == runId else { return } // captured or superseded
            self.lastRunId = nil // close the window
            Analytics.shared.track("optimize_capture_abandoned", props: [
                "run_id": runId,
                "recipe_id": recipeId,
                "trigger": self.lastTrigger,
            ])
        }
    }

    /// Phase 3 opt-in bracket: off the AO critical path. Arms the bracket at
    /// Ready — it fires right after the user's own capture completes
    /// (Section D; no post-Ready timer that can collide with the shutter).
    /// No-op when the toggle is off.
    private func maybeCaptureOptInBracket(
        session: CameraSession,
        runId: String,
        recipeId: String,
        features: SceneFeatures,
        coachOnly: Bool,
        solution: SettingsSolver.Solution,
        verifyResidualEV: Double?,
        lensDeviceType: String
    ) {
        // Generation-based currency: the user's capture consumes lastRunId,
        // so an id check would always fail at fire time. A newer run or
        // clear() bumps the generation and drops the armed bracket.
        let generation = runGeneration
        AOBracketCapture.shared.armBracket(
            run: AOBracketRun(
                runId: runId,
                recipeId: recipeId,
                capturedAt: Date(),
                coachOnly: coachOnly,
                features: features,
                isCurrent: { [weak self] in self?.runGeneration == generation },
                userCaptureInFlight: { [weak self] in self?.isUserCaptureInFlight ?? false },
                motionCapShutter: solution.shutterCapSeconds,
                planTargetEV: solution.targetEV,
                appliedShutterSec: appliedDialsAtReady?.shutterSec,
                appliedISO: appliedDialsAtReady?.iso,
                verifyResidualEV: verifyResidualEV,
                lensDeviceType: lensDeviceType
            )
        )
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
    ///
    /// Pass 2 may change the recipe's *intent* (EV offset ±1 stop, white
    /// balance, focus, look intensity, other non-exposure targets) but NEVER
    /// applies the server's absolute shutter/ISO directly: its exposure is
    /// re-anchored to the run's metered `E_auto` (`pass2Anchor`), re-planned
    /// with the recipe's priority/cap, and verified like Pass 1.
    private func schedulePass2CloudRefine(
        session: CameraSession,
        entitlements: EntitlementsStore,
        recipe: Recipe,
        sceneNote: String,
        probeJPEG: Data?,
        generation: Int,
        wroteDials: Bool,
        pass2Anchor: Pass2ExposureAnchor?
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
        let anchor = pass2Anchor
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
                    // Pass 2 intent: white balance, focus, look intensity and
                    // other non-exposure targets. The server's absolute
                    // shutter/ISO are stripped here — never applied directly.
                    _ = await session.applyPhoneTargets(Self.pass2IntentTargets(from: targets))
                    // Pass 2 exposure: the server's exposure re-anchored to the
                    // run's metered E_auto (±1 stop), re-planned with the
                    // recipe's priority/cap, applied via the normal apply
                    // path, then verified with the plan's priority and cap.
                    if let plan = Self.pass2ExposurePlan(targets: targets, anchor: anchor),
                       !Task.isCancelled {
                        _ = await Self.applyPass2Exposure(
                            plan: plan,
                            priority: anchor?.priority,
                            apply: { durationSeconds, iso in
                                await session.applyPhoneTargets(PhoneTargets(
                                    exposureDurationSec: durationSeconds,
                                    iso: "\(Int(iso.rounded()))"))
                            },
                            verify: { targetEV, priority, shutterCapSeconds in
                                await session.verifyExposure(
                                    targetEV: targetEV,
                                    priority: priority,
                                    shutterCapSeconds: shutterCapSeconds)
                            })
                    }
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
                wroteDials: entitlements.canApplyDials,
                // Manual Teach-sheet refine: no metered anchor from a run —
                // intent only (WB/focus/look), never absolute exposure.
                pass2Anchor: nil
            )
        }
    }

    func cancelPass2CloudRefine() {
        cloudRefineTask?.cancel()
        cloudRefineTask = nil
        isCloudRefining = false
    }

    // MARK: - Pass 2 exposure plumbing (Section B: planner-respecting refine)

    /// The Pass 1 exposure context carried into the Pass 2 cloud task, so the
    /// server's absolute exposure can be re-planned from the run's metered
    /// anchor — never applied directly.
    struct Pass2ExposureAnchor {
        /// Metered exposure product from the run's converged AE state.
        var eAuto: Double
        /// The recipe's exposure priority (nil → no custom exposure).
        var priority: ExposurePlanner.Priority?
        var motion: ExposurePlanner.MotionContext
        var limits: ExposurePlanner.DeviceLimits
    }

    /// Auto-scheduling gate for Pass 2. The first successful optimize stays
    /// local-only ("first_win_local"); the Settings toggle gates the rest
    /// ("disabled"); `auto_first_capture` never triggers a cloud call
    /// ("auto_first_capture"). Each skip reason fires only when actually true.
    enum CloudRefineGate: Equatable {
        case allow
        case skip(reason: String)
    }

    /// Pass 2 auto-scheduling gate. Pure — unit-tested.
    nonisolated static func cloudRefineGate(
        isFirstSuccessPending: Bool,
        cloudRefineEnabled: Bool,
        trigger: String
    ) -> CloudRefineGate {
        if isFirstSuccessPending { return .skip(reason: "first_win_local") }
        if !cloudRefineEnabled { return .skip(reason: "disabled") }
        if trigger == "auto_first_capture" { return .skip(reason: "auto_first_capture") }
        return .allow
    }

    /// The server's exposure as a delta in stops relative to the run's
    /// metered `eAuto`. Prefers the absolute shutter/ISO pair; falls back to
    /// a bare EV bias (already a relative offset). Nil when the server sent
    /// no usable exposure — an intent-only refine. Pure — unit-tested.
    nonisolated static func cloudExposureDeltaEV(targets: PhoneTargets, eAuto: Double) -> Double? {
        guard eAuto > 0 else { return nil }
        let durationSec = targets.exposureDurationSec
            ?? targets.shutter.flatMap(RecipeCameraMapper.parseShutter)
        let isoVal = targets.iso.flatMap(RecipeCameraMapper.parseISO)
        if let d = durationSec, let i = isoVal, d > 0, i > 0 {
            return log2((d * Double(i)) / eAuto)
        }
        if let evRaw = targets.ev, let ev = RecipeCameraMapper.parseEV(evRaw) {
            return Double(ev)
        }
        return nil
    }

    /// Pass 2 may move exposure at most ±1 stop from the metered anchor.
    /// Pure — unit-tested.
    nonisolated static func clampedCloudEVDelta(_ delta: Double) -> Double {
        min(max(delta, -1), 1)
    }

    /// Intent-only targets: everything the server sent except absolute
    /// exposure. Pass 2 may change white balance, focus, look intensity and
    /// other non-exposure levers — never shutter/ISO. Pure — unit-tested.
    nonisolated static func pass2IntentTargets(from targets: PhoneTargets) -> PhoneTargets {
        var t = targets
        t.shutter = nil
        t.exposureDurationSec = nil
        t.iso = nil
        t.ev = nil
        return t
    }

    /// The Pass 2 exposure plan: the server's exposure as a ±1-stop-clamped
    /// delta vs the run's `E_auto`, re-run through `ExposurePlanner` with the
    /// recipe's priority/cap. Nil when the server sent no exposure or the
    /// anchor allows no custom exposure — Pass 2 then changes intent only.
    /// Pure — unit-tested.
    nonisolated static func pass2ExposurePlan(
        targets: PhoneTargets,
        anchor: Pass2ExposureAnchor?
    ) -> ExposurePlanner.Plan? {
        guard let anchor, anchor.eAuto > 0, let priority = anchor.priority else { return nil }
        if case .systemAuto = priority { return nil }
        guard let delta = cloudExposureDeltaEV(targets: targets, eAuto: anchor.eAuto) else { return nil }
        return ExposurePlanner.plan(
            eAuto: anchor.eAuto,
            targetEV: clampedCloudEVDelta(delta),
            priority: priority,
            motion: anchor.motion,
            limits: anchor.limits)
    }

    /// Pass 2 closed loop: apply the planner's shutter/ISO via the normal
    /// apply path, then verify with the plan's priority and cap. The
    /// apply/verify closures are the test seam — production passes
    /// `applyPhoneTargets` / `verifyExposure`; tests pass spies. Returns the
    /// verify result (nil when the plan needs no custom exposure, or the task
    /// was cancelled before verify).
    nonisolated static func applyPass2Exposure(
        plan: ExposurePlanner.Plan,
        priority: ExposurePlanner.Priority?,
        apply: @MainActor (Double, Float) async -> Bool,
        verify: @MainActor (Double, ExposurePlanner.Priority?, Double?) async -> CameraSession.ExposureVerifyResult
    ) async -> CameraSession.ExposureVerifyResult? {
        guard plan.useCustomExposure else { return nil }
        _ = await apply(plan.shutterSeconds, plan.iso)
        guard !Task.isCancelled else { return nil }
        return await verify(plan.targetEV, priority, plan.shutterCapSeconds)
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
