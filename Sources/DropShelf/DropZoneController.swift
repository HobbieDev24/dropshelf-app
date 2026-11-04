import Foundation
import AppKit
import SwiftUI

/// Manages the floating "drop zone" panel shown near the screen edge while the
/// user is dragging files. Dropping files onto it triggers shelf creation.
final class DropZoneController {
    typealias Drop = (_ screenPoint: CGPoint, _ urls: [URL]) -> Void

    private let onDrop: Drop
    private var panel: DropZonePanel?

    init(onDrop: @escaping Drop) {
        self.onDrop = onDrop
    }

    func show() {
        if panel == nil { build() }
        guard let panel else { return }
        position(panel)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.20
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.72, 0.18, 1.0)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.42, 0.0, 0.58, 1.0)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    private func build() {
        let size = NSSize(width: 168, height: 168)
        let panel = DropZonePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false

        let dropView = DropZoneView(frame: NSRect(origin: .zero, size: size))
        dropView.onDrop = { [weak self] point, urls in
            self?.onDrop(point, urls)
        }
        panel.contentView = dropView
        self.panel = panel
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let v = screen.visibleFrame
        // Center of the screen, matching where the shelf itself appears.
        let origin = CGPoint(x: v.midX - panel.frame.width / 2,
                             y: v.midY - panel.frame.height / 2)
        panel.setFrameOrigin(origin)
    }
}

final class DropZonePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The drag-accepting view, styled to match Dropover: a frosted-glass rounded
/// panel (vibrancy blur) with a soft hairline border, a circular accent "plus"
/// badge, and a clean label. Highlights with an accent glow while dragging over.
final class DropZoneView: NSView {
    var onDrop: ((CGPoint, [URL]) -> Void)?
    private var isHighlighted = false {
        didSet { updateHighlight() }
    }

    private let corner: CGFloat = 22

    private let blur: NSVisualEffectView = {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        v.wantsLayer = true
        // Dropover's drop zone is always dark, regardless of system appearance.
        v.appearance = NSAppearance(named: .darkAqua)
        return v
    }()

    private let border = CAShapeLayer()
    private let boltButton = NSView()
    private let boltIcon = NSImageView()
    private let label = NSTextField(labelWithString: "Drop files here")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
        wantsLayer = true
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        // Dark frosted glass background. NSVisualEffectView ignores
        // layer.cornerRadius, so it must be clipped with a rounded maskImage.
        blur.frame = bounds
        blur.autoresizingMask = [.width, .height]
        blur.maskImage = Self.roundedMask(corner: corner)
        addSubview(blur)

        // Hairline border on top of the glass.
        border.frame = bounds
        border.fillColor = nil
        border.lineWidth = 1
        border.strokeColor = NSColor.white.withAlphaComponent(0.10).cgColor
        layer?.addSublayer(border)

        // Rounded-square lightning button in the TOP-RIGHT corner (Dropover style).
        let btnSize: CGFloat = 34
        boltButton.wantsLayer = true
        boltButton.layer?.cornerRadius = 9
        boltButton.layer?.cornerCurve = .continuous
        boltButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        boltButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(boltButton)

        let boltCfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        boltIcon.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(boltCfg)
        boltIcon.contentTintColor = .white
        boltIcon.imageScaling = .scaleNone
        boltIcon.translatesAutoresizingMaskIntoConstraints = false
        boltButton.addSubview(boltIcon)

        // Centered "Drop files here" label.
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = NSColor.white.withAlphaComponent(0.55)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            boltButton.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            boltButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            boltButton.widthAnchor.constraint(equalToConstant: btnSize),
            boltButton.heightAnchor.constraint(equalToConstant: btnSize),
            boltIcon.centerXAnchor.constraint(equalTo: boltButton.centerXAnchor),
            boltIcon.centerYAnchor.constraint(equalTo: boltButton.centerYAnchor),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    override func layout() {
        super.layout()
        blur.maskImage = Self.roundedMask(corner: corner)
        border.frame = bounds
        let inset = bounds.insetBy(dx: 0.5, dy: 0.5)
        border.path = CGPath(roundedRect: inset, cornerWidth: corner, cornerHeight: corner, transform: nil)
    }

    /// A resizable rounded-rect mask so vibrancy is clipped to rounded corners.
    private static func roundedMask(corner: CGFloat) -> NSImage {
        let edge = corner * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: corner, left: corner, bottom: corner, right: corner)
        image.resizingMode = .stretch
        return image
    }

    /// All decorative subviews must be transparent to drag hit-testing so drops
    /// reach this registered drop target (the bug that made files get rejected).
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    private func updateHighlight() {
        let dur = 0.25
        let ease = CAMediaTimingFunction(name: .easeInEaseOut)

        // View-backed layers suppress implicit animation, so animate explicitly.
        func animateColor(_ layer: CALayer, key: String, to color: CGColor) {
            let from = layer.presentation()?.value(forKeyPath: key) ?? layer.value(forKeyPath: key)
            let anim = CABasicAnimation(keyPath: key)
            anim.fromValue = from
            anim.toValue = color
            anim.duration = dur
            anim.timingFunction = ease
            layer.add(anim, forKey: key)
            layer.setValue(color, forKeyPath: key)
        }

        let borderColor = (isHighlighted
            ? NSColor.controlAccentColor.withAlphaComponent(0.85)
            : NSColor.white.withAlphaComponent(0.10)).cgColor
        animateColor(border, key: "strokeColor", to: borderColor)

        if let btnLayer = boltButton.layer {
            let btnColor = (isHighlighted
                ? NSColor.controlAccentColor
                : NSColor.white.withAlphaComponent(0.12)).cgColor
            animateColor(btnLayer, key: "backgroundColor", to: btnColor)
        }

        label.textColor = NSColor.white.withAlphaComponent(isHighlighted ? 0.85 : 0.55)
    }

    // MARK: Dragging destination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isHighlighted = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isHighlighted = false
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isHighlighted = false
        let pb = sender.draggingPasteboard
        guard let objs = pb.readObjects(forClasses: [NSURL.self], options: [:]) as? [URL],
              !objs.isEmpty else {
            return false
        }
        // Screen point of the drop.
        let screenPoint: CGPoint
        if let window = self.window {
            let inWindow = sender.draggingLocation
            screenPoint = window.convertPoint(toScreen: inWindow)
        } else {
            screenPoint = .zero
        }
        onDrop?(screenPoint, objs)
        return true
    }
}
