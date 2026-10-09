import Foundation
import UIKit

enum APIError: LocalizedError {
    case invalidURL
    case http(Int, String?)
    case paywall(PaywallPayload)
    case missingKey(String)
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API URL. Check Settings."
        case .http(let code, let body): return body ?? "Request failed (\(code))"
        case .paywall(let p): return p.error ?? "Free Peek limit reached. Upgrade to Pro."
        case .missingKey(let msg): return msg
        case .decoding(let e): return "Bad response: \(e.localizedDescription)"
        case .transport(let e): return e.localizedDescription
        }
    }
}

/// Not MainActor-isolated: created off the main thread while reading URLSession bytes.
/// Isolating this enum forced the SSE read loop onto MainActor and deferred UI event Tasks until the stream finished.
enum RecommendStreamEvent: Sendable {
    case phase(String)
    case status(String)
    case reasoning(String)
    case content(String)
    case result(RecommendResponse)
    case error(String, Int?)

    /// Short chrome / Ask copy for phase events (status.message overrides when present).
    static func statusCopy(forPhase phase: String) -> String? {
        switch phase {
        case "started": return "Matching a recipe…"
        case "sensing": return "Reading the scene…"
        case "thinking": return "Matching a recipe…"
        case "writing": return "Writing tips…"
        case "done": return "Recipe ready…"
        // Aliases if an older/newer contract slips through
        case "start": return "Matching a recipe…"
        case "sense": return "Reading the scene…"
        case "reason", "reasoning": return "Matching a recipe…"
        case "write", "content": return "Writing tips…"
        default: return nil
        }
    }
}

final class APIClient: ObservableObject {
    static let shared = APIClient()

    @Published var baseURLString: String {
        didSet {
            UserDefaults.standard.set(baseURLString, forKey: Self.baseURLKey)
        }
    }

    private static let baseURLKey = "api.baseURL"
    /// Production API (photo.grepawk.com). Settings can override for staging.
    private static let defaultBaseURL = "https://photo.grepawk.com"
    private static let legacyPlaceholderHosts: Set<String> = [
        "https://photo-recipes.example.com",
        "http://photo-recipes.example.com",
        "https://photo-recipes.example.com/",
    ]

    private let session: URLSession
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()
    private let encoder = JSONEncoder()

    /// Outcome of re-syncing the App Store entitlement after the server answered 402.
    enum PaywallRecovery: Sendable {
        /// No current StoreKit entitlement — the 402 is legitimate.
        case notEntitled
        /// Server now recognises Pro — retry the request.
        case synced
        /// StoreKit says Pro but the server could not verify it.
        case syncFailed(String)
    }

    /// Set by StoreKitManager. Called once when a quota-gated request gets 402.
    var paywallRecovery: (@Sendable () async -> PaywallRecovery)?

