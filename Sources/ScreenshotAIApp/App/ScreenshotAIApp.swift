import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if !UserDefaults.standard.bool(forKey: AppDefaultsKeys.silentOperationEnabled) {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

@main
struct ScreenshotAIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var store = DemoTaskStore()
    @State private var floatingPromptPanel = FloatingPromptPanelController()
    @State private var didRegisterHotKeys = false
    @State private var didApplySilentStartup = false
    @State private var suppressNextSilentStartupDismiss = false

    var body: some Scene {
        Window("ScreenshotAI Base", id: "main") {
            MainWindowView(store: store)
                .onAppear {
                    registerGlobalHotKeysIfNeeded()
                    openFloatingOrbIfNeeded()
                    applySilentStartupIfNeeded()
                }
                .onChange(of: store.floatingOrbEnabled) { _, isEnabled in
                    if isEnabled {
                        openWindow(id: "floatingOrb")
                    } else {
                        dismissWindow(id: "floatingOrb")
                    }
                }
        }
        .defaultSize(width: 980, height: 720)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("设置...") {
                    showMainWindow(section: .settings)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        MenuBarExtra("Screenshot AI", systemImage: "camera.viewfinder") {
            Button("打开主窗口") {
                showMainWindow(section: .capture)
            }
            Button("打开时间线") {
                showMainWindow(section: .timeline)
            }
            Button("截图并本地 OCR  \(store.shortcutDisplay(for: .localOCRCapture))") {
                runLocalOCRCapture()
            }
            .disabled(store.isCapturing || store.isRunning)
            Divider()
            Button("按当前模式截图  \(store.shortcutDisplay(for: .manualCapture))") {
                runCurrentModeCapture()
            }
            Button("自动截图并执行  \(store.shortcutDisplay(for: .autoCapture))") {
                runAutoCapture()
            }
            Button("批量截图") {
                store.setMode(.batch)
                store.addBatchDemo()
                presentAfterUserVisibleAction(section: .capture)
            }
            Divider()
            Button(store.floatingOrbEnabled ? "隐藏悬浮球" : "显示悬浮球") {
                toggleFloatingOrb()
            }
            Button(store.silentOperationEnabled ? "关闭静默操作" : "开启静默操作") {
                store.silentOperationEnabled.toggle()
            }
            Divider()
            Button("设置") {
                showMainWindow(section: .settings)
            }
            Divider()
            Button("退出") {
                NSApp.terminate(nil)
            }
        }

        Window("悬浮球", id: "floatingOrb") {
            FloatingOrbView(
                store: store,
                cycleMode: {
                    floatingPromptPanel.close()
                    store.cycleCaptureMode()
                },
                runCurrentModeCapture: {
                    runCurrentModeCapture()
                },
                runLocalOCRCapture: {
                    runLocalOCRCapture()
                },
                openMainWindow: {
                    showMainWindow(section: .capture)
                },
                openPromptInput: {
                    openPromptInput()
                },
                hideOrb: {
                    store.floatingOrbEnabled = false
                    dismissWindow(id: "floatingOrb")
                }
            )
            .frame(width: 54, height: 54)
        }
        .defaultSize(width: 54, height: 54)
    }

    private func registerGlobalHotKeysIfNeeded() {
        guard !didRegisterHotKeys else { return }
        didRegisterHotKeys = true

        GlobalHotKeyService.shared.register { action in
            switch action {
            case .manualCapture:
                runCurrentModeCapture()
            case .autoCapture:
                runAutoCapture()
            case .openTaskCenter:
                showMainWindow(section: .timeline)
            case .localOCRCapture:
                runLocalOCRCapture()
            }
        }
    }

    private func runCurrentModeCapture() {
        switch store.captureMode {
        case .manual:
            Task {
                let succeeded = await store.captureScreenshot()
                await MainActor.run {
                    guard succeeded else {
                        if store.captureErrorMessage != nil { showMainWindow(section: .capture) }
                        return
                    }
                    presentAfterCapture(section: .capture, requiresInput: true)
                }
            }
        case .auto:
            runAutoCapture()
        case .batch:
            Task {
                let succeeded = await store.captureScreenshot()
                await MainActor.run {
                    guard succeeded else {
                        if store.captureErrorMessage != nil { showMainWindow(section: .capture) }
                        return
                    }
                    presentAfterCapture(section: .capture, allowsPromptInput: true)
                }
            }
        }
    }

    private func runAutoCapture() {
        store.setMode(.auto)
        Task {
            await store.captureAndRunActivePrompt()
            await MainActor.run {
                presentAfterCapture(section: .capture)
                openPromptInput()
            }
        }
    }

    private func runLocalOCRCapture() {
        Task {
            guard await store.captureAndRunLocalOCR() else { return }
            await MainActor.run {
                presentAfterCapture(section: .capture, allowsPromptInput: true)
                openPromptInput()
            }
        }
    }

    @MainActor
    private func showMainWindow(section: MainAppSection) {
        suppressNextSilentStartupDismiss = true
        didApplySilentStartup = true
        store.selectedSection = section
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    private func presentAfterCapture(
        section: MainAppSection,
        requiresInput: Bool = false,
        allowsPromptInput: Bool = false
    ) {
        if store.captureErrorMessage != nil {
            showMainWindow(section: section)
            return
        }
        if store.silentOperationEnabled {
            openFloatingOrbIfNeeded()
            if requiresInput || allowsPromptInput {
                openPromptInput()
            }
            return
        }
        showMainWindow(section: section)
    }

    @MainActor
    private func presentAfterUserVisibleAction(section: MainAppSection) {
        if store.silentOperationEnabled {
            openFloatingOrbIfNeeded()
            return
        }
        showMainWindow(section: section)
    }

    @MainActor
    private func openFloatingOrbIfNeeded() {
        guard store.floatingOrbEnabled else { return }
        openWindow(id: "floatingOrb")
    }

    @MainActor
    private func openPromptInput() {
        floatingPromptPanel.show(
            store: store,
            runPrompt: { prompt in
                Task { @MainActor in
                    store.currentResultText = nil
                    store.customPrompt = prompt
                    await store.runCustomPrompt()
                }
            },
            runRevision: { instruction in
                Task { @MainActor in
                    store.revisionInstruction = instruction
                    await store.reviseCurrentResult()
                }
            },
            openMainWindow: {
                showMainWindow(section: .capture)
            }
        )
    }

    @MainActor
    private func applySilentStartupIfNeeded() {
        guard store.silentOperationEnabled, !didApplySilentStartup else { return }
        didApplySilentStartup = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if suppressNextSilentStartupDismiss {
                suppressNextSilentStartupDismiss = false
                return
            }
            dismissWindow(id: "main")
        }
    }

    @MainActor
    private func toggleFloatingOrb() {
        store.floatingOrbEnabled.toggle()
        if store.floatingOrbEnabled {
            openWindow(id: "floatingOrb")
        } else {
            dismissWindow(id: "floatingOrb")
        }
    }
}

private enum AppDefaultsKeys {
    static let silentOperationEnabled = "silentOperationEnabled"
}
