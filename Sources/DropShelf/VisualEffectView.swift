import SwiftUI
import AppKit

/// Native macOS vibrancy surface used by the shelf and its layered glass chrome.
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var emphasized: Bool = false
    var cornerRadius: CGFloat = Theme.cornerRadius
    var darkAppearance: Bool = false

    func makeNSView(context: Context) -> RoundedVisualEffectView {
        let view = RoundedVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = emphasized
        view.cornerRadius = cornerRadius
        view.appearance = darkAppearance ? NSAppearance(named: .darkAqua) : nil
        return view
    }

    func updateNSView(_ nsView: RoundedVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.isEmphasized = emphasized
        nsView.cornerRadius = cornerRadius
        nsView.appearance = darkAppearance ? NSAppearance(named: .darkAqua) : nil
    }
}

/// SwiftUI's clip shape cannot reliably mask an embedded AppKit vibrancy view.
/// This clips the blur at the native layer so its corners never leak past the
/// shelf's rounded surface.
final class RoundedVisualEffectView: NSVisualEffectView {
    var cornerRadius: CGFloat = 20 {
        didSet { updateMask() }
    }

    override func layout() {
        super.layout()
        updateMask()
    }

    private func updateMask() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        maskImage = Self.roundedMask(cornerRadius: cornerRadius)
    }

    private static func roundedMask(cornerRadius: CGFloat) -> NSImage {
        let edge = cornerRadius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: cornerRadius, left: cornerRadius,
                                       bottom: cornerRadius, right: cornerRadius)
        image.resizingMode = .stretch
        return image
    }
}

/// Shared palette / metrics so the look stays consistent.
enum Theme {
    static let cornerRadius: CGFloat = 22
    static let itemCorner: CGFloat = 11
    static let accent = Color(nsColor: .controlAccentColor)
    static let glassStroke = Color.white.opacity(0.24)
    static let glassInnerStroke = Color.white.opacity(0.07)
    static let separator = Color.primary.opacity(0.07)
    static let controlCorner: CGFloat = 12

    static let headerHeight: CGFloat = 48
    static let footerHeight: CGFloat = 38

    static let quickMotion = Animation.timingCurve(0.22, 0.72, 0.18, 1.0, duration: 0.18)
    static let surfaceMotion = Animation.timingCurve(0.22, 0.72, 0.18, 1.0, duration: 0.26)

    static func iconButtonBackground(_ hovering: Bool) -> Color {
        hovering ? Color.primary.opacity(0.16) : Color.primary.opacity(0.08)
    }
}

/// Compact native-feeling glass button used in the shelf chrome.
struct CircleIconButton: View {
    let systemName: String
    var help: String = ""
    var tint: Color? = nil
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Theme.iconButtonBackground(hovering))
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(hovering ? 0.28 : 0.14), lineWidth: 0.5)
                    )
                Image(systemName: systemName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint ?? .primary)
            }
            .frame(width: 32, height: 32)
            .scaleEffect(hovering ? 1.04 : 1)
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            withAnimation(Theme.quickMotion) { hovering = isHovering }
        }
        .help(help)
        .contentShape(Circle())
    }
}
