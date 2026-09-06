import AppKit
import SwiftUI

@MainActor
final class FloatingPromptPanelController {
    private var panel: KeyableFloatingPanel?
    private var hostingController: NSHostingController<AnyView>?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var currentSize: FloatingPromptPanelSize = .compact

    func show(
        store: DemoTaskStore,
        runPrompt: @escaping (String) -> Void,
        runRevision: @escaping (String) -> Void,
        openMainWindow: @escaping () -> Void
    ) {
        let panel = panel ?? makePanel()
        self.panel = panel

        let content = FloatingPromptInputView(
            store: store,
            runPrompt: runPrompt,
            runRevision: runRevision,
            openMainWindow: openMainWindow,
            close: { [weak self] in
                self?.close()
            },
            setPanelSize: { [weak self] size in self?.setPanelSize(size) }
        )

        if let hostingController {
            hostingController.rootView = AnyView(content)
        } else {
            let hostingController = NSHostingController(rootView: AnyView(content))
            hostingController.view.frame = NSRect(origin: .zero, size: Self.compactSize)
            hostingController.view.wantsLayer = true
            hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
            panel.contentViewController = hostingController
            self.hostingController = hostingController
        }

        setPanelSize(.compact, animated: false)
        installOutsideClickMonitors()
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        removeOutsideClickMonitors()
        panel?.orderOut(nil)
    }

    private func makePanel() -> KeyableFloatingPanel {
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let origin = NSPoint(
            x: screenFrame.midX - Self.compactSize.width / 2,
            y: screenFrame.minY + 190
        )
        let panel = KeyableFloatingPanel(
            contentRect: NSRect(origin: origin, size: Self.compactSize),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        return panel
    }

    private func setPanelSize(_ size: FloatingPromptPanelSize, animated: Bool = true) {
        guard let panel else { return }
        let targetSize = size.cgSize
        hostingController?.view.frame = NSRect(origin: .zero, size: targetSize)

        guard currentSize != size || !panel.frame.size.isNearlyEqual(to: targetSize) else {
            return
        }

        currentSize = size
        var frame = panel.frame
        let oldMidX = frame.midX
        frame.origin.x = oldMidX - targetSize.width / 2
        frame.origin.y += frame.height - targetSize.height
        frame.size = targetSize
        panel.setFrame(frame, display: true, animate: false)
    }

    private func installOutsideClickMonitors() {
        removeOutsideClickMonitors()

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            if let eventWindow = event.window,
               eventWindow === panel || eventWindow.parent === panel || panel.childWindows?.contains(eventWindow) == true {
                return event
            }
            self.close()
            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
    }

    private func removeOutsideClickMonitors() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }

    private static let compactSize = FloatingPromptPanelSize.compact.cgSize
}

private final class KeyableFloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private extension NSSize {
    func isNearlyEqual(to other: NSSize) -> Bool {
        abs(width - other.width) < 0.5 && abs(height - other.height) < 0.5
    }
}

enum FloatingPromptPanelSize {
    case compact
    case feedback
    case result

    var cgSize: NSSize {
        switch self {
        case .compact:
            return NSSize(width: 360, height: 50)
        case .feedback:
            return NSSize(width: 360, height: 96)
        case .result:
            return NSSize(width: 540, height: 430)
        }
    }
}
