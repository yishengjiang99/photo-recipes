import AVFoundation
import Foundation

/// Tap-to-talk: record m4a → POST /api/stt (Grok) → transcript.
/// Pattern: tap mic to start, tap Stop to upload & commit. No live partials in v1 (batch STT).
@MainActor
final class VoiceCaptureController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case requestingPermission
        case recording
        case uploading
        case error(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var permission: AVAudioSession.RecordPermission = .undetermined

    private var recorder: AVAudioRecorder?
    private var recordURL: URL?
    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
        self.permission = AVAudioSession.sharedInstance().recordPermission
    }

    func toggle(onTranscript: @escaping (String) -> Void) {
        switch phase {
        case .recording:
            Task { await stopAndTranscribe(onTranscript: onTranscript) }
        case .idle, .error:
            Task { await start() }
        case .requestingPermission, .uploading:
            break
        }
    }

    func cancel() {
        recorder?.stop()
        recorder = nil
        if let url = recordURL { try? FileManager.default.removeItem(at: url) }
        recordURL = nil
        phase = .idle
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func start() async {
        phase = .requestingPermission
        let granted = await requestMic()
        permission = AVAudioSession.sharedInstance().recordPermission
        guard granted else {
            phase = .error("Microphone is off")
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("pr-voice-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
            let rec = try AVAudioRecorder(url: url, settings: settings)
            guard rec.prepareToRecord(), rec.record() else {
                phase = .error("Couldn't start recording")
                return
            }
            recorder = rec
            recordURL = url
            phase = .recording
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    private func stopAndTranscribe(onTranscript: @escaping (String) -> Void) async {
        guard let rec = recorder, let url = recordURL else {
            phase = .idle
            return
        }
        rec.stop()
        recorder = nil
        phase = .uploading
        defer {
            try? FileManager.default.removeItem(at: url)
            recordURL = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        do {
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else {
                phase = .error("Didn't catch that — try again")
                return
            }
            let text = try await api.transcribeAudio(data: data, filename: "scene.m4a", mimeType: "audio/mp4")
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                phase = .error("Didn't catch that — try again")
                return
            }
            onTranscript(trimmed)
            phase = .idle
        } catch let APIError.missingKey(msg) {
            phase = .error(msg)
        } catch {
            phase = .error(error.localizedDescription.isEmpty
                ? "Voice unavailable — type your scene"
                : error.localizedDescription)
        }
    }

    private func requestMic() async -> Bool {
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted: return true
        case .denied: return false
        case .undetermined:
            return await withCheckedContinuation { cont in
                session.requestRecordPermission { cont.resume(returning: $0) }
            }
        @unknown default:
            return false
        }
    }
}
