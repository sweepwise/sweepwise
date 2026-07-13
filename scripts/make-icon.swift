#!/usr/bin/swift
// Generates Assets/AppIcon.icns — a macOS-style squircle with a teal→mint
// gradient and the internaldrive + sparkles glyphs. Rerun after design changes:
//   swift scripts/make-icon.swift
import AppKit

let canvas: CGFloat = 1024

func drawIcon() -> NSImage {
    let image = NSImage(size: NSSize(width: canvas, height: canvas))
    image.lockFocus()

    // macOS Big Sur-style icon grid: the squircle fills ~824pt of the 1024 canvas.
    let inset: CGFloat = 100
    let rect = NSRect(x: inset, y: inset, width: canvas - 2 * inset, height: canvas - 2 * inset)
    let squircle = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)

    // Soft drop shadow behind the squircle.
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor.white.setFill()
    squircle.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.04, green: 0.36, blue: 0.33, alpha: 1),  // deep teal
        NSColor(calibratedRed: 0.13, green: 0.62, blue: 0.47, alpha: 1),  // green
        NSColor(calibratedRed: 0.45, green: 0.85, blue: 0.65, alpha: 1),  // mint
    ])!
    gradient.draw(in: squircle, angle: 90)

    // Subtle top highlight for depth.
    let highlight = NSGradient(colors: [
        NSColor.white.withAlphaComponent(0.22),
        NSColor.white.withAlphaComponent(0.0),
    ])!
    let topHalf = NSBezierPath(roundedRect: rect.insetBy(dx: 14, dy: 14), xRadius: 172, yRadius: 172)
    NSGraphicsContext.current?.saveGraphicsState()
    topHalf.addClip()
    highlight.draw(in: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2),
                   angle: 90)
    NSGraphicsContext.current?.restoreGraphicsState()

    func drawSymbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight,
                    center: NSPoint, alpha: CGFloat) {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return }
        let tinted = NSImage(size: symbol.size)
        tinted.lockFocus()
        symbol.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        NSColor.white.withAlphaComponent(alpha).set()
        NSRect(origin: .zero, size: symbol.size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        tinted.draw(at: NSPoint(x: center.x - symbol.size.width / 2,
                                y: center.y - symbol.size.height / 2),
                    from: .zero, operation: .sourceOver, fraction: 1)
    }

    drawSymbol("internaldrive.fill", pointSize: 400, weight: .medium,
               center: NSPoint(x: canvas / 2, y: canvas / 2 - 30), alpha: 0.97)
    drawSymbol("sparkles", pointSize: 150, weight: .semibold,
               center: NSPoint(x: canvas / 2 + 205, y: canvas / 2 + 185), alpha: 0.95)

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, size: Int, to url: URL) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
               from: NSRect(x: 0, y: 0, width: canvas, height: canvas),
               operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let fm = FileManager.default
let root = URL(fileURLWithPath: CommandLine.arguments.first!)
    .deletingLastPathComponent().deletingLastPathComponent()
let assets = root.appendingPathComponent("Assets")
let iconset = assets.appendingPathComponent("Sweepwise.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)

let icon = drawIcon()
for size in [16, 32, 128, 256, 512] {
    writePNG(icon, size: size, to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    writePNG(icon, size: size * 2, to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path,
                  "-o", assets.appendingPathComponent("AppIcon.icns").path]
try! task.run()
task.waitUntilExit()
try? fm.removeItem(at: iconset)
print(task.terminationStatus == 0 ? "Wrote Assets/AppIcon.icns" : "iconutil failed")
