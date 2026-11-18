import AppKit
import CryptoKit
import Observation

/// A dotted numeric version such as `1.0.12`; a leading `v` (as in release tags) is ignored.
struct AppVersion: Comparable, CustomStringConvertible {
    let parts: [Int]

    init?(_ string: String) {
        let digits = string.hasPrefix("v") ? String(string.dropFirst()) : string
        let parsed = digits.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        let parts = parsed.compactMap { $0 }
        guard !parts.isEmpty, parts.count == parsed.count, parts.allSatisfy({ $0 >= 0 }) else { return nil }
        self.parts = parts
    }

    var description: String { parts.map(String.init).joined(separator: ".") }

    /// Trailing zeros don't count: 1.0 and 1.0.0 are the same version.
    private var significant: [Int] {
        Array(parts[..<(parts.lastIndex { $0 != 0 }.map { $0 + 1 } ?? 0)])
    }

    static func == (a: AppVersion, b: AppVersion) -> Bool { a.significant == b.significant }
    static func < (a: AppVersion, b: AppVersion) -> Bool {
        a.significant.lexicographicallyPrecedes(b.significant)
    }
}

/// The parts of a GitHub release the updater needs.
struct Release: Decodable {
    struct Asset: Decodable {
        let name: String
        /// API URL of the asset; works for private repos, unlike `browser_download_url`.
        let url: URL
        /// `sha256:<hex>`, as reported by GitHub.
        let digest: String?
    }

    let tagName: String
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }

    var version: AppVersion? { AppVersion(tagName) }
    var archive: Asset? { assets.first { $0.name == Updater.archiveName } }
}

enum UpdateError: LocalizedError, Equatable {
    case http(Int)
    case notAccessible
    case noArchive
    case checksumMismatch
    case invalidBundle(String)

    var errorDescription: String? {
        switch self {
        case .http(let code): "Update check failed (HTTP \(code))"
        case .notAccessible: "Can't read releases — sign in with gh auth login"
        case .noArchive: "Release has no \(Updater.archiveName)"
        case .checksumMismatch: "Update download failed its checksum"
        case .invalidBundle(let why): "Update rejected: \(why)"
        }
    }
}

