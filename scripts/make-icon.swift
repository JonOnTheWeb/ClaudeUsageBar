// Renders Resources/AppIcon.png, the 1024×1024 source for the app icon.
// scripts/make-app.sh turns it into AppIcon.icns at build time.
//
//   swift scripts/make-icon.swift
//
// Same twelve-spoke starburst as the menu bar glyph, on a dark rounded
// square laid out on Apple's icon grid (824 pt square centred in 1024).
import AppKit

let canvas: CGFloat = 1024
let image = NSImage(size: NSSize(width: canvas, height: canvas), flipped: false) { rect in
    let inset = (canvas - 824) / 2
    let square = NSRect(x: inset, y: inset, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: square, xRadius: 185, yRadius: 185)
    NSGradient(starting: NSColor(srgbRed: 0.24, green: 0.24, blue: 0.27, alpha: 1),
               ending: NSColor(srgbRed: 0.11, green: 0.11, blue: 0.13, alpha: 1))!
        .draw(in: shape, angle: -90)

    let centre = NSPoint(x: rect.midX, y: rect.midY)
    let lengths: [CGFloat] = [300, 225, 280, 245]
    let path = NSBezierPath()
    path.lineWidth = 72
    path.lineCapStyle = .round
    for spoke in 0..<12 {
        let angle = CGFloat(spoke) / 12 * 2 * .pi + .pi / 2
        let length = lengths[spoke % lengths.count]
        path.move(to: centre)
        path.line(to: NSPoint(x: centre.x + cos(angle) * length, y: centre.y + sin(angle) * length))
    }
    NSColor(srgbRed: 0.85, green: 0.47, blue: 0.34, alpha: 1).setStroke()
    path.stroke()
    return true
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: canvas, height: canvas))
NSGraphicsContext.restoreGraphicsState()

let output = URL(fileURLWithPath: "Resources/AppIcon.png")
try rep.representation(using: .png, properties: [:])!.write(to: output)
print("Wrote \(output.path)")
