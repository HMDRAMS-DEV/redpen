import SwiftUI

/// One screenshot as a page: the image, the red pen over it, and the notes panel under it
/// when a note runs long. Draw anywhere on it. A circle opens a note beside it and starts
/// listening; a click opens a note right there.
struct PageView: View {
    @Environment(ReviewStore.self) private var store
    let shot: Shot

    var body: some View {
        GeometryReader { geometry in
            let layout = Markup.layout(shot, excluding: store.activeNoteID)
            let page = layout.pageSize
            // Never larger than one point per pixel, so small images stay crisp.
            let scale = min(geometry.size.width / page.width, geometry.size.height / page.height, 1)
            let size = CGSize(width: page.width * scale, height: page.height * scale)

            ZStack(alignment: .topLeading) {
                Color.white
                Image(decorative: shot.image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: shot.size.width * scale, height: shot.size.height * scale)
                Canvas { context, _ in
                    context.withCGContext { cg in
                        cg.scaleBy(x: scale, y: scale)
                        Markup.draw(shot, layout: layout, live: store.liveStroke, in: cg)
                    }
                }
                .frame(width: size.width, height: size.height)
                .allowsHitTesting(false)

                PenSurface(scale: scale, imageSize: shot.size)
                    .frame(width: size.width, height: size.height)

                if let note = store.activeNote {
                    NoteField(note: note, shot: shot, scale: scale)
                        .id(note.id)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.black.opacity(0.08)))
            .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: layout.footerHeight)
        }
    }
}

/// Takes the pen. Sits under the live note, so clicks inside the note still place the cursor.
private struct PenSurface: View {
    @Environment(ReviewStore.self) private var store
    let scale: CGFloat
    let imageSize: CGSize

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let point = CGPoint(x: min(max(value.location.x / scale, 0), imageSize.width),
                                            y: value.location.y / scale)
                        store.penMoved(to: point)
                    }
                    .onEnded { _ in store.penEnded(tapLength: 5 / scale) }
            )
            .onHover { inside in
                if inside { NSCursor.crosshair.push() } else { NSCursor.pop() }
            }
    }
}

/// The note being written, as red handwriting you can type into. Superwhisper pastes here too.
private struct NoteField: View {
    @Environment(ReviewStore.self) private var store
    let note: Note
    let shot: Shot
    let scale: CGFloat
    @FocusState private var focused: Bool
    @State private var pulse = false

    var body: some View {
        let m = Markup.metrics(for: shot.size)
        let measured = Markup.measure(note.text.isEmpty ? placeholder : note.text, font: m.handFont, width: m.noteWidth)
        let box = CGSize(width: max(measured.width, m.fontSize * 6), height: measured.height)
        let frame = Markup.place(box, beside: note.target, in: shot.size, gap: m.gap)
        let pad: CGFloat = 5

        VStack(alignment: .leading, spacing: 4) {
            TextField(placeholder, text: Binding(get: { note.text }, set: { store.typed($0) }), axis: .vertical)
                .textFieldStyle(.plain)
                .font(Font(Markup.handFont(m.fontSize * scale)))
                .foregroundStyle(Color(nsColor: Markup.pen))
                .focused($focused)
                .frame(width: frame.width * scale + 2, alignment: .leading)
                .onSubmit { store.commitNote() }
                .onExitCommand { store.commitNote() }
            if Markup.isLong(note) {
                Text("Long note. It goes under the image.")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(pad)
        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color(nsColor: Markup.pen).opacity(0.35)))
        .overlay(alignment: .topLeading) {
            if store.voice.isListening {
                Circle()
                    .fill(Color(nsColor: Markup.pen))
                    .frame(width: 8, height: 8)
                    .scaleEffect(pulse ? 1.25 : 0.8)
                    .opacity(pulse ? 1 : 0.55)
                    .offset(x: -3, y: -3)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }
                    }
                    .accessibilityLabel("Listening")
            }
        }
        .offset(x: frame.minX * scale - pad, y: frame.minY * scale - pad)
        .onAppear { focused = true }
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topLeading)))
    }

    private var placeholder: String {
        guard store.voice.isListening else { return "Type a note" }
        return store.voice.engine == .superwhisper ? "Superwhisper is listening…" : "Listening…"
    }
}
