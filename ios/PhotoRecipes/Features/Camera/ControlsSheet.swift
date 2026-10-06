import SwiftUI
import UIKit

/// Progressive disclosure Controls sheet (···) — Core · Light · Lens · Capture · Looks.
/// Design: design-handoff-capabilities-comms-v1. Full-bleed viewfinder stays clean.
struct ControlsSheet: View {
    enum Tab: String, CaseIterable, Identifiable {
        case core = "Core"
        case light = "Light"
        case lens = "Lens"
        case capture = "Capture"
        case looks = "Looks"
        var id: String { rawValue }
    }

    @ObservedObject var session: CameraSession
    @ObservedObject var optimizer: AutoOptimizeController
    @EnvironmentObject private var entitlements: EntitlementsStore
    @Environment(\.dismiss) private var dismiss

    var initialTab: Tab = .core
    @State private var tab: Tab = .core
    @State private var lookIntensity: Double = CreativeLookCatalog.defaultIntensity

    private let shutterStops: [Double] = [1/1000, 1/500, 1/250, 1/125, 1/60, 1/30, 1/15, 1/8, 1/4, 1/2, 1, 2, 4, 8, 15, 30]
    private let isoStops: [Float] = [50, 100, 200, 400, 800, 1600, 3200]

    var onTeach: (() -> Void)?
    var onLookApplied: ((CreativeLook) -> Void)?

    /// Server-configurable free dials (Pro always).
    private var canApplyDials: Bool { entitlements.canApplyDials }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Exclusive tap tabs — segmented Picker lost first hits to sheet
                // drag + presentationBackgroundInteraction / viewfinder gestures.
                controlsTabBar
                    .zIndex(10)

                ScrollView {
                    Group {
                        switch tab {
                        case .core: coreTab
                        case .light: lightTab
                        case .lens: lensTab
                        case .capture: captureTab
                        case .looks: looksTab
                        }
                    }
                    .padding(AppTheme.space4)
                }

