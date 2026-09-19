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

@MainActor
final class APIClient: ObservableObject {
    static let shared = APIClient()

    @Published var baseURLString: String {
        didSet {
            UserDefaults.standard.set(baseURLString, forKey: Self.baseURLKey)
        }
    }

    private static let baseURLKey = "api.baseURL"
    /// Placeholder production host — replace in Settings or Debug.xcconfig.
    private static let defaultBaseURL = "https://photo-recipes.example.com"

    private let session: URLSession
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()
    private let encoder = JSONEncoder()

    init(session: URLSession? = nil) {
        let stored = UserDefaults.standard.string(forKey: Self.baseURLKey)
        self.baseURLString = (stored?.isEmpty == false) ? stored! : Self.defaultBaseURL

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
    }

    struct PushRegisterResponse: Decodable {
        var ok: Bool?
        var guestId: String?
        var error: String?
    }

    /// Register APNs device token. Soft-fails on 404/503 (server may not ship yet).
    func registerPushToken(token: String, environment: String, appVersion: String) async throws {
        var req = URLRequest(url: try url("/api/push/register"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = PushRegisterRequest(
            token: token,
            platform: "ios",
            bundleId: "com.ragnus.mvp",
            environment: environment,
            appVersion: appVersion
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

    /// Downscale / JPEG-compress for vision uploads (~1280px long edge).
    static func compressForVision(_ image: UIImage, maxDimension: CGFloat = 1280, quality: CGFloat = 0.72) -> Data? {
        let size = image.size
        let longest = max(size.width, size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: quality)
    }
}
