import AppKit

/// The menu bar glyph: a quick pen loop, like a circle around a mistake. A template image, so
/// it follows the menu bar, until new screenshots arrive; then the loop turns red and circles
/// how many are waiting, written in the pen's hand.
enum MenuBarIcon {
    static func image(pending: Int) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let loop = Ink.Loop(center: CGPoint(x: 9, y: 9.2), radii: CGSize(width: 7.2, height: 6.4),
                                rotation: -0.35, start: -2.3, clockwise: true)
            let path = NSBezierPath(cgPath: Ink.path(loop))
            path.lineWidth = 1.7
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            guard pending > 0 else {
                NSColor.black.setStroke()
                path.stroke()
                return true
            }
            let isDark = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let pen = NSColor(hex: isDark ? 0xFF5A4E : 0xE5271E)
            pen.setStroke()
            path.stroke()
            let label = NSAttributedString(string: pending > 9 ? "9+" : "\(pending)", attributes: [
                .font: Markup.handFont(pending > 9 ? 9 : 12),
                .foregroundColor: pen,
            ])
            let size = label.size()
            label.draw(at: CGPoint(x: 9 - size.width / 2, y: 9.2 - size.height / 2))
            return true
        }
        image.isTemplate = pending == 0
        image.accessibilityDescription = pending > 0 ? "Redpen, \(pending) new screenshots" : "Redpen"
        return image
    }
}
