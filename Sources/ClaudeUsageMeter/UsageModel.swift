import Foundation

/// One rate-limit window (5-hour session or 7-day weekly).
struct UsageWindow: Codable, Equatable {
    var utilization: Double
    var resetsAt: Date?

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
        utilization = try c.decodeIfPresent(Double.self, forKey: .utilization) ?? 0
        resetsAt = (try c.decodeIfPresent(String.self, forKey: .resetsAt)).flatMap(parseISO8601)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(utilization, forKey: .utilization)
        try c.encodeIfPresent(resetsAt.map { Int($0.timeIntervalSince1970) }, forKey: .resetsAt)
    }

    /// Fraction (0...1) of the window that has elapsed, given the window's total length.
    func elapsedFraction(windowLength: TimeInterval, now: Date = Date()) -> Double? {
        guard let resetsAt else { return nil }
        let remaining = resetsAt.timeIntervalSince(now)
        return min(max(1 - remaining / windowLength, 0), 1)
    }
}

struct Usage: Decodable, Equatable {
    var fiveHour: UsageWindow?
    var sevenDay: UsageWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
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
