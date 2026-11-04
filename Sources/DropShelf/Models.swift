import Foundation
import AppKit
import Combine

// MARK: - View mode

/// How a shelf lays out its items.
enum ShelfViewMode: String, Codable {
    case grid
    case list
}

// MARK: - ShelfItem

/// A single file/folder living on a shelf. Reference type so a list cell can
/// observe asynchronous thumbnail loading.
final class ShelfItem: ObservableObject, Identifiable, Hashable {
    let id: UUID
    @Published var url: URL
    @Published var thumbnail: NSImage?
    @Published var isLoadingThumbnail: Bool = false
    /// True when the app materialized this item into its staging folder (a
    /// dropped text snippet or image). Such files are owned by the
    /// app and are cleaned up when removed / when the shelf is closed.
    let isStaged: Bool

    init(id: UUID = UUID(), url: URL, isStaged: Bool = false) {
        self.id = id
        self.url = url
        self.isStaged = isStaged
    }

    var displayName: String { url.lastPathComponent }

    var isDirectory: Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }

    var fileExists: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// Human-readable size, or nil for directories / unknown.
    var sizeString: String? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let bytes = values.fileSize else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    func loadThumbnailIfNeeded(size: CGSize = CGSize(width: 80, height: 80)) {
        guard thumbnail == nil, !isLoadingThumbnail else { return }
        isLoadingThumbnail = true
        ThumbnailService.shared.generate(for: url, size: size) { [weak self] image in
            guard let self else { return }
            self.thumbnail = image
            self.isLoadingThumbnail = false
        }
    }

    static func == (lhs: ShelfItem, rhs: ShelfItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - ShelfModel

/// A shelf: an ordered collection of items shown in one floating window.
final class ShelfModel: ObservableObject, Identifiable {
    let id: UUID
    let createdAt: Date
    @Published var title: String
    @Published var items: [ShelfItem]
    @Published var pinned: Bool
    /// Selected items (for spacebar QuickLook & multi-item actions). Not persisted.
    @Published var selectedItemIDs: Set<UUID> = []
    /// Anchor for shift-range selection. Not persisted.
    var selectionAnchorID: UUID?
    /// Grid (default) vs list presentation.
    @Published var viewMode: ShelfViewMode = .grid
    /// Last on-screen origin (bottom-left, screen coords) so reopened/pinned
    /// shelves return to where the user left them.
    @Published var lastOrigin: CGPoint?

    init(id: UUID = UUID(),
         createdAt: Date = Date(),
         title: String = "",
         items: [ShelfItem] = [],
         pinned: Bool = false,
         lastOrigin: CGPoint? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.items = items
        self.pinned = pinned
        self.lastOrigin = lastOrigin
    }

    var isEmpty: Bool { items.isEmpty }

    /// A friendly title for menus/labels.
    var effectiveTitle: String {
        if !title.isEmpty { return title }
        switch items.count {
        case 0: return "Empty Shelf"
        case 1: return items[0].displayName
        default: return "\(items.count) items"
        }
    }

    @discardableResult
    func addURLs(_ urls: [URL]) -> Int {
        var existing = Set(items.map { $0.url.standardizedFileURL })
        var added = 0
        for url in urls {
            let std = url.standardizedFileURL
            guard std.isFileURL,
                  !["webloc", "inetloc", "url"].contains(std.pathExtension.lowercased()),
                  existing.insert(std).inserted else { continue }
            items.append(ShelfItem(url: std))
            added += 1
        }
        return added
    }

    /// Append an item the app materialized into its staging folder.
    func addStagedItem(at url: URL) {
        items.append(ShelfItem(url: url.standardizedFileURL, isStaged: true))
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        selectedItemIDs.remove(item.id)
        // A staged item's backing file is owned by the app — delete it.
        if item.isStaged {
            IntakeService.removeStagedFile(item.url, shelfID: id)
        }
    }

    func removeSelected() {
        let chosen = items.filter { selectedItemIDs.contains($0.id) }
        for item in chosen { remove(item) }
    }

    /// Empty the shelf without touching files that merely live at their
    /// original locations. App-owned staged items are cleaned up normally.
    func clear() {
        for item in items { remove(item) }
        selectionAnchorID = nil
    }

    /// Delete every staged file backing this shelf (used on close/cleanup).
    func purgeStagedFiles() {
        for item in items where item.isStaged {
            IntakeService.removeStagedFile(item.url, shelfID: id)
        }
    }

    // MARK: Selection

    func isSelected(_ item: ShelfItem) -> Bool { selectedItemIDs.contains(item.id) }

    /// Select every item (⌘A).
    func selectAll() {
        selectedItemIDs = Set(items.map { $0.id })
        selectionAnchorID = items.first?.id
    }

    /// Clear the selection.
    func deselectAll() {
        selectedItemIDs = []
    }

    /// Click selection honoring ⌘ (toggle) and ⇧ (range from anchor).
    func select(_ item: ShelfItem, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            if selectedItemIDs.contains(item.id) {
                selectedItemIDs.remove(item.id)
            } else {
                selectedItemIDs.insert(item.id)
                selectionAnchorID = item.id
            }
        } else if modifiers.contains(.shift),
                  let anchorID = selectionAnchorID,
                  let a = items.firstIndex(where: { $0.id == anchorID }),
                  let b = items.firstIndex(where: { $0.id == item.id }) {
            let range = a <= b ? a...b : b...a
            selectedItemIDs.formUnion(items[range].map { $0.id })
        } else {
            // Plain click: toggle a single selection.
            if selectedItemIDs == [item.id] {
                selectedItemIDs = []
            } else {
                selectedItemIDs = [item.id]
            }
            selectionAnchorID = item.id
        }
    }

    /// URLs of selected items, or all items when nothing is selected.
    var selectedOrAllURLs: [URL] {
        let chosen = items.filter { selectedItemIDs.contains($0.id) }
        return (chosen.isEmpty ? items : chosen).map { $0.url }
    }

    var fileURLs: [URL] { items.map { $0.url } }
}

