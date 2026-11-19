import AppKit
import Observation
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let service: UsageService
    private let statusLine: StatusLineInstaller
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel: MenuPanel
    private var redrawTimer: Timer?

    init(service: UsageService, updater: Updater, statusLine: StatusLineInstaller) {
        self.service = service
        self.statusLine = statusLine
        panel = MenuPanel(rootView: PopoverView(service: service, updater: updater, statusLine: statusLine))
        super.init()

        panel.onClose = { [weak self] in self?.statusItem.button?.highlight(false) }

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
        }

        redraw()
        observe()
        // Keep the elapsed-time marker moving between polls.
        redrawTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.redraw() }
        }
    }

    private func observe() {
        withObservationTracking {
            _ = service.usage
            _ = service.error
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.redraw()
                self?.observe()
            }
        }
    }

    private func redraw() {
        guard let button = statusItem.button else { return }
        button.image = BarRenderer.image(usage: service.usage, stale: service.isStale || service.usage == nil)
        button.toolTip = tooltip()
    }

    private func tooltip() -> String {
        guard let usage = service.usage else { return service.error ?? "Loading Claude usage…" }
        return WindowKind.allCases.compactMap { kind in
            usage.window(kind).map { "\(kind.label): \($0.percent)%" }
        }.joined(separator: "  ·  ")
    }

    /// Opens the panel without a click (`--show-panel` at launch, for testing/screenshots).
    func showPanel() {
        if !panel.isVisible { togglePopover() }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        guard !panel.isVisible else { return panel.close() }
        Task { await service.refresh() }
        statusLine.refresh()
        panel.show(below: button)
        // Keep the item highlighted while open, like a system menu.
        DispatchQueue.main.async { button.highlight(true) }
    }
}
