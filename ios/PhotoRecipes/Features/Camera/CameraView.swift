import SwiftUI
import UIKit
import AVFoundation

struct CameraView: View {
    @EnvironmentObject private var entitlements: EntitlementsStore
    @EnvironmentObject private var router: CameraRouter
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @StateObject private var session = CameraSession()
    @StateObject private var optimizer = AutoOptimizeController()
    @StateObject private var voice = VoiceCaptureController()
    @StateObject private var horizon = HorizonMonitor()
    /// Opt-in bracket capture progress — shows the "Saving improvement data…" chip.
    @ObservedObject private var bracketCapture = AOBracketCapture.shared

    @State private var sceneNote = ""
    @State private var sceneFromViewfinder = false
    /// Snapshot of sceneNote when dictation starts — partials replace utterance, not append.
    @State private var voiceDictationBase = ""
    @State private var isDescribingScene = false
    @State private var showMicDenied = false
    @State private var describeTask: Task<Void, Never>?
    @State private var lastSceneDescribeAt: Date?
    /// In-flight voice → Recommend/AO; each new endpointed utterance cancels & replaces.
    @State private var voiceIntentTask: Task<Void, Never>?

    @State private var showTeach = false
    @State private var showRecipePicker = false
    @State private var showOverflow = false
    @State private var showClearConfirm = false
    // Chrome revamp: slide-out controls drawer (replaces the old dials sheet).
    @State private var showControlsDrawer = false
    @State private var drawerTab: ControlsSheet.Tab = .core
    @State private var drawerLookIntensity: Double = CreativeLookCatalog.defaultIntensity
    // Last captured photo for the finder thumbnail.
    @State private var lastCaptureImage: UIImage?
    @State private var showLastPhoto = false
    @State private var isCapturing = false
    @State private var captureError: String?
    @State private var showCoachMarks = false
    @State private var coachStep = 0
    @State private var lookToast: String?
    /// Top-chrome toast for flash / flip (short-lived).
    @State private var chromeToast: String?
    @State private var chromeToastTask: Task<Void, Never>?
    /// On-finder AO apply burst (dial deltas) — collapses into BeforeAfterChip.
    @State private var showApplyBurst = false
    @State private var applyBurstTask: Task<Void, Never>?

    /// Viewfinder-native still-capture feedback (flash / freeze / Saved chip).
    @State private var showCaptureFlash = false
    @State private var captureFreezeImage: UIImage?
    @State private var showSavedChip = false
    @State private var shutterPressScale: CGFloat = 1.0
    @State private var captureFeedbackTask: Task<Void, Never>?
    @State private var savedChipTask: Task<Void, Never>?

    /// Scene TextField focus + keyboard avoidance (full-bleed finder ignores safe area).
    @FocusState private var sceneFieldFocused: Bool
    @State private var keyboardHeight: CGFloat = 0

    /// Recommend state — the finder button is removed; /api/recommend stays wired
    /// for Ask (··· → Coach) and voice flows, which drive runRecommend() directly.
    @State private var isRecommending = false
    @State private var recommendResult: RecommendResponse?
    @State private var recommendError: String?
    @State private var showRecommendResult = false
    /// Live SSE status.message / phase copy shown in finder chrome while streaming.
    @State private var recommendStreamStatus: String?
    @State private var recommendStreamPhase: String?

    /// Press-and-hold compare: preview shows the unstyled original while true.
    @State private var comparingOriginal = false
    /// Post-save celebration ("Try another photo" + reminder offer).
    @State private var postSaveCard: PostSaveCard.Model?

