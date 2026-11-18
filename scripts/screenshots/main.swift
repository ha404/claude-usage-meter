// Renders the README screenshots from sample data. Run via scripts/screenshots.sh.
import AppKit
import SwiftUI

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
let now = Date()
let scale: CGFloat = 2

func window(_ utilization: Double, elapsed: Double, _ kind: WindowKind) -> UsageWindow {
    UsageWindow(utilization: utilization, resetsAt: now.addingTimeInterval(kind.length * (1 - elapsed)))
}

func savePNG(_ rep: NSBitmapImageRep, _ name: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent(name))
    print("wrote docs/\(name)")
}

/// Draws into a bitmap at `scale`x with a flipped (top-left origin) coordinate space.
func render(width: CGFloat, height: CGFloat, _ draw: (NSRect) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    ctx.cgContext.translateBy(x: 0, y: height)
    ctx.cgContext.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx.cgContext, flipped: true)
    draw(NSRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let dark = NSAppearance(named: .darkAqua)!
NSAppearance.current = dark

// MARK: - Menu bar states

let states: [(String, Usage)] = [
    ("On pace", Usage(fiveHour: window(20, elapsed: 0.45, .fiveHour), sevenDay: window(36, elapsed: 0.5, .sevenDay))),
    ("Past the marker", Usage(fiveHour: window(48, elapsed: 0.3, .fiveHour), sevenDay: window(36, elapsed: 0.5, .sevenDay))),
    ("Past it, 85%+ used", Usage(fiveHour: window(90, elapsed: 0.7, .fiveHour), sevenDay: window(62, elapsed: 0.55, .sevenDay))),
    ("Limit reached", Usage(fiveHour: window(100, elapsed: 0.8, .fiveHour), sevenDay: window(70, elapsed: 0.6, .sevenDay))),
]

let cellW: CGFloat = 130, barH: CGFloat = 24, captionH: CGFloat = 20
let states_rep = render(width: cellW * CGFloat(states.count), height: barH + captionH + 8) { rect in
    NSColor(white: 0.12, alpha: 1).setFill()
    rect.fill()
    for (i, (caption, usage)) in states.enumerated() {
        let x = CGFloat(i) * cellW
        NSColor(white: 0.2, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: x + 8, y: 6, width: cellW - 16, height: barH), xRadius: 5, yRadius: 5).fill()
        let img = BarRenderer.image(usage: usage, stale: false, now: now)
        img.draw(in: NSRect(x: x + (cellW - img.size.width) / 2, y: 6 + (barH - img.size.height) / 2,
                            width: img.size.width, height: img.size.height),
                 from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        let text = NSAttributedString(string: caption, attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor(white: 0.75, alpha: 1)])
        text.draw(at: NSPoint(x: x + (cellW - text.size().width) / 2, y: barH + 12))
    }
}
savePNG(states_rep, "menubar-states.png")

// MARK: - Popover

let popoverFramed = MainActor.assumeIsolated { () -> NSBitmapImageRep in
let popoverService = UsageService(preview: Usage(
    fiveHour: window(48, elapsed: 0.3, .fiveHour),
    sevenDay: window(36, elapsed: 0.5, .sevenDay)))
let host = NSHostingView(rootView: PopoverView(service: popoverService))
host.appearance = dark
host.frame.size = host.fittingSize
let popoverWindow = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
popoverWindow.appearance = dark
popoverWindow.backgroundColor = NSColor(white: 0.16, alpha: 1)
popoverWindow.contentView = host
host.layoutSubtreeIfNeeded()
RunLoop.main.run(until: Date().addingTimeInterval(0.3))
let popoverRep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
host.cacheDisplay(in: host.bounds, to: popoverRep)
return render(width: host.bounds.width, height: host.bounds.height) { rect in
    let path = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
    path.addClip()
    NSColor(white: 0.16, alpha: 1).setFill()
    rect.fill()
    popoverRep.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
}
}
savePNG(popoverFramed, "popover.png")

// MARK: - Status line (ANSI output rendered as a terminal)

let ansiColors: [String: NSColor] = [
    "32": .systemGreen, "33": .systemOrange, "31": .systemRed,
    "90": NSColor(white: 0.5, alpha: 1), "37": .white, "0": NSColor(white: 0.85, alpha: 1)]

func attributed(ansi: String, font: NSFont) -> NSAttributedString {
    let out = NSMutableAttributedString()
    var color = ansiColors["0"]!
    var bold = false
    let parts = ansi.components(separatedBy: "\u{1B}[")
    for (i, part) in parts.enumerated() {
        var text = Substring(part)
        if i > 0, let m = part.firstIndex(of: "m") {
            for code in part[..<m].split(separator: ";").map(String.init) {
                if code == "0" { color = ansiColors["0"]!; bold = false }
                else if code == "1" { bold = true }
                else if let c = ansiColors[code] { color = c }
            }
            text = part[part.index(after: m)...]
        }
        let f = bold ? NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) : font
        out.append(NSAttributedString(string: String(text), attributes: [.font: f, .foregroundColor: color]))
    }
    return out
}

let lines = CommandLine.arguments.dropFirst(2).map { $0 }
let font = NSFont(name: "Menlo", size: 12)!  // has the block glyphs, so bars render without gaps
let rendered = lines.map { attributed(ansi: $0, font: font) }
let lineH: CGFloat = 22, pad: CGFloat = 14
let termW = (rendered.map { $0.size().width }.max() ?? 0) + pad * 2
let statusRep = render(width: termW, height: CGFloat(lines.count) * lineH + pad * 2) { rect in
    NSColor(white: 0.1, alpha: 1).setFill()
    NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
    for (i, line) in rendered.enumerated() {
        line.draw(at: NSPoint(x: pad, y: pad + CGFloat(i) * lineH + (lineH - line.size().height) / 2))
    }
}
savePNG(statusRep, "statusline.png")
