import SwiftUI
import AVFoundation

/// First-run single-screen onboarding (portrait). Tips cycle in-place; Get Started always visible.
/// Canonical mock: `assets/marketing/onboarding/08-single-screen-portrait.png`
struct OnboardingView: View {
    var onFinished: () -> Void

    @State private var tipIndex = 0
    @State private var isRequestingCamera = false
    @State private var dragOffset: CGFloat = 0

    private static let tips: [Tip] = [
        Tip(
            title: "Auto Optimize",
            body: "Point at the shot — we write shutter, ISO, EV, WB & focus."
        ),
        Tip(
            title: "Recommend & Looks",
            body: "Recipe from the scene. Looks = capture grades, not beauty filters."
        ),
        Tip(
            title: "Capture",
            body: "See settings change, then press shutter. Teach explains why."
        ),
    ]

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: AppTheme.space6)

                wordmark
                    .padding(.top, AppTheme.space5)

                Spacer(minLength: AppTheme.space5)

                tipCarousel
                    .padding(.horizontal, AppTheme.space3)

                pageDots
                    .padding(.top, AppTheme.space4)

                Spacer(minLength: AppTheme.space6)

                ctaBlock
                    .padding(.horizontal, AppTheme.space5)
                    .padding(.bottom, AppTheme.space7)
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Chrome

    private var background: some View {
        ZStack {
            AppTheme.bg
            LinearGradient(
                colors: [
                    Color(hex: 0x1A1410),
                    AppTheme.bg,
                    Color(hex: 0x0A0A0A),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            // Soft amber wash (cinematic, no bundled hero asset required).
            RadialGradient(
                colors: [
                    AppTheme.accent.opacity(0.14),
                    Color.clear,
                ],
                center: .top,
                startRadius: 20,
                endRadius: 420
            )
            .blendMode(.plusLighter)
        }
    }

    private var wordmark: some View {
        VStack(spacing: AppTheme.space2) {
            Text("AI Camera - Auto Recipes")
                .font(.system(size: 28, weight: .semibold, design: .default))
                .foregroundStyle(AppTheme.ink)
                .tracking(0.4)
            Text("Set the shot. Then take it.")
                .font(AppTheme.bodySm())
                .foregroundStyle(AppTheme.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var tipCarousel: some View {
        HStack(spacing: AppTheme.space2) {
            chevronButton(systemName: "chevron.left", label: "Previous tip") {
                cycle(-1)
            }

            tipCard(Self.tips[tipIndex])
                .offset(x: dragOffset)
                .gesture(swipeGesture)
                .animation(.easeOut(duration: 0.18), value: tipIndex)
                .frame(maxWidth: .infinity)

            chevronButton(systemName: "chevron.right", label: "Next tip") {
                cycle(1)
            }
        }
        .frame(minHeight: 120)
    }

    private func tipCard(_ tip: Tip) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.space3) {
            Text(tip.title)
                .font(AppTheme.title())
                .foregroundStyle(AppTheme.accent)
            Text(tip.body)
                .font(AppTheme.body())
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.space4)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous)
                .fill(Color.black.opacity(0.45))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous)
                        .stroke(AppTheme.border.opacity(0.55), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tip.title). \(tip.body)")
        .accessibilityHint("Tip \(tipIndex + 1) of \(Self.tips.count)")
    }

    private func chevronButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: AppTheme.touchMin, height: AppTheme.touchMin)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<Self.tips.count, id: \.self) { i in
                Circle()
                    .fill(i == tipIndex ? AppTheme.accent : AppTheme.borderStrong)
                    .frame(width: i == tipIndex ? 8 : 7, height: i == tipIndex ? 8 : 7)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tip \(tipIndex + 1) of \(Self.tips.count)")
    }

    private var ctaBlock: some View {
        VStack(spacing: AppTheme.space3) {
            Button {
                Task { await getStarted() }
            } label: {
                Text(isRequestingCamera ? "Continuing…" : "Get Started")
                    .font(AppTheme.bodyMedium())
                    .foregroundStyle(AppTheme.accentOnAccent)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [AppTheme.accentSoft, AppTheme.accent],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
            }
            .buttonStyle(.plain)
            .disabled(isRequestingCamera)
            .accessibilityLabel("Get Started")
            .accessibilityHint("Requests camera access, then opens the camera.")

            Text("We'll ask for Camera access next.")
                .font(AppTheme.caption())
                .foregroundStyle(AppTheme.inkSecondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Actions

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                dragOffset = value.translation.width * 0.35
            }
            .onEnded { value in
                let dx = value.translation.width
                withAnimation(.easeOut(duration: 0.18)) { dragOffset = 0 }
                if dx < -50 {
                    cycle(1)
                } else if dx > 50 {
                    cycle(-1)
                }
            }
    }

    private func cycle(_ delta: Int) {
        let count = Self.tips.count
        tipIndex = (tipIndex + delta + count) % count
        Analytics.shared.track(
            "onboarding_tip_cycle",
            props: ["index": "\(tipIndex)", "delta": "\(delta)"]
        )
    }

    private func getStarted() async {
        guard !isRequestingCamera else { return }
        isRequestingCamera = true
        Analytics.shared.track("onboarding_get_started", props: ["tipIndex": "\(tipIndex)"])

        // Camera permission only — never push here.
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            Analytics.shared.track(
                granted ? "camera_permission_granted" : "camera_permission_denied",
                props: ["source": "onboarding_get_started"]
            )
        }

        UserDefaults.standard.set(true, forKey: OnboardingStore.completedKey)
        isRequestingCamera = false
        onFinished()
    }
}

// MARK: - Model / store

private struct Tip: Identifiable, Equatable {
    var id: String { title }
    let title: String
    let body: String
}

enum OnboardingStore {
    static let completedKey = "hasCompletedOnboarding"

    static var hasCompleted: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }
}

#if DEBUG
#Preview {
    OnboardingView(onFinished: {})
}
#endif
