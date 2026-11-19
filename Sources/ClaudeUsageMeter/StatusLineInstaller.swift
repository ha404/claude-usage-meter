import Foundation
import Observation

/// Installs the Claude Code status line from the copy of `scripts/` bundled in the app,
/// so installs that never see the repo (Homebrew, release zips) can still set it up.
@MainActor
@Observable
final class StatusLineInstaller {
    private(set) var isInstalled = false
    private(set) var isBusy = false
    private(set) var error: String?

    private static let home = FileManager.default.homeDirectoryForCurrentUser
    private static let target = home.appendingPathComponent(".claude/usage-meter-statusline.sh")
    private static let settings = home.appendingPathComponent(".claude/settings.json")

    private static func bundled(_ name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "sh")
    }

    /// Whether this build carries the scripts (only the .app does, not `swift run`).
    var isAvailable: Bool { Self.bundled("install-statusline") != nil }

    init() {
        refresh()
    }

    /// Re-reads settings.json, and keeps an installed script in step with this app version.
    func refresh() {
        // Match on the script name: older installs wrote the command without quotes.
        isInstalled = Self.currentCommand()?.contains(Self.target.lastPathComponent) == true
        if isInstalled { Self.syncScript() }
    }

    func install() async {
        guard let script = Self.bundled("install-statusline") else { return }
        isBusy = true
        defer { isBusy = false }
        // GUI apps get a minimal PATH; the installer needs jq, which may come from Homebrew.
        let path = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        let result = try? await Shell.run("/usr/bin/env", ["PATH=\(path)", "/bin/bash", script.path])
        error = result?.status == 0 ? nil : "Couldn't install the status line (is jq installed?)"
        refresh()
    }

    private static func currentCommand() -> String? {
        guard let data = try? Data(contentsOf: settings),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let statusLine = json["statusLine"] as? [String: Any] else { return nil }
        return statusLine["command"] as? String
    }

    /// Copies the bundled status line script over the installed one when they differ, so
    /// fixes that ship with an app update reach the terminal too.
    private static func syncScript() {
        guard let source = bundled("statusline"),
              let fresh = try? Data(contentsOf: source),
              (try? Data(contentsOf: target)) != fresh else { return }
        try? fresh.write(to: target, options: .atomic)
    }
}
