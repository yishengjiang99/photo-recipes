import SwiftUI
import AVFoundation

struct CameraView: View {
    @EnvironmentObject private var entitlements: EntitlementsStore
    @EnvironmentObject private var router: CameraRouter

    @StateObject private var session = CameraSession()
    @StateObject private var optimizer = AutoOptimizeController()
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
        .onDisappear {
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

                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    agentColumn
                    bottomBar
                }
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            iconBtn(session.flash.icon) { session.flash = session.flash.next }
            iconBtn(session.showGrid ? "grid" : "grid") { session.showGrid.toggle() }
            Spacer()
            if session.focusLocked || session.exposureLocked {
                Text("AE/AF LOCK")
                    .font(AppTheme.overline())
                    .foregroundStyle(AppTheme.aeLock)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(AppTheme.agentStatusBg))
            }
            if horizon.isAvailable {
                Circle()
                    .fill(horizon.isLevel ? AppTheme.agentReady : AppTheme.agentWarn)
                    .frame(width: 8, height: 8)
                    .rotationEffect(.degrees(-horizon.rollDegrees))
            }
            iconBtn("arrow.triangle.2.circlepath.camera") { session.flipCamera() }
        }
        .padding(.horizontal, AppTheme.space4)
        .padding(.vertical, 8)
        .background(
            LinearGradient(colors: [AppTheme.cameraScrim, .clear], startPoint: .top, endPoint: .bottom)
        )
    }

    private var agentColumn: some View {
        VStack(spacing: 8) {
            if let clamp = session.clampMessages.last {
                Text(clamp)
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.radiusSm)
                            .fill(AppTheme.agentStatusBg)
                            .overlay(RoundedRectangle(cornerRadius: AppTheme.radiusSm).stroke(AppTheme.tip, lineWidth: 1))
                    )
            }

            BeforeAfterChip(
                diffs: optimizer.diffs,
                recipeTitle: optimizer.chosenRecipeTitle,
                onTap: { showDials = true }
            )

            AgentStatusPill(
                phase: optimizer.phase,
                verifyWarning: optimizer.verifyWarning,
                onStop: { optimizer.clear() }
            )

            if case .ready = optimizer.phase {
                Button("Why this?") { showTeach = true }
                    .font(AppTheme.bodySmMedium())
                    .foregroundStyle(AppTheme.inkSecondary)
            }

            recipeBadge

            Button {
                Task { await runOptimize() }
            } label: {
                HStack(spacing: 8) {
                    if optimizer.phase.isRunning {
                        ProgressView().tint(.white)
                        Text("Optimizing…")
                    } else {
                        Image(systemName: "bolt.fill")
                        Text("Auto Optimize")
                    }
                }
                .font(AppTheme.bodyMedium())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.radiusMd)
                        .fill(AppTheme.accent.opacity(canOptimize ? 1 : 0.4))
                )
            }
            .disabled(!canOptimize || optimizer.phase.isRunning)
            .padding(.horizontal, AppTheme.space4)

            if !entitlements.isPro {
                Text(optimizer.freeRemainingToday > 0
                     ? "\(optimizer.freeRemainingToday) left today"
                     : "Free Peek limit reached")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.inkTertiary)
            }
        }
        .padding(.bottom, 8)
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

    private var bottomBar: some View {
        VStack(spacing: 10) {
            Text(session.readoutLine)
                .font(AppTheme.monoSm())
                .foregroundStyle(AppTheme.ink)
                .shadow(color: .black.opacity(0.7), radius: 1, y: 1)

            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppTheme.surface)
                        .frame(width: 44, height: 44)
                    if let thumb = session.lastThumb {
                        Image(uiImage: thumb)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Image(systemName: "photo").foregroundStyle(AppTheme.inkTertiary)
                    }
                }
                .frame(width: 56)

                Spacer()

                Button {
                    Task { await takePhoto() }
                } label: {
                    ZStack {
                        Circle()
                            .stroke(AppTheme.shutterRing, lineWidth: 4)
                            .frame(width: 76, height: 76)
                        Circle()
                            .fill(AppTheme.shutterCore.opacity(isCapturing ? 0.5 : 1))
                            .frame(width: 62, height: 62)
                    }
                }
                .disabled(isCapturing)
                .accessibilityLabel("Shutter")

                Spacer()

                Button {
                    if entitlements.isPro {
                        showDials = true
                    } else {
                        entitlements.showPaywall = true
                    }
                } label: {
                    Image(systemName: "camera.aperture")
                        .font(.title2)
                        .foregroundStyle(AppTheme.ink)
                        .frame(width: 56, height: 56)
                }
                .accessibilityLabel("Manual dials")
            }
            .padding(.horizontal, AppTheme.space5)
            .padding(.bottom, 12)

            if let captureError {
                Text(captureError)
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.danger)
                    .padding(.bottom, 4)
            }
        }
        .padding(.top, 12)
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

    private func runOptimize() async {
        guard canOptimize else {
            entitlements.showPaywall = true
            return
        }
        await optimizer.run(
            session: session,
            entitlements: entitlements,
            preferStagedRecipeId: session.appliedRecipeId ?? router.stagedRecipeId
        )
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
