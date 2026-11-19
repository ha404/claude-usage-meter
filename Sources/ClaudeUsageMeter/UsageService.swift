import Foundation
import Observation
import ServiceManagement

enum UsageError: LocalizedError, Equatable {
    case noCredentials
    case tokenExpired
    case http(Int, retryAfter: TimeInterval?)

    var errorDescription: String? {
        switch self {
        case .noCredentials: "No Claude Code login found in Keychain"
        case .tokenExpired: "Claude Code token expired — run claude to refresh"
        case .http(429, _): "Usage endpoint is rate limiting — backing off"
        case .http(let code, _): "Usage request failed (HTTP \(code))"
        }
    }
}

@MainActor
@Observable
final class UsageService {
    private(set) var usage: Usage?
    private(set) var lastUpdated: Date?
    private(set) var error: String?
    private(set) var isLoading = false
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled

    var isStale: Bool { error != nil && usage != nil }

    nonisolated static let pollInterval: TimeInterval = 60
    nonisolated static let maxBackoff: TimeInterval = 900
    nonisolated static let maxRetryAfter: TimeInterval = 3600
    /// Opening the popover refreshes, but never more often than this.
    nonisolated static let manualRefreshInterval: TimeInterval = 10
    /// Switching apps refreshes too (so the numbers are current when you come back to
    /// the terminal), at most this often.
    nonisolated static let focusRefreshInterval: TimeInterval = 20

    private var failures = 0
    private var lastAttempt = Date.distantPast
    private var backoffUntil = Date.distantPast
    private var pollTask: Task<Void, Never>?

    init() {}

    /// Seeds state without fetching; used to render the README screenshots.
    init(preview usage: Usage) {
        self.usage = usage
        self.lastUpdated = Date()
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task {
            while !Task.isCancelled {
                // Timed from the last attempt of any kind, so a refresh triggered by the
                // user stands in for the next scheduled poll rather than adding to it.
                let due = max(backoffUntil, lastAttempt.addingTimeInterval(Self.pollInterval))
                let wait = due.timeIntervalSinceNow
                if wait > 0 {
                    try? await Task.sleep(for: .seconds(wait))
                    continue
                }
                await poll()
            }
        }
    }

    /// A refresh prompted by the user. Ignored while backing off, or when the last attempt
    /// was less than `interval` ago.
    func refresh(ifOlderThan interval: TimeInterval = manualRefreshInterval) async {
        let earliest = max(backoffUntil, lastAttempt.addingTimeInterval(interval))
        guard Date() >= earliest else { return }
        await poll()
    }

    /// Registers or unregisters the login item. Returns whether the change took effect;
    /// `launchAtLogin` always reflects what the system actually has.
    @discardableResult
    func setLaunchAtLogin(_ enabled: Bool) -> Bool {
        try? enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        launchAtLogin = SMAppService.mainApp.status == .enabled
        return launchAtLogin == enabled
    }

    private func poll() async {
        guard !isLoading else { return }
        isLoading = true
        lastAttempt = Date()
        defer { isLoading = false }
        do {
            let fresh = try await Self.fetch()
            usage = fresh
            lastUpdated = Date()
            error = nil
            failures = 0
            backoffUntil = .distantPast
            CacheWriter.write(fresh)
        } catch {
            failures += 1
            backoffUntil = Date().addingTimeInterval(Self.retryDelay(after: error, failures: failures))
            self.error = error.localizedDescription
        }
    }

    /// How long to wait before trying again. Credential problems are local and cheap to
    /// re-check, so they keep the normal cadence; anything that reached (or failed to
    /// reach) the server backs off exponentially, honouring `Retry-After` when given.
    nonisolated static func retryDelay(after error: Error, failures: Int) -> TimeInterval {
        switch error {
        case UsageError.noCredentials, UsageError.tokenExpired:
            return pollInterval
        case UsageError.http(_, let retryAfter?):
            return min(max(retryAfter, pollInterval), maxRetryAfter)
        default:
            return min(pollInterval * pow(2, Double(min(max(failures, 0), 10))), maxBackoff)
        }
    }

    // MARK: - Networking

    private nonisolated static func fetch() async throws -> Usage {
        let token = try await readAccessToken()
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("claude-code/2.1.311", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: req)
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        if status == 401 { throw UsageError.tokenExpired }
        guard status == 200 else {
            let retryAfter = http?.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw UsageError.http(status, retryAfter: retryAfter)
        }
        return try JSONDecoder().decode(Usage.self, from: data)
    }

    /// Reads Claude Code's OAuth token via the `security` CLI. We never refresh the token
    /// ourselves: refreshing rotates it and would sign Claude Code out.
    private nonisolated static func readAccessToken() async throws -> String {
        let result = try await Shell.run(
            "/usr/bin/security", ["find-generic-password", "-s", "Claude Code-credentials", "-w"])
        guard result.status == 0 else { throw UsageError.noCredentials }

        struct Creds: Decodable {
            struct OAuth: Decodable { let accessToken: String; let expiresAt: Double? }
            let claudeAiOauth: OAuth
        }
        guard let creds = try? JSONDecoder().decode(Creds.self, from: result.output) else {
            throw UsageError.noCredentials
        }
        if let exp = creds.claudeAiOauth.expiresAt, exp / 1000 < Date().timeIntervalSince1970 {
            throw UsageError.tokenExpired
        }
        return creds.claudeAiOauth.accessToken
    }
}
