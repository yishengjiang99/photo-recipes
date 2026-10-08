import SwiftUI
import Combine

/// Backing store for the Developer-section gradient overlay toggle.
enum GradientOverlaySettings {
    static let enabledKey = "ao.devGradientOverlayEnabled"

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }
}

/// Debug overlay for the 13-ratio re-exposure gradient curve (Phase 4 input
/// sanity check). Thin by design: all data shaping lives in
/// `GradientCurveData` (unit-tested); this view only draws bars from the
/// latest `GPUStatsEngine` outputs. Never rendered in tests.
struct GradientCurveView: View {
    @State private var data: GradientCurveData?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let data {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(data.normalizedScores.indices, id: \.self) { i in
                        VStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(i == data.argmaxIndex
                                      ? Color.accentColor
                                      : Color.secondary.opacity(0.5))
                                .frame(height: max(4, CGFloat(data.normalizedScores[i]) * 64))
                            if i % 3 == 0 {
                                Text(Self.ratioLabel(data.ratios[i]))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 88)
                HStack {
                    if let arg = data.argmaxIndex {
                        Text("argmax r=\(Self.ratioLabel(data.ratios[arg])) (index \(arg))")
                    }
                    Spacer()
                    if data.gpuMs > 0 {
                        Text(String(format: "GPU %.2f ms", data.gpuMs))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text("No frame stats yet — open the Camera tab and point at a scene.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { refresh() }
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            refresh()
        }
    }

    private func refresh() {
        if let stats = GPUStatsEngine.shared.latestStats(maxAge: 5) {
            data = GradientCurveData.from(stats)
        }
    }

    private static func ratioLabel(_ r: Float) -> String {
        r < 1 ? String(format: "%.2f", r) : String(format: "%.1f", r)
    }
}
