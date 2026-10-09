import SwiftUI

struct ManualDialsSheet: View {
    @ObservedObject var session: CameraSession
    @ObservedObject var optimizer: AutoOptimizeController
    @EnvironmentObject private var entitlements: EntitlementsStore

    private var canApplyDials: Bool { entitlements.canApplyDials }
    @Environment(\.dismiss) private var dismiss

    private let shutterStops: [Double] = [1/1000, 1/500, 1/250, 1/125, 1/60, 1/30, 1/15, 1/8, 1/4, 1/2, 1, 2, 4, 8, 15, 30]
    private let isoStops: [Float] = [50, 100, 200, 400, 800, 1600, 3200]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.space4) {
                    Text("Manual override")
                        .font(AppTheme.displayTitle())
                        .foregroundStyle(AppTheme.ink)
                    Text(canApplyDials
                         ? (entitlements.isPro
                            ? "Agent set these — adjust anytime"
                            : "Free Peek — dials unlocked. Shared daily Optimize quota still applies.")
                         : "Free Peek shows ghost dials. Upgrade to edit.")
                        .font(AppTheme.bodySm())
                        .foregroundStyle(AppTheme.inkSecondary)

                    if optimizer.isDirtyOverride && canApplyDials {
                        HStack {
                            Text("You changed the agent’s settings")
                                .font(AppTheme.bodySm())
                                .foregroundStyle(AppTheme.inkSecondary)
                            Spacer()
                            Button("Reset to agent") {
                                optimizer.resetToAgent(session: session)
                            }
                            .font(AppTheme.bodySmMedium())
                            .foregroundStyle(AppTheme.accent)
                        }
                        .padding(AppTheme.space3)
                        .background(RoundedRectangle(cornerRadius: AppTheme.radiusMd).fill(AppTheme.surface))
                    }

                    modeRow
                    shutterRow
                    isoRow
                    evRow

                    if let guidance = session.apertureGuidance {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("APERTURE")
                                .font(AppTheme.overline())
                                .foregroundStyle(AppTheme.inkTertiary)
                            Text(guidance)
                                .font(AppTheme.monoSm())
                                .foregroundStyle(AppTheme.ink)
                            Text("Guidance only — phone lenses are fixed.")
                                .font(AppTheme.caption())
                                .foregroundStyle(AppTheme.inkTertiary)
                        }
                        .padding(AppTheme.space3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: AppTheme.radiusMd).fill(AppTheme.surface))
                    }

                    Text("Educational recipes · real capture uses device limits")
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.inkTertiary)
                }
                .padding(AppTheme.space4)
            }
            .background(AppTheme.bg.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(AppTheme.accent)
                }
            }
        }
        .presentationDetents([.fraction(0.45), .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.45)))
    }

    private var modeRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MODE")
                .font(AppTheme.overline())
                .foregroundStyle(AppTheme.inkTertiary)
            HStack(spacing: 8) {
                ForEach(CameraSession.CaptureMode.allCases) { mode in
                    let enabled = canApplyDials || mode == .auto
                    Button {
                        if enabled {
                            session.captureMode = mode
                            if mode == .auto { session.unlockExposure() }
                            optimizer.markDirty(session: session)
                        } else {
                            entitlements.presentHardPaywall(trigger: "dials_locked")
                        }
                    } label: {
                        Text(mode.shortLabel)
                            .font(AppTheme.monoSm())
                            .foregroundStyle(session.captureMode == mode ? AppTheme.accentOnAccent : AppTheme.inkSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: AppTheme.radiusSm)
                                    .fill(session.captureMode == mode ? AppTheme.accent : AppTheme.surface2)
                            )
                            .opacity(enabled ? 1 : 0.45)
                    }
                }
            }
        }
    }

    private var shutterRow: some View {
        dialScroller(title: "SHUTTER", value: RecipeCameraMapper.formatShutter(session.exposureSeconds), locked: !canApplyDials) {
            ForEach(shutterStops, id: \.self) { s in
                Button {
                    guard canApplyDials else { entitlements.presentHardPaywall(trigger: "dials_locked"); return }
                    Task { @MainActor in
                        await session.setShutter(s)
                        optimizer.markDirty(session: session)
                    }
                } label: {
                    Text(RecipeCameraMapper.formatShutter(s))
                        .font(AppTheme.monoSm())
                        .foregroundStyle(AppTheme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().stroke(AppTheme.border, lineWidth: 1))
                }
            }
        }
    }

    private var isoRow: some View {
        dialScroller(title: "ISO", value: RecipeCameraMapper.formatISO(session.iso), locked: !canApplyDials) {
            ForEach(isoStops, id: \.self) { v in
                Button {
                    guard canApplyDials else { entitlements.presentHardPaywall(trigger: "dials_locked"); return }
                    Task { @MainActor in
                        await session.setISO(v)
                        optimizer.markDirty(session: session)
                    }
                } label: {
                    Text("\(Int(v))")
                        .font(AppTheme.monoSm())
                        .foregroundStyle(AppTheme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().stroke(AppTheme.border, lineWidth: 1))
                }
            }
        }
    }

    private var evRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("EV")
                    .font(AppTheme.overline())
                    .foregroundStyle(AppTheme.inkTertiary)
                Spacer()
                Text(String(format: "%+.1f", session.evBias))
                    .font(AppTheme.monoSm())
                    .foregroundStyle(AppTheme.ink)
                if !canApplyDials {
                    Image(systemName: "lock.fill").font(.caption2).foregroundStyle(AppTheme.inkTertiary)
                }
            }
            Slider(
                value: Binding(
                    get: { Double(session.evBias) },
                    set: { newVal in
                        guard canApplyDials else { entitlements.presentHardPaywall(trigger: "dials_locked"); return }
                        session.setEV(Float(newVal))
                        optimizer.markDirty(session: session)
                    }
                ),
                in: Double(session.capabilities.minEV)...Double(session.capabilities.maxEV),
                step: 0.3
            )
            .tint(AppTheme.accent)
            .disabled(!canApplyDials)
        }
        .padding(AppTheme.space3)
        .background(RoundedRectangle(cornerRadius: AppTheme.radiusMd).fill(AppTheme.surface))
    }

    private func dialScroller<Content: View>(
        title: String,
        value: String,
        locked: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(AppTheme.overline())
                    .foregroundStyle(AppTheme.inkTertiary)
                Spacer()
                Text(value)
                    .font(AppTheme.monoSm())
                    .foregroundStyle(AppTheme.ink)
                if locked {
                    Image(systemName: "lock.fill").font(.caption2).foregroundStyle(AppTheme.inkTertiary)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { content() }
            }
        }
        .padding(AppTheme.space3)
        .background(RoundedRectangle(cornerRadius: AppTheme.radiusMd).fill(AppTheme.surface))
        .opacity(locked ? 0.7 : 1)
    }
}
