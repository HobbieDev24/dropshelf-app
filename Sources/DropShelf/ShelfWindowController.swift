import Foundation
import AppKit
import SwiftUI
import Quartz

/// A borderless floating panel that hosts one shelf's SwiftUI view.
/// Uses NSPanel with `.nonactivatingPanel` so interacting with it doesn't
/// steal focus from the user's current app — matching a utility-shelf feel.
final class ShelfWindowController: NSObject {
    let shelf: ShelfModel
    private(set) weak var coordinator: AppCoordinator?
    var window: ShelfPanel?

    private var hostingView: MovableHostingView<ShelfRootView>?
    private lazy var quickLook = ShelfQuickLook(shelf: shelf)

    // Layout constants
    static let width: CGFloat = 204
    static let collapsedHeight: CGFloat = 212
    static let expandedHeight: CGFloat = 410

    init(shelf: ShelfModel, coordinator: AppCoordinator) {
        self.shelf = shelf
        self.coordinator = coordinator
        super.init()
        build()
    }

    private func build() {
        let initialWidth = shelf.viewMode == .list ? 380 : Self.width
        let panel = ShelfPanel(
            contentRect: NSRect(x: 0, y: 0, width: initialWidth, height: Self.collapsedHeight),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // Let AppKit derive the shadow from the clipped transparent content.
        // A SwiftUI shadow is clipped to the rectangular window buffer and was
        // responsible for the visible underline outside the rounded corners.
        panel.hasShadow = true
        // Drag the whole panel from any inert area (header background, padding).
        // Buttons and the tap-to-edit title remain interactive.
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.minSize = NSSize(width: Self.width, height: Self.collapsedHeight)
        panel.maxSize = NSSize(width: 720, height: 820)
        panel.delegate = self
        panel.quickLook = quickLook

        let root = ShelfRootView(
            shelf: shelf,
            controller: self
        )
        let hosting = MovableHostingView(rootView: root)
        hosting.onFileDrop = { [weak shelf] urls in
            shelf?.addURLs(urls)
            ShelfStore.shared.save()

        }
        hosting.registerForDraggedTypes([.fileURL])
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.layer?.isOpaque = false
        hosting.translatesAutoresizingMaskIntoConstraints = false

        // Clip at the native AppKit boundary. SwiftUI clipping alone cannot
        // reliably mask NSVisualEffectView, which caused square backing pixels
        // to remain visible around the shelf's continuous corners.
        let container = ShelfContentContainerView(cornerRadius: Theme.cornerRadius)
        container.embed(hosting)
        panel.contentView = container
        self.hostingView = hosting
        self.window = panel
    }

    // MARK: - Positioning

    private func defaultOrigin() -> CGPoint {
        // Center of the main screen.
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let visible = screen.visibleFrame
        let size = window?.frame.size ?? NSSize(width: Self.width, height: Self.collapsedHeight)
        let x = visible.midX - size.width / 2
        let y = visible.midY - size.height / 2
        return CGPoint(x: x, y: y)
    }

    func showAndFocus(animate: Bool) {
        guard let window else { return }
        let origin = shelf.lastOrigin ?? defaultOrigin()
        window.setFrameOrigin(clampToScreen(origin, size: window.frame.size))

        if animate {
            window.alphaValue = 0
            window.makeKeyAndOrderFront(nil)
            window.invalidateShadow()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.24
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.72, 0.18, 1.0)
                window.animator().alphaValue = 1
            }
            animateContentScale(from: 0.97, to: 1.0, duration: 0.28)
        } else {
            window.alphaValue = 1
            window.orderFront(nil)
            window.invalidateShadow()
        }
    }

    private func animateContentScale(from: CGFloat, to: CGFloat, duration: CFTimeInterval) {
        guard let layer = hostingView?.layer ?? window?.contentView?.layer else { return }
        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.72, 0.18, 1.0)
        layer.add(animation, forKey: "shelfContentScale")
    }

    func closeWithAnimation(_ completion: @escaping () -> Void) {
        guard let window else { completion(); return }
        // Remember last position before closing.
        shelf.lastOrigin = window.frame.origin
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.42, 0.0, 0.58, 1.0)
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
            completion()
        })
    }

    // MARK: - Resize for expand/collapse

    func setExpanded(_ expanded: Bool) {
        guard let window else { return }
        let targetHeight = expanded ? Self.expandedHeight : Self.collapsedHeight
        var frame = window.frame
        let delta = targetHeight - frame.size.height
        // Grow downward by keeping the top edge fixed.
        frame.origin.y -= delta
        frame.size.height = targetHeight
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.72, 0.18, 1.0)
            window.animator().setFrame(clampedFrame(frame), display: true)
        }
    }

    /// Give list rows enough horizontal room while preserving the window's
    /// center. The user can continue resizing from any panel edge afterward.
    func setViewMode(_ mode: ShelfViewMode) {
        guard let window else { return }
        shelf.viewMode = mode
        ShelfStore.shared.save()

        let targetWidth: CGFloat = mode == .list ? 380 : Self.width
        guard abs(window.frame.width - targetWidth) > 0.5 else { return }
        var frame = window.frame
        let centerX = frame.midX
        frame.size.width = targetWidth
        frame.origin.x = centerX - targetWidth / 2

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.26
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.72, 0.18, 1.0)
            window.animator().setFrame(clampedFrame(frame), display: true)
        }
    }

    // MARK: - Dragging the window from the header

    func persistPosition() {
        guard let window else { return }
        shelf.lastOrigin = window.frame.origin
        ShelfStore.shared.save()
    }

    // MARK: - Screen clamping

    private func clampToScreen(_ origin: CGPoint, size: CGSize) -> CGPoint {
        let screen = screenContaining(origin) ?? NSScreen.main ?? NSScreen.screens[0]
        let v = screen.visibleFrame
        var x = origin.x
        var y = origin.y
        x = min(max(x, v.minX), v.maxX - size.width)
        y = min(max(y, v.minY), v.maxY - size.height)
        return CGPoint(x: x, y: y)
    }

    private func clampedFrame(_ frame: NSRect) -> NSRect {
        var f = frame
        let origin = clampToScreen(f.origin, size: f.size)
        f.origin = origin
        return f
    }

    private func screenContaining(_ point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }
}

