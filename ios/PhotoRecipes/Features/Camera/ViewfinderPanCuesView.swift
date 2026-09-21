import SwiftUI

/// Quiet edge chevrons — recipe tags + agentic `panCue` (never neon).
struct ViewfinderPanCue: Equatable {
    var left = false
    var right = false
    var up = false
    var down = false
    var caption: String? = nil

    var isEmpty: Bool { !left && !right && !up && !down }
}

enum ViewfinderPanCueResolver {
    static func resolve(
        recipeId: String?,
        agentPhase: AutoOptimizeController.Phase,
        agentStatus: String?,
        agentPanCue: PanCue?
    ) -> ViewfinderPanCue? {
        let recipe = recipeId.flatMap { BundledPresets.recipe(id: $0) }
        let status = (agentStatus ?? agentPhase.statusCopy).trimmingCharacters(in: .whitespacesAndNewlines)
        let hasPan = agentPanCue?.direction != nil
        let hasAgentSignal = agentPhase != .idle && (!status.isEmpty || hasPan)

        if recipe == nil && !hasAgentSignal { return nil }

        var cue = ViewfinderPanCue()
        if let agentPanCue, let dir = agentPanCue.direction {
            applyPanCue(direction: dir, note: agentPanCue.note, to: &cue)
        } else {
            if let recipe { applyRecipe(recipe, to: &cue) }
            if hasAgentSignal { applyStatusHooks(status.lowercased(), to: &cue) }
        }
        return cue.isEmpty ? nil : cue
    }

    private static func applyPanCue(direction: String, note: String?, to cue: inout ViewfinderPanCue) {
        // Map direction literally — never fall through "down"/"lower" to L/R (Build 28).
        // Those looked like tappable controls on composition / get-down-low.
        switch direction.lowercased() {
        case "left":
            cue.left = true
        case "right":
            cue.right = true
        case "either", "horizontal", "both", "pan":
            cue.left = true
            cue.right = true
        case "down", "lower", "below":
            cue.down = true
        case "up", "above":
            cue.up = true
        default:
            // Unknown direction → caption only (no fake edge buttons).
            break
        }
        if let note, !note.isEmpty { cue.caption = note }
    }

    private static func applyRecipe(_ recipe: Recipe, to cue: inout ViewfinderPanCue) {
        let id = recipe.id.lowercased()
        let blob = "\(id) \(recipe.title.lowercased()) \(recipe.blurb.lowercased())"
        if recipe.tags.contains(.motion) || id.contains("panning") || blob.contains("panning") {
            cue.left = true; cue.right = true
            cue.caption = "pan with subject →"
        }
        if recipe.tags.contains(.composition) || id.contains("get-down-low") || blob.contains("knee-height") {
            cue.down = true
            if cue.caption == nil {
                cue.caption = id.contains("get-down-low") ? "Drop lower" : "include foreground ↓"
            }
        }
    }

    private static func applyStatusHooks(_ status: String, to cue: inout ViewfinderPanCue) {
        if status.contains("pann") || status.contains("sensing motion") || status.contains("follow") {
            cue.left = true; cue.right = true
        }
        if status.contains("low") || status.contains("kneel") || status.contains("get down") {
            cue.down = true
        }
        if status.contains("look up") || status.contains("tilt up") {
            cue.up = true
        }
    }
}

struct ViewfinderPanCuesView: View {
    let cue: ViewfinderPanCue
    var bottomInset: CGFloat = 120
    var topInset: CGFloat = 64

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private var chevronOpacity: Double {
        reduceMotion ? 0.75 : (pulse ? 0.55 : 0.9)
    }

    var body: some View {
        ZStack {
            HStack {
                if cue.left { chevron("chevron.left") }
                Spacer(minLength: 0)
                if cue.right { chevron("chevron.right") }
            }
            .padding(.horizontal, 14)
            .padding(.top, topInset)
            .padding(.bottom, bottomInset)

            VStack {
                if cue.up { chevron("chevron.up").padding(.top, topInset) }
                Spacer(minLength: 0)
                if let caption = cue.caption, !caption.isEmpty {
                    Text(caption)
                        .font(AppTheme.caption())
                        .foregroundStyle(Color.white.opacity(0.8))
                        .shadow(color: .black.opacity(0.45), radius: 1, y: 1)
                        .padding(.bottom, 6)
                }
                if cue.down {
                    chevron("chevron.down").padding(.bottom, bottomInset)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityLabel(accessibilitySummary)
        .onAppear { startPulse() }
        .onChange(of: cue) { _, _ in startPulse() }
        .onChange(of: reduceMotion) { _, _ in startPulse() }
    }

    private func chevron(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 26, weight: .semibold))
            .foregroundStyle(Color.white.opacity(chevronOpacity))
            .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
            .frame(width: 44, height: 44)
    }

    private var accessibilitySummary: String {
        var parts: [String] = []
        if cue.left && cue.right { parts.append("Pan left or right") }
        else if cue.left { parts.append("Pan left") }
        else if cue.right { parts.append("Pan right") }
        if cue.up { parts.append("Tilt up") }
        if cue.down { parts.append("Get lower") }
        if let c = cue.caption { parts.append(c) }
        return parts.joined(separator: ". ")
    }

    private func startPulse() {
        pulse = false
        guard !reduceMotion, !cue.isEmpty else { return }
        withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { pulse = true }
    }
}
