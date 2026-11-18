import Foundation

/// Writes the latest usage to ~/.claude/usage-meter-cache.json so the Claude Code
/// status line can fall back to it when Claude Code doesn't pass rate limits on stdin.
enum CacheWriter {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/usage-meter-cache.json")

    private struct Payload: Encodable {
        let timestamp: Int
        let five_hour: UsageWindow?
        let seven_day: UsageWindow?
    }

    static func write(_ usage: Usage) {
        let payload = Payload(
            timestamp: Int(Date().timeIntervalSince1970),
            five_hour: usage.fiveHour,
            seven_day: usage.sevenDay
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
