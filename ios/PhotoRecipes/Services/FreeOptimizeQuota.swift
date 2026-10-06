import Foundation

/// Free Auto Optimize allowance — counts **successful** optimizes only. Taps, timeouts,
/// cancels, retries and failures never consume a use or trigger the hard gate.
///
/// Funnel proposal (2026-10-06): a new install gets a welcome window of up to
/// `welcomeLimit` successful optimizes in its first 24 hours, then the standard
/// daily pool (server `freeDailyLimit`, default 5).
///
/// Local Auto Optimize never calls the server, so this pool is tracked on device and is
/// independent of the server Ask/Recommend quota (`asksRemaining`).
struct FreeOptimizeQuota {
    static let welcomeLimit = 10
    static let welcomeWindow: TimeInterval = 24 * 3600
    static let defaultDailyLimit = 5

    static let installDateKey = "app.installDate"
    static let welcomeUsesKey = "autoOptimize.welcomeUses"
    /// Same keys as the pre-1.2 daily counter so in-flight installs keep their count.
    static let dailyUsesKey = "autoOptimize.freeUses.day"
    static let dailyDateKey = "autoOptimize.freeUses.date"
    static let totalSuccessKey = "autoOptimize.successTotal"

    let defaults: UserDefaults
    let now: () -> Date
    let calendar: Calendar

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.defaults = defaults
        self.now = now
        self.calendar = calendar
    }

    /// Call once at launch, before anything else writes UserDefaults. Installs that predate
    /// this build (already onboarded / telemetry id present) are back-dated so only new
    /// installs get the welcome window.
    @discardableResult
    func ensureInstallDate(existingUser: Bool) -> Date {
        if let d = defaults.object(forKey: Self.installDateKey) as? Date { return d }
        let d = existingUser ? now().addingTimeInterval(-2 * Self.welcomeWindow) : now()
        defaults.set(d, forKey: Self.installDateKey)
        return d
    }

    var installDate: Date {
        (defaults.object(forKey: Self.installDateKey) as? Date) ?? now()
    }

    var inWelcomeWindow: Bool {
        now().timeIntervalSince(installDate) < Self.welcomeWindow
    }

    /// Hours since install (telemetry `hours_since_install`).
    var hoursSinceInstall: Int {
        max(0, Int(now().timeIntervalSince(installDate) / 3600))
    }

    /// 0 on install day, 1 the next calendar day, …
    var dayIndex: Int {
        let a = calendar.startOfDay(for: installDate)
        let b = calendar.startOfDay(for: now())
        return max(0, calendar.dateComponents([.day], from: a, to: b).day ?? 0)
    }

    func limit(serverDailyLimit: Int?) -> Int {
        let daily = serverDailyLimit ?? Self.defaultDailyLimit
        return inWelcomeWindow ? max(Self.welcomeLimit, daily) : daily
    }

    private var todayStamp: String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: now())
    }

    var dailyUsesToday: Int {
        defaults.string(forKey: Self.dailyDateKey) == todayStamp
            ? defaults.integer(forKey: Self.dailyUsesKey)
            : 0
    }

    var usedInCurrentWindow: Int {
        inWelcomeWindow ? defaults.integer(forKey: Self.welcomeUsesKey) : dailyUsesToday
    }

    func remaining(serverDailyLimit: Int?) -> Int {
        max(0, limit(serverDailyLimit: serverDailyLimit) - usedInCurrentWindow)
    }

    var successfulUsesTotal: Int {
        defaults.integer(forKey: Self.totalSuccessKey)
    }

    /// Record one successful optimize. `countsAgainstFree` is false for Pro / unlimited.
    func recordSuccess(countsAgainstFree: Bool = true) {
        defaults.set(successfulUsesTotal + 1, forKey: Self.totalSuccessKey)
        guard countsAgainstFree else { return }
        if inWelcomeWindow {
            defaults.set(defaults.integer(forKey: Self.welcomeUsesKey) + 1, forKey: Self.welcomeUsesKey)
        }
        let stamp = todayStamp
        let today = defaults.string(forKey: Self.dailyDateKey) == stamp
            ? defaults.integer(forKey: Self.dailyUsesKey)
            : 0
        defaults.set(stamp, forKey: Self.dailyDateKey)
        defaults.set(today + 1, forKey: Self.dailyUsesKey)
    }
}
