import AppKit

/// Lays out and draws the red pen: circles, lines, and notes, plus the notes panel under the
/// image for anything too long to write in the margin. The editor and the exported PNG share
/// this code, so what you see is what the model gets.
///
/// All coordinates are image pixels with a top-left origin. Callers hand over a context whose
/// y axis points down.
enum Markup {
    /// Teacher's red. Fixed, not adaptive, because it lands on the exported image.
    static let pen = NSColor(hex: 0xE5271E)
    static let paper = NSColor(hex: 0xF7F5F3)
    static let ink = NSColor(hex: 0x0D0D0D)

    /// Notes longer than this move under the image, where an LLM reads them as plain text.
    static let longNoteLength = 90

    struct Metrics {
        var fontSize: CGFloat
        var penWidth: CGFloat
        var noteWidth: CGFloat
        var gap: CGFloat
        var handFont: NSFont
        var bodyFont: NSFont
    }

    static func metrics(for size: CGSize) -> Metrics {
        // Scale with the image's area so a phone screenshot and a 5K desktop both read well.
        let base = sqrt(size.width * size.height)
        let fontSize = max(15, base * 0.022)
        return Metrics(
            fontSize: fontSize,
            penWidth: max(3, base * 0.0034),
            noteWidth: max(fontSize * 6, min(size.width * 0.42, fontSize * 15)),
            gap: fontSize * 0.45,
            handFont: handFont(fontSize),
            bodyFont: .systemFont(ofSize: fontSize * 0.78)
        )
    }

    static func handFont(_ size: CGFloat) -> NSFont {
        NSFont(name: "Noteworthy-Bold", size: size) ?? .systemFont(ofSize: size, weight: .semibold)
    }

    static func isLong(_ note: Note) -> Bool {
        note.text.trimmingCharacters(in: .whitespacesAndNewlines).count > longNoteLength
    }

    struct Layout {
        struct Inline { var note: Note; var frame: CGRect }
        struct Numbered { var number: Int; var note: Note; var marker: CGRect; var footerFrame: CGRect }

        var imageSize: CGSize
        var inline: [Inline] = []
        var numbered: [Numbered] = []
        var footerHeight: CGFloat = 0

        var pageSize: CGSize { CGSize(width: imageSize.width, height: imageSize.height + footerHeight) }

        /// The note under a point, for click-to-edit.
        func note(at point: CGPoint) -> Note? {
            if let hit = inline.first(where: { $0.frame.insetBy(dx: -8, dy: -8).contains(point) }) { return hit.note }
            return numbered.first(where: { $0.marker.insetBy(dx: -8, dy: -8).contains(point) || $0.footerFrame.contains(point) })?.note
        }
    }

    /// Lays out every note except `excluding`, which the editor shows as a live text field.
    static func layout(_ shot: Shot, excluding: Note.ID? = nil) -> Layout {
        let size = shot.size
        let m = metrics(for: size)
        var layout = Layout(imageSize: size)
        let pad = m.fontSize * 1.1
        var y = size.height + pad
        for note in shot.notes where note.id != excluding && !note.isEmpty {
            if isLong(note) {
                let number = layout.numbered.count + 1
                let label = "\(number)"
                let markerSize = markerSize(label, m)
                let marker = place(markerSize, beside: note.target, in: size, gap: m.gap)
                let textWidth = size.width - pad * 2 - markerSize.width - m.gap * 1.5
                let height = max(markerSize.height, measure(note.text, font: m.bodyFont, width: textWidth).height)
                let frame = CGRect(x: 0, y: y - m.gap / 2, width: size.width, height: height + m.gap)
                layout.numbered.append(.init(number: number, note: note, marker: marker, footerFrame: frame))
                y += height + m.fontSize * 0.7
            } else {
                let text = measure(note.text, font: m.handFont, width: m.noteWidth)
                layout.inline.append(.init(note: note, frame: place(text, beside: note.target, in: size, gap: m.gap)))
            }
        }
        if !layout.numbered.isEmpty {
            layout.footerHeight = y - size.height - m.fontSize * 0.7 + pad
        }
        return layout
    }

