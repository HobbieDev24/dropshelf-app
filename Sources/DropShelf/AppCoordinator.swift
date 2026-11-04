import Foundation
import AppKit
import SwiftUI
import Combine

/// Central object that owns all windows and coordinates the app's behavior.
/// Created once by the AppDelegate.
final class AppCoordinator {
    static var shared: AppCoordinator?

    let store = ShelfStore.shared
    let prefs = Preferences.shared

    private var shelfWindows: [UUID: ShelfWindowController] = [:]
    private var settingsWindow: NSWindow?
    private var dragMonitor: DragMonitor?

    /// Notification posted whenever the set of on-screen shelves changes.
    static let openShelvesChanged = Notification.Name("DropShelf.openShelvesChanged")

    /// Shelves that currently have an on-screen window, newest first.
    var openShelves: [ShelfModel] {
        let live = shelfWindows.keys.compactMap { store.shelf(with: $0) }
        return live.sorted { $0.createdAt > $1.createdAt }
    }

    private func notifyOpenChanged() {
        NotificationCenter.default.post(name: Self.openShelvesChanged, object: nil)
    }

    init() {
        AppCoordinator.shared = self
    }

    func start() {

        // Sweep staging folders left behind by a crash / forced quit.
        IntakeService.sweepOrphans(liveShelfIDs: Set(store.shelves.map { $0.id }))

        // Reopen pinned shelves from last session.
        for shelf in store.pinnedShelves {
            showWindow(for: shelf, animate: false)
        }

        // Begin global drag detection for drop-zones.
        let monitor = DragMonitor { [weak self] screenPoint, urls in
            self?.handleDragLanded(at: screenPoint, urls: urls)
        }
        monitor.start()
        self.dragMonitor = monitor
        prefs.$dropZonesEnabled.dropFirst().sink { [weak monitor] enabled in
            if enabled { monitor?.start() } else { monitor?.stop() }
        }.store(in: &cancellables)


    }

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Shelf creation

    /// Create a brand-new shelf seeded with `urls`. Always shown centered on
    /// screen (drop location is ignored on purpose).
    @discardableResult
    func createShelf(with urls: [URL]) -> ShelfModel {
        let shelf = ShelfModel()
        shelf.addURLs(urls)
        store.add(shelf)
        showWindow(for: shelf, animate: true)
        return shelf
    }

    /// Add files to an existing on-screen shelf, or make a new one.
    func addFiles(_ urls: [URL], toExisting shelf: ShelfModel?) {
        if let shelf {
            shelf.addURLs(urls)
            showWindow(for: shelf, animate: true)
        } else {
            createShelf(with: urls)
        }
    }

    // MARK: - Window management

    func showWindow(for shelf: ShelfModel, animate: Bool) {
        if let existing = shelfWindows[shelf.id] {
            existing.showAndFocus(animate: animate)
            return
        }
        let controller = ShelfWindowController(shelf: shelf, coordinator: self)
        shelfWindows[shelf.id] = controller
        controller.showAndFocus(animate: animate)
        notifyOpenChanged()
    }

    /// Close the shelf window via "X". Files referenced in place are left
    /// exactly where they are (untouched at their origin). A non-pinned shelf is
    /// moved into the recently-closed history so it can be reopened; its staged
    /// (app-materialized) files ride along until the history entry is evicted.
    func dismissShelf(_ shelf: ShelfModel) {
        if let controller = shelfWindows[shelf.id] {
            controller.closeWithAnimation { [weak self] in
                self?.shelfWindows[shelf.id] = nil
                self?.notifyOpenChanged()
            }
        }
        if !shelf.pinned {
            store.archiveClosed(shelf)
        }
    }

    /// Reopen a shelf from the recently-closed history.
    func reopenFromHistory(id: UUID) {
        guard let shelf = store.restoreFromHistory(id: id) else { return }
        store.add(shelf)
        showWindow(for: shelf, animate: true)
    }

    func togglePin(_ shelf: ShelfModel) {
        shelf.pinned.toggle()
        store.save()
    }

    func windowController(for shelf: ShelfModel) -> ShelfWindowController? {
        shelfWindows[shelf.id]
    }

    // MARK: - Drag landed

    private func handleDragLanded(at screenPoint: CGPoint, urls: [URL]) {
        guard !urls.isEmpty else { return }
        // If the drag ended over an existing shelf window, add to it.
        if let shelf = shelfAt(screenPoint: screenPoint) {
            addFiles(urls, toExisting: shelf)
        } else {
            createShelf(with: urls)
        }
    }

    private func shelfAt(screenPoint: CGPoint) -> ShelfModel? {
        for (id, controller) in shelfWindows {
            if let window = controller.window, window.frame.contains(screenPoint) {
                return store.shelf(with: id)
            }
        }
        return nil
    }

    // MARK: - Settings

    func showSettings() {
        if let window = settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let view = SettingsView()
            .environmentObject(prefs)
            .environmentObject(store)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "DropShelf Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 560, height: 460))
        window.isReleasedWhenClosed = false
        window.center()
        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
