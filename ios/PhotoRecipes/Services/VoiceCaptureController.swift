import AVFoundation
import Foundation
import Speech

/// Tap-to-talk dictation with live partials in the bound text field.
/// Default: on-device `SFSpeechRecognizer` (`requiresOnDeviceRecognition` when supported).
/// Silent fallback: Grok `/api/stt` batch when on-device Speech is unavailable.
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

    private let api: APIClient

    // On-device Speech
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    private var latestTranscript = ""
    private var didEmitFinal = false
    private var usingOnDevice = false

    // Grok batch fallback
    private var recorder: AVAudioRecorder?
    private var recordURL: URL?

    private var onPartial: ((String) -> Void)?
    private var onTranscript: ((String) -> Void)?

    init(api: APIClient = .shared) {
        self.api = api
        self.permission = AVAudioSession.sharedInstance().recordPermission
    }

    func toggle(
        onPartial: @escaping (String) -> Void = { _ in },
        onTranscript: @escaping (String) -> Void
    ) {
        switch phase {
        case .recording:
            Task { await stopAndFinalize() }
        case .idle, .error:
            self.onPartial = onPartial
            self.onTranscript = onTranscript
            Task { await start() }
        case .requestingPermission, .uploading:
            break
        }
    }

    func cancel() {
        tearDownSpeech(emitFinal: false)
        tearDownRecorder()
        latestTranscript = ""
        didEmitFinal = false
        usingOnDevice = false
        onPartial = nil
        onTranscript = nil
        phase = .idle
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Start

    private func start() async {
        phase = .requestingPermission
        latestTranscript = ""
        didEmitFinal = false

        let micOK = await requestMic()
        permission = AVAudioSession.sharedInstance().recordPermission
        guard micOK else {
            phase = .error("Microphone is off")
            return
        }

        let speechOK = await requestSpeechAuth()
        if speechOK, await startOnDeviceSpeech() {
            return
        }

        // On-device unavailable / failed → silent Grok batch (no live partials).
        await startGrokRecording()
    }

    private func startOnDeviceSpeech() async -> Bool {
        let recognizer = SFSpeechRecognizer(locale: .current)
            ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer, recognizer.isAvailable else { return false }

        let onDevice = recognizer.supportsOnDeviceRecognition
        guard onDevice else { return false }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = true
            if #available(iOS 16.0, *) {
                request.addsPunctuation = true
            }

            let engine = AVAudioEngine()
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { return false }

            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }

            engine.prepare()
            try engine.start()

            speechRecognizer = recognizer
            recognitionRequest = request
            audioEngine = engine
            usingOnDevice = true
            phase = .recording

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    guard self.usingOnDevice, self.phase == .recording || self.phase == .uploading else { return }

                    if let result {
                        let text = result.bestTranscription.formattedString
                        self.latestTranscript = text
                        // Stream every update into the field; commit final only on Stop
                        // so Auto Optimize / finalize aren't fired mid-utterance.
                        if !text.isEmpty {
                            self.onPartial?(text)
                        }
                    }

                    if let error, self.phase == .recording {
                        // Ignore benign end-of-audio noise; Stop path commits explicitly.
                        let ns = error as NSError
                        if ns.domain == "kAFAssistantErrorDomain", ns.code == 1110 {
                            return
                        }
                    }
                }
            }
            return true
        } catch {
            tearDownSpeech(emitFinal: false)
            return false
        }
    }

    private func startGrokRecording() async {
        usingOnDevice = false
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

    // MARK: - Stop / finalize

    private func stopAndFinalize() async {
        if usingOnDevice {
            await stopOnDeviceAndFinalize()
        } else {
            await stopGrokAndTranscribe()
        }
    }

    private func stopOnDeviceAndFinalize() async {
        // Keep phase as recording until we have text — avoid flash-empty via uploading UI.
        recognitionRequest?.endAudio()
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }

        // Brief window for Speech to deliver isFinal; then commit latest partial.
        try? await Task.sleep(nanoseconds: 350_000_000)
        emitFinalIfNeeded(latestTranscript)

        tearDownSpeech(emitFinal: false)
        usingOnDevice = false
        if phase != .error {
            phase = .idle
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func emitFinalIfNeeded(_ text: String) {
        guard !didEmitFinal else { return }
        didEmitFinal = true
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            // Don't wipe partials already shown — leave field as-is; surface soft error.
            phase = .error("Didn't catch that — try again")
            return
        }
        // Final replaces the same utterance segment the partials already painted (views use base+text).
        onPartial?(trimmed)
        onTranscript?(trimmed)
    }

    private func stopGrokAndTranscribe() async {
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
            onTranscript?(trimmed)
            phase = .idle
        } catch let APIError.missingKey(msg) {
            phase = .error(msg)
        } catch {
            phase = .error(error.localizedDescription.isEmpty
                ? "Voice unavailable — type your scene"
                : error.localizedDescription)
        }
    }

    // MARK: - Teardown

    private func tearDownSpeech(emitFinal: Bool) {
        if emitFinal {
            emitFinalIfNeeded(latestTranscript)
        }
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        if let engine = audioEngine {
            if engine.isRunning {
                engine.inputNode.removeTap(onBus: 0)
                engine.stop()
            }
        }
        audioEngine = nil
        speechRecognizer = nil
    }

    private func tearDownRecorder() {
        recorder?.stop()
        recorder = nil
        if let url = recordURL { try? FileManager.default.removeItem(at: url) }
        recordURL = nil
    }

    // MARK: - Permissions

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

    private func requestSpeechAuth() async -> Bool {
        let status = SFSpeechRecognizer.authorizationStatus()
        switch status {
        case .authorized: return true
        case .denied, .restricted: return false
        case .notDetermined:
            return await withCheckedContinuation { cont in
                SFSpeechRecognizer.requestAuthorization { newStatus in
                    cont.resume(returning: newStatus == .authorized)
                }
            }
        @unknown default:
            return false
        }
    }
}