/// A hosting view whose otherwise-inert regions participate in native window
/// movement. Interactive descendants (buttons and file drag sources) still
/// receive their own mouse events.
final class MovableHostingView<Content: View>: NSHostingView<Content> {
    var onFileDrop: (([URL]) -> Void)?
    override var mouseDownCanMoveWindow: Bool { true }

    private func fileURLs(_ sender: NSDraggingInfo) -> [URL] {
        sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        fileURLs(sender).isEmpty ? super.draggingEntered(sender) : .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        fileURLs(sender).isEmpty ? super.draggingUpdated(sender) : .copy
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !fileURLs(sender).isEmpty || super.prepareForDragOperation(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(sender)
        guard !urls.isEmpty else { return super.performDragOperation(sender) }
        onFileDrop?(urls)
        return true
    }
}

/// Transparent window content with a native rounded clipping boundary.
/// Keeping the mask in AppKit clips both SwiftUI and embedded vibrancy views.
final class ShelfContentContainerView: NSView {
    private let clippedContent = NSView()

    init(cornerRadius: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        clippedContent.translatesAutoresizingMaskIntoConstraints = false
        clippedContent.wantsLayer = true
        clippedContent.layer?.backgroundColor = NSColor.clear.cgColor
        clippedContent.layer?.cornerRadius = cornerRadius
        clippedContent.layer?.cornerCurve = .continuous
        clippedContent.layer?.masksToBounds = true
        addSubview(clippedContent)

        NSLayoutConstraint.activate([
            clippedContent.leadingAnchor.constraint(equalTo: leadingAnchor),
            clippedContent.trailingAnchor.constraint(equalTo: trailingAnchor),
            clippedContent.topAnchor.constraint(equalTo: topAnchor),
            clippedContent.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

    }

    required init?(coder: NSCoder) { nil }

    // The explicit header drag surface moves the panel. Returning false here
    // keeps AppKit from claiming perimeter events before resize strips see them.
    override var mouseDownCanMoveWindow: Bool { false }

    func embed(_ view: NSView) {
        clippedContent.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: clippedContent.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: clippedContent.trailingAnchor),
            view.topAnchor.constraint(equalTo: clippedContent.topAnchor),
            view.bottomAnchor.constraint(equalTo: clippedContent.bottomAnchor),
        ])
    }
}

