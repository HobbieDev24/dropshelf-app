import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Scrollable grid or list of item cells, depending on `shelf.viewMode`.
struct ShelfBodyView: View {
    @ObservedObject var shelf: ShelfModel
    weak var controller: ShelfWindowController?
    let expanded: Bool

    private let columns = [
        GridItem(.fixed(78), spacing: 10),
        GridItem(.fixed(78), spacing: 10)
    ]

    private var visibleItems: [ShelfItem] {
        expanded ? shelf.items : Array(shelf.items.prefix(2))
    }

    var body: some View {
        if shelf.items.isEmpty {
            EmptyShelfView()
        } else if !expanded && shelf.viewMode == .grid {
            CollapsedShelfStack(shelf: shelf)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                ZStack(alignment: .top) {
                    if shelf.viewMode == .grid {
                        gridContent
                            .transition(.opacity)
                    } else {
                        listContent
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity)
                .animation(.easeInOut(duration: 0.22), value: shelf.viewMode)
            }
            // Click empty space to clear selection.
            .background(
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { shelf.selectedItemIDs = [] }
            )
        }
    }

    private var gridContent: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(visibleItems) { item in
                ShelfItemCell(item: item, shelf: shelf)
                    .frame(width: 78, height: 100)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var listContent: some View {
        LazyVStack(spacing: 2) {
            ForEach(visibleItems) { item in
                ShelfItemCell(item: item, shelf: shelf)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// Dropover-style compact preview: files read as one tactile stack instead of
/// separate mini grid cells. Expanding the count capsule reveals item details.
private struct CollapsedShelfStack: View {
    @ObservedObject var shelf: ShelfModel

    private var previewItems: [ShelfItem] { Array(shelf.items.prefix(3)) }
    private var allURLs: [URL] { shelf.items.map(\.url) }

    var body: some View {
        FileDragSourceView(
            urlsProvider: { allURLs },
            dragImagesProvider: {
                shelf.items.map {
                    $0.thumbnail ?? ThumbnailService.shared.icon(for: $0.url,
                                                                  size: CGSize(width: 72, height: 82))
                }
            },
            onMoveCompleted: removeMoved
        ) {
            ZStack {
                ForEach(Array(previewItems.enumerated()), id: \.element.id) { index, item in
                    StackPreviewCard(item: item)
                        .rotationEffect(.degrees(rotation(for: index)))
                        .offset(x: xOffset(for: index), y: yOffset(for: index))
                        .zIndex(Double(previewItems.count - index))
                }
            }
            .frame(width: 104, height: 104)
            .contentShape(Rectangle())
        }
        .frame(width: 104, height: 104)
        .help("Drag all files")
    }

    private func rotation(for index: Int) -> Double {
        switch index { case 1: return -5; case 2: return 5; default: return 0 }
    }

    private func xOffset(for index: Int) -> CGFloat {
        switch index { case 1: return -5; case 2: return 5; default: return 2 }
    }

    private func yOffset(for index: Int) -> CGFloat { CGFloat(index) * -2 }

    private func removeMoved(_ urls: [URL]) {
        let moved = Set(urls.map(\.standardizedFileURL))
        for item in shelf.items where moved.contains(item.url.standardizedFileURL) {
            shelf.remove(item)
        }
        ShelfStore.shared.save()
    }
}

private struct StackPreviewCard: View {
    @ObservedObject var item: ShelfItem

    var body: some View {
        Group {
            if let image = item.thumbnail {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.secondary)
                    .padding(15)
            }
        }
        .frame(width: 78, height: 88)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
        )
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.white.opacity(0.65), lineWidth: 0.6)
        )
        .shadow(color: .black.opacity(0.22), radius: 5, y: 3)
        .onAppear { item.loadThumbnailIfNeeded() }
    }
}

struct EmptyShelfView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.accent.opacity(0.8))
            Text("Drop files here")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

/// A single item, rendered as a grid tile or a list row. Supports drag-out
/// (honoring multi-selection + ⌘-move), selection, and a context menu.
struct ShelfItemCell: View {
    @ObservedObject var item: ShelfItem
    @ObservedObject var shelf: ShelfModel

    @State private var hovering = false

    private var isSelected: Bool { shelf.isSelected(item) }

    /// URLs this drag should carry: the whole selection if the dragged item is
    /// part of a multi-selection, otherwise just this item.
    private func dragURLs() -> [URL] {
        if isSelected && shelf.selectedItemIDs.count > 1 {
            return shelf.items.filter { shelf.selectedItemIDs.contains($0.id) }.map { $0.url }
        }
        return [item.url]
    }

    private func dragImages() -> [NSImage] {
        let urls = dragURLs()
        return urls.map { url in
            if url == item.url, let thumb = item.thumbnail { return thumb }
            return ThumbnailService.shared.icon(for: url, size: CGSize(width: 56, height: 56))
        }
    }