// MARK: - Codable persistence records

private struct ShelfItemRecord: Codable {
    let id: UUID
    let path: String
    var isStaged: Bool? = nil
}

private struct ShelfRecord: Codable {
    let id: UUID
    let createdAt: Date
    let title: String
    let pinned: Bool
    let items: [ShelfItemRecord]
    let originX: Double?
    let originY: Double?
    var viewMode: String? = nil
}

// MARK: - ShelfStore

/// Owns the list of shelves and persists pinned ones to disk.
final class ShelfStore: ObservableObject {
    static let shared = ShelfStore()

    @Published private(set) var shelves: [ShelfModel] = []
    /// The last few shelves closed via "X" (most-recent first). In-memory only;
    /// staged files of evicted entries are purged.
    @Published private(set) var recentlyClosed: [ShelfModel] = []
    private let maxRecent = 5

    private let saveURL: URL
    private var cancellables = Set<AnyCancellable>()

    private init() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("DropShelf", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.saveURL = dir.appendingPathComponent("shelves.json")
        load()
    }

    func add(_ shelf: ShelfModel) {
        shelves.append(shelf)
        observe(shelf)
        save()
    }

    func remove(id: UUID) {
        shelves.removeAll { $0.id == id }
        save()
    }

    /// Close a non-pinned shelf: push it onto the recently-closed list so the
    /// user can reopen it, evicting (and cleaning up) the oldest beyond the cap.
    func archiveClosed(_ shelf: ShelfModel) {
        shelves.removeAll { $0.id == shelf.id }
        shelf.selectedItemIDs = []
        recentlyClosed.removeAll { $0.id == shelf.id }
        recentlyClosed.insert(shelf, at: 0)
        while recentlyClosed.count > maxRecent {
            let evicted = recentlyClosed.removeLast()
            evicted.purgeStagedFiles()
            IntakeService.removeStagingDir(for: evicted)
        }
        save()
    }

    /// Pull a shelf back out of history (it's about to be shown again).
    func restoreFromHistory(id: UUID) -> ShelfModel? {
        guard let idx = recentlyClosed.firstIndex(where: { $0.id == id }) else { return nil }
        return recentlyClosed.remove(at: idx)
    }

    /// Forget all history, purging staged files.
    func clearHistory() {
        for shelf in recentlyClosed {
            shelf.purgeStagedFiles()
            IntakeService.removeStagingDir(for: shelf)
        }
        recentlyClosed.removeAll()
    }

    func shelf(with id: UUID) -> ShelfModel? {
        shelves.first { $0.id == id }
    }

    var pinnedShelves: [ShelfModel] {
        shelves.filter { $0.pinned }
    }

    /// Re-save whenever a shelf's persisted-relevant fields change.
    private func observe(_ shelf: ShelfModel) {
        shelf.objectWillChange
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] in self?.save() }
            .store(in: &cancellables)
    }

    // MARK: Persistence

    func save() {
        // Only persist pinned shelves; transient shelves vanish on quit.
        let records = shelves.filter { $0.pinned }.map { shelf in
            ShelfRecord(
                id: shelf.id,
                createdAt: shelf.createdAt,
                title: shelf.title,
                pinned: shelf.pinned,
                items: shelf.items.map { ShelfItemRecord(id: $0.id, path: $0.url.path, isStaged: $0.isStaged) },
                originX: shelf.lastOrigin.map { Double($0.x) },
                originY: shelf.lastOrigin.map { Double($0.y) },
                viewMode: shelf.viewMode.rawValue
            )
        }
        do {
            let data = try JSONEncoder().encode(records)
            try data.write(to: saveURL, options: Data.WritingOptions.atomic)
        } catch {
            NSLog("DropShelf: failed to save shelves: \(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let records = try? JSONDecoder().decode([ShelfRecord].self, from: data) else { return }
        for record in records {
            let items = record.items.filter {
                !["webloc", "inetloc", "url"].contains(URL(fileURLWithPath: $0.path).pathExtension.lowercased())
            }.map { ShelfItem(id: $0.id, url: URL(fileURLWithPath: $0.path), isStaged: $0.isStaged ?? false) }
            var origin: CGPoint? = nil
            if let x = record.originX, let y = record.originY {
                origin = CGPoint(x: x, y: y)
            }
            let shelf = ShelfModel(
                id: record.id,
                createdAt: record.createdAt,
                title: record.title,
                items: items,
                pinned: record.pinned,
                lastOrigin: origin
            )
            shelf.viewMode = record.viewMode.flatMap(ShelfViewMode.init) ?? .grid
            shelves.append(shelf)
            observe(shelf)
        }
    }
}
