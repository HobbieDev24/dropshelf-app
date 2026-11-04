import SwiftUI
import AppKit
import Combine

// A file named `main.swift` runs as top-level code — do NOT use @main here.

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let coordinator = AppCoordinator()
        self.coordinator = coordinator
        coordinator.start()

        setupStatusItem()

        // Rebuild the menu whenever shelves change (pinned shelves section).
        ShelfStore.shared.$shelves
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildMenu() }
            .store(in: &cancellables)

        // …and whenever the recently-closed history changes.
        ShelfStore.shared.$recentlyClosed
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildMenu() }
            .store(in: &cancellables)

        // …and whenever the set of on-screen shelves changes.
        NotificationCenter.default.publisher(for: AppCoordinator.openShelvesChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildMenu() }
            .store(in: &cancellables)

    }

    private var cancellables = Set<AnyCancellable>()

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "tray.full.fill",
                                   accessibilityDescription: "DropShelf")
            button.image?.isTemplate = true
        }
        self.statusItem = item
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        populateMenu(menu)
        statusItem?.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        populateMenu(menu)
    }

    private func populateMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        // New empty shelf.
        let newItem = NSMenuItem(title: "New Shelf", action: #selector(newShelf), keyEquivalent: "n")
        newItem.target = self
        menu.addItem(newItem)

        menu.addItem(.separator())

        let pinnedIDs = Set(ShelfStore.shared.pinnedShelves.map { $0.id })

        // Currently open shelves (the "current" shelves on screen).
        let open = coordinator?.openShelves ?? []
        if !open.isEmpty {
            addHeader("Open Shelves", to: menu)
            for shelf in open {
                addShelfRow(shelf,
                            to: menu,
                            action: #selector(openPinned(_:)),
                            pinned: pinnedIDs.contains(shelf.id))
            }
            menu.addItem(.separator())
        }

        // Pinned shelves that aren't already shown above as open.
        let pinned = ShelfStore.shared.pinnedShelves.filter { shelf in
            !open.contains(where: { $0.id == shelf.id })
        }
        if !pinned.isEmpty {
            addHeader("Pinned Shelves", to: menu)
            for shelf in pinned {
                addShelfRow(shelf, to: menu, action: #selector(openPinned(_:)), pinned: true)
            }
            menu.addItem(.separator())
        }

        if open.isEmpty && pinned.isEmpty {
            let placeholder = NSMenuItem(title: "No Open or Pinned Shelves", action: nil, keyEquivalent: "")
            placeholder.isEnabled = false
            menu.addItem(placeholder)
            menu.addItem(.separator())
        }

        // Recently closed shelves (the "previous" shelves, in-memory history).
        let recent = ShelfStore.shared.recentlyClosed
        if !recent.isEmpty {
            addHeader("Recently Closed", to: menu)
            for shelf in recent {
                addShelfRow(shelf, to: menu, action: #selector(reopenRecent(_:)), pinned: false)
            }
            let clearItem = NSMenuItem(title: "Clear Recently Closed",
                                       action: #selector(clearRecent),
                                       keyEquivalent: "")
            clearItem.target = self
            menu.addItem(clearItem)
            menu.addItem(.separator())
        }

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let aboutItem = NSMenuItem(title: "About DropShelf", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit DropShelf", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

    }

    // MARK: - Menu builders

    private func addHeader(_ title: String, to menu: NSMenu) {
        let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
    }

    private func addShelfRow(_ shelf: ShelfModel,
                             to menu: NSMenu,
                             action: Selector,
                             pinned: Bool) {
        let pin = pinned ? "📌 " : ""
        let item = NSMenuItem(title: "   \(pin)\(shelf.effectiveTitle)  (\(shelf.items.count))",
                              action: action,
                              keyEquivalent: "")
        item.target = self
        item.representedObject = shelf.id.uuidString
        if let first = shelf.items.first {
            item.image = ThumbnailService.shared.icon(for: first.url)
        }
        menu.addItem(item)
    }

    // MARK: - Actions

    @objc private func newShelf() {
        coordinator?.createShelf(with: [])
    }

    @objc private func openPinned(_ sender: NSMenuItem) {
        guard let idString = sender.representedObject as? String,
              let id = UUID(uuidString: idString),
              let shelf = ShelfStore.shared.shelf(with: id) else { return }
        coordinator?.showWindow(for: shelf, animate: true)
    }

    @objc private func reopenRecent(_ sender: NSMenuItem) {
        guard let idString = sender.representedObject as? String,
              let id = UUID(uuidString: idString) else { return }
        coordinator?.reopenFromHistory(id: id)
    }

    @objc private func clearRecent() {
        ShelfStore.shared.clearHistory()
    }

    @objc private func openSettings() {
        coordinator?.showSettings()
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "DropShelf"
        alert.informativeText = "A floating shelf for files.\nDrag files anywhere to stash them, then move or share."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu-bar agent, no Dock icon
app.run()