    private func removeMoved(_ urls: [URL]) {
        let moved = Set(urls.map { $0.standardizedFileURL })
        withAnimation(.easeOut(duration: 0.15)) {
            for victim in shelf.items where moved.contains(victim.url.standardizedFileURL) {
                shelf.remove(victim)
            }
        }
        ShelfStore.shared.save()
    }

    var body: some View {
        FileDragSourceView(
            urlsProvider: dragURLs,
            dragImagesProvider: dragImages,
            onMoveCompleted: removeMoved,
            onSelect: { modifiers in shelf.select(item, modifiers: modifiers) }
        ) {
            Group {
                switch shelf.viewMode {
                case .grid: gridTile
                case .list: listRow
                }
            }
        }
        .contextMenu { contextMenu }
    }

    @ViewBuilder
    private var contextMenu: some View {
        // When the right-clicked item is part of a multi-selection, actions
        // apply to the whole selection; otherwise just this item.
        let multi = isSelected && shelf.selectedItemIDs.count > 1
        let urls = multi ? shelf.items.filter { shelf.selectedItemIDs.contains($0.id) }.map { $0.url }
                         : [item.url]

        if multi {
            Button("Reveal \(urls.count) in Finder") { ShareService.revealInFinder(urls) }
            Button("Copy \(urls.count) Files") { ShareService.copyToClipboard(urls) }
            Divider()
            Button("Remove \(urls.count) from Shelf", role: .destructive) {
                shelf.removeSelected()
                ShelfStore.shared.save()
            }
        } else {
            Button("Open") { ShareService.open(item.url) }
            Button("Reveal in Finder") { ShareService.revealInFinder([item.url]) }
            Button("Copy") { ShareService.copyToClipboard([item.url]) }
            Divider()
            Button("Remove from Shelf", role: .destructive) {
                shelf.remove(item)
                ShelfStore.shared.save()
            }
        }
    }

    // MARK: Grid tile

    private var gridTile: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                thumbnail
                    .frame(width: 66, height: 66)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.itemCorner, style: .continuous)
                            .fill(isSelected ? Theme.accent.opacity(0.18) : Color.primary.opacity(0.06))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Theme.itemCorner, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.itemCorner, style: .continuous)
                            .strokeBorder(isSelected ? Theme.accent : Color.white.opacity(0.08),
                                          lineWidth: isSelected ? 2 : 0.5)
                    )

                if hovering { removeButton.offset(x: 6, y: -6) }
            }

            Text(item.displayName)
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
                .frame(width: 82)
                .foregroundStyle(item.fileExists ? Color.primary : Color.secondary)
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: Theme.itemCorner + 2, style: .continuous)
                .fill(isSelected ? Theme.accent.opacity(0.24)
                     : (hovering ? Color.white.opacity(0.08) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.itemCorner + 2, style: .continuous)
                .strokeBorder(isSelected ? Theme.accent.opacity(0.85)
                              : Color.white.opacity(hovering ? 0.18 : 0),
                              lineWidth: isSelected ? 1.25 : 0.5)
        )
        .opacity(item.fileExists ? 1 : 0.5)
        .scaleEffect(hovering ? 1.015 : 1.0)
        .shadow(color: .black.opacity(hovering ? 0.18 : 0), radius: 6, y: 3)
        .onHover { isHovering in withAnimation(Theme.quickMotion) { hovering = isHovering } }
        .animation(Theme.quickMotion, value: isSelected)
        .onAppear { item.loadThumbnailIfNeeded() }
        .help(item.url.path)
        .contentShape(Rectangle())
    }

    // MARK: List row

    private var listRow: some View {
        HStack(spacing: 8) {
            thumbnail
                .frame(width: 24, height: 24)

            Text(item.displayName)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(item.fileExists ? Color.primary : Color.secondary)

            Spacer(minLength: 4)

            if let size = item.sizeString {
                Text(size)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            if hovering { removeButton }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: Theme.itemCorner, style: .continuous)
                .fill(isSelected ? Theme.accent.opacity(0.24)
                                 : (hovering ? Color.white.opacity(0.08) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.itemCorner, style: .continuous)
                .strokeBorder(isSelected ? Theme.accent.opacity(0.80)
                              : Color.white.opacity(hovering ? 0.16 : 0),
                              lineWidth: isSelected ? 1.25 : 0.5)
        )
        .opacity(item.fileExists ? 1 : 0.5)
        .onHover { isHovering in withAnimation(Theme.quickMotion) { hovering = isHovering } }
        .animation(Theme.quickMotion, value: isSelected)
        .onAppear { item.loadThumbnailIfNeeded() }
        .help(item.url.path)
        .contentShape(Rectangle())
    }

    // MARK: Shared pieces

    private var removeButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { shelf.remove(item) }
            ShelfStore.shared.save()
        } label: {
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(.white, .red)
                .background(Circle().fill(.white).padding(3))
        }
        .buttonStyle(.plain)
        .help("Remove from shelf")
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = item.thumbnail {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(shelf.viewMode == .grid ? 4 : 0)
        } else {
            Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                .font(.system(size: shelf.viewMode == .grid ? 24 : 16))
                .foregroundStyle(.secondary)
        }
    }
}
