import AppKit
import SwiftUI

struct WindowMaterialBackground: View {
    var body: some View {
        Rectangle()
            .fill(.clear)
            .ignoresSafeArea()
    }
}

private struct GlassPanelModifier: ViewModifier {
    var cornerRadius: CGFloat
    var material: Material
    var isInteractive: Bool

    func body(content: Content) -> some View {
        content
            .background(material, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.primary.opacity(isInteractive ? 0.10 : 0.06), lineWidth: 0.6)
            }
            .shadow(color: .black.opacity(0.06), radius: isInteractive ? 12 : 7, y: isInteractive ? 5 : 3)
    }
}

extension View {
    func glassPanel(
        cornerRadius: CGFloat = 12,
        material: Material = .regularMaterial,
        isInteractive: Bool = false
    ) -> some View {
        modifier(
            GlassPanelModifier(
                cornerRadius: cornerRadius,
                material: material,
                isInteractive: isInteractive
            )
        )
    }
}

struct FloatingWindowConfigurator: NSViewRepresentable {
    var onWindowChange: ((NSWindow) -> Void)?
    var targetSize: CGSize?
    var hidesTitleChrome = true
    var snapsToEdge = false
    var acceptsTextInput = false
    var isMovableByWindowBackground = true

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            onWindowChange?(window)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.level = .floating
            window.isMovableByWindowBackground = isMovableByWindowBackground
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            if hidesTitleChrome {
                window.styleMask = [.borderless]
            } else {
                window.styleMask.insert(.titled)
                window.styleMask.insert(.closable)
                window.styleMask.insert(.fullSizeContentView)
            }
            window.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
                .transient
            ]
            if let targetSize {
                window.setContentSize(targetSize)
            }
            if snapsToEdge, !context.coordinator.didSnapInitially {
                context.coordinator.didSnapInitially = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    window.snapToNearestScreenEdge(padding: 10, animated: false)
                }
            }
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            if acceptsTextInput {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    final class Coordinator {
        var didSnapInitially = false
    }
}

extension NSWindow {
    func snapToNearestScreenEdge(padding: CGFloat = 10, animated: Bool = true) {
        guard let screen = screen ?? NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        var frame = frame
        let leftX = visibleFrame.minX + padding
        let rightX = visibleFrame.maxX - frame.width - padding
        frame.origin.x = frame.midX < visibleFrame.midX ? leftX : rightX
        frame.origin.y = min(
            max(frame.origin.y, visibleFrame.minY + padding),
            visibleFrame.maxY - frame.height - padding
        )
        setFrame(frame, display: true, animate: animated)
    }
}
