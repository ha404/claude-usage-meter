import Foundation

/// One rate-limit window (5-hour session or 7-day weekly).
struct UsageWindow: Decodable, Equatable {
    /// Below this utilization a window is never flagged for pace: a brand-new window is
    /// always "ahead" of a marker that starts at zero, and that isn't worth a warning.
    static let paceFloor: Double = 10
    /// Past the marker *and* at or above this utilization is critical.
    static let criticalLevel: Double = 85

    let utilization: Double
    let resetsAt: Date?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    init(utilization: Double, resetsAt: Date?) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Required: a response without it is a schema change, not "0% used".
        utilization = try c.decode(Double.self, forKey: .utilization)
        resetsAt = (try c.decodeIfPresent(String.self, forKey: .resetsAt)).flatMap(parseISO8601)
    }

    /// Utilization as the whole percentage shown to the user.
    var percent: Int { Int(utilization.rounded()) }

    /// How worried to be. The elapsed-time marker is only "even pace", not a limit, so
    /// passing it is an early heads-up (orange) once usage is past `paceFloor`. Red is
    /// reserved for being past the marker *and* near the real limit. Falls back to
    /// absolute levels when there's no reset time.
    func severity(windowLength: TimeInterval, now: Date = Date()) -> Severity {
        if utilization >= 100 { return .exhausted }

        guard let elapsed = elapsedFraction(windowLength: windowLength, now: now) else {
            if utilization >= 80 { return .critical }
            return utilization >= 50 ? .warning : .normal
        }
        guard utilization > elapsed * 100, utilization >= Self.paceFloor else { return .normal }
        return utilization >= Self.criticalLevel ? .critical : .warning
    }

    /// Fraction (0...1) of the window that has elapsed, given the window's total length.
    func elapsedFraction(windowLength: TimeInterval, now: Date = Date()) -> Double? {
        guard let resetsAt else { return nil }
        let remaining = resetsAt.timeIntervalSince(now)
        return min(max(1 - remaining / windowLength, 0), 1)
    }
}

struct Usage: Decodable, Equatable {
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

enum Severity: Int, Comparable {
    case normal, warning, critical, exhausted

    static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
}

enum WindowKind: CaseIterable {
    case fiveHour, sevenDay

    var label: String { self == .fiveHour ? "5h" : "7d" }
    var title: String { self == .fiveHour ? "5-hour window" : "Weekly window" }
    var length: TimeInterval { self == .fiveHour ? 5 * 3600 : 7 * 86400 }
}

extension Usage {
    func window(_ kind: WindowKind) -> UsageWindow? {
        kind == .fiveHour ? fiveHour : sevenDay
    }
}

/// Parses timestamps like `2026-11-18T14:40:00.757896+00:00` (microsecond precision,
/// which ISO8601DateFormatter does not reliably accept) by dropping the fractional part.
func parseISO8601(_ s: String) -> Date? {
    let trimmed = s.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: trimmed)
}