    var body: some View {
        ZStack {
            AppTheme.bg.ignoresSafeArea()
            switch session.auth {
            case .authorized:
                viewfinder
            case .notDetermined:
                permissionCover(
                    title: "Camera access",
                    body: "ProTune AI Camera needs the camera to apply field recipes to live capture.",
                    primary: "Continue",
                    primaryAction: {
                        Task {
                            await session.checkAuth()
                            if session.auth == .authorized {
                                await session.start()
                                horizon.start()
                            }
                        }
                    },
                    secondary: "Not now",
                    secondaryAction: { router.selectedTab = .library }
                )
            case .denied, .restricted:
                permissionCover(
                    title: "Camera is off",
                    body: "Enable camera in Settings to shoot with recipes.",
                    primary: "Open Settings",
                    primaryAction: {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    },
                    secondary: "Browse recipes",
                    secondaryAction: { router.selectedTab = .library }
                )
            }
        }
        .task {
            await session.checkAuth()
            if session.auth == .authorized {
                await session.start()
                horizon.start()
                // Pass 1 ML: feed video frames to the scene sensor.
                session.frameConsumer = { buffer, timestamp in
                    Task { await SceneSensor.shared.ingestFrame(buffer, at: timestamp) }
                }
                await SceneSensor.shared.start()
                await SceneSensor.shared.setVisible(true)
                // Phase 2: probe-JPEG fallback for refreshNow when no video
                // frames have arrived (session interruption / lens switch).
                await SceneSensor.shared.setProbeProvider { [weak session] in
                    guard let session else { throw CameraSession.CamError.noFrame }
                    return try await session.captureProbeFrame()
                }
            }
            applyStagingIfNeeded()
            if CameraCoachMarksStore.shouldShow {
                coachStep = 0
                showCoachMarks = true
            }
        }
        .onChange(of: router.stagedRecipeId) { _, _ in applyStagingIfNeeded() }
        .onChange(of: router.pendingAutoOptimize) { _, pending in
            if pending { Task { await consumePendingAutoOptimizeIfNeeded() } }
        }
        .onAppear {
            Analytics.shared.track("camera_open", props: ["source": "camera_tab"])
            describeTask?.cancel()
            describeTask = Task { await refreshSceneFromViewfinder() }
            Task { await consumePendingAutoOptimizeIfNeeded() }
            if CameraCoachMarksStore.shouldShow {
                coachStep = 0
                showCoachMarks = true
            }
        }
        .alert("Microphone is off", isPresented: $showMicDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Type instead", role: .cancel) {}
        } message: {
            Text("Enable the microphone to dictate a scene for Auto Optimize.")
        }

        .onChange(of: session.subjectAreaChangeToken) { _, token in
            guard token > 0, canOptimize else { return }
            // monitorSubjectAreaChange → debounced re-run of Auto Optimize,
            // gated: a re-run pulses the preview (converge, then re-lock),
            // so it only fires when the scene would actually change recipes.
            Task {
                switch await optimizer.shouldRerunOnSubjectChange() {
                case .rerun: await runOptimize(trigger: "subject_change")
                case .skip(let reason):
                    Analytics.shared.track("ao_subject_change_skipped", props: ["reason": reason])
                }
            }
        }

        .onChange(of: voice.phase) { _, phase in
            switch phase {
            case .error:
                if voice.permission == .denied { showMicDenied = true }
            default:
                break
            }
        }
        .onDisappear {
            voice.cancel()
            describeTask?.cancel()
            voiceIntentTask?.cancel()
            chromeToastTask?.cancel()
            applyBurstTask?.cancel()
            captureFeedbackTask?.cancel()
            savedChipTask?.cancel()
            Task { await SceneSensor.shared.setVisible(false) }
            session.stop()
            horizon.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let screen = UIScreen.main.bounds
            let overlap = max(0, screen.maxY - frame.origin.y)
            withAnimation(.easeOut(duration: 0.22)) { keyboardHeight = overlap }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.22)) { keyboardHeight = 0 }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            // Keep video-output frames upright for Vision when the interface rotates.
            session.updateVideoOutputOrientation()
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    sceneFieldFocused = false
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .fontWeight(.semibold)
            }
        }
        .sheet(isPresented: $showTeach) {
            TeachModeSheet(
                recipeTitle: Recipe.chromeTitle(forStoredTitle: optimizer.chosenRecipeTitle ?? session.appliedRecipeTitle, id: optimizer.chosenRecipeId ?? session.appliedRecipeId),
                oneLiner: optimizer.teachOneLiner,
                tips: optimizer.tips,
                diffs: optimizer.coreDiffs,
                advancedDiffs: optimizer.advancedDiffs,
                verifyWarning: optimizer.verifyWarning,
                coachOnly: optimizer.coachOnly,
                activeLook: session.activeCreativeLook,
                onReoptimizeSubject: {
                    showTeach = false
                    Task { await runOptimize(trigger: "teach") }
                },
                onDone: { showTeach = false }
            )
            .environmentObject(entitlements)
        }
        .sheet(isPresented: $showRecipePicker) {
            RecipePickerSheet { recipe in
                showRecipePicker = false
                Task { @MainActor in _ = await session.apply(recipe: recipe) }
            }
        }
        .sheet(isPresented: $showOverflow) {
            CameraOverflowSheet(
                showGrid: $session.showGrid,
                canTeach: optimizer.phase == .ready || optimizer.teachOneLiner != nil,
                recommendDisabled: isRecommending || optimizer.phase.isRunning,
                isRecommending: isRecommending,
                isOptimizing: optimizer.phase.isRunning,
                canUndo: undoOptimizeAvailable,
                onLibrary: {
                    showOverflow = false
                    router.selectedTab = .library
                },
                onCoach: {
                    showOverflow = false
                    router.selectedTab = .ask
                },
                onSettings: {
                    showOverflow = false
                    router.selectedTab = .settings
                },
                onDials: {
                    showOverflow = false
                    openControlsDrawer(tab: .core)
                },
                onTeach: {
                    showOverflow = false
                    showTeach = true
                },
                onRecipes: {
                    showOverflow = false
                    showRecipePicker = true
                },
                onRecommend: {
                    showOverflow = false
                    Task { await runRecommend() }
                },
                onAutoOptimize: {
                    showOverflow = false
                    Task { await runOptimize(trigger: "manual") }
                },
                onUndo: {
                    showOverflow = false
                    undoOptimize()
                },
                onVoice: {
                    showOverflow = false
                    voice.toggle(
                        onPartial: { applyCameraVoicePartial($0) },
                        onTranscript: { applyCameraVoiceFinal($0) }
                    )
                },
                onRefreshScene: {
                    showOverflow = false
                    Task { await refreshSceneFromViewfinder(auto: false) }
                },
                onClearRecipe: session.appliedRecipeTitle == nil ? nil : {
                    showOverflow = false
                    showClearConfirm = true
                }
            )
            .presentationDetents([.medium])
        }
        .confirmationDialog("Remove recipe from this session?", isPresented: $showClearConfirm) {
            Button("Remove", role: .destructive) {
                session.clearRecipe()
                optimizer.clear()
            }
            Button("Keep", role: .cancel) {}
        }
        .sheet(isPresented: $showRecommendResult) {
            CameraRecommendResultSheet(
                result: recommendResult,
                errorText: recommendError,
                isLoading: isRecommending,
                statusMessage: recommendStreamStatus,
                onApply: { recipe in
                    showRecommendResult = false
                    applyRecommendToCamera(recipe: recipe, response: recommendResult)
                },
                onDismiss: {
                    showRecommendResult = false
                    recommendResult = nil
                    recommendError = nil
                },
                onUpgrade: {
                    showRecommendResult = false
                    entitlements.presentHardPaywall(trigger: "recommend_upgrade", force: true)
                }
            )
            .environmentObject(entitlements)
            .environmentObject(router)
            .presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $showLastPhoto) {
            if let img = lastCaptureImage {
                LastPhotoViewer(image: img)
            }
        }
    }

    // MARK: - Full-bleed viewfinder

    private var viewfinder: some View {
        GeometryReader { geo in
            // Preview ignores safe area (full-bleed). GeometryReader does too, so
            // geo.safeAreaInsets is typically zero — read the key window instead.
            let safe = Self.keyWindowSafeAreaInsets()
            let safeTop = safe.top
            let safeBottom = safe.bottom
            let compact = isCompactChrome(width: geo.size.width, height: geo.size.height)
            let bottomScrim: CGFloat = (compact ? 112 : 136) + safeBottom
            let topChromeH: CGFloat = (compact ? 56 : 64) + safeTop
            ZStack {
                CameraPreviewView(
                    session: session.session,
                    previewLUTId: comparingOriginal ? nil : session.previewLUTId,
                    creativeLook: comparingOriginal ? nil : session.activeCreativeLook,
                    onPreviewLayer: { layer in
                        // UI → device point-of-interest conversion for tap-to-focus
                        // and Auto Optimize's Vision → device path. Also re-applies
                        // the video-output rotation now the session is streaming.
                        session.devicePointConverter = PreviewLayerDevicePointConverter(layer: layer)
                        session.updateVideoOutputOrientation()
                    }
                )
                    .ignoresSafeArea()
                    .simultaneousGesture(
                        SpatialTapGesture().onEnded { value in
                            // Dismiss Scene keyboard on finder tap (also sets AE/AF).
                            if sceneFieldFocused { dismissSceneKeyboard() }
                            // Keep focus taps out of top/bottom chrome so flash / flip / ··· stay tappable.
                            let y = value.location.y
                            let kbPad = keyboardHeight > 0 ? max(0, keyboardHeight - safeBottom) : 0
                            guard y > topChromeH, y < geo.size.height - bottomScrim - kbPad else { return }
                            let pt = CGPoint(
                                x: value.location.x / geo.size.width,
                                y: value.location.y / geo.size.height
                            )
                            // UI-space tap → device point of interest; the reticle
                            // keeps the UI point.
                            session.focusOnUIPoint(pt, lock: entitlements.canApplyDials)
                        }
                    )

                if session.showGrid {
                    ruleOfThirds.allowsHitTesting(false)
                }

                if let pt = session.focusPoint {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(session.focusLocked ? AppTheme.aeLock : Color.white, lineWidth: 1.5)
                        .frame(width: 64, height: 64)
                        .position(x: pt.x * geo.size.width, y: pt.y * geo.size.height)
                        .allowsHitTesting(false)
                }

                if showsPanCues, let cue = activePanCue {
                    ViewfinderPanCuesView(
                        cue: cue,
                        bottomInset: bottomScrim + 24,
                        topInset: (compact ? 52 : 64) + safeTop
                    )
                    .allowsHitTesting(false)
                }

                // Mid-finder AO apply burst — impossible to miss dial writes.
                if showApplyBurst, !optimizer.coreDiffs.isEmpty {
                    ApplyBurstBanner(diffs: optimizer.coreDiffs)
                        .padding(.horizontal, 20)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        .allowsHitTesting(false)
                        .zIndex(15)
                }

                VStack(spacing: 0) {
                    topOverlay(compact: compact, topSafeInset: safeTop)
                        .zIndex(12)
                    Spacer(minLength: 0)
                        // Tap empty finder to dismiss Scene keyboard.
                        .contentShape(Rectangle())
                        .onTapGesture { dismissSceneKeyboard() }
                    bottomOverlay(
                        compact: compact,
                        width: geo.size.width,
                        scrimHeight: bottomScrim,
                        bottomSafeInset: safeBottom
                    )
                    // Pad chrome above the software keyboard (finder ignoresSafeArea, so
                    // SwiftUI's default avoidance does not lift Scene / AO / shutter).
                    Color.clear.frame(height: keyboardHeight > 0 ? max(0, keyboardHeight - safeBottom) : 0)
                }
                .zIndex(10)
                .animation(.easeOut(duration: 0.22), value: keyboardHeight)

                // Side chrome: controls drawer (left) + filter rail (right),
                // between the top/bottom chrome and the capture feedback.
                sideChrome(
                    compact: compact,
                    topInset: topChromeH,
                    bottomInset: bottomScrim
                )
                .zIndex(11)

                // Capture feedback ABOVE chrome + preview (B20 sat at zIndex 8–9 under chrome 10;
                // ~80ms flash was also easy to miss; heavy haptic was gated on Photos save).
                if let freeze = captureFreezeImage {
                    Image(uiImage: freeze)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .zIndex(90)
                }
                if showCaptureFlash {
                    Color.white
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .zIndex(91)
                }
                if showSavedChip {
                    VStack {
                        Spacer(minLength: 0)
                        Text("Saved")
                            .font(AppTheme.caption())
                            .foregroundStyle(AppTheme.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(AppTheme.agentStatusBg)
                                    .overlay(Capsule().stroke(AppTheme.border.opacity(0.5), lineWidth: 1))
                            )
                            .padding(.bottom, bottomScrim + 4 + (keyboardHeight > 0 ? max(0, keyboardHeight - safeBottom) : 0))
                    }
                    .allowsHitTesting(false)
                    .zIndex(92)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
                }
                // Section D: opt-in bracket capture progress — small,
                // non-modal, above the saved chip while it runs.
                if bracketCapture.isSavingBracketData {
                    VStack {
                        Spacer(minLength: 0)
                        Text("Saving improvement data…")
                            .font(AppTheme.caption())
                            .foregroundStyle(AppTheme.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(AppTheme.agentStatusBg)
                                    .overlay(Capsule().stroke(AppTheme.border.opacity(0.5), lineWidth: 1))
                            )
                            .padding(.bottom, bottomScrim + 48 + (keyboardHeight > 0 ? max(0, keyboardHeight - safeBottom) : 0))
                    }
                    .allowsHitTesting(false)
                    .zIndex(92)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
                }

                if showCoachMarks {
                    CameraCoachMarksView(step: $coachStep) {
                        showCoachMarks = false
                        CameraCoachMarksStore.markSeen()
                    }
                    .transition(.opacity)
                    .zIndex(20)
                }

                if let card = postSaveCard {
                    ZStack {
                        Color.black.opacity(0.55)
                            .ignoresSafeArea()
                            .onTapGesture { dismissPostSaveCard(action: "backdrop") }
                        PostSaveCard(
                            model: card,
                            onNext: { dismissPostSaveCard(action: "try_another") },
                            onRemind: {
                                dismissPostSaveCard(action: "remind")
                                Task { await PushNotificationManager.shared.requestReminderPermission(source: "post_save_card") }
                            }
                        )
                    }
                    .transition(.opacity)
                    .zIndex(95)
                }
            }
            .onChange(of: optimizer.applyFeedbackToken) { _, token in
                guard token > 0 else { return }
                if !optimizer.coreDiffs.isEmpty {
                    presentApplyBurst()
                } else if let title = Recipe.chromeTitle(
                    forStoredTitle: optimizer.chosenRecipeTitle ?? session.appliedRecipeTitle,
                    id: optimizer.chosenRecipeId ?? session.appliedRecipeId
                ) {
                    // Empty dial deltas — still confirm Apply so Optimize never feels silent.
                    presentChromeToast("Ready · \(title)")
                }
            }
        }
        .ignoresSafeArea()
    }

    /// Window safe-area insets for full-bleed viewfinders (GeometryProxy insets are zero after ignoresSafeArea).
    private static func keyWindowSafeAreaInsets() -> UIEdgeInsets {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap { $0.windows }
        if let key = windows.first(where: { $0.isKeyWindow }) {
            return key.safeAreaInsets
        }
        return windows.first?.safeAreaInsets ?? .zero
    }

    private func isCompactChrome(width: CGFloat, height: CGFloat) -> Bool {
        if horizontalSizeClass == .regular { return false }
        return width <= 375 || height < 700
    }

    /// Build 28: one primary status surface at a time — don't stack top recipe badge +
    /// AgentStatusPill ("Matching…") + bottom BeforeAfter marketing chip + pan cues.
    private var isStatusBusy: Bool {
        isRecommending || optimizer.phase.isRunning
    }

    /// Prefer short status / look toast over persistent recipe badge while busy.
    /// Before/after chip only when Ready and not mid-Recommend / mid-burst.
    /// (Currently not rendered on the finder — kept for the detail sheet.)
    private var showsBeforeAfterChip: Bool {
        guard case .ready = optimizer.phase else { return false }
        guard !showApplyBurst, !isRecommending else { return false }
        return !optimizer.coreDiffs.isEmpty
    }

    /// Undo availability for the overflow sheet — same condition as the old
    /// result row: a completed optimize with something to revert.
    private var undoOptimizeAvailable: Bool {
        guard case .ready = optimizer.phase else { return false }
        return !optimizer.coreDiffs.isEmpty || session.appliedRecipeTitle != nil
    }

    /// Hide pan-edge chrome while Recommend/AO status is the primary surface.
    private var showsPanCues: Bool {
        !isStatusBusy && !showApplyBurst
    }

    /// Short status for AgentStatusPill — never marketing recipe titles.
    /// Nil when Ready + BeforeAfterChip already carries the outcome (avoid double stack).
    private var primaryStatusCopy: String? {
        if let s = recommendChromeStatus, !s.isEmpty { return s }
        if optimizer.phase.isRunning {
            let copy = optimizer.phase.statusCopy
            return copy.isEmpty ? "Optimizing…" : copy
        }
        if let w = optimizer.verifyWarning, !w.isEmpty { return w }
        if case .ready = optimizer.phase, optimizer.isCloudRefining { return "Ready · refining…" }
        if case .ready = optimizer.phase, optimizer.suggestedLook != nil {
            let name = optimizer.suggestedLook?.displayName ?? "look"
            return "Ready · \(name)"
        }
        if case .error(let msg) = optimizer.phase { return msg }
        // Ready with diffs → BeforeAfterChip is the status; idle → nothing.
        if case .ready = optimizer.phase { return nil }
        let pill = optimizer.pillStatus
        return pill.isEmpty ? nil : pill
    }

    private var activePanCue: ViewfinderPanCue? {
        ViewfinderPanCueResolver.resolve(
            recipeId: session.appliedRecipeId ?? optimizer.chosenRecipeId,
            agentPhase: optimizer.phase,
            agentStatus: {
                if let s = optimizer.senseSummary, !s.isEmpty { return s }
                let copy = optimizer.phase.statusCopy
                return copy.isEmpty ? nil : copy
            }(),
            agentPanCue: optimizer.panCue
        )
    }

    private func topOverlay(compact: Bool, topSafeInset: CGFloat) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                floatingIcon(session.flash.icon, accessibility: "Flash \(session.flash.modeCaption)") {
                    cycleFlash()
                }
                Spacer(minLength: 4)
                if session.focusLocked || session.exposureLocked {
                    Text("AE/AF LOCK")
                        .font(AppTheme.overline())
                        .foregroundStyle(AppTheme.aeLock)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(AppTheme.agentStatusBg))
                        .allowsHitTesting(false)
                }
                if horizon.isAvailable {
                    Circle()
                        .fill(horizon.isLevel ? AppTheme.agentReady : AppTheme.agentWarn)
                        .frame(width: 8, height: 8)
                        .rotationEffect(.degrees(-horizon.rollDegrees))
                        .allowsHitTesting(false)
                }
                // Mode pill removed from top bar — mode is announced once as the
                // small label above the shutter. Top chrome is flash, AE/AF LOCK,
                // flip, overflow only.
                floatingIcon("arrow.triangle.2.circlepath.camera", accessibility: "Flip camera") {
                    flipCameraWithFeedback()
                }
                // Upgrade entry — hidden once Pro.
                if !entitlements.isPro {
                    Button {
                        Analytics.shared.track("upgrade_tap", props: ["source": "top_chrome"])
                        entitlements.presentHardPaywall(trigger: "upgrade_top", force: true)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "crown.fill")
                                .font(.caption2.weight(.bold))
                            Text("Pro")
                                .font(AppTheme.caption().weight(.bold))
                        }
                        .foregroundStyle(AppTheme.accentOnAccent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(AppTheme.accent))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Upgrade to Pro")
                    .accessibilityHint("Opens the Pro upgrade")
                }
                floatingIcon("ellipsis", accessibility: "More") {
                    showOverflow = true
                }
            }

            if let chromeToast {
                Text(chromeToast)
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(AppTheme.agentStatusBg))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .allowsHitTesting(false)
            }

            // Statuses live on top — the center of the finder stays clear.
            // Single status line, then the chip row.
            statusSection(compact: compact)
        }
        .padding(.horizontal, compact ? 10 : 14)
        // Sit snug under status bar / Dynamic Island (inset + ~6pt clearance).
        .padding(.top, topSafeInset + 6)
        .contentShape(Rectangle())
        .background(
            LinearGradient(
                colors: [AppTheme.cameraScrim.opacity(0.85), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 88 + topSafeInset)
            .frame(maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)
        )
    }

    /// Statuses on top: single status line + chip row. The center of the
    /// finder stays clear for the actual photography.
    private func statusSection(compact: Bool) -> some View {
        let hPad: CGFloat = compact ? 10 : 14
        return VStack(spacing: compact ? 6 : 8) {
            // Single primary status: busy Recommend/AO, or ready warnings.
            if isStatusBusy || primaryStatusCopy != nil {
                AgentStatusPill(
                    phase: optimizer.phase,
                    verifyWarning: nil,
                    statusOverride: primaryStatusCopy ?? recommendChromeStatus ?? optimizer.pillStatus,
                    isBusy: isRecommending || optimizer.phase.isRunning,
                    onStop: isStatusBusy ? { optimizer.clear(); cancelInFlightVoiceIntent() } : nil,
                    onTapDetail: { showTeach = true }
                )
            }

            // One chip row: the look chip. The scene text field lives at the
            // bottom — always visible, with its mic button.
            HStack(spacing: 8) {
                if let mode = lookChipMode {
                    LookChip(
                        mode: mode,
                        onApply: {
                            if let look = optimizer.suggestedLook {
                                Analytics.shared.track("look_applied", props: ["look_id": look.id, "source": "chip"])
                            }
                            optimizer.applySuggestedLook(session: session)
                        },
                        onDismiss: {
                            if let look = optimizer.suggestedLook {
                                Analytics.shared.track("look_dismissed", props: ["look_id": look.id, "source": "chip"])
                            }
                            optimizer.dismissSuggestedLook()
                        },
                        onClear: {
                            if let look = session.activeCreativeLook {
                                let auto = look.id == optimizer.autoAppliedLookId
                                Analytics.shared.track("look_undone", props: [
                                    "look_id": look.id,
                                    "auto_applied": auto ? "1" : "0",
                                    "rank": "1",
                                    "source": "chip",
                                ])
                                if auto { optimizer.autoAppliedLookId = nil }
                            }
                            session.clearActiveLook()
                        },
                        onOpenLooks: {
                            openControlsDrawer(tab: .looks)
                        }
                    )
                }
            }
            .padding(.horizontal, hPad)
        }
    }

    private func bottomOverlay(compact: Bool, width: CGFloat, scrimHeight: CGFloat, bottomSafeInset: CGFloat) -> some View {
        let hPad: CGFloat = width <= 320 ? 8 : (compact ? 12 : 16)

        return VStack(spacing: compact ? 6 : 8) {
            // Bottom holds the controls: scene field + mic, then the shutter
            // flanked by Auto Optimize. Statuses live on top; the center stays clear.

            // Scene text field — always visible, with the mic button inline.
            sceneFieldRow(compact: compact)
                .padding(.horizontal, hPad)

            // Transient suggestion chips live here, above the shutter.
            if let alsoId = optimizer.alsoTryRecipeId, !optimizer.phase.isRunning {
                Button {
                    let parent = optimizer.lastRunId
                    Analytics.shared.track("also_try_tap", props: [
                        "recipe_id": alsoId,
                        "from_recipe_id": optimizer.chosenRecipeId ?? "",
                        "run_id": parent ?? "",
                    ])
                    session.appliedRecipeId = nil
                    router.stagedRecipeId = alsoId
                    Task { await runOptimize(trigger: "also_try", parentRunId: parent) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "shuffle")
                        Text("Also try: \(optimizer.alsoTryRecipeTitle ?? alsoId)")
                            .font(AppTheme.caption())
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(AppTheme.agentStatusBg))
                }
                .foregroundStyle(AppTheme.ink)
                .padding(.horizontal, hPad)
            }

            shutterRow(compact: compact, hPad: hPad)

            if let captureError {
                Text(captureError)
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.danger)
            }
        }
        // Keep shutter / CTAs clear of the home indicator (prior 10pt gap + inset).
        .padding(.bottom, 10 + bottomSafeInset)
        .padding(.top, 8)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [.clear, AppTheme.cameraScrim],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: scrimHeight)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)
        )
    }

    private var isVoiceListening: Bool {
        if case .recording = voice.phase { return true }
        if case .uploading = voice.phase { return true }
        return false
    }

    /// Scene text field — always visible, with the mic button inline.
    /// Tapping the mic dictates; partials stream into the field.
    private func sceneFieldRow(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // Real TextField so STT partials stream into a visible text box (App Review).
                TextField("Describe the scene…", text: $sceneNote, axis: .vertical)
                    .lineLimit(1...3)
                    .font(AppTheme.bodySm())
                    .foregroundStyle(AppTheme.ink)
                    .focused($sceneFieldFocused)
                    .submitLabel(.return)
                    .onSubmit { submitSceneQuery() }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.radiusSm, style: .continuous)
                            .fill(AppTheme.agentStatusBg)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.radiusSm, style: .continuous)
                                    .stroke(
                                        isVoiceListening ? AppTheme.accent.opacity(0.7) : AppTheme.border.opacity(0.7),
                                        lineWidth: 1
                                    )
                            )
                    )
                    .onChange(of: sceneNote) { _, new in
                        sceneFromViewfinder = false
                        // Vertical-axis fields insert a newline on Return instead of submitting.
                        if new.contains("\n") {
                            sceneNote = new.replacingOccurrences(of: "\n", with: " ")
                                .trimmingCharacters(in: .whitespaces)
                            submitSceneQuery()
                        }
                    }

                if isDescribingScene {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Button {
                        voice.toggle(
                            onPartial: { applyCameraVoicePartial($0) },
                            onTranscript: { applyCameraVoiceFinal($0) }
                        )
                    } label: {
                        Image(systemName: isVoiceListening ? "mic.fill" : "mic")
                            .font(.body.weight(.medium))
                            .foregroundStyle(isVoiceListening ? AppTheme.accent : AppTheme.inkSecondary)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(AppTheme.agentStatusBg))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isVoiceListening ? "Stop dictation" : "Dictate scene")
                }
            }

            if case .error(let msg) = voice.phase {
                Button {
                    voice.clearError()
                } label: {
                    Text(msg)
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(msg)
                .accessibilityHint("Dismisses the voice error")
            }
        }
    }

    private func shutterRow(compact: Bool, hPad: CGFloat) -> some View {
        let outer: CGFloat = compact ? 68 : 76
        let inner: CGFloat = compact ? 56 : 62
        // Fixed side slots keep the shutter optically centered: last-photo
        // thumbnail on the left, Auto Optimize primary CTA on the right.
        let sideSlot: CGFloat = compact ? 108 : 124

        return VStack(spacing: 4) {
            // Mode announced once, small label above the shutter.
            if let modeTitle = finderModeTitle {
                Text(modeTitle)
                    .font(AppTheme.overline())
                    .foregroundStyle(AppTheme.inkSecondary)
                    .allowsHitTesting(false)
            }

            HStack(spacing: 0) {
                // Last captured photo — opens the library.
                lastPhotoButton(compact: compact)
                    .frame(width: sideSlot, alignment: .leading)

                Spacer(minLength: 0)

                Button {
                    Analytics.shared.track("shutter_tap", props: ["source": "camera"])
                    Task { await takePhoto() }
                } label: {
                    ZStack {
                        Circle()
                            .stroke(AppTheme.shutterRing, lineWidth: compact ? 3 : 4)
                            .frame(width: outer, height: outer)
                        Circle()
                            .fill(AppTheme.shutterCore.opacity(isCapturing ? 0.55 : 1))
                            .frame(width: inner, height: inner)
                    }
                    .scaleEffect(shutterPressScale)
                }
                .buttonStyle(.plain)
                .disabled(isCapturing)
                .accessibilityLabel("Shutter")
                // Hold to compare: long-press shows the original. Replaces the
                // old Hold to compare pill.
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                        guard session.activeCreativeLook != nil || session.previewLUTId != nil else { return }
                        comparingOriginal = true
                        // Phase 3 outcome label: user inspected before vs after.
                        Analytics.shared.track("optimize_beforeafter_toggle", props: [
                            "expanded": "1",
                            "recipe_id": optimizer.chosenRecipeId ?? "",
                            "run_id": optimizer.lastRunId ?? "",
                        ])
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0).onEnded { _ in
                        if comparingOriginal { comparingOriginal = false }
                    }
                )

                Spacer(minLength: 0)

                // Auto Optimize — the primary CTA, right of the shutter.
                aoPrimaryButton(compact: compact)
                    .frame(width: sideSlot, alignment: .trailing)
            }
        }
        .padding(.horizontal, hPad)
    }

    /// Auto Optimize as the primary finder CTA: filled accent, sparkles icon.
    /// Keeps the running state (ProgressView + "Working…") and disabled-while-running.
    private func aoPrimaryButton(compact: Bool) -> some View {
        Button {
            Analytics.shared.track("ao_tap", props: ["source": "finder"])
            Task { await runOptimize(trigger: "manual") }
        } label: {
            HStack(spacing: 6) {
                if optimizer.phase.isRunning {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(AppTheme.accentOnAccent)
                } else {
                    Image(systemName: "sparkles")
                        .font(.callout.weight(.bold))
                }
                Text(optimizer.phase.isRunning ? "Working…" : "Optimize")
                    .font(AppTheme.bodySmMedium())
            }
            .foregroundStyle(AppTheme.accentOnAccent)
            .padding(.horizontal, compact ? 14 : 16)
            .padding(.vertical, compact ? 10 : 12)
            .background(
                Capsule()
                    .fill(AppTheme.accent)
                    .shadow(color: AppTheme.accent.opacity(0.35), radius: 8, x: 0, y: 2)
            )
            .opacity(optimizer.phase.isRunning ? 0.85 : 1)
        }
        .buttonStyle(.plain)
        .disabled(optimizer.phase.isRunning)
        .accessibilityLabel("Auto Optimize")
        .accessibilityHint("Runs Auto Optimize on the current scene")
    }

    /// Last captured photo thumbnail — opens that photo full screen. Subtle
    /// placeholder until the first capture this session, when it opens Photos
    /// (add-only library access, so we can't read earlier shots ourselves).
    private func lastPhotoButton(compact: Bool) -> some View {
        Button {
            Analytics.shared.track("last_photo_tap", props: ["source": "finder"])
            if lastCaptureImage != nil {
                showLastPhoto = true
            } else if let url = URL(string: "photos-redirect://") {
                UIApplication.shared.open(url)
            }
        } label: {
            Group {
                if let img = lastCaptureImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(AppTheme.inkTertiary)
                }
            }
            .frame(width: compact ? 50 : 56, height: compact ? 50 : 56)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Last photo")
        .accessibilityHint("Opens your most recent photo")
    }

    // MARK: - Chrome revamp: side rails + controls drawer

    /// Opens the slide-out controls drawer on the given tab.
    private func openControlsDrawer(tab: ControlsSheet.Tab) {
        drawerTab = tab
        if tab == .looks, let active = session.activeCreativeLook {
            drawerLookIntensity = active.resolvedIntensity
        } else if tab == .looks, let suggested = optimizer.suggestedLook {
            drawerLookIntensity = suggested.resolvedIntensity
        }
        Analytics.shared.track("controls_drawer_open", props: ["tab": tab.rawValue])
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            showControlsDrawer = true
        }
    }

    private func drawerWidth(compact: Bool) -> CGFloat { compact ? 264 : 288 }

    /// Side chrome: controls drawer (left, slides as one unit with its handle)
    /// and the filter rail (right edge). Vertically centered between the top
    /// and bottom chrome so the feed's center stays clear.
    private func sideChrome(compact: Bool, topInset: CGFloat, bottomInset: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            // Drawer panel + attached handle — one sliding unit. Closed, only
            // the handle peeks out at the left edge.
            HStack(spacing: 0) {
                controlsDrawerPanel(compact: compact)
                    .frame(width: drawerWidth(compact: compact))
                    .frame(maxHeight: .infinity)
                drawerHandleButton(compact: compact)
                    .padding(.leading, 6)
            }
            .frame(maxHeight: .infinity)
            .offset(x: showControlsDrawer ? 0 : -drawerWidth(compact: compact))
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: showControlsDrawer)

            // Filter rail pinned to the right edge.
            filterRail(compact: compact)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, 8)
        }
        .padding(.top, topInset + 12)
        .padding(.bottom, bottomInset + 12)
    }

    /// Big, easy-to-tap handle for the controls drawer. Toggles open/closed.
    private func drawerHandleButton(compact: Bool) -> some View {
        Button {
            if showControlsDrawer {
                Analytics.shared.track("controls_drawer_close", props: ["source": "handle"])
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    showControlsDrawer = false
                }
            } else {
                openControlsDrawer(tab: drawerTab)
            }
        } label: {
            Image(systemName: showControlsDrawer ? "chevron.left" : "slider.horizontal.3")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
                .frame(width: 56, height: 56)
                .background(Circle().fill(Color.black.opacity(0.45)))
                .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showControlsDrawer ? "Close controls" : "Open controls")
        .accessibilityHint("Slides the manual controls drawer in or out")
    }

    /// The slide-out drawer panel. Mostly transparent (ultra-thin material) and
    /// narrow so the camera feed stays visible behind and around it.
    private func controlsDrawerPanel(compact: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    Analytics.shared.track("controls_drawer_close", props: ["source": "chevron"])
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        showControlsDrawer = false
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppTheme.inkSecondary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close controls")

                Text("Controls")
                    .font(AppTheme.bodySmMedium())
                    .foregroundStyle(AppTheme.ink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ControlsSheet.Tab.allCases) { t in
                        Button {
                            drawerTab = t
                        } label: {
                            Text(t.rawValue)
                                .font(AppTheme.caption().weight(.semibold))
                                .foregroundStyle(drawerTab == t ? AppTheme.accentOnAccent : AppTheme.inkSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(drawerTab == t ? AppTheme.accent : Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(t.rawValue) controls")
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.bottom, 8)

            ScrollView {
                ControlsPanelView(
                    session: session,
                    optimizer: optimizer,
                    tab: drawerTab,
                    lookIntensity: $drawerLookIntensity,
                    onLookApplied: { look in
                        Analytics.shared.track("look_applied", props: ["look_id": look.id, "source": "drawer"])
                    }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
        )
        .padding(.vertical, 4)
    }

    /// Right-edge vertical rail of filter/look icon buttons. Tapping applies
    /// the look through the same path as the Looks tab.
    private var filterRailLooks: [(id: String, icon: String)] {
        [
            ("warmGlow", "sun.max"),
            ("goldenHour", "sunset"),
            ("monoInk", "circle.lefthalf.filled"),
            ("crispCool", "snowflake"),
            ("moodyFilm", "film"),
        ]
    }

    private func filterRail(compact: Bool) -> some View {
        VStack(spacing: compact ? 10 : 12) {
            filterRailButton(
                icon: "slash.circle",
                label: "No look",
                isActive: session.activeCreativeLook == nil,
                action: clearRailLook
            )
            ForEach(filterRailLooks, id: \.id) { item in
                filterRailButton(
                    icon: item.icon,
                    label: CreativeLookCatalog.displayName(for: item.id),
                    isActive: session.activeCreativeLook?.id == item.id,
                    action: { applyRailLook(id: item.id) }
                )
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background(Capsule().fill(Color.black.opacity(0.35)))
    }

    private func filterRailButton(icon: String, label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.body.weight(isActive ? .bold : .medium))
                .foregroundStyle(isActive ? AppTheme.accentOnAccent : AppTheme.ink)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(isActive ? AppTheme.accent : Color.white.opacity(0.12))
                        .overlay(Circle().stroke(isActive ? AppTheme.accent : Color.white.opacity(0.25), lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint(isActive ? "Active look" : "Applies this look")
    }

    private func applyRailLook(id: String) {
        guard entitlements.canApplyDials else {
            entitlements.presentHardPaywall(trigger: "dials_locked")
            return
        }
        let look = CreativeLook(id: id, intensity: CreativeLookCatalog.defaultIntensity)
        session.setActiveLook(look)
        optimizer.dismissSuggestedLook()
        Analytics.shared.track("look_applied", props: ["look_id": id, "source": "filter_rail"])
        optimizer.markDirty(session: session)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func clearRailLook() {
        if let look = session.activeCreativeLook, look.id == optimizer.autoAppliedLookId {
            optimizer.autoAppliedLookId = nil
        }
        session.clearActiveLook()
        Analytics.shared.track("look_undone", props: ["source": "filter_rail"])
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Mode title for the small label above the shutter — announced once.
    private var finderModeTitle: String? {
        Recipe.chromeTitle(
            forStoredTitle: session.appliedRecipeTitle,
            id: session.appliedRecipeId
        )
    }

    private var lookChipMode: LookChip.Mode? {
        if let active = session.activeCreativeLook {
            return .active(active)
        }
        if let suggested = optimizer.suggestedLook {
            return .suggested(suggested)
        }
        return nil
    }

    /// Shared Free Peek Optimize pool remaining (Pro / unlimited → true). Used for auto re-run gate + paywall on tap — not for button disabled/gray.
    private var canOptimize: Bool { optimizer.canRun(entitlements: entitlements) }

    private var ruleOfThirds: some View {
        GeometryReader { g in
            Path { p in
                let w = g.size.width, h = g.size.height
                p.move(to: .init(x: w/3, y: 0)); p.addLine(to: .init(x: w/3, y: h))
                p.move(to: .init(x: 2*w/3, y: 0)); p.addLine(to: .init(x: 2*w/3, y: h))
                p.move(to: .init(x: 0, y: h/3)); p.addLine(to: .init(x: w, y: h/3))
                p.move(to: .init(x: 0, y: 2*h/3)); p.addLine(to: .init(x: w, y: 2*h/3))
            }
            .stroke(Color.white.opacity(0.22), lineWidth: 1)
        }
    }

    // MARK: - Actions

    /// Live STT: paint base + current utterance (partial or final) without flash-empty.
    private func applyCameraVoicePartial(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if voiceDictationBase.isEmpty {
            sceneNote = t
        } else if t.isEmpty {
            sceneNote = voiceDictationBase
        } else {
            sceneNote = voiceDictationBase + " " + t
        }
        sceneFromViewfinder = false
    }

    /// Endpointed utterance (silence pause or tap-Stop): APPLY-FILTERS → Recommend SSE
    /// with **this utterance** as message (server #119 forces B&W → monoInk); else AO.
    /// Latest utterance cancels any in-flight Recommend/AO — looks don't stack.
    private func applyCameraVoiceFinal(_ text: String) {
        // Partials already paint the full Speech transcript into sceneNote for display.
        // Intent matching + Recommend message use **last utterance only**, not the note.
        let plan = ApplyFiltersIntent.planVoiceEndpoint(text)
        if plan.cancelInFlight {
            cancelInFlightVoiceIntent()
        }
        switch plan.action {
        case .none:
            return
        case .recommend(let utterance):
            if applyNamedLookLocally(utterance, source: "voice") { return }
            // Pass utterance as Recommend message so server look-force (monoInk @ 0.55) sees B&W.
            voiceIntentTask = Task { await runRecommend(messageOverride: utterance) }
        case .optimize:
            // Default mic path: Auto Optimize → applyPhoneTargets (PR #11); AO Pass 2 keeps autoApplyLook false.
            voiceIntentTask = Task { await runOptimize(trigger: "voice") }
        }
    }

    /// Cancel prior voice-driven Recommend/AO so a later utterance replaces (e.g. warm → B&W).
    private func cancelInFlightVoiceIntent() {
        voiceIntentTask?.cancel()
        voiceIntentTask = nil
        if optimizer.phase.isRunning {
            optimizer.clear()
        }
        if isRecommending {
            isRecommending = false
            recommendStreamStatus = nil
            recommendStreamPhase = nil
        }
    }

    private func refreshSceneFromViewfinder(auto: Bool = true) async {
        if auto {
            // Automatic probes never clobber text the user typed themselves.
            if !sceneNote.isEmpty && !sceneFromViewfinder { return }
            // One automatic caption per camera visit is enough — tab switches
            // must not re-sense or burn anything.
            if let last = lastSceneDescribeAt, Date().timeIntervalSince(last) < 30 { return }
        }
        describeTask?.cancel()
        lastSceneDescribeAt = Date()
        let task = Task { @MainActor in
            isDescribingScene = true
            defer { isDescribingScene = false }
            // Local only: caption from the on-device scene sensor.
            // No probe capture, no network — the Grok auto-upload is gone.
            var features = await SceneSensor.shared.current().features
            if await SceneSensor.shared.current().age > 1.0 {
                let metering = session.meteringSample()
                if let fresh = await SceneSensor.shared.refreshNow(metering: metering, note: sceneNote) {
                    features = fresh
                }
            }
            let caption = SceneChipText.make(features: features)
            // Never clobber live STT / typed note while mic is active.
            if case .recording = voice.phase { return }
            if case .uploading = voice.phase { return }
            if case .requestingPermission = voice.phase { return }
            if sceneNote.isEmpty || sceneFromViewfinder {
                sceneNote = caption
                sceneFromViewfinder = true
            }
        }
        describeTask = task
        await task.value
    }

    private func runOptimize(trigger: String = "manual", parentRunId: String? = nil) async {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        // Quota exhausted (not Pro/unlimited): paywall + visible error/toast — never silent.
        // Quota counts successful optimizes only; free_quota_hit is tracked by presentHardPaywall.
        guard canOptimize else {
            // Automatic runs never surface the hard gate.
            guard trigger == "manual" || trigger == "voice" || trigger == "deep_link" else { return }
            print("[AO] tap → paywall (quota exhausted)")
            entitlements.presentHardPaywall(trigger: "free_quota", force: true)
            optimizer.phase = .error("Free Peek limit reached — upgrade for more")
            presentChromeToast("Free Peek limit — see Pro")
            Analytics.shared.track("auto_optimize_fail", props: ["error_code": "quota", "error_class": "quota", "path": "camera_tap", "trigger": trigger])
            return
        }
        if optimizer.phase.isRunning {
            print("[AO] tap ignored — already running phase=\(optimizer.phase.statusCopy)")
            return
        }
        print("[AO] tap → run sceneNoteChars=\(sceneNote.count)")
        await optimizer.run(
            session: session,
            entitlements: entitlements,
            preferStagedRecipeId: AutoOptimizeController.pinnedRecipeId(
                staged: router.stagedRecipeId,
                applied: session.appliedRecipeId,
                aoChosen: optimizer.chosenRecipeId),
            sceneNote: sceneNote,
            elevationDegrees: horizon.isAvailable ? horizon.cameraElevationDegrees : nil,
            handShake: horizon.isAvailable ? horizon.handShakeRadPerSec : nil,
            isTripodSteady: horizon.isAvailable ? horizon.isTripodSteady : nil,
            trigger: trigger,
            parentRunId: parentRunId
        )
        // applyFeedbackToken / phase drive burst, toast, or error pill — never silent.
        if case .ready = optimizer.phase {
            let title = optimizer.chosenRecipeTitle ?? session.appliedRecipeTitle ?? "recipe"
            print("[AO] ready recipe=\(title) diffs=\(optimizer.coreDiffs.count)")
            // Query applied — clear the box for the next one (user-initiated runs only).
            if trigger == "manual" || trigger == "voice" { sceneNote = "" }
            // Soft Pro nudge once after first success — never blocks the result.
            entitlements.presentSoftNudgeIfNeeded(trigger: "post_first_optimize")
            if session.activeCreativeLook != nil {
                presentLookToastIfNeeded()
            }
        } else if case .error(let msg) = optimizer.phase {
            // Failure: original preserved, button reads "Try Auto Optimize", no paywall.
            print("[AO] error \(msg)")
        }
    }

    private func undoOptimize() {
        comparingOriginal = false
        optimizer.undo(session: session)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        presentChromeToast("Original restored")
    }

    /// Guided first win: the first capture in a new install auto-runs the local optimizer once
    /// (not on camera open). Skipped after a prior undo / opt-out or while anything is running.
    private func maybeAutoRunFirstOptimize(isFirstCapture: Bool) async {
        guard isFirstCapture, FirstWinAutoRun.isEligible else { return }
        guard !optimizer.phase.isRunning, !isRecommending, canOptimize, session.isRunning else { return }
        FirstWinAutoRun.markAttempted()
        await runOptimize(trigger: "auto_first_capture")
    }

    private func dismissPostSaveCard(action: String) {
        withAnimation(.easeOut(duration: 0.18)) { postSaveCard = nil }
        Analytics.shared.track("post_save_card_action", props: ["action": action])
    }

    /// Live chrome copy while Recommend SSE is in flight (nil when idle).
    private var recommendChromeStatus: String? {
        guard isRecommending else { return nil }
        if let s = recommendStreamStatus, !s.isEmpty { return s }
        return "Matching a recipe…"
    }

    /// Hide dead-end “not available” / “guidance only” banners after Recommend; keep dial clamps.
    /// Coach recommend from viewfinder frame and/or scene note.
    /// Uses `recommendStream` for live status; falls back to non-stream `recommend` if SSE fails to start.
    /// Apply writes recipe + phoneTargets via applyPhoneTargets (same as AO) from the result sheet.
    /// - Parameter messageOverride: when set (voice APPLY-FILTERS), sent as Recommend `message`
    ///   instead of the full Scene note so server look-force + intent use last utterance only.
    private func runRecommend(messageOverride: String? = nil) async {
        recommendError = nil
        recommendResult = nil
        recommendStreamStatus = "Matching a recipe…"
        recommendStreamPhase = nil
        isRecommending = true
        defer {
            isRecommending = false
            recommendStreamStatus = nil
            recommendStreamPhase = nil
        }

        let note = sceneNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let override = messageOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
        var jpeg: Data?
        do {
            try Task.checkCancellation()
            let raw = try await session.captureProbeFrame()
            try Task.checkCancellation()
            if let img = UIImage(data: raw), let c = APIClient.compressForVision(img) {
                jpeg = c
            } else if !raw.isEmpty {
                jpeg = raw
            }
        } catch is CancellationError {
            return
        } catch {
            // Soft-fail probe; may still recommend from scene note alone.
        }

        let hadHeldFrame = jpeg != nil
        let fromVoice = !(override?.isEmpty ?? true)
        Analytics.shared.track("recommend_cta_tap", props: [
            "surface": "camera",
            "source": fromVoice ? "voice_endpoint" : "shutter_row",
            "had_held_frame": hadHeldFrame ? "true" : "false",
        ])

        let message: String
        if let override, !override.isEmpty {
            message = override
        } else if !note.isEmpty {
            message = note
        } else if jpeg != nil {
            message = "From viewfinder"
        } else {
            recommendError = "Add a scene note or enable the camera"
            showRecommendResult = true
            return
        }

        let streamStarted = RecommendStreamStartFlag()
        do {
            try Task.checkCancellation()
            let response = try await APIClient.shared.recommendStream(
                message: message,
                favorites: Array(entitlements.favoriteIds),
                imageJPEGData: jpeg
            ) { event in
                streamStarted.mark()
                // Deliver on main without waiting for the SSE read task to finish (see RecommendStreamEvent note).
                if Thread.isMainThread {
                    applyRecommendStreamEvent(event)
                } else {
                    DispatchQueue.main.async {
                        applyRecommendStreamEvent(event)
                    }
                }
            }
            try Task.checkCancellation()
            recommendResult = response
            recommendError = nil
            // Prefer auto-apply so the viewfinder changes immediately (autoApplyLook: true; no schema change).
            // Server #119 may force monoInk @ 0.55 for B&W utterances.
            if let recipe = response.preset ?? BundledPresets.recipe(id: response.resolvedPresetId ?? "") {
                applyRecommendToCamera(recipe: recipe, response: response, message: message)
            } else {
                // Look-only payload (no recipe) — still auto-apply creativeLook onto finder.
                applyRecommendLookOnly(response: response, message: message)
            }
            assertApplyFiltersLook(message: message, response: response)
            // Query applied — clear the box for the next one.
            sceneNote = ""
            // Voice auto-apply: toast look name; skip result sheet so no second tap.
            if fromVoice, session.activeCreativeLook != nil {
                showRecommendResult = false
            } else {
                showRecommendResult = true
            }
            await entitlements.refresh()
        } catch is CancellationError {
            return
        } catch let APIError.paywall(payload) {
            recommendError = payload.error ?? "Free Peek limit reached. Upgrade to Pro."
            entitlements.presentHardPaywall(trigger: "recommend_quota", force: true)
            showRecommendResult = true
            await entitlements.refresh()
        } catch let APIError.missingKey(msg) {
            recommendError = msg
            showRecommendResult = true
        } catch {
            if streamStarted.value {
                recommendError = error.localizedDescription
                showRecommendResult = true
                return
            }
            // Stream failed to start — fall back to non-stream recommend.
            recommendStreamStatus = "Matching a recipe…"
            do {
                try Task.checkCancellation()
                let response = try await APIClient.shared.recommend(
                    message: message,
                    favorites: Array(entitlements.favoriteIds),
                    imageJPEGData: jpeg
                )
                try Task.checkCancellation()
                recommendResult = response
                recommendError = nil
                if let recipe = response.preset ?? BundledPresets.recipe(id: response.resolvedPresetId ?? "") {
                    applyRecommendToCamera(recipe: recipe, response: response, message: message)
                } else {
                    applyRecommendLookOnly(response: response, message: message)
                }
                assertApplyFiltersLook(message: message, response: response)
                // Query applied — clear the box for the next one.
                sceneNote = ""
                if fromVoice, session.activeCreativeLook != nil {
                    showRecommendResult = false
                } else {
                    showRecommendResult = true
                }
                await entitlements.refresh()
            } catch is CancellationError {
                return
            } catch let APIError.paywall(payload) {
                recommendError = payload.error ?? "Free Peek limit reached. Upgrade to Pro."
                entitlements.presentHardPaywall(trigger: "recommend_quota", force: true)
                showRecommendResult = true
                await entitlements.refresh()
            } catch let APIError.missingKey(msg) {
                recommendError = msg
                showRecommendResult = true
            } catch {
                recommendError = error.localizedDescription
                showRecommendResult = true
            }
        }
    }


    /// When Recommend returns creativeLook without a resolvable recipe, still bake onto finder.
    private func applyRecommendLookOnly(response: RecommendResponse, message: String? = nil) {
        guard let targets = mergeCreativeLook(response: response, message: message),
              targets.creativeLook != nil || response.creativeLook != nil || ApplyFiltersIntent.forcedLook(for: message ?? "") != nil else { return }
        if entitlements.canApplyDials {
            Task { @MainActor in _ = await session.applyPhoneTargets(targets, autoApplyLook: true) }
        } else if let look = targets.creativeLook ?? response.creativeLook {
            session.setActiveLook(look)
        }
        session.suppressDeadEndClampMessages()
        if session.activeCreativeLook != nil {
            optimizer.suggestedLook = nil
        }
        presentLookToastIfNeeded()
    }

    private func presentLookToastIfNeeded() {
        guard let look = session.activeCreativeLook else { return }
        let copy = "Look · \(look.displayName)"
        lookToast = copy
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            if lookToast == copy { lookToast = nil }
        }
    }

    /// Client matched APPLY-FILTERS but server returned no creativeLook — never silent no-op.
    /// B&W is covered by client forcedLook (parity with server #119) so skip the toast when we force.
    private func assertApplyFiltersLook(message: String, response: RecommendResponse) {
        guard ApplyFiltersIntent.matches(message) else { return }
        if ApplyFiltersIntent.resolvedLook(from: response) != nil { return }
        if ApplyFiltersIntent.forcedLook(for: message) != nil { return }
        recommendError = ApplyFiltersIntent.missingLookMessage
        presentChromeToast(ApplyFiltersIntent.missingLookMessage)
        Analytics.shared.track("apply_filters_missing_look", props: [
            "surface": "camera",
            "message_chars": "\(message.count)",
        ])
    }

    /// Merge phoneTargets.creativeLook ← top-level ← B&W force (client parity with server #119).
    private func mergeCreativeLook(response: RecommendResponse?, message: String?) -> PhoneTargets? {
        ApplyFiltersIntent.mergeCreativeLook(response: response, message: message)
    }

    /// Apply Recommend recipe + phoneTargets + creativeLook onto the live viewfinder (dials + bake path).
    private func applyRecommendToCamera(recipe: Recipe, response: RecommendResponse?, message: String? = nil) {
        let targets = mergeCreativeLook(response: response, message: message)
        let canApplyDials = entitlements.canApplyDials
        // Applies are async now (awaitable exposure writes); the dial-write
        // branch runs on the main actor right after.
        Task { @MainActor in
            _ = await session.apply(recipe: recipe)
            if canApplyDials, let targets {
                _ = await session.applyPhoneTargets(targets, autoApplyLook: true)
            }
        }
        if !(canApplyDials && targets != nil), let look = targets?.creativeLook ?? response?.creativeLook {
            // Free Peek may lock dials — still bake the look onto preview/still so the finder changes.
            session.setActiveLook(look)
            if let lut = targets?.previewLUT, !lut.isEmpty {
                session.previewLUTId = lut
            }
        }
        session.suppressDeadEndClampMessages()
        // Promote look onto AO chip state as active (not merely suggested).
        if session.activeCreativeLook != nil {
            optimizer.suggestedLook = nil
        }
        // e.g. "Look · Mono Ink" after B&W → monoInk @ 0.55 auto-apply (no second Apply tap).
        presentLookToastIfNeeded()
        Analytics.shared.track("recommend_applied", props: [
            "recipe_id": recipe.id,
            "has_look": session.activeCreativeLook != nil ? "true" : "false",
            "has_lut": session.previewLUTId != nil ? "true" : "false",
            "look_id": session.activeCreativeLook?.id ?? "",
        ])
    }

    private func applyRecommendStreamEvent(_ event: RecommendStreamEvent) {
        switch event {
        case .phase(let phase):
            recommendStreamPhase = phase
            if let copy = RecommendStreamEvent.statusCopy(forPhase: phase) {
                recommendStreamStatus = copy
            } else if !phase.isEmpty, phase != "done", phase != "error" {
                recommendStreamStatus = phase.replacingOccurrences(of: "_", with: " ").capitalized + "…"
            }
        case .status(let message):
            recommendStreamStatus = message
        case .error(let message, _):
            recommendError = message
        case .reasoning, .content, .result:
            break
        }
    }

    private func takePhoto() async {
        guard !isCapturing else { return }
        isCapturing = true
        optimizer.isUserCaptureInFlight = true
        captureError = nil
        dismissSceneKeyboard()

        // Immediate shutter press: scale + medium impact (don't wait for AVCapture).
        withAnimation(.easeOut(duration: 0.07)) { shutterPressScale = 0.86 }
        let medium = UIImpactFeedbackGenerator(style: .medium)
        medium.prepare()
        medium.impactOccurred()

        do {
            let data = try await session.capturePhoto()
            // Refresh the finder last-photo thumbnail.
            if let img = UIImage(data: data) { lastCaptureImage = img }
            // Unlock shutter ASAP — feedback overlays must not gate the next shot.
            isCapturing = false
            optimizer.isUserCaptureInFlight = false
            withAnimation(.spring(response: 0.28, dampingFraction: 0.52)) {
                shutterPressScale = 1.0
            }
            // Unmissable viewfinder flash + freeze on every successful capture return
            // (do NOT wait for Photos library write).
            playCaptureFeedback(jpeg: data)
            let isFirstCapture = !PushNotificationManager.shared.hasCompletedFirstCapture
            // Flags first capture + re-registers an existing grant (no prompt here).
            PushNotificationManager.shared.noteFirstSuccessfulCapture()
            let optimizedAtCapture: Bool = {
                if case .ready = optimizer.phase { return true }
                return false
            }()

            do {
                try await PhotoLibrarySaver.saveJPEG(data)
                Analytics.shared.track("capture_success", props: [
                    "source": "camera",
                    "is_first_capture": isFirstCapture ? "1" : "0",
                    "permission_state": "authorized",
                    "optimized": optimizedAtCapture ? "1" : "0",
                ])
                presentSavedChip()
                if optimizedAtCapture, PostSaveCelebration.shouldShow {
                    PostSaveCelebration.markShown()
                    let offer = !PushNotificationManager.shared.didAskPushPermission
                    postSaveCard = PostSaveCard.Model(
                        image: UIImage(data: data),
                        recipeTitle: Recipe.chromeTitle(
                            forStoredTitle: optimizer.chosenRecipeTitle ?? session.appliedRecipeTitle,
                            id: optimizer.chosenRecipeId ?? session.appliedRecipeId
                        ),
                        settingsCount: optimizer.coreDiffs.count,
                        lookName: session.activeCreativeLook?.displayName,
                        offerReminder: offer
                    )
                    Analytics.shared.track("post_save_card_view", props: ["offer_reminder": offer ? "1" : "0"])
                }
            } catch {
                // Capture already succeeded — keep flash/freeze; surface save error only.
                captureError = error.localizedDescription
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
            await maybeAutoRunFirstOptimize(isFirstCapture: isFirstCapture)
        } catch {
            isCapturing = false
            optimizer.isUserCaptureInFlight = false
            withAnimation(.easeOut(duration: 0.15)) { shutterPressScale = 1.0 }
            captureError = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    /// Full-bleed white flash + freeze of captured JPEG + heavy haptic.
    /// Runs on every successful `capturePhoto` return — never gated on Photos save.
    private func playCaptureFeedback(jpeg: Data) {
        captureFeedbackTask?.cancel()
        // Section D: the FINAL dial state is labeled at capture — the deferred
        // `optimize_dial_override` event fires here (or after 3 s of dial
        // inactivity, whichever comes first).
        optimizer.recordPendingOverrideLabel()
        // Section D: fire the armed opt-in bracket right after the user's own
        // capture (they're holding still on this scene) — before
        // takeRecentRunIdForCapture consumes the run id.
        bracketCapture.userCaptureDidComplete(session: session)
        // Outcome of the last optimize when the shutter lands within 30 s.
        if let runId = optimizer.takeRecentRunIdForCapture() {
            let secondsAfterReady = optimizer.lastRunDate
                .map { max(0, Int(Date().timeIntervalSince($0))) } ?? -1
            Analytics.shared.track("optimize_photo_captured", props: [
                "recipe_id": optimizer.chosenRecipeId ?? session.appliedRecipeId ?? "",
                "run_id": runId,
                "seconds_after_ready": "\(secondsAfterReady)",
            ])
        }
        let freeze = UIImage(data: jpeg) ?? session.lastThumb
        // Heavy shutter thunk immediately — B20 deferred this until after library save.
        let heavy = UIImpactFeedbackGenerator(style: .heavy)
        heavy.prepare()
        heavy.impactOccurred(intensity: 1.0)

        // Snap flash + freeze on with zero animation so the blink cannot be skipped.
        var flashTxn = Transaction()
        flashTxn.disablesAnimations = true
        withTransaction(flashTxn) {
            showCaptureFlash = true
            captureFreezeImage = freeze
        }
        // Ensure a layout pass before we schedule fade — avoids clearing before first paint.
        captureFeedbackTask = Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(nanoseconds: 180_000_000) // ~180ms solid white peak (was 80ms)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.16)) { showCaptureFlash = false }
            // Hold freeze so the still is readable (~550ms total).
            try? await Task.sleep(nanoseconds: 380_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) { captureFreezeImage = nil }
        }
    }

    /// Light non-modal confirmation — chrome stays out of the way of AO / Recommend.
    private func presentSavedChip() {
        savedChipTask?.cancel()
        withAnimation(.easeOut(duration: 0.14)) { showSavedChip = true }
        savedChipTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.18)) { showSavedChip = false }
        }
    }

    /// Return key on the scene field: same routing as a spoken utterance
    /// (look request → Recommend, anything else → Auto Optimize).
    private func submitSceneQuery() {
        dismissSceneKeyboard()
        let plan = ApplyFiltersIntent.planVoiceEndpoint(sceneNote)
        if plan.cancelInFlight {
            cancelInFlightVoiceIntent()
        }
        switch plan.action {
        case .none:
            return
        case .recommend(let utterance):
            if applyNamedLookLocally(utterance, source: "scene_field") { return }
            voiceIntentTask = Task { await runRecommend(messageOverride: utterance) }
        case .optimize:
            voiceIntentTask = Task { await runOptimize(trigger: "manual") }
        }
    }

    /// Named look ("black and white", "moody", …) → bake it onto the finder right away.
    /// No Recommend round trip: the look is already known, and waiting on the server meant
    /// a slow / failed / over-quota request left the finder unchanged.
    /// Returns false when the utterance names no look or dials are locked (server path decides).
    private func applyNamedLookLocally(_ utterance: String, source: String) -> Bool {
        guard entitlements.canApplyDials,
              var look = ApplyFiltersIntent.forcedLook(for: utterance) else { return false }
        // Asked-for B&W means no colour left — the default 0.55 blend still reads as colour.
        if look.id == "monoInk" { look.intensity = 1 }
        session.setActiveLook(look)
        optimizer.dismissSuggestedLook()
        optimizer.markDirty(session: session)
        Analytics.shared.track("look_applied", props: ["look_id": look.id, "source": source])
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        presentLookToastIfNeeded()
        // Query applied — clear the box for the next one.
        sceneNote = ""
        return true
    }

    private func dismissSceneKeyboard() {
        sceneFieldFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func consumePendingAutoOptimizeIfNeeded() async {
        guard router.consumePendingAutoOptimize() else { return }
        guard session.auth == .authorized else {
            // Re-stage so we retry after camera auth.
            router.pendingAutoOptimize = true
            return
        }
        if !session.isRunning {
            await session.start()
            horizon.start()
        }
        await runOptimize(trigger: "deep_link")
    }

    private func applyStagingIfNeeded() {
        guard let id = router.stagedRecipeId,
              let recipe = BundledPresets.recipe(id: id) else { return }
        // Recipe switch via Library shortly after an optimize — outcome of that run.
        if id != optimizer.chosenRecipeId,
           let runId = optimizer.lastRunId,
           let at = optimizer.lastRunDate,
           Date().timeIntervalSince(at) <= 30 {
            Analytics.shared.track("optimize_recipe_switched", props: [
                "from_recipe_id": optimizer.chosenRecipeId ?? "",
                "to_recipe_id": id,
                "source": "library",
                "run_id": runId,
            ])
        }
        if router.pendingApply {
            let stagedTargets = router.stagedPhoneTargets
            router.stagedPhoneTargets = nil
            router.pendingApply = false
            Task { @MainActor in
                _ = await session.apply(recipe: recipe)
                if let targets = stagedTargets {
                    // Ask / Recommend Apply → bake look immediately (same as runRecommend).
                    _ = await session.applyPhoneTargets(targets, autoApplyLook: true)
                }
            }
        } else {
            session.appliedRecipeId = recipe.id
            session.appliedRecipeTitle = recipe.title
        }
    }

    private func floatingIcon(
        _ system: String,
        accessibility: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .background(Circle().fill(Color.black.opacity(0.35)))
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .contentShape(Circle())
        .accessibilityLabel(accessibility ?? system)
    }

    private func cycleFlash() {
        session.flash = session.flash.next
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let mode = session.flash
        // Flash only fires on the next still (AVCapturePhotoSettings). Toast makes that obvious;
        // on the back camera, briefly pulse torch so “On” is also visible in the preview.
        switch mode {
        case .on:
            presentChromeToast("Flash On — next photo")
            session.pulseTorchForFlashPreview()
        case .auto:
            presentChromeToast("Flash Auto")
        case .off:
            presentChromeToast("Flash Off")
        }
    }

    private func flipCameraWithFeedback() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let goingFront = !session.isFront
        optimizer.resetForCameraFlip(session: session)
        session.flipCamera()
        presentChromeToast(goingFront ? "Front camera" : "Back camera")
    }

    private func presentChromeToast(_ message: String) {
        chromeToastTask?.cancel()
        withAnimation(.easeOut(duration: 0.15)) { chromeToast = message }
        chromeToastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.2)) { chromeToast = nil }
        }
    }

    private func presentApplyBurst() {
        applyBurstTask?.cancel()
        withAnimation(.easeOut(duration: 0.18)) { showApplyBurst = true }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        applyBurstTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.25)) { showApplyBurst = false }
        }
    }

    private func permissionCover(
        title: String,
        body: String,
        primary: String,
        primaryAction: @escaping () -> Void,
        secondary: String,
        secondaryAction: @escaping () -> Void
    ) -> some View {
        ZStack {
            AppTheme.cameraScrimStrong.ignoresSafeArea()
            VStack(alignment: .leading, spacing: AppTheme.space4) {
                Text(title)
                    .font(AppTheme.displayTitle())
                    .foregroundStyle(AppTheme.ink)
                Text(body)
                    .font(AppTheme.body())
                    .foregroundStyle(AppTheme.inkSecondary)
                Button(primary, action: primaryAction)
                    .buttonStyle(PrimaryButtonStyle(filled: true))
                Button(secondary, action: secondaryAction)
                    .font(AppTheme.bodySmMedium())
                    .foregroundStyle(AppTheme.inkSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .padding(AppTheme.space5)
        }
    }
}

struct CameraOverflowSheet: View {
    @Binding var showGrid: Bool
    var canTeach: Bool
    var recommendDisabled: Bool = false
    var isRecommending: Bool = false
    var isOptimizing: Bool = false
    var canUndo: Bool = false
    var onLibrary: () -> Void
    var onCoach: () -> Void
    var onSettings: () -> Void
    var onDials: () -> Void
    var onTeach: () -> Void
    var onRecipes: () -> Void
    var onRecommend: () -> Void
    var onAutoOptimize: () -> Void
    var onUndo: (() -> Void)?
    var onVoice: () -> Void
    var onRefreshScene: () -> Void
    var onClearRecipe: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        onLibrary()
                    } label: {
                        Label("Library", systemImage: "books.vertical.fill")
                    }
                    Button {
                        onCoach()
                    } label: {
                        Label("Coach", systemImage: "text.bubble.fill")
                    }
                    Button {
                        onSettings()
                    } label: {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                }
                Section {
                    Button {
                        onAutoOptimize()
                    } label: {
                        HStack {
                            Label(
                                isOptimizing ? "Optimizing…" : "Auto Optimize",
                                systemImage: "bolt.fill"
                            )
                            if isOptimizing {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isOptimizing)
                    if let onUndo, canUndo {
                        Button {
                            onUndo()
                        } label: {
                            Label("Undo optimize", systemImage: "arrow.uturn.backward")
                        }
                    }
                    Button {
                        onVoice()
                    } label: {
                        Label("Voice describe scene", systemImage: "mic.fill")
                    }
                    Button {
                        onRefreshScene()
                    } label: {
                        Label("Refresh scene from viewfinder", systemImage: "arrow.clockwise")
                    }
                }
                Section {
                    Button("Controls…", action: onDials)
                    if canTeach {
                        Button("Why this? (Teach)", action: onTeach)
                    }
                    Button("Recipes", action: onRecipes)
                    Button {
                        onRecommend()
                    } label: {
                        HStack {
                            Label(
                                isRecommending ? "Matching…" : "Recommend recipe",
                                systemImage: "sparkles"
                            )
                            if isRecommending {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(recommendDisabled)
                    .accessibilityLabel("Recommend recipe")
                    Toggle("Rule of thirds grid", isOn: $showGrid)
                    if let onClearRecipe {
                        Button("Clear recipe", role: .destructive, action: onClearRecipe)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.bg)
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct RecipePickerSheet: View {
    var onPick: (Recipe) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(BundledPresets.all) { recipe in
                Button { onPick(recipe) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recipe.title).font(AppTheme.bodyMedium()).foregroundStyle(AppTheme.ink)
                        Text(recipe.keySetting).font(AppTheme.monoSm()).foregroundStyle(AppTheme.inkSecondary)
                    }
                }
                .listRowBackground(AppTheme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.bg)
            .navigationTitle("Recipes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}


/// Coach recommend result from Camera lower-left Recommend (also ···).
/// Apply to Camera writes recipe dials + optional phoneTargets from JSON.
struct CameraRecommendResultSheet: View {
    let result: RecommendResponse?
    let errorText: String?
    var isLoading: Bool = false
    /// Live SSE status copy while matching (falls back to generic copy).
    var statusMessage: String? = nil
    var onApply: (Recipe) -> Void
    var onDismiss: () -> Void
    var onUpgrade: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var navigateRecipe: Recipe?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.space4) {
                    if isLoading && result == nil && (errorText == nil || errorText?.isEmpty == true) {
                        HStack(spacing: AppTheme.space3) {
                            ProgressView()
                            Text(statusMessage?.isEmpty == false ? statusMessage! : "Matching a recipe…")
                                .font(AppTheme.bodySm())
                                .foregroundStyle(AppTheme.inkSecondary)
                        }
                        .padding(AppTheme.space3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let errorText, !errorText.isEmpty {
                        VStack(alignment: .leading, spacing: AppTheme.space2) {
                            Text(errorText)
                                .font(AppTheme.bodySm())
                                .foregroundStyle(AppTheme.inkSecondary)
                            if errorText.lowercased().contains("limit") || errorText.lowercased().contains("upgrade") {
                                Button("Upgrade · 7-day trial", action: onUpgrade)
                                    .buttonStyle(PrimaryButtonStyle(filled: true))
                            }
                        }
                        .padding(AppTheme.space3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous)
                                .fill(AppTheme.surface2)
                        )
                    }

                    if let r = result {
                        resultCard(r)
                    }
                }
                .padding(AppTheme.space4)
            }
            .background(AppTheme.bg.ignoresSafeArea())
            .navigationTitle("Recommendation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        onDismiss()
                        dismiss()
                    }
                }
            }
            .navigationDestination(item: $navigateRecipe) { recipe in
                RecipeDetailView(recipe: recipe)
            }
        }
    }

    @ViewBuilder
    private func resultCard(_ r: RecommendResponse) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.space3) {
            HStack(spacing: 6) {
                if r.vision == true {
                    Circle().fill(AppTheme.vision).frame(width: 6, height: 6)
                }
                Text(r.vision == true ? "From viewfinder" : "Recommendation")
                    .font(AppTheme.overline())
                    .tracking(0.8)
                    .foregroundStyle(AppTheme.inkTertiary)
            }

            let recipe = r.preset ?? BundledPresets.recipe(id: r.resolvedPresetId ?? "")
            if let recipe {
                Text(recipe.title)
                    .font(AppTheme.displayTitle())
                    .foregroundStyle(AppTheme.ink)
            }

            if let reason = r.reason {
                Text(reason)
                    .font(AppTheme.bodySm())
                    .foregroundStyle(AppTheme.inkSecondary)
            }

            HStack(spacing: AppTheme.space2) {
                if let recipe {
                    Button {
                        navigateRecipe = recipe
                    } label: {
                        Text("Open recipe")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle(filled: true))

                    Button {
                        onApply(recipe)
                        dismiss()
                    } label: {
                        Label("Apply to Camera", systemImage: "camera.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle(filled: true))
                }
                Button {
                    onDismiss()
                    dismiss()
                } label: {
                    Text("Try another")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(filled: false))
            }
        }
        .padding(AppTheme.space4)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous)
                .fill(AppTheme.surface2)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 1)
                )
        )
    }
}


