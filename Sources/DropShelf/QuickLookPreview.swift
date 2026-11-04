import AppKit
import Quartz

/// Bridges a shelf's items to a shared `QLPreviewPanel`. Set as the panel's
/// data source + delegate while a shelf window controls QuickLook. Pressing the
/// spacebar over a shelf opens this; space/Esc (handled by QuickLook itself)
/// dismisses it, and the arrow keys page through every file on the shelf.
final class ShelfQuickLook: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    weak var shelf: ShelfModel?

    init(shelf: ShelfModel) {
        self.shelf = shelf
        super.init()
    }

    /// Index of the first selected item, or 0 when nothing is selected.
    var preferredIndex: Int {
        guard let shelf else { return 0 }
        if let idx = shelf.items.firstIndex(where: { shelf.selectedItemIDs.contains($0.id) }) {
            return idx
        }
        return 0
    }

    // MARK: QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        shelf?.items.count ?? 0
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard let shelf, index >= 0, index < shelf.items.count else { return nil }
        // NSURL conforms to QLPreviewItem.
        return shelf.items[index].url as NSURL
    }

    // MARK: QLPreviewPanelDelegate

    /// Let key events (esp. space to dismiss, arrows to page) behave naturally.
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        false
    }
}
