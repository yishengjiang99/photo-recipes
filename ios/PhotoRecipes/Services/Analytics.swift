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

    static let baseProps: [String: String] = {
        let info = Bundle.main.infoDictionary
        return [
            "app_version": info?["CFBundleShortVersionString"] as? String ?? "unknown",
            "build": info?["CFBundleVersion"] as? String ?? "unknown",
        ]
    }()

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
        if event == "auto_optimize_success" {
            Attribution.shared.noteAutoOptimizeSuccess()
        }
        var cleaned: [String: String] = [:]
        // Event contract: every event carries app_version + build (+ install age) so
        // journeys reconstruct by version. Explicit props win.
        var merged = Self.baseProps
        let quota = FreeOptimizeQuota()
        merged["hours_since_install"] = "\(quota.hoursSinceInstall)"
        merged["is_new_user"] = quota.inWelcomeWindow ? "1" : "0"
        for (k, v) in props { merged[k] = v }
        for (k, v) in merged {
            // Coordinates are matched as whole keys only — the old substring "lat" also
            // dropped latency_ms and platform.
            if k.range(of: "email|phone|image|photo|base64|gps|token|password", options: .regularExpression) != nil
                || k.range(of: "^(lat|lng|lon|latitude|longitude)$", options: .regularExpression) != nil {
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
