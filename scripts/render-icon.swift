// Renders Redpen's app icon into the asset catalog, plus copies for the website.
//
//     swift scripts/render-icon.swift
//
// Run from the repo root. The mark is the product's own gesture: a page of text with one
// line circled in red pen, the loop overshooting its start the way a real hand does.

import AppKit

let output = URL(fileURLWithPath: "Redpen/Assets.xcassets/AppIcon.appiconset")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func draw(in context: CGContext, size: CGFloat) {
    context.scaleBy(x: size / 1024, y: size / 1024)

    // The macOS icon grid: an 824pt rounded square centered on a 1024pt canvas, with a soft shadow.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: color(0x000000, 0.3))
    context.addPath(shape)
    context.setFillColor(color(0xF7F5F3))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()
    let paper = CGGradient(colorsSpace: nil, colors: [color(0xFFFFFF), color(0xEEEAE5)] as CFArray, locations: nil)!
    context.drawLinearGradient(paper, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    context.restoreGState()

    context.saveGState()
    context.addPath(CGPath(roundedRect: tile.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 183, cornerHeight: 183, transform: nil))
    context.setStrokeColor(color(0x000000, 0.06))
    context.setLineWidth(3)
    context.strokePath()
    context.restoreGState()

    // Lines of text on the page, centered on the tile. The circled one is ink; the rest are quiet.
    let lines: [(y: CGFloat, width: CGFloat, dark: Bool)] = [
        (672, 470, false), (592, 380, false), (512, 300, true), (432, 440, false), (352, 340, false),
    ]
    for line in lines {
        let rect = CGRect(x: 512 - line.width / 2, y: line.y - 17, width: line.width, height: 34)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 17, cornerHeight: 17, transform: nil))
        context.setFillColor(line.dark ? color(0x0D0D0D, 0.78) : color(0x0D0D0D, 0.12))
        context.fillPath()
    }

    // The loop, drawn like the app draws one: it overshoots and lands a little wider.
    let path = CGMutablePath()
    let center = CGPoint(x: 512, y: 512), a: CGFloat = 250, b: CGFloat = 92, tilt: CGFloat = 0.07
    let start: CGFloat = 2.5, sweep = 2 * CGFloat.pi + 0.55
    for step in 0...160 {
        let t = CGFloat(step) / 160
        let angle = start - sweep * t
        let grow = 1 + 0.08 * t
        let u = a * grow * cos(angle), v = b * grow * sin(angle)
        let point = CGPoint(x: center.x + u * cos(tilt) - v * sin(tilt), y: center.y + u * sin(tilt) + v * cos(tilt))
        if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    context.addPath(path)
    context.setStrokeColor(color(0xE5271E))
    context.setLineWidth(30)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.strokePath()
}

func png(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    draw(in: context.cgContext, size: CGFloat(pixels))
    context.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try png(pixels: points * scale).write(to: output.appending(path: name))
        images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)"])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: output.appending(path: "Contents.json"))
print("Wrote \(images.count) icons to \(output.path)")

let site = URL(fileURLWithPath: "site/assets")
try FileManager.default.createDirectory(at: site, withIntermediateDirectories: true)
try png(pixels: 512).write(to: site.appending(path: "icon.png"))
try png(pixels: 64).write(to: site.appending(path: "favicon.png"))
print("Wrote icons to \(site.path)")
