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

    @State private var sceneNote = ""
    @State private var sceneFromViewfinder = false
    @State private var sceneExpanded = false
    /// Snapshot of sceneNote when dictation starts — partials replace utterance, not append.
    @State private var voiceDictationBase = ""
    @State private var isDescribingScene = false
    @State private var showMicDenied = false
    @State private var describeTask: Task<Void, Never>?

    @State private var showDials = false
    @State private var showTeach = false
    @State private var showRecipePicker = false
    @State private var showOverflow = false
    @State private var showClearConfirm = false
    @State private var isCapturing = false
    @State private var captureError: String?
    @State private var controlsTab: ControlsSheet.Tab = .core
    @State private var showCoachMarks = false
    @State private var coachStep = 0
    @State private var lookToast: String?
    /// Top-chrome toast for flash / flip (short-lived).
    @State private var chromeToast: String?
    @State private var chromeToastTask: Task<Void, Never>?
    /// On-finder AO apply burst (dial deltas) — collapses into BeforeAfterChip.
    @State private var showApplyBurst = false
    @State private var applyBurstTask: Task<Void, Never>?

    /// Coach Recommend — primary labeled control lower-left of shutter (Library lives in ···).
    @State private var isRecommending = false
    @State private var recommendResult: RecommendResponse?
    @State private var recommendError: String?
    @State private var showRecommendResult = false

    var body: some View {
        ZStack {
            AppTheme.bg.ignoresSafeArea()
            switch session.auth {
            case .authorized:
                viewfinder
            case .notDetermined:
                permissionCover(
                    title: "Camera access",
                    body: "Photo Recipes needs the camera to apply field recipes to live capture.",
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
            // monitorSubjectAreaChange → debounced re-run of Auto Optimize (same apply path).
            Task { await runOptimize() }
        }

        .onChange(of: voice.phase) { _, phase in
            switch phase {
            case .recording:
                // Expand Scene chip so the live TextField is visible while speaking.
                if !sceneExpanded {
                    withAnimation(.easeInOut(duration: 0.18)) { sceneExpanded = true }
                }
            case .error:
                if voice.permission == .denied { showMicDenied = true }
            default:
                break
            }
        }
        .onDisappear {
            voice.cancel()
            describeTask?.cancel()
            chromeToastTask?.cancel()
            applyBurstTask?.cancel()
            session.stop()
            horizon.stop()
        }
        .sheet(isPresented: $showDials) {
            ControlsSheet(
                session: session,
                optimizer: optimizer,
                initialTab: controlsTab,
                onTeach: {
                    Analytics.shared.track("teach_open", props: ["source": "controls"])
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showTeach = true }
                },
                onLookApplied: { look in
                    Analytics.shared.track("look_applied", props: ["look_id": look.id, "source": "controls"])
                    lookToast = nil
                }
            )
            .environmentObject(entitlements)
            .id(controlsTab)
        }
        .sheet(isPresented: $showTeach) {
            TeachModeSheet(
                recipeTitle: optimizer.chosenRecipeTitle ?? session.appliedRecipeTitle,
                oneLiner: optimizer.teachOneLiner,
                tips: optimizer.tips,
                diffs: optimizer.coreDiffs,
                advancedDiffs: optimizer.advancedDiffs,
                verifyWarning: optimizer.verifyWarning,
                coachOnly: optimizer.coachOnly,
                activeLook: session.activeCreativeLook,
                onReoptimizeSubject: {
                    showTeach = false
                    Task { await runOptimize() }
                },
                onDone: { showTeach = false }
            )
            .environmentObject(entitlements)
        }
        .sheet(isPresented: $showRecipePicker) {
            RecipePickerSheet { recipe in
                showRecipePicker = false
                _ = session.apply(recipe: recipe)
            }
        }
        .sheet(isPresented: $showOverflow) {
            CameraOverflowSheet(
                showGrid: $session.showGrid,
                canTeach: optimizer.phase == .ready || optimizer.teachOneLiner != nil,
                recommendDisabled: isRecommending || optimizer.phase.isRunning,
                isRecommending: isRecommending,
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
                    controlsTab = .core
                    showDials = true
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
                onApply: { recipe in
                    showRecommendResult = false
                    _ = session.apply(recipe: recipe)
                    // Fast Recommend JSON → same applyPhoneTargets path as Auto Optimize.
                    if entitlements.canApplyDials, let targets = recommendResult?.phoneTargets {
                        _ = session.applyPhoneTargets(targets)
                    }
                },
                onDismiss: {
                    showRecommendResult = false
                    recommendResult = nil
                    recommendError = nil
                },
                onUpgrade: {
                    showRecommendResult = false
                    entitlements.showPaywall = true
                }
            )
            .environmentObject(entitlements)
            .environmentObject(router)
            .presentationDetents([.medium, .large])
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
                    previewLUTId: session.previewLUTId,
                    creativeLook: session.activeCreativeLook
                )
                    .ignoresSafeArea()
                    .simultaneousGesture(
                        SpatialTapGesture().onEnded { value in
                            // Keep focus taps out of top/bottom chrome so flash / flip / ··· stay tappable.
                            let y = value.location.y
                            guard y > topChromeH, y < geo.size.height - bottomScrim else { return }
                            let pt = CGPoint(
                                x: value.location.x / geo.size.width,
                                y: value.location.y / geo.size.height
                            )
                            session.focus(at: pt, lock: entitlements.canApplyDials)
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

                if let cue = activePanCue {
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
                        .allowsHitTesting(false)
                    bottomOverlay(
                        compact: compact,
                        width: geo.size.width,
                        scrimHeight: bottomScrim,
                        bottomSafeInset: safeBottom
                    )
                }
                .zIndex(10)

                if showCoachMarks {
                    CameraCoachMarksView(step: $coachStep) {
                        showCoachMarks = false
                        CameraCoachMarksStore.markSeen()
                    }
                    .transition(.opacity)
                    .zIndex(20)
                }
            }
            .onChange(of: optimizer.applyFeedbackToken) { _, token in
                guard token > 0 else { return }
                if !optimizer.coreDiffs.isEmpty {
                    presentApplyBurst()
                } else if let title = optimizer.chosenRecipeTitle ?? session.appliedRecipeTitle {
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
                if let title = session.appliedRecipeTitle {
                    Text(title)
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(AppTheme.recipeBadgeBg)
                                .overlay(Capsule().stroke(AppTheme.accent.opacity(0.45), lineWidth: 1))
                        )
                        .onTapGesture { showClearConfirm = true }
                }
                floatingIcon("arrow.triangle.2.circlepath.camera", accessibility: "Flip camera") {
                    flipCameraWithFeedback()
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

    private func bottomOverlay(compact: Bool, width: CGFloat, scrimHeight: CGFloat, bottomSafeInset: CGFloat) -> some View {
        let hPad: CGFloat = width <= 320 ? 8 : (compact ? 12 : 16)
        let ctaH: CGFloat = compact ? 40 : 44

        return VStack(spacing: compact ? 6 : 8) {
            if let clamp = session.clampMessages.last {
                Text(clamp)
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.radiusSm)
                            .fill(AppTheme.agentStatusBg)
                            .overlay(RoundedRectangle(cornerRadius: AppTheme.radiusSm).stroke(AppTheme.tip, lineWidth: 1))
                    )
                    .padding(.horizontal, hPad)
            }

            AgentStatusPill(
                phase: optimizer.phase,
                verifyWarning: optimizer.verifyWarning,
                statusOverride: optimizer.pillStatus,
                onStop: { optimizer.clear() }
            )

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
                    onClear: { session.clearActiveLook() },
                    onOpenLooks: {
                        controlsTab = .looks
                        showDials = true
                    }
                )
                .padding(.horizontal, hPad)
            }

            if let lookToast {
                Text(lookToast)
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(AppTheme.agentStatusBg))
            }

            sceneMicRow(compact: compact)
                .padding(.horizontal, hPad)

            // Always enabled + full yellow when camera chrome is shown (auth OK).
            // Over Free Peek Optimize quota → tap presents Pro paywall (not grayed-out).
            Button {
                Task { await runOptimize() }
            } label: {
                HStack(spacing: 6) {
                    if optimizer.phase.isRunning {
                        ProgressView().tint(AppTheme.accentOnAccent).scaleEffect(0.85)
                        Text("Optimizing…")
                    } else {
                        Image(systemName: "bolt.fill")
                        Text(compact ? "Optimize" : "Auto Optimize")
                    }
                }
                .font(AppTheme.bodySmMedium())
                .foregroundStyle(AppTheme.accentOnAccent)
                .padding(.horizontal, 18)
                .frame(height: ctaH)
                .background(Capsule().fill(AppTheme.accent))
            }
            .disabled(optimizer.phase.isRunning)
            .accessibilityLabel("Auto Optimize")

            if case .ready = optimizer.phase, !showApplyBurst {
                BeforeAfterChip(
                    diffs: optimizer.coreDiffs,
                    recipeTitle: optimizer.chosenRecipeTitle,
                    hasMoreAdvanced: !optimizer.advancedDiffs.isEmpty,
                    onTap: {
                        controlsTab = .core
                        showDials = true
                    },
                    onMore: {
                        controlsTab = .light
                        showDials = true
                    }
                )
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

    private func sceneMicRow(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Group {
                    if sceneExpanded || isVoiceListening {
                        // Real TextField so STT partials stream into a visible text box (App Review).
                        TextField("e.g. silky waterfall, sharp rocks…", text: $sceneNote, axis: .vertical)
                            .lineLimit(2...4)
                            .font(AppTheme.bodySm())
                            .foregroundStyle(AppTheme.ink)
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
                            .onChange(of: sceneNote) { _, _ in
                                sceneFromViewfinder = false
                            }
                    } else {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) { sceneExpanded.toggle() }
                        } label: {
                            HStack(spacing: 6) {
                                if sceneFromViewfinder {
                                    Text("From viewfinder")
                                        .font(AppTheme.overline())
                                        .foregroundStyle(AppTheme.inkSecondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            Capsule()
                                                .fill(AppTheme.accentMuted)
                                                .overlay(Capsule().stroke(AppTheme.border, lineWidth: 1))
                                        )
                                }
                                Text(sceneNote.isEmpty ? "Scene…" : sceneNote)
                                    .font(AppTheme.caption())
                                    .foregroundStyle(sceneNote.isEmpty ? AppTheme.inkTertiary : AppTheme.ink)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(AppTheme.inkTertiary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(AppTheme.agentStatusBg)
                                    .overlay(Capsule().stroke(AppTheme.border.opacity(0.7), lineWidth: 1))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if isDescribingScene {
                    ProgressView().scaleEffect(0.7)
                } else if !isVoiceListening {
                    Button {
                        Task { await refreshSceneFromViewfinder() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.inkSecondary)
                            .frame(width: 36, height: 36)
                    }
                }

                VoiceDictateButton(
                    controller: voice,
                    enabled: !optimizer.phase.isRunning && !isDescribingScene,
                    onWillStart: {
                        voiceDictationBase = sceneNote.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !sceneExpanded {
                            withAnimation(.easeInOut(duration: 0.18)) { sceneExpanded = true }
                        }
                    },
                    onPartial: { applyCameraVoicePartial($0) },
                    onTranscript: { applyCameraVoiceFinal($0) }
                )
            }

            if sceneExpanded && !isVoiceListening {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { sceneExpanded = false }
                } label: {
                    Text("Collapse scene")
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.inkTertiary)
                }
                .buttonStyle(.plain)
            }

            VoiceStatusCaption(controller: voice)
        }
    }

    private func shutterRow(compact: Bool, hPad: CGFloat) -> some View {
        let side: CGFloat = compact ? 48 : 56
        let outer: CGFloat = compact ? 68 : 76
        let inner: CGFloat = compact ? 56 : 62
        let recommendDisabled = isRecommending || optimizer.phase.isRunning

        return HStack(spacing: 0) {
            // Labeled Recommend (not photo/library thumb). Library stays in ··· More.
            Button {
                guard !recommendDisabled else { return }
                Task { await runRecommend() }
            } label: {
                VStack(spacing: 2) {
                    if isRecommending {
                        ProgressView()
                            .tint(AppTheme.ink)
                            .scaleEffect(0.75)
                            .frame(height: 18)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: compact ? 14 : 16, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                    }
                    Text(compact ? "Rec" : "Recommend")
                        .font(AppTheme.overline())
                        .foregroundStyle(AppTheme.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(width: side, height: side)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.35))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(AppTheme.border.opacity(0.6), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(recommendDisabled)
            .opacity(recommendDisabled ? 0.45 : 1)
            .accessibilityLabel(isRecommending ? "Matching recipe" : "Recommend")

            Spacer(minLength: 8)

            Button {
                Analytics.shared.track("shutter_tap", props: ["source": "camera"])
                Task { await takePhoto() }
            } label: {
                ZStack {
                    Circle()
                        .stroke(AppTheme.shutterRing, lineWidth: compact ? 3 : 4)
                        .frame(width: outer, height: outer)
                    Circle()
                        .fill(AppTheme.shutterCore.opacity(isCapturing ? 0.5 : 1))
                        .frame(width: inner, height: inner)
                }
            }
            .disabled(isCapturing)
            .accessibilityLabel("Shutter")

            Spacer(minLength: 8)

            floatingIcon("ellipsis.circle") {
                controlsTab = .core
                showDials = true
            }
            .frame(width: side, height: side)
            .accessibilityLabel("Controls")
        }
        .padding(.horizontal, hPad)
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

    /// Final utterance: commit text (same compose as partials) then Auto Optimize apply path.
    private func applyCameraVoiceFinal(_ text: String) {
        applyCameraVoicePartial(text)
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        // Camera mic shares Auto Optimize → applyPhoneTargets (PR #11); not text-only.
        Task { await runOptimize() }
    }

    private func refreshSceneFromViewfinder() async {
        describeTask?.cancel()
        let task = Task { @MainActor in
            isDescribingScene = true
            defer { isDescribingScene = false }
            do {
                let raw = try await session.captureProbeFrame()
                let jpeg: Data
                if let img = UIImage(data: raw), let c = APIClient.compressForVision(img) {
                    jpeg = c
                } else {
                    jpeg = raw
                }
                try Task.checkCancellation()
                let caption = try await APIClient.shared.describeScene(imageJPEGData: jpeg)
                try Task.checkCancellation()
                let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                // Never clobber live STT / typed note while mic is active.
                if case .recording = voice.phase { return }
                if case .uploading = voice.phase { return }
                if case .requestingPermission = voice.phase { return }
                if sceneNote.isEmpty || sceneFromViewfinder {
                    sceneNote = trimmed
                    sceneFromViewfinder = true
                }
            } catch is CancellationError {
                return
            } catch {}
        }
        describeTask = task
        await task.value
    }

    private func runOptimize() async {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        // Quota exhausted (not Pro/unlimited): paywall + visible error/toast — never silent.
        guard canOptimize else {
            print("[AO] tap → paywall (quota exhausted)")
            entitlements.showPaywall = true
            optimizer.phase = .error("Free Peek limit reached — upgrade for more")
            presentChromeToast("Free Peek limit — see Pro")
            Analytics.shared.track("auto_optimize_fail", props: ["error_code": "quota", "path": "camera_tap"])
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
            preferStagedRecipeId: session.appliedRecipeId ?? router.stagedRecipeId,
            sceneNote: sceneNote,
            devicePitchDegrees: horizon.isAvailable ? horizon.pitchDegrees : nil
        )
        // applyFeedbackToken / phase drive burst, toast, or error pill — never silent.
        if case .ready = optimizer.phase {
            let title = optimizer.chosenRecipeTitle ?? session.appliedRecipeTitle ?? "recipe"
            print("[AO] ready recipe=\(title) diffs=\(optimizer.coreDiffs.count)")
        } else if case .error(let msg) = optimizer.phase {
            print("[AO] error \(msg)")
        }
    }

    /// Coach recommend from viewfinder frame and/or scene note.
    /// Apply writes recipe + phoneTargets via applyPhoneTargets (same as AO).
    /// Triggered from ··· overflow — not primary finder chrome.
    private func runRecommend() async {
        recommendError = nil
        recommendResult = nil
        isRecommending = true
        showRecommendResult = true
        defer { isRecommending = false }

        let note = sceneNote.trimmingCharacters(in: .whitespacesAndNewlines)
        var jpeg: Data?
        do {
            let raw = try await session.captureProbeFrame()
            if let img = UIImage(data: raw), let c = APIClient.compressForVision(img) {
                jpeg = c
            } else if !raw.isEmpty {
                jpeg = raw
            }
        } catch {
            // Soft-fail probe; may still recommend from scene note alone.
        }

        let hadHeldFrame = jpeg != nil
        Analytics.shared.track("recommend_cta_tap", props: [
            "surface": "camera",
            "source": "shutter_row",
            "had_held_frame": hadHeldFrame ? "true" : "false",
        ])

        let message: String
        if !note.isEmpty {
            message = note
        } else if jpeg != nil {
            message = "From viewfinder"
        } else {
            recommendError = "Add a scene note or enable the camera"
            return
        }

        do {
            let response = try await APIClient.shared.recommend(
                message: message,
                favorites: Array(entitlements.favoriteIds),
                imageJPEGData: jpeg
            )
            recommendResult = response
            recommendError = nil
            await entitlements.refresh()
        } catch let APIError.paywall(payload) {
            recommendError = payload.error ?? "Free Peek limit reached. Upgrade to Pro."
            entitlements.showPaywall = true
            await entitlements.refresh()
        } catch let APIError.missingKey(msg) {
            recommendError = msg
        } catch {
            recommendError = error.localizedDescription
        }
    }

    private func takePhoto() async {
        isCapturing = true
        captureError = nil
        defer { isCapturing = false }
        do {
            let data = try await session.capturePhoto()
            try await PhotoLibrarySaver.saveJPEG(data)
            Analytics.shared.track("capture_success", props: ["source": "camera"])
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch {
            captureError = error.localizedDescription
        }
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
        await runOptimize()
    }

    private func applyStagingIfNeeded() {
        guard let id = router.stagedRecipeId,
              let recipe = BundledPresets.recipe(id: id) else { return }
        if router.pendingApply {
            _ = session.apply(recipe: recipe)
            if let targets = router.stagedPhoneTargets {
                _ = session.applyPhoneTargets(targets)
            }
            router.stagedPhoneTargets = nil
            router.pendingApply = false
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
    var onLibrary: () -> Void
    var onCoach: () -> Void
    var onSettings: () -> Void
    var onDials: () -> Void
    var onTeach: () -> Void
    var onRecipes: () -> Void
    var onRecommend: () -> Void
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
                            Text("Matching a recipe…")
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
