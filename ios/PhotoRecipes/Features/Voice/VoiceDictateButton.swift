import SwiftUI

/// Quiet mic control (design-handoff-voice-v1).
/// Idle: ink-secondary ghost circle. Recording: accent ring soft opacity pulse 1.2s.
/// Tap to talk / tap Stop. Live partials stream into the bound field via onPartial.
/// Reduce Motion → static accent ring.
struct VoiceDictateButton: View {
    @ObservedObject var controller: VoiceCaptureController
    var enabled: Bool = true
    /// Interim / partial transcript for the current utterance (live in the text field).
    var onPartial: ((String) -> Void)? = nil
    /// Final utterance — commit cleanly; Camera also kicks Auto Optimize from here.
    var onTranscript: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Button {
            guard enabled || isRecording else { return }
            controller.toggle(
                onPartial: { text in onPartial?(text) },
                onTranscript: onTranscript
            )
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(ringColor, lineWidth: 1.5)
                    .background(Circle().fill(fillColor))
                    .frame(width: 44, height: 44)
                    .opacity(recordingOpacity)
                Image(systemName: glyph)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(glyphColor)
            }
            .frame(width: AppTheme.touchMin, height: AppTheme.touchMin)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled && !isRecording)
        .opacity((!enabled && !isRecording) ? 0.4 : 1)
        .accessibilityLabel(a11y)
        .onChange(of: controller.phase) { _, new in
            guard case .recording = new else { pulse = false; return }
            if reduceMotion {
                pulse = false
            } else {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
    }

    private var isRecording: Bool {
        if case .recording = controller.phase { return true }
        return false
    }
    private var isUploading: Bool {
        if case .uploading = controller.phase { return true }
        return false
    }
    private var glyph: String {
        if isRecording { return "stop.fill" }
        if isUploading { return "ellipsis" }
        return "mic"
    }
    private var glyphColor: Color {
        isRecording || isUploading ? AppTheme.accent : AppTheme.inkSecondary
    }
    private var ringColor: Color {
        isRecording || isUploading ? AppTheme.accent : AppTheme.borderStrong
    }
    private var fillColor: Color {
        isRecording ? AppTheme.accentMuted : Color.clear
    }
    private var recordingOpacity: Double {
        if isRecording && !reduceMotion { return pulse ? 1.0 : 0.45 }
        return 1.0
    }
    private var a11y: String {
        if isRecording { return "Stop dictation" }
        if isUploading { return "Transcribing" }
        return "Dictate scene"
    }
}

struct VoiceStatusCaption: View {
    @ObservedObject var controller: VoiceCaptureController
    var body: some View {
        Group {
            switch controller.phase {
            case .recording:
                Text("Listening…")
                    .font(AppTheme.bodySm())
                    .foregroundStyle(AppTheme.inkSecondary)
            case .uploading:
                Text("Matching your words…")
                    .font(AppTheme.bodySm())
                    .foregroundStyle(AppTheme.inkSecondary)
            case .error(let msg):
                Text(msg)
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.danger)
            default:
                EmptyView()
            }
        }
    }
}
