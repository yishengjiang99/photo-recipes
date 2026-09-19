import Foundation

/// Lightweight analytics for Experiment 1 push (pre-alarm shoot brief).
/// Posts allowlisted events to `POST /api/push/events` when available; always mirrors locally.
@MainActor
final class PushAnalytics {
    static let shared = PushAnalytics()

    /// Allowlisted by server contract — do not invent names.
    enum Event: String {
        case pushPermissionPromptShown = "push_permission_prompt_shown"
        case pushPermissionAccepted = "push_permission_accepted"
        case pushPermissionDenied = "push_permission_denied"
        case pushOpened = "push_opened"
        case autoOptimizeStarted = "auto_optimize_started"
    }

    private let logKey = "push.analytics.events"
    private let lastPushOpenedKey = "push.analytics.lastPushOpenedAt"
    private let maxLocalEvents = 100

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    /// Timestamp of last `push_opened` for 2h attribution of Auto Optimize starts.
    var lastPushOpenedAt: Date? {
        let t = UserDefaults.standard.double(forKey: lastPushOpenedKey)
        guard t > 0 else { return nil }
        return Date(timeIntervalSince1970: t)
    }

    var isWithinPushAttributionWindow: Bool {
        guard let opened = lastPushOpenedAt else { return false }
        return Date().timeIntervalSince(opened) <= 2 * 60 * 60
    }

    func track(_ event: Event, properties: [String: String] = [:]) {
        var props = properties
        let now = Date()
        let iso = ISO8601DateFormatter().string(from: now)
        props["timestamp"] = iso

        if event == .pushOpened {
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: lastPushOpenedKey)
        }
        if event == .autoOptimizeStarted, isWithinPushAttributionWindow {
            props["attributedToPush"] = "true"
            if let opened = lastPushOpenedAt {
                props["pushOpenedAt"] = ISO8601DateFormatter().string(from: opened)
            }
        }

        appendLocal(event: event.rawValue, properties: props)
        Task { await postSoft(event: event.rawValue, properties: props) }
    }

    /// Local ring buffer for debugging / offline.
    func recentLocalEvents() -> [[String: Any]] {
        UserDefaults.standard.array(forKey: logKey) as? [[String: Any]] ?? []
    }

    private func appendLocal(event: String, properties: [String: String]) {
        var entries = recentLocalEvents()
        var row: [String: Any] = ["event": event]
        for (k, v) in properties { row[k] = v }
        entries.append(row)
        if entries.count > maxLocalEvents {
            entries = Array(entries.suffix(maxLocalEvents))
        }
        UserDefaults.standard.set(entries, forKey: logKey)
    }

    private func postSoft(event: String, properties: [String: String]) async {
        do {
            try await api.postPushEvent(name: event, properties: properties)
        } catch {
            // Fail soft — local log is enough when endpoint is missing.
            #if DEBUG
            print("[PushAnalytics] soft fail \(event): \(error.localizedDescription)")
            #endif
        }
    }
}