/// Short-lived on-finder confirmation when Auto Optimize writes phoneTargets.
/// Lists before→after dial deltas, then collapses into BeforeAfterChip.
struct ApplyBurstBanner: View {
    let diffs: [AutoOptimizeController.DiffLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.accent)
                Text("Settings applied")
                    .font(AppTheme.bodySmMedium())
                    .foregroundStyle(AppTheme.ink)
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(diffs.prefix(5)) { d in
                    HStack(spacing: 6) {
                        Text(d.label)
                            .font(AppTheme.overline())
                            .foregroundStyle(AppTheme.inkTertiary)
                            .frame(width: 52, alignment: .leading)
                        Text(d.before)
                            .font(AppTheme.monoSm())
                            .foregroundStyle(AppTheme.diffBefore)
                            .strikethrough()
                        Text("→")
                            .font(AppTheme.caption())
                            .foregroundStyle(AppTheme.inkTertiary)
                        Text(d.after)
                            .font(AppTheme.monoSm())
                            .foregroundStyle(AppTheme.diffAfter)
                        if d.clamped {
                            Text("clamped")
                                .font(AppTheme.overline())
                                .foregroundStyle(AppTheme.warn)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous)
                .fill(AppTheme.agentStatusBg)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous)
                        .stroke(AppTheme.accent.opacity(0.55), lineWidth: 1.5)
                )
        )
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        .accessibilityLabel(diffs.map { "\($0.label) \($0.before) to \($0.after)" }.joined(separator: ", "))
    }
}

/// Full-screen view of the most recent capture (pinch to zoom, tap ✕ to return to the finder).
private struct LastPhotoViewer: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(zoom * pinch)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gesture(
                    MagnificationGesture()
                        .updating($pinch) { value, state, _ in state = value }
                        .onEnded { zoom = min(max(zoom * $0, 1), 5) }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.easeOut(duration: 0.2)) { zoom = zoom > 1 ? 1 : 2.5 }
                }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(Circle().fill(Color.white.opacity(0.18)))
            }
            .padding(16)
            .accessibilityLabel("Close")
        }
    }
}

/// Thread-safe flag: true once any Recommend SSE event arrives (vs. fail-to-start).
final class RecommendStreamStartFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var started = false
    var value: Bool {
        lock.lock(); defer { lock.unlock() }
        return started
    }
    func mark() {
        lock.lock(); started = true; lock.unlock()
    }
}
