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
    private let isPreview: Bool

    private static let home = FileManager.default.homeDirectoryForCurrentUser
    private static let target = home.appendingPathComponent(".claude/usage-meter-statusline.sh")
    private static let settings = home.appendingPathComponent(".claude/settings.json")

    private static func bundled(_ name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "sh")
    }

    /// Whether this build carries the scripts (only the .app does, not `swift run`).
    var isAvailable: Bool { isPreview || Self.bundled("install-statusline") != nil }

    init() {
        isPreview = false
        refresh()
    }

    /// Fixed state without touching the disk; used to render the README screenshots.
    init(previewInstalled: Bool) {
        isPreview = true
        isInstalled = previewInstalled
    }

    /// Re-reads settings.json, and keeps an installed script in step with this app version.
    func refresh() {
        guard !isPreview else { return }
        // Match on the script name: older installs wrote the command without quotes.
        let command = Self.currentEntry()?["command"] as? String
        isInstalled = command?.contains(Self.target.lastPathComponent) == true
        if isInstalled { Self.syncScript() }
    }

    /// Installs the status line, or removes it again. Installing over an existing install
    /// is safe and brings its settings.json entry up to date.
    func setInstalled(_ installed: Bool) async {
        guard !isBusy, let script = Self.bundled("install-statusline") else { return }
        isBusy = true
        defer { isBusy = false }
        // GUI apps get a minimal PATH; the installer needs jq, which may come from Homebrew.
        let path = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        let arguments = ["PATH=\(path)", "/bin/bash", script.path] + (installed ? [] : ["--uninstall"])
        let result = try? await Shell.run("/usr/bin/env", arguments)
        error = result?.status == 0
            ? nil
            : "Couldn't \(installed ? "install" : "remove") the status line (is jq installed?)"
        refresh()
    }

    /// The `statusLine` entry of Claude Code's settings.json, if any.
    private static func currentEntry() -> [String: Any]? {
        guard let data = try? Data(contentsOf: settings),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["statusLine"] as? [String: Any]
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
