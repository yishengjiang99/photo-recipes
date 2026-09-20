import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var entitlements: EntitlementsStore
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var storeKit: StoreKitManager

    @State private var healthText = ""
    @State private var isChecking = false
    @State private var deepCoachEnabled = AutoOptimizeController.deepCoachEnabled

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
                                entitlements.showPaywall = true
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
                        Text("Manage or cancel: Settings → [your name] → Subscriptions → Grok Camera Pro.")
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
                        Toggle("Cloud refine (Grok)", isOn: $deepCoachEnabled)
                            .onChange(of: deepCoachEnabled) { _, on in
                                AutoOptimizeController.cloudRefineEnabled = on
                            }
                        Text("On by default. Pass 1 Auto Optimize is always on-device (instant). Pass 2 optionally calls /api/recommend to refine dials within the chosen recipe — never blocks shutter. Uses Ask quota when free; soft-skips on 402/offline.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section("Voice") {
                        Text("Camera dictate runs the same Auto Optimize → apply path as the button (including phoneTargets). Uses your Optimize quota.")
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
