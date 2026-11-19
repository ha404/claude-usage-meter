// Renders the app icon (the menu bar's pace bars, scaled up on graphite) into an .iconset.
// Run via scripts/make-icon.sh.
import AppKit

func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
            blue: CGFloat(v & 0xff) / 255, alpha: a)
}

/// Draws the icon on a 1024-point canvas, following the macOS grid: an 824pt rounded-rect
/// body centered with a ~185pt corner radius and a soft drop shadow.
func drawIcon() {
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 20
    shadow.shadowOffset = NSSize(width: 0, height: -8)
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(starting: hex(0x34373D), ending: hex(0x141518))!.draw(in: body, angle: -90)

    let w: CGFloat = 560, h: CGFloat = 112, gap: CGFloat = 30, x = body.midX - w / 2
    bar(NSRect(x: x, y: body.midY + gap, width: w, height: h), fill: 0.42, color: hex(0x34C759))
    bar(NSRect(x: x, y: body.midY - gap - h, width: w, height: h), fill: 0.74, color: hex(0xFF9F0A))

    // The pace tick, overhanging both bars.
    let tickW: CGFloat = 24, tickX = x + w * 0.58
    NSColor.white.setFill()
    NSBezierPath(roundedRect: NSRect(x: tickX - tickW / 2, y: body.midY - gap - h - 34,
                                     width: tickW, height: 2 * (gap + h + 34)),
                 xRadius: tickW / 2, yRadius: tickW / 2).fill()
    NSGraphicsContext.restoreGraphicsState()
}

func bar(_ rect: NSRect, fill: CGFloat, color: NSColor) {
    let track = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
    hex(0xFFFFFF, 0.14).setFill()
    track.fill()
    NSGraphicsContext.saveGraphicsState()
    track.addClip()
    color.setFill()
    NSRect(x: rect.minX, y: rect.minY, width: rect.width * fill, height: rect.height).fill()
    NSGraphicsContext.restoreGraphicsState()
}

/// Renders at an exact pixel size (vector, not downscaled) so small sizes stay crisp.
func png(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high
    let scale = CGFloat(pixels) / 1024
    ctx.cgContext.scaleBy(x: scale, y: scale)
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try png(pixels: size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try png(pixels: size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