                footer
            }
            .background(AppTheme.bg.ignoresSafeArea())
            .navigationTitle("Controls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(AppTheme.accent)
                }
            }
            .onAppear {
                tab = initialTab
                if let active = session.activeCreativeLook {
                    lookIntensity = active.resolvedIntensity
                } else if let suggested = optimizer.suggestedLook {
                    lookIntensity = suggested.resolvedIntensity
                }
            }
        }
        .presentationDetents([.fraction(0.5), .large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
        .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.5)))
    }

    /// Exclusive tap tabs — sheet drag / background interaction must not eat the first hit.
    private var controlsTabBar: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases) { t in
                let selected = tab == t
                Button {
                    tab = t
                } label: {
                    Text(t.rawValue)
                        .font(AppTheme.bodySmMedium())
                        .foregroundStyle(selected ? AppTheme.accentOnAccent : AppTheme.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.radiusSm)
                                .fill(selected ? AppTheme.accent : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                // Win over sheet resize pan + presentationBackgroundInteraction hits.
                .highPriorityGesture(
                    TapGesture().onEnded { tab = t }
                )
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                .accessibilityLabel(t.rawValue)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMd)
                .fill(AppTheme.surface)
        )
        .padding(.horizontal, AppTheme.space3)
        .padding(.vertical, AppTheme.space2)
    }

    private var footer: some View {
        HStack(spacing: AppTheme.space3) {
            if onTeach != nil {
                Button("Teach why") {
                    dismiss()
                    onTeach?()
                }
                .font(AppTheme.bodySmMedium())
                .foregroundStyle(AppTheme.inkSecondary)
            }
            Spacer()
            Button("Reset to Auto") {
                guard canApplyDials else { entitlements.presentHardPaywall(trigger: "dials_locked"); return }
                session.unlockExposure()
                session.unlockFocus()
                session.captureMode = .auto
                session.clearActiveLook()
                optimizer.dismissSuggestedLook()
                optimizer.markDirty()
            }
            .font(AppTheme.bodySmMedium())
            .foregroundStyle(AppTheme.accent)
            if !canApplyDials {
                Button("Unlock") { entitlements.presentHardPaywall(trigger: "dials_locked") }
                    .font(AppTheme.bodySmMedium())
                    .foregroundStyle(AppTheme.tip)
            }
        }
        .padding(.horizontal, AppTheme.space4)
        .padding(.vertical, AppTheme.space3)
        .background(AppTheme.surface.ignoresSafeArea(edges: .bottom))
    }

    // MARK: - Core

    private var coreTab: some View {
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
                    Button("Reset to agent") { optimizer.resetToAgent(session: session) }
                        .font(AppTheme.bodySmMedium())
                        .foregroundStyle(AppTheme.accent)
                }
                .padding(AppTheme.space3)
                .background(RoundedRectangle(cornerRadius: AppTheme.radiusMd).fill(AppTheme.surface))
            }

            modeRow
            dialScroller(title: "SHUTTER", value: RecipeCameraMapper.formatShutter(session.exposureSeconds), locked: !canApplyDials) {
                ForEach(shutterStops, id: \.self) { s in
                    dialChip(RecipeCameraMapper.formatShutter(s)) {
                        guard canApplyDials else { entitlements.presentHardPaywall(trigger: "dials_locked"); return }
                        session.setShutter(s); optimizer.markDirty()
                    }
                }
            }
            dialScroller(title: "ISO", value: "\(Int(session.iso.rounded()))", locked: !canApplyDials) {
                ForEach(isoStops, id: \.self) { v in
                    dialChip("\(Int(v))") {
                        guard canApplyDials else { entitlements.presentHardPaywall(trigger: "dials_locked"); return }
                        session.setISO(v); optimizer.markDirty()
                    }
                }
            }
            evRow
            wbFocusZoomRow

            if let guidance = session.apertureGuidance {
                coachCaption(title: "APERTURE", value: guidance, note: "Guidance only — phone lenses are fixed.")
            }

            Text("Educational recipes · real capture uses device limits")
                .font(AppTheme.caption())
                .foregroundStyle(AppTheme.inkTertiary)
        }
    }

    private var modeRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MODE").font(AppTheme.overline()).foregroundStyle(AppTheme.inkTertiary)
            HStack(spacing: 8) {
                ForEach(CameraSession.CaptureMode.allCases) { mode in
                    let enabled = canApplyDials || mode == .auto
                    Button {
                        if enabled {
                            session.captureMode = mode
                            if mode == .auto { session.unlockExposure() }
                            optimizer.markDirty()
                        } else { entitlements.presentHardPaywall(trigger: "dials_locked") }
                    } label: {
                        Text(mode.shortLabel)
                            .font(AppTheme.monoSm())
                            .foregroundStyle(session.captureMode == mode ? AppTheme.accentOnAccent : AppTheme.inkSecondary)
                            .frame(maxWidth: .infinity).frame(height: 40)
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

    private var evRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("EV").font(AppTheme.overline()).foregroundStyle(AppTheme.inkTertiary)
                Spacer()
                Text(String(format: "%+.1f", session.evBias)).font(AppTheme.monoSm()).foregroundStyle(AppTheme.ink)
                if !canApplyDials {
                    Image(systemName: "lock.fill").font(.caption2).foregroundStyle(AppTheme.inkTertiary)
                }
            }
            Slider(
                value: Binding(
                    get: { Double(session.evBias) },
                    set: { newVal in
                        guard canApplyDials else { entitlements.presentHardPaywall(trigger: "dials_locked"); return }
                        session.setEV(Float(newVal)); optimizer.markDirty()
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

    private var wbFocusZoomRow: some View {
        VStack(alignment: .leading, spacing: AppTheme.space3) {
            HStack {
                Text("WB").font(AppTheme.overline()).foregroundStyle(AppTheme.inkTertiary)
                Spacer()
                Text(session.whiteBalanceLocked ? "Locked" : "Auto")
                    .font(AppTheme.monoSm()).foregroundStyle(AppTheme.ink)
            }
            HStack {
                Text("FOCUS").font(AppTheme.overline()).foregroundStyle(AppTheme.inkTertiary)
                Spacer()
                Text(session.focusLocked ? "Locked" : "Cont.")
                    .font(AppTheme.monoSm()).foregroundStyle(AppTheme.ink)
                Button(session.focusLocked ? "Unlock" : "Lock center") {
                    guard canApplyDials else { entitlements.presentHardPaywall(trigger: "dials_locked"); return }
                    if session.focusLocked { session.unlockFocus() }
                    else { session.focus(at: CGPoint(x: 0.5, y: 0.5), lock: true) }
                    optimizer.markDirty()
                }
                .font(AppTheme.caption())
                .foregroundStyle(AppTheme.accent)
            }
            HStack {
                Text("ZOOM").font(AppTheme.overline()).foregroundStyle(AppTheme.inkTertiary)
                Spacer()
                Text(session.lensLabel).font(AppTheme.monoSm()).foregroundStyle(AppTheme.ink)
            }
            HStack(spacing: 8) {
                ForEach([1.0, 2.0, 3.0], id: \.self) { z in
                    dialChip(String(format: "%.0f×", z)) {
                        guard canApplyDials else { entitlements.presentHardPaywall(trigger: "dials_locked"); return }
                        session.setZoomFactor(z); optimizer.markDirty()
                    }
                }
            }
        }
        .padding(AppTheme.space3)
        .background(RoundedRectangle(cornerRadius: AppTheme.radiusMd).fill(AppTheme.surface))
    }

    // MARK: - Light

    private var lightTab: some View {
        VStack(alignment: .leading, spacing: AppTheme.space4) {
            Text("Light tools")
                .font(AppTheme.displayTitle())
                .foregroundStyle(AppTheme.ink)
            Text("Torch, flash, and low-light tools. Capture settings stay primary.")
                .font(AppTheme.bodySm())
                .foregroundStyle(AppTheme.inkSecondary)

            rowCard {
                HStack {
                    Text("Flash").font(AppTheme.bodySmMedium()).foregroundStyle(AppTheme.ink)
                    Spacer()
                    Button {
                        session.flash = session.flash.next
                        optimizer.markDirty()
                    } label: {
                        Label(session.flash.rawValue.capitalized, systemImage: session.flash.icon)
                            .font(AppTheme.monoSm())
                            .foregroundStyle(AppTheme.ink)
                    }
                }
            }

            toggleRow(
                title: "Torch",
                isOn: session.torchOn,
                available: session.supportsTorch,
                unavailable: "Not available on this camera"
            ) { on in
                guard canApplyDials else { entitlements.presentHardPaywall(trigger: "dials_locked"); return }
                session.setTorch(on)
                optimizer.markDirty()
            }

            toggleRow(
                title: "Low-light boost",
                isOn: session.lowLightBoostOn,
                available: session.supportsLowLightBoost,
                unavailable: "Not available on this camera"
            ) { on in
                guard canApplyDials else { entitlements.presentHardPaywall(trigger: "dials_locked"); return }
                session.setLowLightBoost(on)
                optimizer.markDirty()
            }

            rowCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Custom exposure")
                        .font(AppTheme.bodySmMedium()).foregroundStyle(AppTheme.ink)
                    Text(session.capabilities.supportsCustomExposure
                         ? "Locked shutter/ISO via Core tab when mode is S/M."
                         : "Not available on this camera")
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.inkTertiary)
                }
            }
        }
    }

    // MARK: - Lens

    private var lensTab: some View {
        VStack(alignment: .leading, spacing: AppTheme.space4) {
            Text("Lens")
                .font(AppTheme.displayTitle())
                .foregroundStyle(AppTheme.ink)
            Text("Optical lens pick when the device has UW / Wide / Tele. Zoom fallback otherwise.")
                .font(AppTheme.bodySm())
                .foregroundStyle(AppTheme.inkSecondary)

            HStack(spacing: 8) {
                ForEach(CameraSession.LensChoice.allCases) { lens in
                    let available = session.supportsLens(lens)
                    Button {
                        guard canApplyDials else { entitlements.presentHardPaywall(trigger: "dials_locked"); return }
                        guard available else { return }
                        session.selectLens(lens)
                        optimizer.markDirty()
                    } label: {
                        Text(lens.label)
                            .font(AppTheme.monoSm())
                            .foregroundStyle(session.selectedLens == lens ? AppTheme.accentOnAccent : AppTheme.inkSecondary)
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: AppTheme.radiusSm)
                                    .fill(session.selectedLens == lens ? AppTheme.accent : AppTheme.surface2)
                            )
                            .opacity(available ? 1 : 0.35)
                    }
                    .disabled(!available)
                }
            }

            if !session.supportsLens(.ultraWide) && !session.supportsLens(.tele) {
                Text("Not available on this camera — use zoom on Core.")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.inkTertiary)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("LENS POSITION")
                        .font(AppTheme.overline()).foregroundStyle(AppTheme.inkTertiary)
                    Spacer()
                    Text(String(format: "%.2f", session.lensPosition))
                        .font(AppTheme.monoSm()).foregroundStyle(AppTheme.ink)
                }
                if session.supportsLensPosition {
                    Slider(
                        value: Binding(
                            get: { session.lensPosition },
                            set: { v in
                                guard canApplyDials else { entitlements.presentHardPaywall(trigger: "dials_locked"); return }
                                session.setLensPosition(v)
                                optimizer.markDirty()
                            }
                        ),
                        in: 0...1
                    )
                    .tint(AppTheme.accent)
                    .disabled(!canApplyDials)
                } else {
                    Text("Not available on this camera")
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.inkTertiary)
                }
            }
            .padding(AppTheme.space3)
            .background(RoundedRectangle(cornerRadius: AppTheme.radiusMd).fill(AppTheme.surface))
        }
    }

    // MARK: - Capture

    private var captureTab: some View {
        VStack(alignment: .leading, spacing: AppTheme.space4) {
            Text("Capture")
                .font(AppTheme.displayTitle())
                .foregroundStyle(AppTheme.ink)
            Text("Brackets, HDR, and frame rate — not pinned on the viewfinder.")
                .font(AppTheme.bodySm())
                .foregroundStyle(AppTheme.inkSecondary)

            toggleRow(
                title: "Video HDR",
                isOn: session.videoHDROn,
                available: session.supportsVideoHDR,
                unavailable: "Not available on this camera"
            ) { on in
                guard canApplyDials else { entitlements.presentHardPaywall(trigger: "dials_locked"); return }
                session.setVideoHDR(on)
                optimizer.markDirty()
            }

            rowCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Frame rate")
                        .font(AppTheme.bodySmMedium()).foregroundStyle(AppTheme.ink)
                    HStack(spacing: 8) {
                        ForEach([24.0, 30.0, 60.0], id: \.self) { fps in
                            dialChip(String(format: "%.0f fps", fps)) {
                                guard canApplyDials else { entitlements.presentHardPaywall(trigger: "dials_locked"); return }
                                session.setPreferredFrameRate(fps)
                                optimizer.markDirty()
                            }
                        }
                    }
                    Text(session.preferredFrameRate.map { String(format: "Preferred %.0f fps", $0) } ?? "Device default")
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.inkTertiary)
                }
            }

            rowCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Brackets / HDR")
                        .font(AppTheme.bodySmMedium()).foregroundStyle(AppTheme.ink)
                    if let stops = session.pendingBracketStops, !stops.isEmpty {
                        Text("Pending: \(stops.map { String(format: "%+.1f", $0) }.joined(separator: ", ")) EV")
                            .font(AppTheme.monoSm()).foregroundStyle(AppTheme.inkSecondary)
                        Text("Use shutter / bracket burst when stops are staged.")
                            .font(AppTheme.caption()).foregroundStyle(AppTheme.inkTertiary)
                    } else {
                        Text("No bracket staged. Agent may write stops via phoneTargets.")
                            .font(AppTheme.caption()).foregroundStyle(AppTheme.inkTertiary)
                    }
                }
            }
        }
    }

    // MARK: - Looks

    private var looksTab: some View {
        VStack(alignment: .leading, spacing: AppTheme.space4) {
            Text("Looks")
                .font(AppTheme.displayTitle())
                .foregroundStyle(AppTheme.ink)
            Text("Capture grades with intensity — live preview & still bake when intensity > 0. Not beauty filters.")
                .font(AppTheme.bodySm())
                .foregroundStyle(AppTheme.inkSecondary)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("INTENSITY")
                        .font(AppTheme.overline()).foregroundStyle(AppTheme.inkTertiary)
                    Spacer()
                    Text(String(format: "%.2f", lookIntensity))
                        .font(AppTheme.monoSm()).foregroundStyle(AppTheme.ink)
                }
                Slider(value: $lookIntensity, in: 0...1)
                    .tint(AppTheme.accent)
                    .onChange(of: lookIntensity) { _, v in
                        if abs(v - 0) < 0.02 || abs(v - 0.5) < 0.02 || abs(v - 1) < 0.02 {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        if var active = session.activeCreativeLook {
                            active.intensity = v
                            session.setActiveLook(active)
                        }
                    }
            }
            .padding(AppTheme.space3)
            .background(RoundedRectangle(cornerRadius: AppTheme.radiusMd).fill(AppTheme.surface))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(pinnedLooks, id: \.id) { look in
                    lookCell(look)
                }
            }
        }
    }

    /// Suggested pin first, then catalog.
    private var pinnedLooks: [CreativeLook] {
        var ids = CreativeLookCatalog.allIds
        if let sid = optimizer.suggestedLook?.id ?? session.activeCreativeLook?.id,
           let idx = ids.firstIndex(of: sid) {
            ids.remove(at: idx)
            ids.insert(sid, at: 0)
        }
        return ids.map { id in
            let intensity: Double = {
                if session.activeCreativeLook?.id == id { return lookIntensity }
                if optimizer.suggestedLook?.id == id {
                    return optimizer.suggestedLook?.resolvedIntensity ?? lookIntensity
                }
                return lookIntensity
            }()
            return CreativeLook(id: id, intensity: intensity)
        }
    }

    private func lookCell(_ look: CreativeLook) -> some View {
        let isSuggested = optimizer.suggestedLook?.id == look.id
        let isActive = session.activeCreativeLook?.id == look.id
        return Button {
            guard canApplyDials else { entitlements.presentHardPaywall(trigger: "dials_locked"); return }
            let applied = CreativeLook(id: look.id, intensity: lookIntensity)
            session.setActiveLook(applied)
            optimizer.dismissSuggestedLook()
            onLookApplied?(applied)
            optimizer.markDirty()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(look.displayName)
                        .font(AppTheme.bodySmMedium())
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if isSuggested {
                        Text("Suggested")
                            .font(AppTheme.overline())
                            .foregroundStyle(AppTheme.tip)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(AppTheme.tipBg))
                    }
                }
                Text(look.id)
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.inkTertiary)
                    .lineLimit(1)
            }
            .padding(AppTheme.space3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radiusMd)
                    .fill(AppTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.radiusMd)
                            .stroke(isActive ? AppTheme.accent : AppTheme.border, lineWidth: isActive ? 1.5 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shared chrome

    private func dialScroller<Content: View>(
        title: String,
        value: String,
        locked: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(AppTheme.overline()).foregroundStyle(AppTheme.inkTertiary)
                Spacer()
                Text(value).font(AppTheme.monoSm()).foregroundStyle(AppTheme.ink)
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

    private func dialChip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppTheme.monoSm())
                .foregroundStyle(AppTheme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().stroke(AppTheme.border, lineWidth: 1))
        }
    }

    private func rowCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(AppTheme.space3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: AppTheme.radiusMd).fill(AppTheme.surface))
    }

    private func toggleRow(
        title: String,
        isOn: Bool,
        available: Bool,
        unavailable: String,
        onChange: @escaping (Bool) -> Void
    ) -> some View {
        rowCard {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(title, isOn: Binding(
                    get: { isOn },
                    set: { onChange($0) }
                ))
                .tint(AppTheme.accent)
                .disabled(!available || !canApplyDials)
                .foregroundStyle(AppTheme.ink)
                if !available {
                    Text(unavailable)
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.inkTertiary)
                }
            }
        }
    }

    private func coachCaption(title: String, value: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(AppTheme.overline()).foregroundStyle(AppTheme.inkTertiary)
            Text(value).font(AppTheme.monoSm()).foregroundStyle(AppTheme.ink)
            Text(note).font(AppTheme.caption()).foregroundStyle(AppTheme.inkTertiary)
        }
        .padding(AppTheme.space3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: AppTheme.radiusMd).fill(AppTheme.surface))
    }
}
