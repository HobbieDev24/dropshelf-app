import Foundation
import AppKit

/// Centralizes all "do something with these files" actions: copy to clipboard,
/// AirDrop, reveal in Finder.
enum ShareService {

    // MARK: - Clipboard

    /// Put the actual file references on the pasteboard so they can be pasted
    /// into Finder / Mail / etc.
    static func copyToClipboard(_ urls: [URL]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls as [NSURL])

    }

    // MARK: - AirDrop

    /// Opens the standard macOS share sheet pre-targeted to AirDrop.
    /// `anchor` is the view to position the picker relative to.
    static func airDrop(_ urls: [URL], anchor: NSView?) {
        guard let service = NSSharingService(named: .sendViaAirDrop) else {

            presentError("AirDrop is not available on this Mac.")
            return
        }
        if service.canPerform(withItems: urls) {
            service.perform(withItems: urls)
        } else {
            // Fall back to a full share picker anchored to the button.
            presentSharePicker(urls, anchor: anchor)
        }
    }

    /// Full system share sheet (all services), as a fallback / general share.
    static func presentSharePicker(_ urls: [URL], anchor: NSView?) {
        let picker = NSSharingServicePicker(items: urls)
        if let anchor {
            picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        } else if let window = NSApp.keyWindow, let content = window.contentView {
            picker.show(relativeTo: .zero, of: content, preferredEdge: .minY)
        }
    }

    // MARK: - Reveal

    static func revealInFinder(_ urls: [URL]) {
        let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(existing)
    }

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    // MARK: - Move

    /// Ask for a destination and move each file there. Existing destination
    /// files are never overwritten. The completion returns original URLs that
    /// moved successfully so the caller can remove only those shelf entries.
    static func moveToFolder(_ urls: [URL], completion: @escaping ([URL]) -> Void) {
        guard !urls.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.title = urls.count == 1 ? "Move File" : "Move \(urls.count) Files"
        panel.prompt = "Move Here"
        panel.message = "Choose a destination folder. Existing files will not be replaced."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }

            DispatchQueue.global(qos: .userInitiated).async {
                var moved: [URL] = []
                var failures: [String] = []

                for source in urls {
                    let target = destination.appendingPathComponent(source.lastPathComponent,
                                                                    isDirectory: source.hasDirectoryPath)
                    do {
                        guard source.standardizedFileURL != target.standardizedFileURL else {
                            throw CocoaError(.fileWriteFileExists)
                        }
                        try FileManager.default.moveItem(at: source, to: target)
                        moved.append(source)
                    } catch {
                        failures.append(source.lastPathComponent)
                    }
                }

                DispatchQueue.main.async {
                    completion(moved)
                    if !failures.isEmpty {
                        presentError("Could not move: \(failures.joined(separator: ", ")). The files remain on the shelf.")
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private static func presentError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "DropShelf"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
