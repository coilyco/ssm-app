// Draws the app icon as an iconset. Usage: swift scripts/make-icon.swift <iconset-dir>
import AppKit

let base: CGFloat = 1024

func draw(_ pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(pixels) / base
    NSGraphicsContext.current?.cgContext.scaleBy(x: scale, y: scale)

    // The macOS icon grid: an 824 point body centred in the 1024 canvas.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    NSGradient(starting: NSColor(red: 0.20, green: 0.45, blue: 0.95, alpha: 1),
               ending: NSColor(red: 0.09, green: 0.16, blue: 0.48, alpha: 1))!.draw(in: shape, angle: -90)

    let config = NSImage.SymbolConfiguration(pointSize: 440, weight: .semibold)
    if let key = NSImage(systemSymbolName: "key.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let tinted = NSImage(size: key.size, flipped: false) { rect in
            key.draw(in: rect)
            NSColor.white.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        let size = tinted.size
        tinted.draw(in: NSRect(x: (base - size.width) / 2, y: (base - size.height) / 2, width: size.width, height: size.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

guard CommandLine.arguments.count == 2 else { fatalError("usage: make-icon.swift <iconset-dir>") }
let dir = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
for point in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let name = factor == 1 ? "icon_\(point)x\(point).png" : "icon_\(point)x\(point)@2x.png"
        let png = draw(point * factor).representation(using: .png, properties: [:])!
        try png.write(to: dir.appendingPathComponent(name))
    }
}
