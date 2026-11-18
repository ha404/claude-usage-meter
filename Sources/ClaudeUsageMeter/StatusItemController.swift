import AppKit
import Observation
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let service: UsageService
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var redrawTimer: Timer?

    init(service: UsageService) {
        self.service = service
        super.init()

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PopoverView(service: service))

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
            usage.window(kind).map { "\(kind.label): \(Int($0.utilization.rounded()))%" }
        }.joined(separator: "  ·  ")
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            Task { await service.refresh() }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
