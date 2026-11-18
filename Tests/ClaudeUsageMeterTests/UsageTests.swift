import Foundation
import Testing
@testable import ClaudeUsageMeter

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let fiveHours: TimeInterval = 5 * 3600

/// A 5-hour window at `used` percent with `elapsed` (0...1) of it gone; `nil` means no reset time.
private func window(_ used: Double, elapsed: Double?) -> UsageWindow {
    UsageWindow(utilization: used, resetsAt: elapsed.map { now.addingTimeInterval(fiveHours * (1 - $0)) })
}

/// (percent used, fraction elapsed, expected severity) — shared with the status line parity test.
let paceCases: [(used: Double, elapsed: Double?, expected: Severity)] = [
    (1, 0.01, .normal),      // a fresh window is ahead of a marker at zero: not a warning
    (9.4, 0.02, .normal),    // still under the floor
    (12, 0.02, .warning),    // over the floor and ahead of pace
    (20, 0.45, .normal),     // behind pace
    (48, 0.30, .warning),
    (48.9, 0.482, .warning), // fractions count: 48.9% used vs 48.2% elapsed
    (84, 0.50, .warning),
    (90, 0.70, .critical),
    (90, 0.95, .normal),     // high, but on pace
    (100, 0.80, .exhausted),
    (30, nil, .normal),      // no reset time: absolute levels
    (60, nil, .warning),
    (85, nil, .critical),
]

@Test(arguments: paceCases.indices)
func severityFollowsPace(_ index: Int) {
    let c = paceCases[index]
    #expect(window(c.used, elapsed: c.elapsed).severity(windowLength: fiveHours, now: now) == c.expected)
}

@Test func elapsedFractionIsClamped() {
    #expect(window(0, elapsed: 0.25).elapsedFraction(windowLength: fiveHours, now: now) == 0.25)
    #expect(window(0, elapsed: 1.5).elapsedFraction(windowLength: fiveHours, now: now) == 1)
    #expect(window(0, elapsed: -0.5).elapsedFraction(windowLength: fiveHours, now: now) == 0)
    #expect(window(0, elapsed: nil).elapsedFraction(windowLength: fiveHours, now: now) == nil)
}

@Test func parsesTimestampsWithMicroseconds() {
    #expect(parseISO8601("2026-11-18T14:40:00.757896+00:00") == parseISO8601("2026-11-18T14:40:00Z"))
    #expect(parseISO8601("2026-11-18T14:40:00Z")?.timeIntervalSince1970 == 1_795_012_800)
    #expect(parseISO8601("not a date") == nil)
}

@Test func decodesUsageResponse() throws {
    let json = #"{"five_hour":{"utilization":48.5,"resets_at":"2026-11-18T14:40:00.1+00:00"},"seven_day":null}"#
    let usage = try JSONDecoder().decode(Usage.self, from: Data(json.utf8))
    #expect(usage.fiveHour?.utilization == 48.5)
    #expect(usage.fiveHour?.percent == 49)
    #expect(usage.fiveHour?.resetsAt != nil)
    #expect(usage.sevenDay == nil)
}

@Test func missingUtilizationIsAnErrorNotZero() {
    let json = #"{"five_hour":{"resets_at":"2026-11-18T14:40:00Z"}}"#
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(Usage.self, from: Data(json.utf8)) }
}

@Test func retryDelayBacksOff() {
    let network = URLError(.timedOut)
    #expect(UsageService.retryDelay(after: network, failures: 1) == 120)
    #expect(UsageService.retryDelay(after: network, failures: 2) == 240)
    #expect(UsageService.retryDelay(after: network, failures: 50) == UsageService.maxBackoff)
    #expect(UsageService.retryDelay(after: UsageError.http(500, retryAfter: nil), failures: 1) == 120)
    #expect(UsageService.retryDelay(after: UsageError.http(429, retryAfter: 300), failures: 1) == 300)
    #expect(UsageService.retryDelay(after: UsageError.http(429, retryAfter: 1), failures: 1) == UsageService.pollInterval)
    #expect(UsageService.retryDelay(after: UsageError.http(429, retryAfter: 1e9), failures: 1) == UsageService.maxRetryAfter)
    #expect(UsageService.retryDelay(after: UsageError.tokenExpired, failures: 9) == UsageService.pollInterval)
}
