import SwiftUI
import AppKit

// MARK: - ShareMenuButton

/// The "share" button in the header. Presents AirDrop / Copy. Operates on the
/// current selection when items are selected, otherwise on the whole shelf.
struct ShareMenuButton: View {
    @ObservedObject var shelf: ShelfModel
    weak var controller: ShelfWindowController?

    @State private var hovering = false

    /// What the actions apply to: the selection, or all items if none selected.
    private var targetURLs: [URL] { shelf.selectedOrAllURLs }

    private var scopeSuffix: String {
        let n = shelf.selectedItemIDs.count
        if n >= 1 && n < shelf.items.count {
            return n == 1 ? " (1 selected)" : " (\(n) selected)"
        }
        return ""
    }

    var body: some View {
        Menu {
            Button {
                AppCoordinator.shared?.togglePin(shelf)
            } label: {
                Label(shelf.pinned ? "Unpin Shelf" : "Pin Shelf",
                      systemImage: shelf.pinned ? "pin.slash" : "pin")
            }

            Button {
                ShareService.revealInFinder(targetURLs)
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
            .disabled(shelf.items.isEmpty)

            Button {
                let mode: ShelfViewMode = shelf.viewMode == .grid ? .list : .grid
                if let controller {
                    controller.setViewMode(mode)
                } else {
                    shelf.viewMode = mode
                    ShelfStore.shared.save()
                }
            } label: {
                Label(shelf.viewMode == .grid ? "List View" : "Grid View",
                      systemImage: shelf.viewMode == .grid ? "list.bullet" : "square.grid.2x2")
            }

            Divider()

            Button {
                ShareService.airDrop(targetURLs, anchor: controller?.window?.contentView)
            } label: {
                Label("AirDrop" + scopeSuffix, systemImage: "dot.radiowaves.left.and.right")
            }
            .disabled(shelf.items.isEmpty)

            Button {
                ShareService.presentSharePicker(targetURLs, anchor: controller?.window?.contentView)
            } label: {
                Label("More…", systemImage: "ellipsis")
            }
            .disabled(shelf.items.isEmpty)

            Divider()

            Button {
                IntakeService.ingestClipboard(into: shelf)
            } label: {
                Label("Add From Clipboard", systemImage: "doc.on.clipboard")
            }

            Button {
                ShareService.copyToClipboard(targetURLs)
            } label: {
                Label(copyLabel + scopeSuffix, systemImage: "doc.on.doc")
            }
            .disabled(shelf.items.isEmpty)

            Button {
                ShareService.moveToFolder(targetURLs) { movedURLs in
                    removeMovedItems(movedURLs)
                }
            } label: {
                Label("Move to…", systemImage: "folder.badge.arrow.forward")
            }
            .disabled(shelf.items.isEmpty)

            Divider()

            Button(role: .destructive) {
                withAnimation(Theme.surfaceMotion) { shelf.clear() }
                ShelfStore.shared.save()
            } label: {
                Label("Clear Shelf", systemImage: "clear")
            }
            .disabled(shelf.items.isEmpty)
        } label: {
            ZStack {
                Circle()
                    .fill(Theme.iconButtonBackground(hovering))
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(hovering ? 0.25 : 0.11), lineWidth: 0.5)
                    )
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 32, height: 32)
            .scaleEffect(hovering ? 1.04 : 1)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 32, height: 32)
        .onHover { isHovering in
            withAnimation(Theme.quickMotion) { hovering = isHovering }
        }
        .help("Shelf actions")
    }

    private var copyLabel: String {
        targetURLs.count == 1 ? "Copy File" : "Copy \(targetURLs.count) Files"
    }

    private func removeMovedItems(_ movedURLs: [URL]) {
        let moved = Set(movedURLs.map(\.standardizedFileURL))
        for item in shelf.items where moved.contains(item.url.standardizedFileURL) {
            shelf.remove(item)
        }
        ShelfStore.shared.save()
    }
}
