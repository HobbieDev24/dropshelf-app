import Foundation
import AppKit

/// Detects a system-wide file drag and shows "drop zone" targets near the
/// screen edge. When the user drops files on a zone, the callback fires with
/// the landing point and the dragged file URLs.
///
/// macOS does not expose global drag *contents* to other apps for security
/// reasons, so we use a two-part strategy:
///   1. While the left mouse button is down and moving, we show drop zones.
///   2. The drop zones themselves are real drag-and-drop NSWindows that accept
///      `.fileURL`, so when the user releases over one we read the pasteboard.
final class DragMonitor {
    typealias Handler = (_ screenPoint: CGPoint, _ urls: [URL]) -> Void

    private let handler: Handler
    private var globalMouseDragMonitor: Any?
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
        guard Preferences.shared.dropZonesEnabled else { return }

        // Detect dragging: left mouse dragged anywhere on screen.
        globalMouseDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
            self?.handleDrag(event)
        }
        globalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            self?.shake.reset()
            // Delay hide slightly so a drop onto a zone window can register.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                self?.hideZones()
            }
        }
    }

    func stop() {
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
            guard Self.dragHasFiles() else {
                shake.reset()
                return
            }
            showZones()
        }
    }

    /// True when the current system drag pasteboard contains at least one file URL.
    private static func dragHasFiles() -> Bool {
        let pb = NSPasteboard(name: .drag)
        guard let types = pb.types else { return false }
        // Fast path: the fileURL/filenames types are present.
        if types.contains(.fileURL) || types.contains(NSPasteboard.PasteboardType("NSFilenamesPboardType")) {
            return true
        }
        // Fallback: actually try to read file URLs.
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: opts) as? [URL],
           urls.contains(where: { $0.isFileURL }) {
            return true
        }
        return false
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
