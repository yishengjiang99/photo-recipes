import AVFoundation
import Foundation
import Speech
import os.log

/// Tap-to-talk dictation with live partials in the bound text field.
/// Prefer on-device SFSpeechRecognizer; else Apple Speech (still streams partials);
/// Grok `/api/stt` batch only when Speech is unavailable (no live partials).
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
    /// True when the active path can stream interim transcripts into the field.
    @Published private(set) var streamsPartials = false

    private let api: APIClient
    private let log = Logger(subsystem: "com.ragnus.mvp", category: "VoiceSTT")

    // Apple Speech (on-device or network)
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    private var latestTranscript = ""
    private var didEmitFinal = false
    private var usingSpeechFramework = false

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
        usingSpeechFramework = false
        streamsPartials = false
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
        streamsPartials = false

        let micOK = await requestMic()
        permission = AVAudioSession.sharedInstance().recordPermission
        guard micOK else {
            log.error("mic denied")
            phase = .error("Microphone is off")
            return
        }

        let speechOK = await requestSpeechAuth()
        if speechOK {
            // 1) On-device when supported (privacy + offline).
            if await startSpeech(requiresOnDevice: true) {
                log.info("path=on_device_speech streams=true")
                return
            }
            // 2) Apple Speech with network still streams partials — prefer over Grok batch.
            if await startSpeech(requiresOnDevice: false) {
                log.info("path=apple_speech_network streams=true")
                return
            }
        } else {
            log.info("speech auth denied — falling back to Grok batch")
        }

        // 3) Speech unavailable → Grok batch (final only).
        log.info("path=grok_batch streams=false")
        await startGrokRecording()
    }

    /// Start SFSpeechRecognizer. When `requiresOnDevice` is true, fails closed if unsupported.
    private func startSpeech(requiresOnDevice: Bool) async -> Bool {
        let recognizer = SFSpeechRecognizer(locale: .current)
            ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer, recognizer.isAvailable else { return false }

        if requiresOnDevice {
            guard recognizer.supportsOnDeviceRecognition else { return false }
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if requiresOnDevice {
                request.requiresOnDeviceRecognition = true
            }
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
            usingSpeechFramework = true
            streamsPartials = true
            phase = .recording

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    guard self.usingSpeechFramework,
                          self.phase == .recording || self.phase == .uploading else { return }

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
                        let ns = error as NSError
                        // Ignore benign end-of-audio noise; Stop path commits explicitly.
                        if ns.domain == "kAFAssistantErrorDomain", ns.code == 1110 {
                            return
                        }
                        self.log.error("speech error domain=\(ns.domain, privacy: .public) code=\(ns.code)")
                    }
                }
            }
            return true
        } catch {
            log.error("startSpeech failed: \(error.localizedDescription, privacy: .public)")
            tearDownSpeech(emitFinal: false)
            return false
        }
    }

    private func startGrokRecording() async {
        usingSpeechFramework = false
        streamsPartials = false
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
        if usingSpeechFramework {
            await stopSpeechAndFinalize()
        } else {
            await stopGrokAndTranscribe()
        }
    }

    private func stopSpeechAndFinalize() async {
        recognitionRequest?.endAudio()
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }

        // Brief window for Speech to deliver isFinal; then commit latest partial.
        try? await Task.sleep(nanoseconds: 350_000_000)
        emitFinalIfNeeded(latestTranscript)

        tearDownSpeech(emitFinal: false)
        usingSpeechFramework = false
        streamsPartials = false
        if case .error = phase {
            // keep error
        } else {
            phase = .idle
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func emitFinalIfNeeded(_ text: String) {
        guard !didEmitFinal else { return }
        didEmitFinal = true
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            phase = .error("Didn't catch that — try again")
            return
        }
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
            // Paint field once for batch path (no live partials).
            onPartial?(trimmed)
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
