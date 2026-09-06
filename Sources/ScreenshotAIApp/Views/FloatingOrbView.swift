import AppKit
import SwiftUI
import ScreenshotAIKit

struct FloatingOrbView: View {
    @Bindable var store: DemoTaskStore
    let cycleMode: () -> Void
    let runCurrentModeCapture: () -> Void
    let runLocalOCRCapture: () -> Void
    let openMainWindow: () -> Void
    let openPromptInput: () -> Void
    let hideOrb: () -> Void
    @State private var window: NSWindow?
    @State private var dragStartOrigin: CGPoint?
    @State private var dragStartMouseLocation: CGPoint?
    @State private var didDrag = false

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay {
                    Circle()
                        .strokeBorder(.primary.opacity(0.10), lineWidth: 0.6)
                }

            Image(systemName: orbIcon)
                .font(.system(size: 20, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)

            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
                .offset(x: -16, y: 16)

            if store.batchCount > 0 {
                Text("\(store.batchCount)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.blue, in: Capsule())
                    .offset(x: 16, y: -16)
            }
        }
        .frame(width: 46, height: 46)
        .contentShape(Circle())
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        .highPriorityGesture(tapGesture)
        .gesture(dragGesture)
        .background(
            FloatingWindowConfigurator(
                onWindowChange: { window = $0 },
                targetSize: CGSize(width: 54, height: 54),
                snapsToEdge: true,
                isMovableByWindowBackground: false
            )
        )
        .contextMenu {
            Button {
                openMainWindow()
            } label: {
                Label("打开主窗口", systemImage: "macwindow")
            }

            Button {
                runCurrentModeCapture()
            } label: {
                Label("按当前模式截图", systemImage: "camera.viewfinder")
            }

            Button {
                runLocalOCRCapture()
            } label: {
                Label("截图并本地 OCR", systemImage: "text.viewfinder")
            }

            Button {
                openPromptInput()
            } label: {
                Label("输入 Prompt", systemImage: "text.cursor")
            }

            if store.batchCount > 0 {
                Button {
                    store.clearBatch()
                } label: {
                    Label("清空当前队列", systemImage: "trash")
                }
            }

            Divider()

            Button {
                hideOrb()
            } label: {
                Label("隐藏悬浮球", systemImage: "xmark.circle")
            }
        }
    }

    private var tapGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded { handleTap(count: 2) }
            .exclusively(before: TapGesture(count: 1).onEnded { handleTap(count: 1) })
    }

    private func handleTap(count: Int) {
        guard !didDrag else {
            didDrag = false
            return
        }
        switch FloatingOrbTapRouter.action(forTapCount: count) {
        case .cycleMode: cycleMode()
        case .openPrompt: openPromptInput()
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                guard let window else { return }
                if dragStartOrigin == nil {
                    dragStartOrigin = window.frame.origin
                    dragStartMouseLocation = NSEvent.mouseLocation
                }
                guard let dragStartOrigin, let dragStartMouseLocation else { return }
                let mouseLocation = NSEvent.mouseLocation
                let origin = CGPoint(
                    x: dragStartOrigin.x + mouseLocation.x - dragStartMouseLocation.x,
                    y: dragStartOrigin.y + mouseLocation.y - dragStartMouseLocation.y
                )
                if hypot(mouseLocation.x - dragStartMouseLocation.x, mouseLocation.y - dragStartMouseLocation.y) > 5 {
                    didDrag = true
                }
                window.setFrameOrigin(origin)
            }
            .onEnded { _ in
                window?.snapToNearestScreenEdge(padding: 10, animated: true)
                dragStartOrigin = nil
                dragStartMouseLocation = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    didDrag = false
                }
            }
    }

    private var orbIcon: String {
        if store.isRunning {
            return "sparkles"
        }
        if store.isCapturing {
            return "camera.aperture"
        }
        switch store.captureMode {
        case .manual:
            return "camera.viewfinder"
        case .auto:
            return "bolt.circle"
        case .batch:
            return "rectangle.stack"
        }
    }

    private var statusColor: Color {
        if store.isRunning || store.isCapturing {
            return .blue
        }
        if store.captureMode == .batch, store.batchCount > 0 {
            return .green
        }
        return .secondary
    }
}

enum FloatingOrbTapAction: Equatable { case cycleMode, openPrompt }

enum FloatingOrbTapRouter {
    static func action(forTapCount count: Int) -> FloatingOrbTapAction {
        count >= 2 ? .openPrompt : .cycleMode
    }
}
