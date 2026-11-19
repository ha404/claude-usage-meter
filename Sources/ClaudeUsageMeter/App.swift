import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let service = UsageService()
    private let updater = Updater()
    private let statusLine = StatusLineInstaller()
    private var controller: StatusItemController?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = StatusItemController(service: service, updater: updater, statusLine: statusLine)
        service.start()
        updater.start()
        registerLoginItemOnFirstLaunch()
        if CommandLine.arguments.contains("--show-panel") {
            // Give the status item a moment to be placed in the menu bar.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.controller?.showPanel() }
        }
    }

    /// Tries once per install to register at login; a failed attempt is retried next launch.
    private func registerLoginItemOnFirstLaunch() {
        let key = "didRegisterLoginItem"
        guard !UserDefaults.standard.bool(forKey: key), Bundle.main.bundleIdentifier != nil else { return }
        guard service.setLaunchAtLogin(true) else { return }
        UserDefaults.standard.set(true, forKey: key)
    }
}
