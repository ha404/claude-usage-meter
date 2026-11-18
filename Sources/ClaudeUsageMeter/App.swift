import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let service = UsageService()
    private let updater = Updater()
    private var controller: StatusItemController?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = StatusItemController(service: service, updater: updater)
        service.start()
        updater.start()
        registerLoginItemOnFirstLaunch()
    }

    /// Tries once per install to register at login; a failed attempt is retried next launch.
    private func registerLoginItemOnFirstLaunch() {
        let key = "didRegisterLoginItem"
        guard !UserDefaults.standard.bool(forKey: key), Bundle.main.bundleIdentifier != nil else { return }
        guard service.setLaunchAtLogin(true) else { return }
        UserDefaults.standard.set(true, forKey: key)
    }
}
