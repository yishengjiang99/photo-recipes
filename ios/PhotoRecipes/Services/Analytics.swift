import Foundation
import UIKit

/// In-house funnel telemetry → POST /api/telemetry.
/// Soft no-op on network errors. Never send photos, base64, email, or GPS.
@MainActor
final class Analytics {
    static let shared = Analytics()

    private let anonKey = "telemetry.anonId"
    private let sessionKey = "telemetry.sessionId"
    private let sessionTsKey = "telemetry.sessionTs"
    private let sessionTTL: TimeInterval = 30 * 60

    private let api: APIClient
    private var didBoot = false

    init(api: APIClient = .shared) {
        self.api = api
    }

    var anonId: String {
        let existing = UserDefaults.standard.string(forKey: anonKey)
        if let existing, existing.count >= 8 { return existing }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: anonKey)
        return id
    }

    var sessionId: String {
        let now = Date().timeIntervalSince1970
        let prev = UserDefaults.standard.double(forKey: sessionTsKey)
        var sid = UserDefaults.standard.string(forKey: sessionKey)
        if sid == nil || prev == 0 || now - prev > sessionTTL {
            sid = UUID().uuidString
            UserDefaults.standard.set(sid, forKey: sessionKey)
        }
        UserDefaults.standard.set(now, forKey: sessionTsKey)
        return sid ?? UUID().uuidString
    }

    func bootstrap() {
        guard !didBoot else { return }
        didBoot = true
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        track("session_start")
        track("app_open", props: [
            "platform": "ios",
            "app_version": version ?? "unknown",
        ])
    }

    func track(_ event: String, props: [String: String] = [:]) {
        var cleaned: [String: String] = [:]
        for (k, v) in props {
            if k.range(of: "email|phone|image|photo|base64|gps|lat|lng|token|password", options: .regularExpression) != nil {
                continue
            }
            if v.hasPrefix("data:image") || v.count > 200 { continue }
            cleaned[k] = String(v.prefix(200))
        }
        Task {
            do {
                try await api.postTelemetry(
                    event: event,
                    anonId: anonId,
                    sessionId: sessionId,
                    props: cleaned
                )
            } catch {
                #if DEBUG
                print("[Analytics] soft fail \(event): \(error.localizedDescription)")
                #endif
            }
        }
    }
}
