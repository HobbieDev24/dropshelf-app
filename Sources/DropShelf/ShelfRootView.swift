import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The full contents of one shelf window: header + items + footer, wrapped in
/// the frosted-glass rounded container.
struct ShelfRootView: View {
    @ObservedObject var shelf: ShelfModel
    weak var controller: ShelfWindowController?

    @State private var expanded = false
    @State private var isTargetedForDrop = false

    var body: some View {
        VStack(spacing: 0) {
            ShelfHeaderView(shelf: shelf, controller: controller)
            ShelfBodyView(shelf: shelf, controller: controller, expanded: expanded)
                .frame(maxHeight: .infinity)
            if shouldShowFooter {
                ShelfFooterView(shelf: shelf,
                                controller: controller,
                                expanded: $expanded)
            }
        }
        .background {
            ZStack {
                VisualEffectView(material: .popover,
                                 blendingMode: .behindWindow,
                                 emphasized: false,
                                 cornerRadius: Theme.cornerRadius,
                                 darkAppearance: false)
                LinearGradient(
                    colors: [Color.white.opacity(0.18), Color.white.opacity(0.04), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [Color.white.opacity(0.14), .clear],
                    center: .topTrailing,
                    startRadius: 6,
                    endRadius: 220
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(Theme.glassStroke, lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius - 1, style: .continuous)
                .strokeBorder(Theme.glassInnerStroke, lineWidth: 1)
                .padding(1)
        )
        .overlay(
            // Drop highlight when dragging external files onto the shelf.
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(Theme.accent, lineWidth: 2)
                .opacity(isTargetedForDrop ? 1 : 0)
        )
        .overlay(alignment: .leading) {
            WindowResizeHandle(edge: .left)
                .frame(width: 8)
                .padding(.vertical, 8)
        }
        .overlay(alignment: .trailing) {
            WindowResizeHandle(edge: .right)
                .frame(width: 8)
                .padding(.vertical, 8)
        }
        .overlay(alignment: .top) {
            WindowResizeHandle(edge: .top)
                .frame(height: 8)
        }
        .overlay(alignment: .bottom) {
            WindowResizeHandle(edge: .bottom)
                .frame(height: 8)
        }
        .onChange(of: expanded) { newValue in
            controller?.setExpanded(newValue)
        }
        // Accept existing files only.
        .onDrop(of: [.fileURL], isTargeted: $isTargetedForDrop) { providers in
            handleDrop(providers)
        }
    }

    private var shouldShowFooter: Bool {
        // Footer (expand + reveal) is always useful, but the expand arrow only
        // matters when content overflows. We show the footer whenever there is
        // at least one item.
        !shelf.items.isEmpty
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        // Finder can expose a file's contents through SwiftUI providers without
        // advertising fileURL. Prefer the native drag's original file references.
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = NSPasteboard(name: .drag).readObjects(forClasses: [NSURL.self], options: options) as? [URL],
           !urls.isEmpty {
            shelf.addURLs(urls)
            ShelfStore.shared.save()

            return true
        }
        let fileProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        for provider in fileProviders {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.isFileURL {
                    lock.lock(); urls.append(url); lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            if !urls.isEmpty {
                shelf.addURLs(urls)
                ShelfStore.shared.save()
            }
        }
        return !fileProviders.isEmpty
    }
}

private struct WindowResizeHandle: NSViewRepresentable {
    let edge: ShelfEdgeResizeView.Edge

    func makeNSView(context: Context) -> ShelfEdgeResizeView {
        ShelfEdgeResizeView(edge: edge)
    }

    func updateNSView(_ nsView: ShelfEdgeResizeView, context: Context) {}
}

// MARK: - Header

struct ShelfHeaderView: View {
    @ObservedObject var shelf: ShelfModel
    weak var controller: ShelfWindowController?

    var body: some View {
        ZStack {
            WindowDragHandle()

            Capsule()
                .fill(Color.primary.opacity(0.20))
                .frame(width: 36, height: 4)
                .offset(y: -13)
                .allowsHitTesting(false)

            HStack {
            CircleIconButton(systemName: "xmark", help: "Close shelf (files are kept)") {
                AppCoordinator.shared?.dismissShelf(shelf)
            }

                Spacer()

            ShareMenuButton(shelf: shelf, controller: controller)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: Theme.headerHeight)
    }
}

/// Native drag surface behind the header controls. `performDrag` gives the
/// panel normal free movement even though its content is hosted by SwiftUI.
private struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragNSView { WindowDragNSView() }
    func updateNSView(_ nsView: WindowDragNSView, context: Context) {}
}

private final class WindowDragNSView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

// MARK: - Footer

struct ShelfFooterView: View {
    @ObservedObject var shelf: ShelfModel
    weak var controller: ShelfWindowController?
    @Binding var expanded: Bool

    var body: some View {
        HStack {
            Spacer()
            Button {
                withAnimation(Theme.surfaceMotion) { expanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text("\(shelf.items.count) \(shelf.items.count == 1 ? "File" : "Files")")
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                }
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.primary.opacity(0.70))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .help(expanded ? "Collapse shelf" : "Expand shelf")
            Spacer()
        }
        .frame(height: Theme.footerHeight)
    }
}
