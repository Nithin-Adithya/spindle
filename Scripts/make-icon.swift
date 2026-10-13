// Draws Spindle's icon (a record on a dark tile) and writes Resources/AppIcon.icns.
// Run from the project root: swift Scripts/make-icon.swift
import AppKit

func draw(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(pixels)
    // macOS icons sit on a rounded tile inset from the canvas edge.
    let tile = NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    let path = NSBezierPath(roundedRect: tile, xRadius: s * 0.18, yRadius: s * 0.18)
    NSGradient(colors: [NSColor(red: 0.20, green: 0.17, blue: 0.26, alpha: 1), NSColor(red: 0.07, green: 0.06, blue: 0.10, alpha: 1)])!
        .draw(in: path, angle: -90)

    func circle(_ fraction: CGFloat) -> NSBezierPath {
        let d = s * fraction
        return NSBezierPath(ovalIn: NSRect(x: (s - d) / 2, y: (s - d) / 2, width: d, height: d))
    }
    NSColor(white: 0.03, alpha: 1).setFill()
    circle(0.64).fill()
    NSColor(white: 1, alpha: 0.09).setStroke()
    for ring in 0..<7 {
        let groove = circle(0.60 - CGFloat(ring) * 0.045)
        groove.lineWidth = max(1, s * 0.002)
        groove.stroke()
    }
    NSGradient(colors: [NSColor(red: 1.0, green: 0.62, blue: 0.24, alpha: 1), NSColor(red: 0.93, green: 0.31, blue: 0.33, alpha: 1)])!
        .draw(in: circle(0.25), angle: -60)
    NSColor(white: 0.05, alpha: 1).setFill()
    circle(0.035).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Spindle.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try draw(points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try draw(points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
