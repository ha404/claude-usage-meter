import AppKit

/// Draws the menu bar image: two stacked rows ("5h" and "7d"), each a bar filled to
/// utilization with a vertical tick marking how far through the window we are.
enum BarRenderer {
    static let height: CGFloat = 18
    private static let labelWidth: CGFloat = 13
    private static let barWidth: CGFloat = 38
    private static let rowHeight: CGFloat = 6
    private static let rowGap: CGFloat = 3

    static func color(for severity: Severity) -> NSColor {
        switch severity {
        case .normal: .systemGreen
        case .warning: .systemOrange
        case .critical, .exhausted: .systemRed
        }
    }

    static func image(usage: Usage?, stale: Bool, now: Date = Date()) -> NSImage {
        let size = NSSize(width: labelWidth + barWidth + 2, height: height)
        let image = NSImage(size: size, flipped: true) { _ in
            let top = (height - (rowHeight * 2 + rowGap)) / 2
            for (i, kind) in WindowKind.allCases.enumerated() {
                let y = top + CGFloat(i) * (rowHeight + rowGap)
                drawRow(kind: kind, window: usage?.window(kind), y: y, stale: stale, now: now)
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func drawRow(kind: WindowKind, window: UsageWindow?, y: CGFloat, stale: Bool, now: Date) {
        let alpha: CGFloat = stale ? 0.45 : 1
        let fg = NSColor.labelColor.withAlphaComponent(alpha)
        let severity = window?.severity(windowLength: kind.length, now: now) ?? .normal
        let exhausted = severity == .exhausted

        // At the limit the label becomes a red "!!" so a blocked window stands out.
        let font = NSFont.monospacedSystemFont(ofSize: 7, weight: exhausted ? .heavy : .semibold)
        let labelColor = exhausted ? NSColor.systemRed.withAlphaComponent(alpha) : fg
        let label = NSAttributedString(
            string: exhausted ? "!!" : kind.label,
            attributes: [.font: font, .foregroundColor: labelColor]
        )
        let labelSize = label.size()
        label.draw(at: NSPoint(x: 0, y: y + (rowHeight - labelSize.height) / 2))

        let bar = NSRect(x: labelWidth, y: y, width: barWidth, height: rowHeight)
        let track = NSBezierPath(roundedRect: bar, xRadius: 2, yRadius: 2)
        NSColor.labelColor.withAlphaComponent(0.18 * alpha).setFill()
        track.fill()

        guard let window else { return }

        let pct = min(max(window.utilization / 100, 0), 1)
        if pct > 0 {
            NSGraphicsContext.saveGraphicsState()
            track.addClip()
            color(for: severity).withAlphaComponent(alpha).setFill()
            NSRect(x: bar.minX, y: bar.minY, width: bar.width * pct, height: bar.height).fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        // Elapsed-time marker: where "even pace" would put you right now.
        if !exhausted, let elapsed = window.elapsedFraction(windowLength: kind.length, now: now) {
            let x = (bar.minX + bar.width * elapsed).rounded() + 0.5
            let tick = NSBezierPath()
            tick.move(to: NSPoint(x: x, y: bar.minY - 1.5))
            tick.line(to: NSPoint(x: x, y: bar.maxY + 1.5))
            tick.lineWidth = 1.2
            fg.setStroke()
            tick.stroke()
        }
    }
}