    /// A subscriber must never see the Free Peek paywall: on 402, re-verify with the server and retry once.
    private func withPaywallRecovery<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let APIError.paywall(payload) {
            guard let recover = paywallRecovery else { throw APIError.paywall(payload) }
            switch await recover() {
            case .synced:
                return try await operation()
            case .syncFailed(let reason):
                throw APIError.http(402, "Your Pro subscription is active, but the server couldn't verify it (\(reason)). Try again in a moment, or use Restore Purchases in Settings.")
            case .notEntitled:
                throw APIError.paywall(payload)
            }
        }
    }

    init(session: URLSession? = nil) {
        let stored = UserDefaults.standard.string(forKey: Self.baseURLKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let stored, !stored.isEmpty, !Self.legacyPlaceholderHosts.contains(stored) {
            self.baseURLString = stored
        } else {
            self.baseURLString = Self.defaultBaseURL
        }

        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.httpCookieAcceptPolicy = .always
            config.httpShouldSetCookies = true
            config.httpCookieStorage = HTTPCookieStorage.shared
            config.timeoutIntervalForRequest = 60
            config.timeoutIntervalForResource = 120
            self.session = URLSession(configuration: config)
        }
    }

    private func url(_ path: String) throws -> URL {
        let root = baseURLString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let u = URL(string: root + path) else { throw APIError.invalidURL }
        return u
    }

    // MARK: - Health

    func health() async throws -> HealthResponse {
        let req = URLRequest(url: try url("/api/health"))
        return try await get(req)
    }

    // MARK: - Subscription

    func subscriptionStatus() async throws -> SubscriptionStatus {
        var req = URLRequest(url: try url("/api/subscription-status"))
        req.httpMethod = "GET"
        return try await get(req)
    }

    // MARK: - Recommend (text + optional vision)

    func recommend(
        message: String,
        favorites: [String] = [],
        imageJPEGData: Data? = nil
    ) async throws -> RecommendResponse {
        try await withPaywallRecovery {
            try await recommendOnce(message: message, favorites: favorites, imageJPEGData: imageJPEGData)
        }
    }

    private func recommendOnce(
        message: String,
        favorites: [String],
        imageJPEGData: Data?
    ) async throws -> RecommendResponse {
        var body = RecommendRequest(
            message: message,
            favorites: favorites,
            image: nil
        )
        if let data = imageJPEGData {
            let b64 = data.base64EncodedString()
            body.image = "data:image/jpeg;base64,\(b64)"
        }

        var req = URLRequest(url: try url("/api/recommend"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try encoder.encode(body)

        let (data, response) = try await perform(req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.http(-1, "No HTTP response")
        }

        if http.statusCode == 402 {
            let payload = (try? decoder.decode(PaywallPayload.self, from: data))
                ?? PaywallPayload(error: String(data: data, encoding: .utf8), code: "paywall")
            throw APIError.paywall(payload)
        }
        if http.statusCode == 503 {
            let msg = (try? decoder.decode(RecommendResponse.self, from: data))?.error
                ?? String(data: data, encoding: .utf8)
                ?? "XAI_API_KEY is not set"
            throw APIError.missingKey(msg)
        }
        if !(200..<300).contains(http.statusCode) {
            let msg = (try? decoder.decode(RecommendResponse.self, from: data))?.error
                ?? String(data: data, encoding: .utf8)
            throw APIError.http(http.statusCode, msg)
        }
        do {
            return try decoder.decode(RecommendResponse.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }


    // MARK: - Recommend (SSE stream)

    /// Shared SSE contract with web (`POST /api/recommend/stream`).
    /// Events: phase, status, reasoning, content, result, error.
    func recommendStream(
        message: String,
        favorites: [String] = [],
        imageJPEGData: Data? = nil,
        onEvent: @escaping @Sendable (RecommendStreamEvent) -> Void
    ) async throws -> RecommendResponse {
        try await withPaywallRecovery {
            try await recommendStreamOnce(
                message: message,
                favorites: favorites,
                imageJPEGData: imageJPEGData,
                onEvent: onEvent
            )
        }
    }

    private func recommendStreamOnce(
        message: String,
        favorites: [String],
        imageJPEGData: Data?,
        onEvent: @escaping @Sendable (RecommendStreamEvent) -> Void
    ) async throws -> RecommendResponse {
        var body = RecommendRequest(
            message: message,
            favorites: favorites,
            image: nil
        )
        if let data = imageJPEGData {
            let b64 = data.base64EncodedString()
            body.image = "data:image/jpeg;base64,\(b64)"
        }

        var req = URLRequest(url: try url("/api/recommend/stream"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.httpBody = try encoder.encode(body)
        req.timeoutInterval = 90

        let (bytes, response) = try await session.bytes(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.http(-1, "No HTTP response")
        }
        if http.statusCode == 402 {
            // Drain a small error payload if present
            var data = Data()
            for try await b in bytes {
                data.append(b)
                if data.count > 4096 { break }
            }
            let payload = (try? decoder.decode(PaywallPayload.self, from: data))
                ?? PaywallPayload(error: String(data: data, encoding: .utf8), code: "paywall")
            throw APIError.paywall(payload)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(http.statusCode, "Recommend stream failed (\(http.statusCode))")
        }

        var eventName = "message"
        var dataLines: [String] = []
        var finalResult: RecommendResponse?

        func flushEvent() throws {
            defer {
                eventName = "message"
                dataLines.removeAll(keepingCapacity: true)
            }
            guard !dataLines.isEmpty else { return }
            let raw = dataLines.joined(separator: "\n")
            guard let payloadData = raw.data(using: .utf8) else { return }
            switch eventName {
            case "phase":
                if let obj = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
                   let phase = obj["phase"] as? String {
                    onEvent(.phase(phase))
                }
            case "status":
                if let obj = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
                   let message = obj["message"] as? String {
                    onEvent(.status(message))
                }
            case "reasoning":
                if let obj = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
                   let delta = obj["delta"] as? String {
                    onEvent(.reasoning(delta))
                }
            case "content":
                if let obj = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
                   let delta = obj["delta"] as? String {
                    onEvent(.content(delta))
                }
            case "result":
                let decoded = try decoder.decode(RecommendResponse.self, from: payloadData)
                finalResult = decoded
                onEvent(.result(decoded))
            case "error":
                if let obj = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
                   let error = obj["error"] as? String {
                    let status = obj["status"] as? Int
                    onEvent(.error(error, status))
                    throw APIError.http(status ?? 502, error)
                }
                throw APIError.http(502, "Recommend stream error")
            default:
                break
            }
        }

        for try await line in bytes.lines {
            if line.isEmpty {
                try flushEvent()
                continue
            }
            if line.hasPrefix("event:") {
                eventName = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            }
        }
        try flushEvent()

        guard let result = finalResult else {
            throw APIError.http(502, "Stream ended without a recipe")
        }
        return result
    }

    // MARK: - IAP verify

    struct IAPVerifyRequest: Encodable {
        var signedTransaction: String
        var productId: String
        var plan: String
    }

    struct IAPVerifyResponse: Codable {
        var ok: Bool?
        var pro: Bool?
        var status: String?
        var plan: String?
        var error: String?
    }

    func verifyIAP(signedTransaction: String, productId: String, plan: SubscriptionPlan) async throws -> IAPVerifyResponse {
        var req = URLRequest(url: try url("/api/iap/verify"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = IAPVerifyRequest(
            signedTransaction: signedTransaction,
            productId: productId,
            plan: plan.rawValue
        )
        req.httpBody = try encoder.encode(body)
        let (data, response) = try await perform(req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.http(-1, "No HTTP response")
        }
        if !(200..<300).contains(http.statusCode) {
            let decoded = try? decoder.decode(IAPVerifyResponse.self, from: data)
            throw APIError.http(http.statusCode, decoded?.error ?? String(data: data, encoding: .utf8))
        }
        do {
            return try decoder.decode(IAPVerifyResponse.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }


    // MARK: - Speech-to-text (Grok via /api/stt)

    struct STTResponse: Decodable {
        var text: String?
        var error: String?
    }

    /// Upload recorded audio; server holds XAI_API_KEY. Does not burn Ask/Optimize quota.
    func transcribeAudio(data: Data, filename: String = "scene.m4a", mimeType: String = "audio/mp4") async throws -> String {
        let boundary = "pr-\(UUID().uuidString)"
        var req = URLRequest(url: try url("/api/stt"))
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        func append(_ s: String) { body.append(Data(s.utf8)) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"audio\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        append("\r\n--\(boundary)--\r\n")
        req.httpBody = body

        let (respData, response) = try await perform(req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.http(-1, "No HTTP response")
        }
        let decoded = try? decoder.decode(STTResponse.self, from: respData)
        if http.statusCode == 503 {
            throw APIError.missingKey(decoded?.error ?? "XAI_API_KEY is not set")
        }
        if !(200..<300).contains(http.statusCode) {
            throw APIError.http(http.statusCode, decoded?.error ?? String(data: respData, encoding: .utf8))
        }
        let text = decoded?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty {
            throw APIError.http(422, decoded?.error ?? "Didn't catch that — try again")
        }
        return text
    }

    // MARK: - Describe scene (lightweight vision caption)

    struct DescribeSceneResponse: Decodable {
        var text: String?
        var error: String?
    }

    /// Viewfinder caption for scene prefill. Does NOT burn Ask/Auto Optimize quota.
    func describeScene(imageJPEGData: Data) async throws -> String {
        let payload = ["image": "data:image/jpeg;base64,\(imageJPEGData.base64EncodedString())"]
        var req = URLRequest(url: try url("/api/describe-scene"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try encoder.encode(payload)

        let (respData, response) = try await perform(req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.http(-1, "No HTTP response")
        }
        let decoded = try? decoder.decode(DescribeSceneResponse.self, from: respData)
        if http.statusCode == 503 {
            throw APIError.missingKey(decoded?.error ?? "XAI_API_KEY is not set")
        }
        if !(200..<300).contains(http.statusCode) {
            throw APIError.http(http.statusCode, decoded?.error ?? String(data: respData, encoding: .utf8))
        }
        let text = decoded?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty {
            throw APIError.http(422, decoded?.error ?? "Couldn't describe scene")
        }
        return text
    }


    // MARK: - Push (Experiment 1)

    struct PushRegisterRequest: Encodable {
        var token: String
        var platform: String
        var bundleId: String
        var environment: String
        var appVersion: String
        /// IANA zone so the server schedules evening nudges in local time (not UTC).
        var timezone: String
    }

    struct PushRegisterResponse: Decodable {
        var ok: Bool?
        var guestId: String?
        var error: String?
    }

    /// Register APNs device token. Soft-fails on 404/503 (server may not ship yet).
    func registerPushToken(
        token: String,
        environment: String,
        appVersion: String,
        timezone: String = TimeZone.current.identifier
    ) async throws {
        var req = URLRequest(url: try url("/api/push/register"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = PushRegisterRequest(
            token: token,
            platform: "ios",
            bundleId: "com.ragnus.mvp",
            environment: environment,
            appVersion: appVersion,
            timezone: timezone
        )
        req.httpBody = try encoder.encode(body)
        let (data, response) = try await perform(req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.http(-1, "No HTTP response")
        }
        if http.statusCode == 404 || http.statusCode == 503 {
            throw APIError.http(http.statusCode, "push register unavailable")
        }
        if !(200..<300).contains(http.statusCode) {
            let decoded = try? decoder.decode(PushRegisterResponse.self, from: data)
            throw APIError.http(http.statusCode, decoded?.error ?? String(data: data, encoding: .utf8))
        }
        // 200: { ok, guestId } — guestId is session-side; never surface in UI.
        _ = try? decoder.decode(PushRegisterResponse.self, from: data)
    }

    struct PushPrefs: Codable, Equatable {
        var shootWindow: String?
        var quietHours: String?
        var weeklyCap: Int?
        var pushOptIn: Bool?
        var timezone: String?
    }

    struct PushPrefsResponse: Decodable {
        var ok: Bool?
        var prefs: PushPrefs?
        var error: String?
    }

    /// GET /api/push/prefs — soft-fail if missing.
    func getPushPrefs() async throws -> PushPrefs {
        var req = URLRequest(url: try url("/api/push/prefs"))
        req.httpMethod = "GET"
        let (data, response) = try await perform(req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.http(-1, "No HTTP response")
        }
        if http.statusCode == 404 || http.statusCode == 503 {
            throw APIError.http(http.statusCode, "push prefs unavailable")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(http.statusCode, String(data: data, encoding: .utf8))
        }
        if let wrapped = try? decoder.decode(PushPrefsResponse.self, from: data), let prefs = wrapped.prefs {
            return prefs
        }
        return try decoder.decode(PushPrefs.self, from: data)
    }

    /// PUT /api/push/prefs — soft-fail if missing.
    @discardableResult
    func updatePushPrefs(_ prefs: PushPrefs) async throws -> PushPrefs {
        var req = URLRequest(url: try url("/api/push/prefs"))
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try encoder.encode(prefs)
        let (data, response) = try await perform(req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.http(-1, "No HTTP response")
        }
        if http.statusCode == 404 || http.statusCode == 503 {
            throw APIError.http(http.statusCode, "push prefs unavailable")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(http.statusCode, String(data: data, encoding: .utf8))
        }
        if let wrapped = try? decoder.decode(PushPrefsResponse.self, from: data), let prefs = wrapped.prefs {
            return prefs
        }
        return (try? decoder.decode(PushPrefs.self, from: data)) ?? prefs
    }

    struct PushEventRequest: Encodable {
        var event: String
        var properties: [String: String]?
        var timestamp: String?

        enum CodingKeys: String, CodingKey {
            case event, timestamp
            // Server sanitizeProps reads `props` (not `properties`).
            case properties = "props"
        }
    }

    /// POST /api/push/events — allowlisted names only. Soft-fail on 404/503.
    func postPushEvent(name: String, properties: [String: String] = [:]) async throws {
        var req = URLRequest(url: try url("/api/push/events"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var props = properties
        let ts = props.removeValue(forKey: "timestamp") ?? ISO8601DateFormatter().string(from: Date())
        let body = PushEventRequest(event: name, properties: props.isEmpty ? nil : props, timestamp: ts)
        req.httpBody = try encoder.encode(body)
        let (data, response) = try await perform(req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.http(-1, "No HTTP response")
        }
        if http.statusCode == 404 || http.statusCode == 503 {
            throw APIError.http(http.statusCode, "push events unavailable")
        }
        if !(200..<300).contains(http.statusCode) {
            throw APIError.http(http.statusCode, String(data: data, encoding: .utf8))
        }
    }

    struct TelemetryRequest: Encodable {
        var event: String
        var anon_id: String
        var session_id: String?
        var platform: String
        var app: String
        var props: [String: String]?
    }

    /// POST /api/telemetry — allowlisted funnel events. Soft-fail on transport.
    func postTelemetry(
        event: String,
        anonId: String,
        sessionId: String,
        props: [String: String] = [:]
    ) async throws {
        var req = URLRequest(url: try url("/api/telemetry"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = TelemetryRequest(
            event: event,
            anon_id: anonId,
            session_id: sessionId,
            platform: "ios",
            app: "photo-recipes",
            props: props.isEmpty ? nil : props
        )
        req.httpBody = try encoder.encode(body)
        let (data, response) = try await perform(req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.http(-1, "No HTTP response")
        }
        if http.statusCode == 404 || http.statusCode == 503 {
            throw APIError.http(http.statusCode, "telemetry unavailable")
        }
        if !(200..<300).contains(http.statusCode) {
            throw APIError.http(http.statusCode, String(data: data, encoding: .utf8))
        }
    }

    // MARK: - Helpers

    private func get<T: Decodable>(_ req: URLRequest) async throws -> T {
        let (data, response) = try await perform(req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.http(-1, "No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(http.statusCode, String(data: data, encoding: .utf8))
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }
    }

    /// Downscale / JPEG-compress for vision uploads (~1024px long edge, ~0.65).
    /// Server also shrinks in memory; smaller uploads keep Recommend one-shot fast.
    static func compressForVision(_ image: UIImage, maxDimension: CGFloat = 1024, quality: CGFloat = 0.65) -> Data? {
        let size = image.size
        let longest = max(size.width, size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: quality)
    }
}
