import AppKit
import SwiftUI

/// A borderless panel that drops down just below a status item, the way the system's own
/// menu bar extras (Weather, Control Center) do. NSPopover re-anchors itself when its
/// SwiftUI content resizes and can end up drawn over the menu bar.
@MainActor
final class MenuPanel: NSPanel {
    private let host: SizingHostingView<AnyView>
    private weak var anchor: NSStatusBarButton?
    private var monitors: [Any] = []
    var onClose: (() -> Void)?

    private static let gap: CGFloat = 5
    private static let screenMargin: CGFloat = 8
    private static let cornerRadius: CGFloat = 14

    init<Content: View>(rootView: Content) {
        host = SizingHostingView(rootView: AnyView(rootView))
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        // A mask image (rather than a layer corner radius) also gives the window shadow
        // the rounded shape.
        effect.maskImage = Self.roundedMask(radius: Self.cornerRadius)
        host.autoresizingMask = [.width, .height]
        effect.addSubview(host)
        contentView = effect

        // Content can change size while open (an error row appears, say); keep the top
        // edge pinned under the menu bar.
        host.onResize = { [weak self] in
            DispatchQueue.main.async { self?.reposition() }
        }
    }

    override var canBecomeKey: Bool { true }

    func show(below button: NSStatusBarButton) {
        anchor = button
        reposition()
        orderFrontRegardless()
        makeKey()
        startMonitoring()
    }

    override func close() {
        guard isVisible else { return }
        orderOut(nil)
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        onClose?()
    }

    private func reposition() {
        guard let button = anchor, let barWindow = button.window, let screen = barWindow.screen else { return }
        let size = host.fittingSize
        let item = barWindow.convertToScreen(button.convert(button.bounds, to: nil))
        // Line up with the item's left edge, but stay on screen.
        let x = min(max(item.minX, screen.frame.minX + Self.screenMargin),
                    screen.frame.maxX - Self.screenMargin - size.width)
        let top = barWindow.frame.minY - Self.gap
        let frame = NSRect(x: x, y: top - size.height, width: size.width, height: size.height)
        if frame != self.frame { setFrame(frame, display: true) }
    }

    /// Closes on clicks outside the app (other windows, the rest of the menu bar) and on Esc.
    /// Clicks on our own status item don't reach the global monitor; its action toggles us.
    private func startMonitoring() {
        guard monitors.isEmpty else { return }
        if let global = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown],
            handler: { [weak self] _ in MainActor.assumeIsolated { self?.close() } }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53 else { return event }  // Esc
            self?.close()
            return nil
        }) {
            monitors.append(local)
        }
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// Reports when SwiftUI content changes its ideal size.
private final class SizingHostingView<Content: View>: NSHostingView<Content> {
    var onResize: (() -> Void)?

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        onResize?()
    }
}
