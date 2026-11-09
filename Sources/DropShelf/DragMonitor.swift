import Foundation
import AppKit

/// Shows a drop target after a shake during a fresh file-drag session.
final class DragMonitor {
    typealias Handler = (_ screenPoint: CGPoint, _ urls: [URL]) -> Void

    private let handler: Handler
    private var globalMouseDownMonitor: Any?
    private var globalMouseDragMonitor: Any?
    private var fileDrag = FileDragSession()
    private var globalMouseUpMonitor: Any?
    private var zoneController: DropZoneController?
    private var isShowingZones = false

    init(handler: @escaping Handler) {
        self.handler = handler
        self.zoneController = DropZoneController { [weak self] point, urls in
            self?.handler(point, urls)
            self?.hideZones()
        }
    }

    func start() {
        guard Preferences.shared.dropZonesEnabled, globalMouseDownMonitor == nil else { return }

        // The drag pasteboard survives mouse-up. Snapshot its generation before
        // this gesture so old file data cannot turn a selection rectangle into
        // a file drag.
        globalMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            self?.fileDrag.begin(changeCount: NSPasteboard(name: .drag).changeCount)
            self?.shake.reset()
        }

        // Detect dragging: left mouse dragged anywhere on screen.
        globalMouseDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
            self?.handleDrag(event)
        }
        globalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            self?.fileDrag.end()
            self?.shake.reset()
            // Delay hide slightly so a drop onto a zone window can register.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                self?.hideZones()
            }
        }
    }

    func stop() {
        if let m = globalMouseDownMonitor { NSEvent.removeMonitor(m) }
        globalMouseDownMonitor = nil
        fileDrag.end()
        if let m = globalMouseDragMonitor { NSEvent.removeMonitor(m) }
        if let m = globalMouseUpMonitor { NSEvent.removeMonitor(m) }
        globalMouseDragMonitor = nil
        globalMouseUpMonitor = nil
        shake.reset()
        hideZones()
    }

    private var shake = ShakeDetector()

    private func handleDrag(_ event: NSEvent) {
        guard Preferences.shared.dropZonesEnabled else { return }
        if isShowingZones { return }
        // Dropover-style trigger: the user must *shake* the dragged files
        // (rapid back-and-forth) to summon the zones, so ordinary drags — text
        // selection, moving a window, sliding an icon — never flash them.
        if shake.add(deltaX: event.deltaX, timestamp: event.timestamp) {
            // Only summon the zones when the active drag actually carries files.
            // A text/object selection in another app (e.g. Affinity) doesn't put
            // file URLs on the drag pasteboard, so we ignore it.
            guard fileDrag.containsFiles(on: NSPasteboard(name: .drag)) else {
                shake.reset()
                return
            }
            showZones()
        }
    }

    private func showZones() {
        isShowingZones = true
        shake.reset()
        zoneController?.show()
    }

    private func hideZones() {
        guard isShowingZones else { return }
        isShowingZones = false
        zoneController?.hide()
    }
}

/// A file drag must publish a new payload after the current mouse-down.
/// Merely finding file types on the persistent drag pasteboard is insufficient.
struct FileDragSession {
    private var initialChangeCount: Int?

    mutating func begin(changeCount: Int) {
        initialChangeCount = changeCount
    }

    mutating func end() {
        initialChangeCount = nil
    }

    func containsFiles(on pasteboard: NSPasteboard) -> Bool {
        guard let initialChangeCount,
              pasteboard.changeCount != initialChangeCount else { return false }
        return !Self.fileURLs(on: pasteboard).isEmpty
    }

    static func fileURLs(on pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
        return urls.filter {
            $0.isFileURL &&
            !["webloc", "inetloc", "url"].contains($0.pathExtension.lowercased()) &&
            FileManager.default.fileExists(atPath: $0.path)
        }
    }
}

/// Detects a "shake" gesture from a stream of horizontal mouse deltas: several
/// quick direction reversals, each preceded by a minimum travel, all within a
/// short sliding time window. Tuned to feel like Dropover's shake-to-summon.
private struct ShakeDetector {
    // Tunables.
    private let minSegmentDistance: CGFloat = 10   // px in one direction to count a stroke
    private let requiredReversals = 3              // direction flips needed to qualify
    private let windowDuration: TimeInterval = 0.5 // reversals must fall within this span

    private var lastDirection = 0                  // -1, 0, +1
    private var accumulatedSinceReversal: CGFloat = 0
    private var reversalTimestamps: [TimeInterval] = []

    /// Feeds one drag sample. Returns true once a shake is recognized.
    mutating func add(deltaX: CGFloat, timestamp: TimeInterval) -> Bool {
        let dir = deltaX > 0 ? 1 : (deltaX < 0 ? -1 : 0)
        guard dir != 0 else { return false }

        if lastDirection == 0 || dir == lastDirection {
            accumulatedSinceReversal += abs(deltaX)
            lastDirection = dir
            return false
        }

        // Direction just reversed — count it only if the prior stroke was long
        // enough to be a deliberate shake, not jitter.
        if accumulatedSinceReversal >= minSegmentDistance {
            reversalTimestamps.append(timestamp)
            reversalTimestamps.removeAll { timestamp - $0 > windowDuration }
        }
        lastDirection = dir
        accumulatedSinceReversal = abs(deltaX)
        return reversalTimestamps.count >= requiredReversals
    }

    mutating func reset() {
        lastDirection = 0
        accumulatedSinceReversal = 0
        reversalTimestamps.removeAll()
    }
}
