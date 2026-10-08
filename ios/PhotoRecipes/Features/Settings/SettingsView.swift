import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var entitlements: EntitlementsStore
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var storeKit: StoreKitManager

    @State private var healthText = ""
    @State private var isChecking = false
    @State private var deepCoachEnabled = AutoOptimizeController.deepCoachEnabled
    @State private var useCoreMLScorer = RecipeScorerSelector.useCoreML
    @State private var improveOptIn = AOBracketCapture.optedIn
    @State private var bracketSetCount = 0
    @State private var bracketTotalBytes: Int64 = 0
    @State private var showBracketUploadConfirm = false
    @State private var bracketUploadNote: String? = nil
    @State private var gradientOverlayEnabled = GradientOverlaySettings.enabled

    private func refreshBracketInfo() {
        let sets = AOBracketStore.shared.pendingSets()
        bracketSetCount = sets.count
        bracketTotalBytes = sets.reduce(0) { $0 + $1.bytes }
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.bg.ignoresSafeArea()
                Form {
                    Section("Account") {
                        HStack {
                            Text("Plan")
                            Spacer()
                            EntitlementBadge(isPro: entitlements.isPro)
                        }
                        if let plan = entitlements.status.plan {
                            LabeledContent("Billing period", value: plan.rawValue.capitalized)
                        }
                        if !entitlements.isPro {
                            Button("Upgrade to Pro") {
                                entitlements.presentHardPaywall(trigger: "settings_upgrade", force: true)
                            }
                        }
                        Button("Restore purchases") {
                            Task { await storeKit.restore() }
                        }
                    }

                    Section {
                        TextField("API base URL", text: $api.baseURLString)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        Text("Default placeholder host until you set production. Use http://localhost:8787 with a Mac local API, or your deployed origin (no trailing slash). Cookies (guest/Pro) require credentials + matching host.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(isChecking ? "Checking…" : "Check /api/health") {
                            Task { await checkHealth() }
                        }
                        .disabled(isChecking)
                        if !healthText.isEmpty {
                            Text(healthText).font(.caption.monospaced())
                        }
                    } header: {
                        Text("API")
                    }

                    Section("Billing") {
                        Text("Pro on iOS is unlocked only via App Store In-App Purchase (StoreKit 2). Web Stripe checkout does not unlock this app build.")
                            .font(.caption)
                        Text("Manage or cancel: Settings → [your name] → Subscriptions → AI Camera Pro.")
                            .font(.caption)
                    }

                    Section("Products") {
                        LabeledContent("Yearly", value: IAPProductID.yearly)
                        LabeledContent("Monthly", value: IAPProductID.monthly)
                    }

                    Section("Camera") {
                        Button("Show camera tips") {
                            CameraCoachMarksStore.requestReplay()
                        }
                        Text("Replays the 3 field tips on the Camera tab (Auto Optimize → chips → Controls).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Toggle("Cloud refine (AI)", isOn: $deepCoachEnabled)
                            .onChange(of: deepCoachEnabled) { _, on in
                                AutoOptimizeController.cloudRefineEnabled = on
                            }
                        Text("Off by default (local-first). Pass 1 Auto Optimize is always on-device (instant). Turn on to let Pass 2 optionally call /api/recommend to refine dials within the chosen recipe — never blocks shutter. Uses Ask quota when free; soft-skips on 402/offline.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Toggle("Core ML recipe scorer", isOn: $useCoreMLScorer)
                            .onChange(of: useCoreMLScorer) { _, on in
                                RecipeScorerSelector.useCoreML = on
                            }
                        Text("Experimental. Scores Auto Optimize recipes with a Core ML model instead of the hand-tuned JSON weights. No trained model ships yet — until one is bundled the JSON scorer is used either way.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Toggle("Help improve Auto Optimize", isOn: $improveOptIn)
                            .onChange(of: improveOptIn) { _, on in
                                AOBracketCapture.optedIn = on
                                refreshBracketInfo()
                                Analytics.shared.track("ao_improve_optin", props: ["on": on ? "1" : "0"])
                            }
                        Text("Off by default. When on, each Auto Optimize stores five downsampled exposure-bracket frames (−2…+2 EV) plus exposure stats on this device only, to improve future results. Nothing is ever uploaded without your explicit consent — review and upload from the row below.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if improveOptIn {
                            HStack {
                                Text("Bracket captures on this device")
                                Spacer()
                                Text("\(bracketSetCount) sets · \(Self.formatBytes(bracketTotalBytes))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Button("Review & upload my bracket captures") {
                                showBracketUploadConfirm = true
                            }
                            .disabled(bracketSetCount == 0)
                            if let note = bracketUploadNote {
                                Text(note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onAppear { refreshBracketInfo() }
                    .confirmationDialog(
                        "Upload bracket captures?",
                        isPresented: $showBracketUploadConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Upload \(bracketSetCount) sets") {
                            // Explicit-consent gate: the user tapped twice. The
                            // manifest of what WOULD upload is built here; the
                            // transport itself is a declared stub until the
                            // server endpoint exists — nothing leaves the device.
                            _ = AOBracketStore.shared.pendingUploadManifest()
                            bracketUploadNote = "Uploads aren't available yet — your captures stay on this device."
                            Analytics.shared.track("ao_bracket_upload_consented", props: [
                                "sets": "\(bracketSetCount)",
                                "bytes": "\(bracketTotalBytes)",
                            ])
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This would send \(bracketSetCount) downsampled bracket sets (\(Self.formatBytes(bracketTotalBytes))) to help improve Auto Optimize. Frames are 640px, keep no location data, and are never linked to your identity.")
                    }

                    Section("Developer") {
                        Toggle("Re-exposure gradient overlay", isOn: $gradientOverlayEnabled)
                            .onChange(of: gradientOverlayEnabled) { _, on in
                                GradientOverlaySettings.enabled = on
                            }
                        Text("Debug only. Shows the 13-ratio re-exposure gradient curve and its argmax from the latest frame stats — sanity check on real scenes before Phase 4 training depends on them.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if gradientOverlayEnabled {
                            GradientCurveView()
                        }
                    }

                    Section("Voice") {                       Text("Camera dictate runs the same Auto Optimize → apply path as the button (including phoneTargets). Uses your Optimize quota.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Field Coach mic fills the Ask field only — tap Recommend after. Voice becomes text for scene matching; we don't keep audio clips.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section("About") {
                        LabeledContent("Bundle ID", value: "com.ragnus.mvp")
                        Text("Field technique assistant — recipes with dials + checklists. Not a filter / AI-magic camera app.")
                            .font(.caption)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await entitlements.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                }
            }
        }
    }

    private func checkHealth() async {
        isChecking = true
        defer { isChecking = false }
        do {
            let h = try await api.health()
            healthText = "ok=\(h.ok) hasKey=\(h.hasKey ?? false) stripe=\(h.stripe ?? false) vision=\(h.vision ?? false) stt=\(h.stt ?? false)"
            await entitlements.refresh()
        } catch {
            healthText = error.localizedDescription
        }
    }
}
