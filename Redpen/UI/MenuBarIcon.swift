import AppKit

/// The menu bar glyph: a quick pen loop, like a circle around a mistake. A template image, so
/// it follows the menu bar, until new screenshots arrive; then a red dot asks for a look.
enum MenuBarIcon {
    static func image(pending: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            let loop = Ink.Loop(center: CGPoint(x: 8.6, y: 9.4), radii: CGSize(width: 6.3, height: 4.9),
                                rotation: -0.35, start: -2.3, clockwise: true)
            let path = NSBezierPath(cgPath: Ink.path(loop))
            path.lineWidth = 1.7
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            (pending ? NSColor.labelColor : .black).setStroke()
            path.stroke()
            if pending {
                let dot = NSBezierPath(ovalIn: NSRect(x: rect.maxX - 6.5, y: 0.5, width: 6, height: 6))
                NSColor(hex: 0xE5271E).setFill()
                dot.fill()
            }
            return true
        }
        image.isTemplate = !pending
        image.accessibilityDescription = pending ? "Redpen, new screenshots" : "Redpen"
        return image
    }
}
