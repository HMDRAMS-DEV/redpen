import AppKit
import ImageIO
import SwiftUI

/// Pacer's look with Redpen's red. The popover sits on the system menu material with
/// translucent tiles. The editor is warm paper, so screenshots read like pages on a desk.
/// Dark mode is neutral gray. Type is big and tightly tracked. The only strong color is the pen.
enum Theme {
    @MainActor static var appIcon: NSImage { NSImage(named: "AppIcon") ?? NSApp.applicationIconImage }

    static let canvas = Color(light: 0xF7F5F3, dark: 0x141414)
    static let card = Color(light: 0xFFFFFF, dark: 0x212020)
    static let ink = Color(light: 0x0D0D0D, dark: 0xFFFFFF)
    static let muted = Color(light: 0x85807B, dark: 0xA39E99)
    static let hairline = Color(light: 0xE4E1DD, dark: 0x323131)
    /// The pen, for chrome. Marks on the image always use `Markup.pen`.
    static let pen = Color(light: 0xE5271E, dark: 0xFF5A4E)
    static let penWash = pen.opacity(0.12)
    static let quietWash = Color.primary.opacity(0.07)

    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold)
    }
}

extension View {
    /// Display type: semibold and tightly tracked.
    func display(_ size: CGFloat) -> some View {
        font(Theme.display(size)).tracking(-size * 0.035)
    }

    /// A translucent rounded tile that lets the menu material show through.
    func tile(radius: CGFloat = 14) -> some View {
        background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

/// "Redpen" with the pen's dot, as on the web.
struct Wordmark: View {
    var size: CGFloat = 20

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: size * 0.14) {
            Text("Redpen").display(size).foregroundStyle(Theme.ink)
            Circle().fill(Theme.pen).frame(width: size * 0.3, height: size * 0.3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Redpen")
    }
}

/// Primary and secondary buttons in the calm style. Primary is the pen.
struct PillButtonStyle: ButtonStyle {
    var prominent = true
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12 : 13, weight: .semibold))
            .padding(.horizontal, compact ? 12 : 18)
            .padding(.vertical, compact ? 6 : 9)
            .foregroundStyle(prominent ? .white : Theme.ink)
            .background(prominent ? Theme.pen : Theme.quietWash, in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}

/// A quiet round icon button, like the ones along the bottom of system menus.
struct IconButton: View {
    let symbol: String
    let help: String
    var size: CGFloat = 24
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.5, weight: .medium))
                .foregroundStyle(hovering ? .primary : .secondary)
                .frame(width: size, height: size)
                .background(hovering ? Theme.quietWash : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// A row in the popover: icon, title, and an optional shortcut hint.
struct ActionRow: View {
    let symbol: String
    let title: String
    var hint: String?
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer()
                if let hint {
                    Text(hint).font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(hovering ? Theme.quietWash : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Screenshot thumbnails, made off the main thread and kept for the session.
@MainActor
@Observable
final class Thumbnails {
    static let shared = Thumbnails()
    private var images: [URL: NSImage] = [:]
    private var loading: Set<URL> = []

    func image(for url: URL) -> NSImage? {
        if let image = images[url] { return image }
        if !loading.contains(url) {
            loading.insert(url)
            Task {
                let made = await Task.detached(priority: .utility) { Self.make(url) }.value
                images[url] = made.map { NSImage(cgImage: $0, size: .zero) }
                loading.remove(url)
            }
        }
        return nil
    }

    nonisolated private static func make(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 360,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// A screenshot thumbnail from disk, with a quiet placeholder while it loads.
struct CaptureThumb: View {
    let url: URL
    var height: CGFloat = 64

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.quietWash)
            if let image = Thumbnails.shared.image(for: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
    }
}