/// A dedicated transparent hit strip for one edge of the borderless panel.
/// Separate views are used because a full-window overlay is routed through the
/// SwiftUI host before AppKit can resolve its custom hit test.
final class ShelfEdgeResizeView: NSView {
    enum Edge { case left, right, top, bottom }
    private let edge: Edge
    private var startPoint: NSPoint = .zero
    private var startFrame: NSRect = .zero

    init(edge: Edge) {
        self.edge = edge
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds,
                      cursor: edge == .left || edge == .right ? .resizeLeftRight : .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        startPoint = NSEvent.mouseLocation
        startFrame = window.frame
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - startPoint.x
        let dy = current.y - startPoint.y
        var frame = startFrame

        if edge == .left {
            frame.origin.x += dx
            frame.size.width -= dx
        } else if edge == .right {
            frame.size.width += dx
        }
        if edge == .bottom {
            frame.origin.y += dy
            frame.size.height -= dy
        } else if edge == .top {
            frame.size.height += dy
        }

        let minSize = window.minSize
        let maxSize = window.maxSize
        if frame.width < minSize.width {
            if edge == .left { frame.origin.x = startFrame.maxX - minSize.width }
            frame.size.width = minSize.width
        }
        if frame.height < minSize.height {
            if edge == .bottom { frame.origin.y = startFrame.maxY - minSize.height }
            frame.size.height = minSize.height
        }
        frame.size.width = min(frame.width, maxSize.width)
        frame.size.height = min(frame.height, maxSize.height)

        window.setFrame(frame, display: true)
        window.invalidateShadow()
    }
}

/// NSPanel subclass that can become key (needed for text editing of the title)
/// but never becomes main.
final class ShelfPanel: NSPanel {
    /// QuickLook data source/delegate for the shelf this panel hosts.
    weak var quickLook: ShelfQuickLook?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        // Spacebar toggles QuickLook for the shelf's items (Dropover/Finder feel).
        if event.charactersIgnoringModifiers == " " {
            togglePreviewPanel()
            return
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // ⌘A selects all items; ⌘⇧A (or Esc) clears the selection.
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "a",
           let shelf = quickLook?.shelf {
            if event.modifierFlags.contains(.shift) {
                shelf.deselectAll()
            } else {
                shelf.selectAll()
            }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private func togglePreviewPanel() {
        guard let panel = QLPreviewPanel.shared() else { return }
        if QLPreviewPanel.sharedPreviewPanelExists() && panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: QLPreviewPanelController (responder chain)

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        (quickLook?.shelf?.items.isEmpty == false)
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = quickLook
        panel.delegate = quickLook
        panel.reloadData()
        if let index = quickLook?.preferredIndex {
            panel.currentPreviewItemIndex = index
        }
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }
}

// MARK: - NSWindowDelegate

extension ShelfWindowController: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        // Persist the new origin after the user drags the panel.
        guard let window else { return }
        shelf.lastOrigin = window.frame.origin
    }

    func windowWillClose(_ notification: Notification) {
        persistPosition()
    }
}
