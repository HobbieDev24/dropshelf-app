import SwiftUI
import AppKit

/// Wraps SwiftUI `content` in an AppKit view that starts a *native* dragging
/// session. SwiftUI's `.onDrag` can only ever advertise a copy, so it cannot
/// honor the ⌘-to-move modifier that Dropover (and Finder) use. By driving the
/// drag through `NSDraggingSource` we let the system map ⌘ → move, and we learn
/// the operation the destination actually performed via `endedAt:operation:`.
///
/// Reusable for a single item *or* a whole shelf: `urlsProvider` returns one URL
/// or many. `onMoveCompleted` fires only when the destination reported `.move`,
/// so the caller can drop those items from the shelf (the file itself is moved
/// by the destination — we never delete files ourselves).
struct FileDragSourceView<Content: View>: NSViewRepresentable {
    /// The file URLs to drag, evaluated lazily at drag-start.
    var urlsProvider: () -> [URL]
    /// Drag images, parallel to `urlsProvider()`. Missing entries fall back to
    /// the system file icon.
    var dragImagesProvider: () -> [NSImage]
    /// Called (main thread) with the dragged URLs when the drop was a move.
    var onMoveCompleted: ([URL]) -> Void
    /// Called on a click that did NOT turn into a drag (selection).
    var onSelect: (NSEvent.ModifierFlags) -> Void = { _ in }
    @ViewBuilder var content: () -> Content

    func makeNSView(context: Context) -> DragSourceHostView {
        let host = DragSourceHostView()
        host.urlsProvider = urlsProvider
        host.dragImagesProvider = dragImagesProvider
        host.onMoveCompleted = onMoveCompleted
        host.onSelect = onSelect

        let hosting = NSHostingView(rootView: AnyView(content()))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: host.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
        host.hosting = hosting
        return host
    }

    func updateNSView(_ nsView: DragSourceHostView, context: Context) {
        nsView.urlsProvider = urlsProvider
        nsView.dragImagesProvider = dragImagesProvider
        nsView.onMoveCompleted = onMoveCompleted
        nsView.onSelect = onSelect
        nsView.hosting?.rootView = AnyView(content())
    }
}

/// The AppKit backing view that hosts the SwiftUI tile and owns the whole mouse
/// sequence, so a single press-and-drag starts a drag immediately and a click
/// without movement selects. (Mixing an AppKit gesture recognizer with SwiftUI
/// tap gestures required a second click to drag — this avoids that entirely.)
final class DragSourceHostView: NSView, NSDraggingSource {
    var urlsProvider: (() -> [URL])?
    var dragImagesProvider: (() -> [NSImage])?
    var onMoveCompleted: (([URL]) -> Void)?
    var onSelect: ((NSEvent.ModifierFlags) -> Void)?
    var hosting: NSHostingView<AnyView>?

    private var mouseDownPoint: NSPoint?
    private var didDrag = false
    private var draggedURLs: [URL] = []
    private let dragThreshold: CGFloat = 4

    override var intrinsicContentSize: NSSize {
        hosting?.intrinsicContentSize ?? super.intrinsicContentSize
    }

    // The shelf panel is movable-by-background; without this, a drag starting on
    // a tile would move the whole window instead of dragging the file.
    override var mouseDownCanMoveWindow: Bool { false }

    // Allow a click to register even when the panel isn't key (non-activating).
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        didDrag = false
        // Don't call super: we own this interaction (prevents the window from
        // being dragged by its background from within a tile).
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint, !didDrag else { return }
        let dx = event.locationInWindow.x - start.x
        let dy = event.locationInWindow.y - start.y
        if (dx * dx + dy * dy) >= dragThreshold * dragThreshold {
            didDrag = true
            beginDrag(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownPoint = nil }
        // A press with no drag = selection click.
        if !didDrag {
            onSelect?(event.modifierFlags)
        }
    }

    private func beginDrag(with event: NSEvent) {
        guard let urls = urlsProvider?(), !urls.isEmpty else { return }
        draggedURLs = urls
        let images = dragImagesProvider?() ?? []
        let origin = convert(event.locationInWindow, from: nil)
        let side: CGFloat = 56

        var draggingItems: [NSDraggingItem] = []
        for (index, url) in urls.enumerated() {
            let dragItem = NSDraggingItem(pasteboardWriter: url as NSURL)
            let image = index < images.count
                ? images[index]
                : NSWorkspace.shared.icon(forFile: url.path)
            // Fan multiple items out into a small stack under the cursor.
            let offset = CGFloat(index) * 5
            let frame = NSRect(x: origin.x - side / 2 + offset,
                               y: origin.y - side / 2 - offset,
                               width: side, height: side)
            dragItem.setDraggingFrame(frame, contents: image)
            draggingItems.append(dragItem)
        }
        beginDraggingSession(with: draggingItems, event: event, source: self)
    }

    // MARK: NSDraggingSource

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        switch context {
        case .outsideApplication:
            // Dragging to Finder / other apps: copy by default, ⌘ = move.
            return NSEvent.modifierFlags.contains(.command) ? .move : .copy
        case .withinApplication:
            // Dragging around inside our own app (e.g. over the shelf itself)
            // must do nothing — no copy, so items never get duplicated.
            return []
        @unknown default:
            return .copy
        }
    }

    func draggingSession(_ session: NSDraggingSession,
                         endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        // The destination performs the move (incl. deleting the source file);
        // we just drop the now-moved items from the shelf UI.
        defer { draggedURLs = [] }
        guard operation == .move else { return }
        // Finder can report a move after transferring only part of a group.
        // Keep entries (and staged content) whose source still exists.
        let urls = draggedURLs
        let completion = onMoveCompleted
        // Finder may finish moving files after the drag session ends. Recheck
        // without deleting any source, and retain failed/unmoved entries.
        for delay in [0.0, 0.25, 1.0, 3.0, 10.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let moved = urls.filter { !FileManager.default.fileExists(atPath: $0.path) }
                if !moved.isEmpty { completion?(moved) }
            }
        }
    }
}
