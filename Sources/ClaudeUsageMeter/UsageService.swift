import Foundation
import Observation
import ServiceManagement

enum UsageError: LocalizedError {
    case noCredentials
    case tokenExpired
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .noCredentials: "No Claude Code login found in Keychain"
        case .tokenExpired: "Claude Code token expired — run claude to refresh"
        case .http(let code): "Usage request failed (HTTP \(code))"
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

    var launchAtLogin = SMAppService.mainApp.status == .enabled {
        didSet {
            guard launchAtLogin != oldValue else { return }
            try? launchAtLogin ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        }
    }

    var isStale: Bool { error != nil && usage != nil }

    private var timer: Timer?
    static let pollInterval: TimeInterval = 60

    func start() {
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let fresh = try await Self.fetch()
            usage = fresh
            lastUpdated = Date()
            error = nil
            CacheWriter.write(fresh)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Networking

    private nonisolated static func fetch() async throws -> Usage {
        let token = try readAccessToken()
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("claude-code/2.1.311", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw UsageError.tokenExpired }
        guard status == 200 else { throw UsageError.http(status) }
        return try JSONDecoder().decode(Usage.self, from: data)
    }

    /// Reads Claude Code's OAuth token via the `security` CLI. We never refresh the token
    /// ourselves: refreshing rotates it and would sign Claude Code out.
    private nonisolated static func readAccessToken() throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw UsageError.noCredentials }

        struct Creds: Decodable {
            struct OAuth: Decodable { let accessToken: String; let expiresAt: Double? }
            let claudeAiOauth: OAuth
        }
        guard let creds = try? JSONDecoder().decode(Creds.self, from: data) else {
            throw UsageError.noCredentials
        }
        if let exp = creds.claudeAiOauth.expiresAt, exp / 1000 < Date().timeIntervalSince1970 {
            throw UsageError.tokenExpired
        }
        return creds.claudeAiOauth.accessToken
    }
}
