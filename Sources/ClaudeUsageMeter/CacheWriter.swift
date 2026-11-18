import Foundation

/// Writes the latest usage to ~/.claude/usage-meter-cache.json so the Claude Code
/// status line can fall back to it when Claude Code doesn't pass rate limits on stdin.
enum CacheWriter {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/usage-meter-cache.json")

    /// The cache's own schema (epoch seconds), kept separate from the API's `UsageWindow`.
    private struct Window: Encodable {
        let utilization: Double
        let resets_at: Int?

        init(_ window: UsageWindow) {
            utilization = window.utilization
            resets_at = window.resetsAt.map { Int($0.timeIntervalSince1970) }
        }
    }

    private struct Payload: Encodable {
        let timestamp: Int
        let five_hour: Window?
        let seven_day: Window?
    }

    static func write(_ usage: Usage) {
        let payload = Payload(
            timestamp: Int(Date().timeIntervalSince1970),
            five_hour: usage.fiveHour.map(Window.init),
            seven_day: usage.sevenDay.map(Window.init)
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
