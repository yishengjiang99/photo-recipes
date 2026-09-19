import SwiftUI

/// Quiet edge chevrons that cue the shooter to pan / reframe.
/// Driven by active recipe tags + optional agent status copy — never neon.
struct ViewfinderPanCue: Equatable {
    var left = false
    var right = false
    var up = false
    var down = false

    var isEmpty: Bool { !left && !right && !up && !down }

    static let none = ViewfinderPanCue()
}

enum ViewfinderPanCueResolver {
    /// Hide when no recipe and Auto Optimize is idle; otherwise derive from tags + status hooks.
    static func resolve(
        recipeId: String?,
        agentPhase: AutoOptimizeController.Phase,
        agentStatus: String?
    ) -> ViewfinderPanCue? {
        let recipe = recipeId.flatMap { BundledPresets.recipe(id: $0) }
        let status = (agentStatus ?? agentPhase.statusCopy).trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAgentSignal = agentPhase != .idle && !status.isEmpty

        if recipe == nil && !hasAgentSignal {
            return nil
        }

        var cue = ViewfinderPanCue()

        if let recipe {
            applyRecipe(recipe, to: &cue)
        }
        if hasAgentSignal {
            applyStatusHooks(status.lowercased(), to: &cue)
        }

        return cue.isEmpty ? nil : cue
    }

    private static func applyRecipe(_ recipe: Recipe, to cue: inout ViewfinderPanCue) {
        let id = recipe.id.lowercased()
        let title = recipe.title.lowercased()
        let blob = "\(id) \(title) \(recipe.blurb.lowercased())"

        // Motion / panning → horizontal arrows (required pair).
        if recipe.tags.contains(.motion)
            || id.contains("panning")
            || blob.contains("pan with")
            || blob.contains("panning")
        {
            cue.left = true
            cue.right = true
        }

        // Composition / get-low → down arrow.
        if recipe.tags.contains(.composition)
            || id.contains("get-down-low")
            || id.contains("low")
            || blob.contains("knee-height")
            || blob.contains("get down")
            || blob.contains("getting down")
        {
            cue.down = true
        }
    }

    /// Optional agent status string hooks (Sense/Apply copy).
    private static func applyStatusHooks(_ status: String, to cue: inout ViewfinderPanCue) {
        if status.contains("pann")
            || status.contains("pan ")
            || status.contains("panning")
            || status.contains("sensing motion")
            || status.contains("track subject")
            || status.contains("follow")
        {
            cue.left = true
            cue.right = true
        }
        if status.contains("low")
            || status.contains("kneel")
            || status.contains("get down")
            || status.contains("knee")
            || status.contains("perspective")
        {
            cue.down = true
        }
        if status.contains("look up")
            || status.contains("tilt up")
            || status.contains("raise the")
            || status.contains("point up")
        {
            cue.up = true
        }
    }
}

struct ViewfinderPanCuesView: View {
    let cue: ViewfinderPanCue
    /// Reserve space so down chevron sits above bottom chrome.
    var bottomInset: CGFloat = 200
    var topInset: CGFloat = 72

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private var chevronOpacity: Double {
        if reduceMotion { return 0.7 }
        return pulse ? 0.45 : 0.7
    }

    var body: some View {
        ZStack {
            HStack {
                if cue.left { chevron("chevron.left") }
                Spacer(minLength: 0)
                if cue.right { chevron("chevron.right") }
            }
            .padding(.horizontal, 10)
            .padding(.top, topInset)
            .padding(.bottom, bottomInset)

            VStack {
                if cue.up {
                    chevron("chevron.up")
                        .padding(.top, topInset)
                }
                Spacer(minLength: 0)
                if cue.down {
                    chevron("chevron.down")
                        .padding(.bottom, bottomInset)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .onAppear { startPulseIfNeeded() }
        .onChange(of: reduceMotion) { _, _ in startPulseIfNeeded() }
        .onChange(of: cue) { _, _ in startPulseIfNeeded() }
    }

    private func chevron(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(AppTheme.ink.opacity(chevronOpacity))
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

    private var accessibilitySummary: String {
        var parts: [String] = []
        if cue.left || cue.right { parts.append("Pan left or right") }
        if cue.up { parts.append("Tilt up") }
        if cue.down { parts.append("Get lower") }
        return parts.joined(separator: ". ")
    }

    private func startPulseIfNeeded() {
        pulse = false
        guard !reduceMotion, !cue.isEmpty else { return }
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
            pulse = true
        }
    }
}
