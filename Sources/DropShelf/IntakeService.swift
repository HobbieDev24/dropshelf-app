import Foundation
import AppKit

/// Imports file references and cleans up staged content from older versions.
enum IntakeService {
    /// Root staging directory: Application Support/DropShelf/Staging.
    static var stagingRoot: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DropShelf/Staging", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: base.path)
        return base
    }

    /// Per-shelf staging subfolder, keyed by shelf id.
    static func stagingDir(for shelf: ShelfModel) -> URL {
        stagingDir(forID: shelf.id)
    }

    static func stagingDir(forID id: UUID) -> URL {
        let dir = stagingRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return dir
    }

    /// Remove a shelf's entire staging subfolder.
    static func removeStagingDir(for shelf: ShelfModel) {
        removeStagingDir(forID: shelf.id)
    }

    static func removeStagingDir(forID id: UUID) {
        let dir = stagingRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
    }

    /// Delete any staging subfolders not belonging to a currently-live shelf.
    /// Called at launch to sweep leftovers from a crash/forced quit.
    static func sweepOrphans(liveShelfIDs: Set<UUID>) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: stagingRoot,
                                                        includingPropertiesForKeys: nil) else { return }
        for entry in entries {
            if let id = UUID(uuidString: entry.lastPathComponent), liveShelfIDs.contains(id) {
                continue
            }
            try? fm.removeItem(at: entry)
        }
    }

    /// Only delete a direct child of this shelf's real staging directory.
    /// Resolve symbolic links so saved paths cannot redirect cleanup elsewhere.
    static func removeStagedFile(_ url: URL, shelfID: UUID) {
        let expected = stagingRoot.appendingPathComponent(shelfID.uuidString, isDirectory: true)
            .standardizedFileURL
        guard expected.resolvingSymlinksInPath() == expected,
              url.standardizedFileURL.deletingLastPathComponent() == expected,
              url.resolvingSymlinksInPath().deletingLastPathComponent() == expected else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Clipboard ingestion

    /// Import file references copied in Finder or another file-based app.
    /// Text, image pixels, and web URLs are ignored.
    @discardableResult
    static func ingestClipboard(into shelf: ShelfModel) -> Int {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self],
                                                         options: options) as? [URL],
              !urls.isEmpty else { return 0 }
        let added = shelf.addURLs(urls)
        if added > 0 { ShelfStore.shared.save() }
        return added
    }
}