/// Checks GitHub for a newer release and swaps it in for the running app.
@MainActor
@Observable
final class Updater {
    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(AppVersion)
        case installing(AppVersion)
        case failed(String)
    }

    nonisolated static let repository = "ha404/claude-usage-meter"
    nonisolated static let appName = "ClaudeUsageMeter.app"
    nonisolated static let archiveName = "ClaudeUsageMeter.zip"
    nonisolated static let checkInterval: TimeInterval = 6 * 3600
    private nonisolated static let automaticKey = "automaticUpdates"

    /// `nil` when not running from an app bundle (`swift run`), which disables updating.
    let currentVersion: AppVersion?
    private(set) var status: Status = .idle
    private(set) var automatic: Bool
    private var loop: Task<Void, Never>?

    init(currentVersion: AppVersion? = Updater.bundleVersion) {
        self.currentVersion = currentVersion
        automatic = UserDefaults.standard.object(forKey: Self.automaticKey) as? Bool ?? true
    }

    nonisolated static var bundleVersion: AppVersion? {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        return (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init)
    }

    var isBusy: Bool {
        switch status {
        case .checking, .installing: true
        default: false
        }
    }

    var statusText: String {
        guard let currentVersion else { return "Development build · updates off" }
        switch status {
        case .idle: return "v\(currentVersion)"
        case .checking: return "Checking for updates…"
        case .upToDate: return "v\(currentVersion) · up to date"
        case .available(let version): return "v\(version) available"
        case .installing(let version): return "Installing v\(version)…"
        case .failed(let message): return message
        }
    }

    /// Checks at launch and every `checkInterval` after, while automatic updates are on.
    func start() {
        guard currentVersion != nil, loop == nil else { return }
        loop = Task {
            while !Task.isCancelled {
                if automatic { await check(install: true) }
                try? await Task.sleep(for: .seconds(Self.checkInterval))
            }
        }
    }

    func setAutomatic(_ enabled: Bool) {
        automatic = enabled
        UserDefaults.standard.set(enabled, forKey: Self.automaticKey)
        guard enabled else { return }
        Task { await check(install: true) }
    }

    /// Looks for a newer release; installs it and relaunches when `install` is set,
    /// otherwise just reports it as available.
    func check(install: Bool) async {
        guard let currentVersion, !isBusy else { return }
        status = .checking
        do {
            let release = try await Self.latestRelease()
            guard let version = release.version, version > currentVersion else {
                status = .upToDate
                return
            }
            guard install else {
                status = .available(version)
                return
            }
            status = .installing(version)
            try await Self.install(release, version: version, over: Bundle.main.bundleURL)
            relaunch()
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            Task { @MainActor in
                guard let error else { return NSApp.terminate(nil) }
                self.status = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - GitHub

    private nonisolated static func latestRelease() async throws -> Release {
        let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
        return try JSONDecoder().decode(Release.self, from: try await get(url, accept: "application/vnd.github+json"))
    }

    /// GETs a GitHub API URL anonymously, which is all a public repo needs. A private repo
    /// answers as if it didn't exist, so those responses are retried with the `gh` CLI's token.
    private nonisolated static func get(_ url: URL, accept: String) async throws -> Data {
        do {
            return try await request(url, accept: accept, token: nil)
        } catch UpdateError.http(let code) where [401, 403, 404].contains(code) {
            guard let token = await ghToken() else { throw UpdateError.notAccessible }
            return try await request(url, accept: accept, token: token)
        }
    }

    private nonisolated static func request(_ url: URL, accept: String, token: String?) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue(accept, forHTTPHeaderField: "Accept")
        req.setValue("ClaudeUsageMeter", forHTTPHeaderField: "User-Agent")
        req.setValue(token.map { "Bearer \($0)" }, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: req, delegate: CrossHostRedirects())
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw UpdateError.http(status) }
        return data
    }

    private nonisolated static func ghToken() async -> String? {
        let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]
        guard let gh = candidates.first(where: FileManager.default.isExecutableFile(atPath:)),
              let result = try? await Shell.run(gh, ["auth", "token"]),
              result.status == 0, !result.text.isEmpty
        else { return nil }
        return result.text
    }

    // MARK: - Install

    /// Downloads the release archive, checks it is the app and version it claims to be,
    /// and replaces `bundle` with it.
    private nonisolated static func install(_ release: Release, version: AppVersion, over bundle: URL) async throws {
        guard let asset = release.archive else { throw UpdateError.noArchive }
        let archive = try await get(asset.url, accept: "application/octet-stream")
        if let digest = asset.digest, digest != sha256(archive) { throw UpdateError.checksumMismatch }

        let files = FileManager.default
        // On the app's own volume, so the final swap is a rename rather than a copy.
        let work = try files.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: bundle, create: true)
        defer { try? files.removeItem(at: work) }

        let zip = work.appendingPathComponent(archiveName)
        try archive.write(to: zip)
        try await runTool("/usr/bin/ditto", ["-x", "-k", zip.path, work.path], failure: "couldn't unpack the archive")

        let fresh = work.appendingPathComponent(appName)
        try validate(fresh, is: version)
        try await runTool("/usr/bin/codesign", ["--verify", "--deep", "--strict", fresh.path], failure: "code signature is broken")
        _ = try files.replaceItemAt(bundle, withItemAt: fresh)
    }

    nonisolated static func sha256(_ data: Data) -> String {
        "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func validate(_ app: URL, is version: AppVersion) throws {
        guard let candidate = Bundle(url: app) else { throw UpdateError.invalidBundle("archive has no \(appName)") }
        guard candidate.bundleIdentifier == Bundle.main.bundleIdentifier else {
            throw UpdateError.invalidBundle("it is a different app")
        }
        let found = (candidate.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init)
        guard found == version else { throw UpdateError.invalidBundle("its version doesn't match the release") }
    }

    private nonisolated static func runTool(_ executable: String, _ arguments: [String], failure: String) async throws {
        let result = try await Shell.run(executable, arguments)
        guard result.status == 0 else { throw UpdateError.invalidBundle(failure) }
    }
}

/// GitHub redirects asset downloads to pre-signed storage URLs, which reject requests that
/// also carry our API token — so drop it whenever a redirect leaves the original host.
private final class CrossHostRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest
    ) async -> URLRequest? {
        guard request.url?.host != task.originalRequest?.url?.host else { return request }
        var stripped = request
        stripped.setValue(nil, forHTTPHeaderField: "Authorization")
        return stripped
    }
}
