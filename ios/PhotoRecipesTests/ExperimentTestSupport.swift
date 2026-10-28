import Foundation
@testable import PhotoRecipes

/// Shared fakes for the activation / paywall / timing test suites.
final class FakeAnalyticsSink: AnalyticsEventSink {
    private(set) var events: [(name: String, props: [String: String])] = []

    func track(_ event: String, props: [String: String]) {
        events.append((event, props))
    }

    func count(_ name: String) -> Int { events.filter { $0.name == name }.count }

    func last(_ name: String) -> [String: String]? {
        events.last { $0.name == name }?.props
    }

    func index(of name: String) -> Int? { events.firstIndex { $0.name == name } }

    /// Every prop key ever emitted — used by the Analytics key-filter contract
    /// test (keys containing photo/email/token/… are silently dropped by
    /// `Analytics.track`, so a violation here means lost telemetry in prod).
    var allPropKeys: [String] { events.flatMap { Array($0.props.keys) } }
}

final class FakeMonotonicClock: MonotonicClock {
    private(set) var nowNs: UInt64 = 0
    func nowNanoseconds() -> UInt64 { nowNs }
    func advance(milliseconds: UInt64) { nowNs += milliseconds * 1_000_000 }
}

/// Finds a deterministic install id that hashes into the wanted arm for an
/// experiment, so gate tests don't depend on a particular hash output.
func installId(wanting arm: ExperimentArm, for experiment: Experiment) -> String {
    for i in 0..<10_000 {
        let candidate = "test-install-\(i)"
        if ExperimentAssignment.arm(installId: candidate, salt: experiment.salt) == arm {
            return candidate
        }
    }
    fatalError("no install id found for arm \(arm)")
}
