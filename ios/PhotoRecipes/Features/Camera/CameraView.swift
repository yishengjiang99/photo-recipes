import SwiftUI
import AVFoundation

struct CameraView: View {
    @EnvironmentObject private var entitlements: EntitlementsStore
    @EnvironmentObject private var router: CameraRouter
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @StateObject private var session = CameraSession()
    @StateObject private var optimizer = AutoOptimizeController()
    @StateObject private var voice = VoiceCaptureController()
    @State private var sceneNote = ""
    @State private var sceneFromViewfinder = false
    @State private var isDescribingScene = false
    @State private var showMicDenied = false
    @State private var describeTask: Task<Void, Never>?
    @StateObject private var horizon = HorizonMonitor()

    @State private var showDials = false
    @State private var showTeach = false
    @State private var showRecipePicker = false
    @State private var showClearConfirm = false
    @State private var isCapturing = false
    @State private var captureError: String?

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
        }
        .onChange(of: router.stagedRecipeId) { _, _ in applyStagingIfNeeded() }
        .onAppear {
            describeTask?.cancel()
            describeTask = Task { await refreshSceneFromViewfinder() }
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
        .onChange(of: voice.phase) { _, phase in
            if case .error = phase, voice.permission == .denied { showMicDenied = true }
        }
        .onDisappear {
            voice.cancel()
            describeTask?.cancel()

            session.stop()
            horizon.stop()
        }
        .sheet(isPresented: $showDials) {
            ManualDialsSheet(session: session, optimizer: optimizer)
                .environmentObject(entitlements)
        }
        .sheet(isPresented: $showTeach) {
            TeachModeSheet(
                recipeTitle: optimizer.chosenRecipeTitle ?? session.appliedRecipeTitle,
                oneLiner: optimizer.reasonNote,
                tips: optimizer.tips,
                diffs: optimizer.diffs,
                verifyWarning: optimizer.verifyWarning,
                onDone: { showTeach = false }
            )
            .environmentObject(entitlements)
        }
        .sheet(isPresented: $showRecipePicker) {
            RecipePickerSheet { recipe in
                showRecipePicker = false
                let ok = session.apply(recipe: recipe, asPro: entitlements.isPro)
                if !ok && !entitlements.isPro { entitlements.showPaywall = true }
            }
        }
        .confirmationDialog("Remove recipe from this session?", isPresented: $showClearConfirm) {
            Button("Remove", role: .destructive) {
                session.clearRecipe()
                optimizer.clear()
            }
            Button("Keep", role: .cancel) {}
        }
    }

    // MARK: - Viewfinder

    private var viewfinder: some View {
        GeometryReader { geo in
            let compact = isCompactChrome(width: geo.size.width, height: geo.size.height)
            let chromeBottom = compact ? 168.0 : 200.0
            ZStack {
                CameraPreviewView(session: session.session)
                    .ignoresSafeArea()
                    .simultaneousGesture(
                        SpatialTapGesture().onEnded { value in
                            let pt = CGPoint(
                                x: value.location.x / geo.size.width,
                                y: value.location.y / geo.size.height
                            )
                            session.focus(at: pt, lock: entitlements.isPro)
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
                        bottomInset: chromeBottom,
                        topInset: compact ? 56 : 72
                    )
                }

                VStack(spacing: 0) {
                    topBar(compact: compact)
                    Spacer(minLength: 0)
                    agentColumn(compact: compact, width: geo.size.width)
                    bottomBar(compact: compact)
                }
            }
        }
    }

    /// SE / small phones (~320–375pt wide, ~667pt tall) need tighter chrome.
    /// Prefer size thresholds over size class alone — all iPhones report `.compact`.
    private func isCompactChrome(width: CGFloat, height: CGFloat) -> Bool {
        if horizontalSizeClass == .regular { return false }
        let narrow = width <= 375
        let short = height < 700
        // 390×844 (14/15) stays comfortable; SE / mini / short heights tighten.
        return narrow || short
    }

    private var activePanCue: ViewfinderPanCue? {
        ViewfinderPanCueResolver.resolve(
            recipeId: session.appliedRecipeId ?? optimizer.chosenRecipeId,
            agentPhase: optimizer.phase,
            agentStatus: optimizer.phase.statusCopy.isEmpty ? nil : optimizer.phase.statusCopy
        )
    }

    private func topBar(compact: Bool) -> some View {
        HStack(spacing: compact ? 8 : 12) {
            iconBtn(session.flash.icon) { session.flash = session.flash.next }
            iconBtn(session.showGrid ? "grid" : "grid") { session.showGrid.toggle() }
            Spacer(minLength: 4)
            if session.focusLocked || session.exposureLocked {
                Text("AE/AF LOCK")
                    .font(AppTheme.overline())
                    .foregroundStyle(AppTheme.aeLock)
                    .padding(.horizontal, compact ? 8 : 10)
                    .padding(.vertical, compact ? 4 : 6)
                    .background(Capsule().fill(AppTheme.agentStatusBg))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            if horizon.isAvailable {
                Circle()
                    .fill(horizon.isLevel ? AppTheme.agentReady : AppTheme.agentWarn)
                    .frame(width: 8, height: 8)
                    .rotationEffect(.degrees(-horizon.rollDegrees))
            }
            iconBtn("arrow.triangle.2.circlepath.camera") { session.flipCamera() }
        }
        .padding(.horizontal, compact ? AppTheme.space3 : AppTheme.space4)
        .padding(.vertical, compact ? 6 : 8)
        .background(
            LinearGradient(colors: [AppTheme.cameraScrim, .clear], startPoint: .top, endPoint: .bottom)
        )
    }

    private func agentColumn(compact: Bool, width: CGFloat) -> some View {
        let hPad: CGFloat = width <= 320 ? AppTheme.space2 : (compact ? AppTheme.space3 : AppTheme.space4)
        let ctaHeight: CGFloat = compact ? 44 : 50
        let stackSpacing: CGFloat = compact ? 6 : 8

        return VStack(spacing: stackSpacing) {
            if let clamp = session.clampMessages.last {
                Text(clamp)
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(compact ? 2 : 3)
                    .minimumScaleFactor(0.9)
                    .padding(.horizontal, 12)
                    .padding(.vertical, compact ? 6 : 8)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.radiusSm)
                            .fill(AppTheme.agentStatusBg)
                            .overlay(RoundedRectangle(cornerRadius: AppTheme.radiusSm).stroke(AppTheme.tip, lineWidth: 1))
                    )
                    .padding(.horizontal, hPad)
            }

            BeforeAfterChip(
                diffs: optimizer.diffs,
                recipeTitle: optimizer.chosenRecipeTitle,
                onTap: { showDials = true }
            )
            .padding(.horizontal, hPad)

            AgentStatusPill(
                phase: optimizer.phase,
                verifyWarning: optimizer.verifyWarning,
                onStop: { optimizer.clear() }
            )
            .padding(.horizontal, hPad)

            if case .ready = optimizer.phase {
                Button("Why this?") { showTeach = true }
                    .font(AppTheme.bodySmMedium())
                    .foregroundStyle(AppTheme.inkSecondary)
            }

            recipeBadge
                .padding(.horizontal, hPad)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: AppTheme.space2) {
                    TextField("Describe the scene…", text: $sceneNote, axis: .vertical)
                        .lineLimit(1...3)
                        .font(AppTheme.bodySm())
                        .foregroundStyle(AppTheme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.radiusSm)
                                .fill(AppTheme.bgElevated.opacity(0.92))
                                .overlay(RoundedRectangle(cornerRadius: AppTheme.radiusSm).stroke(AppTheme.border, lineWidth: 1))
                        )
                    VoiceDictateButton(controller: voice, enabled: !optimizer.phase.isRunning && !isDescribingScene) { text in
                        appendCameraVoice(text)
                    }
                }
                HStack(spacing: 8) {
                    if sceneFromViewfinder {
                        Text("From viewfinder")
                            .font(AppTheme.caption())
                            .foregroundStyle(AppTheme.inkTertiary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().stroke(AppTheme.border, lineWidth: 1))
                    }
                    if isDescribingScene {
                        ProgressView().scaleEffect(0.7)
                        Text("Reading scene…")
                            .font(AppTheme.caption())
                            .foregroundStyle(AppTheme.inkTertiary)
                    } else {
                        Button {
                            Task { await refreshSceneFromViewfinder() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                                .font(AppTheme.caption())
                                .foregroundStyle(AppTheme.inkSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
                VoiceStatusCaption(controller: voice)
            }
            .padding(.horizontal, AppTheme.space4)

            Button {
                Task { await runOptimize() }
            } label: {
                HStack(spacing: 8) {
                    if optimizer.phase.isRunning {
                        ProgressView().tint(.white)
                        Text("Optimizing…")
                    } else {
                        Image(systemName: "bolt.fill")
                        Text(compact && width <= 320 ? "Optimize" : "Auto Optimize")
                    }
                }
                .font(compact ? AppTheme.bodySmMedium() : AppTheme.bodyMedium())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: ctaHeight)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.radiusMd)
                        .fill(AppTheme.accent.opacity(canOptimize ? 1 : 0.4))
                )
            }
            .disabled(!canOptimize || optimizer.phase.isRunning)
            .padding(.horizontal, hPad)

            if !entitlements.isPro {
                Text(optimizer.freeRemainingToday > 0
                     ? "\(optimizer.freeRemainingToday) left today"
                     : "Free Peek limit reached")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.inkTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .padding(.bottom, compact ? 4 : 8)
    }

    private var canOptimize: Bool { optimizer.canRun(isPro: entitlements.isPro) }

    @ViewBuilder
    private var recipeBadge: some View {
        if let title = session.appliedRecipeTitle {
            HStack(spacing: 8) {
                Text("Applied · \(title)")
                    .font(AppTheme.bodySmMedium())
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                Button { showClearConfirm = true } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.inkSecondary)
                        .frame(width: 28, height: 28)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(AppTheme.recipeBadgeBg)
                    .overlay(Capsule().stroke(AppTheme.accent.opacity(0.5), lineWidth: 1))
            )
        } else {
            Button { showRecipePicker = true } label: {
                Label("Recipe", systemImage: "plus")
                    .font(AppTheme.bodySmMedium())
                    .foregroundStyle(AppTheme.inkSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().stroke(AppTheme.border, lineWidth: 1))
            }
        }
    }

    private func bottomBar(compact: Bool) -> some View {
        let side: CGFloat = compact ? 48 : 56
        let shutterOuter: CGFloat = compact ? 68 : 76
        let shutterInner: CGFloat = compact ? 56 : 62
        let hPad: CGFloat = compact ? AppTheme.space3 : AppTheme.space5

        return VStack(spacing: compact ? 6 : 10) {
            Text(session.readoutLine)
                .font(compact ? AppTheme.caption() : AppTheme.monoSm())
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .shadow(color: .black.opacity(0.7), radius: 1, y: 1)
                .padding(.horizontal, hPad)

            HStack(spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppTheme.surface)
                        .frame(width: 40, height: 40)
                    if let thumb = session.lastThumb {
                        Image(uiImage: thumb)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Image(systemName: "photo").foregroundStyle(AppTheme.inkTertiary)
                    }
                }
                .frame(width: side, height: side)

                Spacer(minLength: 8)

                Button {
                    Task { await takePhoto() }
                } label: {
                    ZStack {
                        Circle()
                            .stroke(AppTheme.shutterRing, lineWidth: compact ? 3 : 4)
                            .frame(width: shutterOuter, height: shutterOuter)
                        Circle()
                            .fill(AppTheme.shutterCore.opacity(isCapturing ? 0.5 : 1))
                            .frame(width: shutterInner, height: shutterInner)
                    }
                }
                .disabled(isCapturing)
                .accessibilityLabel("Shutter")

                Spacer(minLength: 8)

                Button {
                    if entitlements.isPro {
                        showDials = true
                    } else {
                        entitlements.showPaywall = true
                    }
                } label: {
                    Image(systemName: "camera.aperture")
                        .font(compact ? .title3 : .title2)
                        .foregroundStyle(AppTheme.ink)
                        .frame(width: side, height: side)
                }
                .accessibilityLabel("Manual dials")
            }
            .padding(.horizontal, hPad)
            .padding(.bottom, compact ? 8 : 12)

            if let captureError {
                Text(captureError)
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.danger)
                    .padding(.horizontal, hPad)
                    .padding(.bottom, 4)
            }
        }
        .padding(.top, compact ? 8 : 12)
        .background(
            LinearGradient(colors: [.clear, AppTheme.cameraScrim], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
        )
    }

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

    
    private func appendCameraVoice(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let cur = sceneNote.trimmingCharacters(in: .whitespacesAndNewlines)
        sceneNote = cur.isEmpty ? t : cur + " " + t
        sceneFromViewfinder = false
        if VoiceSettings.autoOptimizeAfterVoice {
            Task { await runOptimize() }
        }
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
                if sceneNote.isEmpty || sceneFromViewfinder {
                    sceneNote = trimmed
                    sceneFromViewfinder = true
                }
            } catch is CancellationError {
                return
            } catch {
                // Soft fail — keep placeholder
            }
        }
        describeTask = task
        await task.value
    }

    private func runOptimize() async {
        guard canOptimize else {
            entitlements.showPaywall = true
            return
        }
        await optimizer.run(session: session, entitlements: entitlements, preferStagedRecipeId: session.appliedRecipeId ?? router.stagedRecipeId
        , sceneNote: sceneNote)
    }

    private func takePhoto() async {
        isCapturing = true
        captureError = nil
        defer { isCapturing = false }
        do {
            let data = try await session.capturePhoto()
            try await PhotoLibrarySaver.saveJPEG(data)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch {
            captureError = error.localizedDescription
        }
    }

    private func applyStagingIfNeeded() {
        guard let id = router.stagedRecipeId,
              let recipe = BundledPresets.recipe(id: id) else { return }
        if router.pendingApply {
            let ok = session.apply(recipe: recipe, asPro: entitlements.isPro)
            if !ok && !entitlements.isPro { entitlements.showPaywall = true }
            router.pendingApply = false
        } else {
            session.appliedRecipeId = recipe.id
            session.appliedRecipeTitle = recipe.title
        }
    }

    private func iconBtn(_ system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
                .frame(width: 44, height: 44)
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
