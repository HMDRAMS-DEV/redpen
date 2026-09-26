import SwiftUI

/// The first screen: what Redpen does in three pictures, then ways to bring screenshots in.
struct EmptyStateView: View {
    @Environment(ReviewStore.self) private var store

    var body: some View {
        VStack(spacing: 26) {
            VStack(spacing: 10) {
                Wordmark(size: 44)
                Text("Circle it. Say it. Paste it into your chat.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }

            HStack(spacing: 14) {
                StepCard(number: 1, title: "Circle anything") { StepArt.circle }
                StepCard(number: 2, title: "Talk") { StepArt.talk }
                StepCard(number: 3, title: "It's written beside it") { StepArt.note }
            }

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Button("Choose from Photos") { store.photoPickerRequested = true }
                        .buttonStyle(PillButtonStyle())
                    Button("Open Images…") { store.fileImporterRequested = true }
                        .buttonStyle(PillButtonStyle(prominent: false))
                    if let latest = store.captures.first {
                        Button("Latest Screenshot") { store.add(urls: [latest.url]) }
                            .buttonStyle(PillButtonStyle(prominent: false))
                    }
                }
                Text("Or drop images anywhere. ⌘V pastes one.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }

            if store.captures.count > 1 {
                RecentStrip()
            }

            SetupCard()
            SuperwhisperCard()
        }
        .padding(32)
        .frame(maxWidth: 720)
    }
}

private struct StepCard<Art: View>: View {
    let number: Int
    let title: String
    @ViewBuilder let art: () -> Art

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            art()
                .frame(height: 96)
                .frame(maxWidth: .infinity)
                .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            HStack(spacing: 8) {
                Text("\(number)")
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.pen)
                    .frame(width: 20, height: 20)
                    .overlay(Circle().strokeBorder(Theme.pen, lineWidth: 1.5))
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
            }
        }
        .padding(12)
        .frame(width: 200)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Tiny drawings of the three steps, using the app's own pen.
private enum StepArt {
    static let pen = Color(nsColor: Markup.pen)

    static var circle: some View {
        ZStack {
            page
            Path(Ink.path(Ink.Loop(center: CGPoint(x: 70, y: 44), radii: CGSize(width: 40, height: 17),
                                   rotation: -0.06, start: -2.4, clockwise: true)))
                .stroke(pen, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        }
        .frame(width: 150, height: 80)
    }

    static var talk: some View {
        HStack(spacing: 4) {
            ForEach([10, 22, 34, 18, 40, 26, 14, 30, 20, 10], id: \.self) { height in
                Capsule().fill(pen).frame(width: 4, height: CGFloat(height))
            }
        }
    }

    static var note: some View {
        ZStack(alignment: .topLeading) {
            page
            Path(Ink.path(Ink.Loop(center: CGPoint(x: 42, y: 44), radii: CGSize(width: 26, height: 14),
                                   rotation: -0.06, start: -2.4, clockwise: true)))
                .stroke(pen, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            Text("too tight")
                .font(Font(Markup.handFont(15)))
                .foregroundStyle(pen)
                .offset(x: 76, y: 32)
        }
        .frame(width: 150, height: 80)
    }

    /// A screenshot, suggested by a few lines of text.
    private static var page: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach([0.62, 0.84, 0.44, 0.72], id: \.self) { width in
                Capsule().fill(Color.primary.opacity(0.12)).frame(width: 118 * width, height: 5)
            }
        }
        .padding(16)
        .frame(width: 150, height: 80, alignment: .topLeading)
    }
}

private struct RecentStrip: View {
    @Environment(ReviewStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent screenshots")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.muted)
            HStack(spacing: 8) {
                ForEach(Array(store.captures.prefix(5))) { capture in
                    Button { store.add(urls: [capture.url]) } label: {
                        CaptureThumb(url: capture.url, height: 64)
                    }
                    .buttonStyle(.plain)
                    .help("Mark up \(capture.url.lastPathComponent)")
                }
            }
        }
        .frame(maxWidth: 628)
    }
}

/// Recommends Superwhisper, which Redpen drives for you, and offers it when installed.
struct SuperwhisperCard: View {
    @Environment(ReviewStore.self) private var store

    var body: some View {
        let voice = store.voice
        if voice.engine != .superwhisper {
            HStack(spacing: 14) {
                Image(systemName: "waveform")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.pen)
                    .frame(width: 40, height: 40)
                    .background(Theme.penWash, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Talk with Superwhisper").font(.system(size: 13, weight: .semibold))
                    Text("When you circle something, Redpen starts Superwhisper for you, and your words land beside the circle.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if voice.superwhisperInstalled {
                    Button("Use Superwhisper") { voice.engine = .superwhisper }
                        .buttonStyle(PillButtonStyle(prominent: false, compact: true))
                } else {
                    Link("Get Superwhisper", destination: Voice.superwhisperSite)
                        .buttonStyle(PillButtonStyle(prominent: false, compact: true))
                }
            }
            .padding(14)
            .frame(maxWidth: 628)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

/// Asks for what the screenshot nudge needs, once. Refusals are handled in Settings.
struct SetupCard: View {
    @Environment(ReviewStore.self) private var store

    var body: some View {
        if store.notificationAccess == .unasked || store.photosAccess == .unasked {
            VStack(alignment: .leading, spacing: 12) {
                SetupRow(symbol: "bell.badge", title: "Ask after each screenshot",
                         detail: "One notification after a burst of screenshots, so you can mark them up.",
                         access: store.notificationAccess, allow: store.allowNotifications)
                SetupRow(symbol: "iphone", title: "Include iPhone screenshots",
                         detail: "Screenshots from your iPhone or iPad arrive through iCloud Photos, and Redpen asks about them too.",
                         access: store.photosAccess, allow: store.allowPhotos)
                HStack(spacing: 4) {
                    Text("Using a Focus? Add Redpen to its allowed apps so the notification gets through.")
                    Button("Focus Settings", action: store.openFocusSettings)
                        .buttonStyle(.plain)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.pen)
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
            }
            .padding(14)
            .frame(maxWidth: 628, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

private struct SetupRow: View {
    let symbol: String
    let title: String
    let detail: String
    let access: Access
    let allow: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.pen)
                .frame(width: 40, height: 40)
                .background(Theme.penWash, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            AccessButton(access: access, allow: allow)
                .buttonStyle(PillButtonStyle(prominent: false, compact: true))
        }
    }
}

/// "Allow" before asking, "On" once allowed, and a way to System Settings after a refusal.
struct AccessButton: View {
    let access: Access
    let allow: () -> Void

    var body: some View {
        switch access {
        case .allowed:
            Label("On", systemImage: "checkmark")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.muted)
        case .unasked:
            Button("Allow", action: allow)
        case .denied:
            Button("Open Settings", action: allow)
        }
    }
}
