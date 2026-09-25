import AppKit

/// One screenshot under review. Everything is in the image's pixel space, top-left origin,
/// so marks export at full resolution and survive any window size.
struct Shot: Identifiable {
    let id = UUID()
    var name: String
    var image: CGImage
    var marks: [Mark] = []
    var notes: [Note] = []
    /// Earlier states of `marks` and `notes`, for undo.
    var history: [Snapshot] = []

    var size: CGSize { CGSize(width: image.width, height: image.height) }
    var hasMarkup: Bool { !marks.isEmpty || notes.contains { !$0.isEmpty } }

    struct Snapshot {
        var marks: [Mark]
        var notes: [Note]
    }

    mutating func checkpoint() {
        history.append(Snapshot(marks: marks, notes: notes))
        if history.count > 100 { history.removeFirst() }
    }

    mutating func undo() -> Bool {
        guard let last = history.popLast() else { return false }
        marks = last.marks
        notes = last.notes
        return true
    }
}

struct Mark: Identifiable, Equatable {
    let id = UUID()
    var ink: Ink

    var bounds: CGRect { ink.path.boundingBoxOfPath }
}

/// A note written beside a circle, or where you clicked.
struct Note: Identifiable, Equatable {
    let id = UUID()
    /// The circle's bounds, or a zero-size rect at the click point.
    var target: CGRect
    var text = ""

    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var isPinned: Bool { target.width == 0 && target.height == 0 }
}