    static func measure(_ text: String, font: NSFont, width: CGFloat) -> CGSize {
        let string = NSAttributedString(string: text.isEmpty ? " " : text, attributes: attributes(font: font))
        let rect = string.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                       options: [.usesLineFragmentOrigin, .usesFontLeading])
        return CGSize(width: ceil(min(rect.width, width)) + 2, height: ceil(rect.height))
    }

    /// Where a note goes: outside the circle, to the right if it fits, then left, below, above.
    /// A note on a clicked point starts at the point, like writing where your pen landed.
    static func place(_ size: CGSize, beside target: CGRect, in image: CGSize, gap: CGFloat) -> CGRect {
        func clamped(_ rect: CGRect) -> CGRect {
            var r = rect
            r.origin.x = min(max(r.minX, 0), max(0, image.width - r.width))
            r.origin.y = min(max(r.minY, 0), max(0, image.height - r.height))
            return r
        }
        if target.width == 0 && target.height == 0 {
            return clamped(CGRect(x: target.minX, y: target.minY - min(size.height, gap * 2.6) / 2, width: size.width, height: size.height))
        }
        let top = target.midY - size.height / 2
        let candidates = [
            CGRect(x: target.maxX + gap, y: top, width: size.width, height: size.height),
            CGRect(x: target.minX - gap - size.width, y: top, width: size.width, height: size.height),
            CGRect(x: target.midX - size.width / 2, y: target.maxY + gap, width: size.width, height: size.height),
            CGRect(x: target.midX - size.width / 2, y: target.minY - gap - size.height, width: size.width, height: size.height),
        ]
        let fits = candidates.first { rect in
            rect.minX >= 0 && rect.maxX <= image.width && rect.minY >= 0 && rect.maxY <= image.height
        } ?? candidates.first { rect in
            // Sideways placements may slide vertically to fit.
            rect.minX >= 0 && rect.maxX <= image.width && rect.height <= image.height
        }
        return clamped(fits ?? candidates[0])
    }

    static func markerSize(_ label: String, _ m: Metrics) -> CGSize {
        let side = m.fontSize * 1.35 + CGFloat(label.count - 1) * m.fontSize * 0.45
        return CGSize(width: side, height: m.fontSize * 1.35)
    }

    // MARK: Drawing

    static func draw(_ shot: Shot, layout: Layout, live: [CGPoint] = [], in context: CGContext) {
        let m = metrics(for: shot.size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        defer { NSGraphicsContext.restoreGraphicsState() }

        context.setStrokeColor(pen.cgColor)
        context.setLineWidth(m.penWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for mark in shot.marks {
            context.addPath(mark.ink.path)
            context.strokePath()
        }
        if live.count > 1 {
            context.addPath(Ink.smoothPath(live))
            context.strokePath()
        }

        for item in layout.inline {
            drawHand(item.note.text, in: item.frame, font: m.handFont)
        }
        for item in layout.numbered {
            drawMarker("\(item.number)", in: item.marker, m, halo: true)
        }

        guard layout.footerHeight > 0 else { return }
        let size = shot.size
        context.setFillColor(paper.cgColor)
        context.fill(CGRect(x: 0, y: size.height, width: size.width, height: layout.footerHeight))
        context.setFillColor(NSColor(hex: 0xE4E1DD).cgColor)
        context.fill(CGRect(x: 0, y: size.height, width: size.width, height: max(1, m.penWidth / 3)))
        let pad = m.fontSize * 1.1
        for item in layout.numbered {
            let marker = markerSize("\(item.number)", m)
            let top = item.footerFrame.minY + m.gap / 2
            drawMarker("\(item.number)", in: CGRect(origin: CGPoint(x: pad, y: top), size: marker), m, halo: false)
            let x = pad + marker.width + m.gap * 1.5
            let body = NSAttributedString(string: item.note.text, attributes: attributes(font: m.bodyFont, color: ink))
            let bodyHeight = measure(item.note.text, font: m.bodyFont, width: size.width - x - pad).height
            // Center one-line notes on the marker; longer ones start level with it.
            let offset = max(0, (marker.height - bodyHeight) / 2)
            body.draw(with: CGRect(x: x, y: top + offset, width: size.width - x - pad, height: bodyHeight + 4),
                      options: [.usesLineFragmentOrigin, .usesFontLeading])
        }
    }

    /// Red handwriting with a soft paper halo, so it reads on busy screenshots.
    static func drawHand(_ text: String, in rect: CGRect, font: NSFont) {
        let options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        var halo = attributes(font: font, color: pen)
        halo[.strokeColor] = NSColor.white.withAlphaComponent(0.9)
        halo[.strokeWidth] = 16
        NSAttributedString(string: text, attributes: halo).draw(with: rect, options: options)
        NSAttributedString(string: text, attributes: attributes(font: font, color: pen)).draw(with: rect, options: options)
    }

    /// A circled number, the way a teacher refers you to a comment at the bottom of the page.
    static func drawMarker(_ label: String, in rect: CGRect, _ m: Metrics, halo: Bool) {
        let ring = NSBezierPath(ovalIn: rect.insetBy(dx: m.penWidth / 2, dy: m.penWidth / 2))
        if halo {
            NSColor.white.withAlphaComponent(0.85).setFill()
            ring.fill()
        }
        ring.lineWidth = max(2, m.penWidth * 0.7)
        pen.setStroke()
        ring.stroke()
        // Handwritten digits read as brackets at this size; a rounded system face stays clear.
        let font = NSFont(descriptor: NSFont.systemFont(ofSize: m.fontSize * 0.72, weight: .bold).fontDescriptor.withDesign(.rounded)!, size: m.fontSize * 0.72)!
        let text = NSAttributedString(string: label, attributes: attributes(font: font, color: pen, alignment: .center))
        let height = measure(label, font: font, width: rect.width).height
        text.draw(with: CGRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height),
                  options: [.usesLineFragmentOrigin, .usesFontLeading])
    }

    static func attributes(font: NSFont, color: NSColor = pen, alignment: NSTextAlignment = .left) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.alignment = alignment
        return [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
    }

    // MARK: Export

    /// The screenshot with its markup, plus the notes panel when there are long notes.
    static func render(_ shot: Shot) -> CGImage? {
        let layout = layout(shot)
        let page = layout.pageSize
        guard let context = CGContext(
            data: nil, width: Int(page.width), height: Int(page.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: page))
        context.translateBy(x: 0, y: page.height)
        context.scaleBy(x: 1, y: -1)

        context.saveGState()
        context.translateBy(x: 0, y: shot.size.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(shot.image, in: CGRect(origin: .zero, size: shot.size))
        context.restoreGState()

        draw(shot, layout: layout, in: context)
        return context.makeImage()
    }

    static func png(_ shot: Shot) -> Data? {
        guard let image = render(shot) else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    static func fileName(_ shot: Shot, index: Int) -> String {
        let base = (shot.name as NSString).deletingPathExtension
            .replacingOccurrences(of: "[^A-Za-z0-9_-]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String(format: "redpen-%02d-%@.png", index + 1, base.isEmpty ? "shot" : String(base.prefix(60)))
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
