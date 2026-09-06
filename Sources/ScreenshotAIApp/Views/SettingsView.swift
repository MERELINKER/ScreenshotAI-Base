import SwiftUI
import ScreenshotAIKit

struct SettingsView: View {
    @Bindable var store: DemoTaskStore

    var body: some View {
        Form {
            Section("屏幕录制权限") {
                Button("打开系统屏幕录制设置") { store.openScreenRecordingSettings() }
                Text("若框选截图无法启动，请确认已允许 ScreenshotAI Base 录制屏幕。授权后退出并重新打开应用。本地 OCR 不需要 API Key。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("AI 接口") {
                TextField("Base URL", text: $store.apiBaseURLString)
                TextField("模型名", text: $store.modelName)
                SecureField("API Key", text: $store.apiKeyDraft)
                Button("保存 API 设置") {
                    store.saveProviderSettings()
                }
                Text(store.providerStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("快捷键") {
                ForEach(HotKeyAction.allCases, id: \.self) { action in
                    HStack {
                        Text(action.title)
                        Spacer()
                        Text(store.shortcutDisplay(for: action))
                            .monospaced()
                            .foregroundStyle(.secondary)
                        Button(store.recordingHotKeyAction == action ? "按下组合键..." : "录制") {
                            store.beginRecordingShortcut(for: action)
                        }
                    }
                }

                Text(store.hotKeyStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("截图保存") {
                Text(store.captureDirectoryPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)

                HStack {
                    Button("选择目录") {
                        store.chooseCaptureDirectory()
                    }
                    Button("打开目录") {
                        store.openCaptureDirectory()
                    }
                }

                Text(store.captureDirectoryStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("默认模式", selection: $store.captureMode) {
                ForEach(CaptureMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            Stepper("批量并发数：\(store.concurrencyLimit)", value: $store.concurrencyLimit, in: 1...8)

            Section("无感操作") {
                Toggle("静默操作：快捷键执行后不弹出主窗口", isOn: $store.silentOperationEnabled)
                Toggle("显示桌面悬浮球", isOn: $store.floatingOrbEnabled)
                Text("静默操作适合自动模式和批量截图：截图、分析、复制结果会在后台完成，需要查看时再打开主窗口或悬浮球。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("历史保留", selection: $store.historyRetention) {
                Text("1 天").tag("1 天")
                Text("7 天").tag("7 天")
                Text("30 天").tag("30 天")
                Text("永不清理").tag("永不清理")
            }

            Toggle("保留原始截图", isOn: $store.keepOriginalScreenshots)

            Section("关于") {
                LabeledContent("应用", value: AppVersionInfo.current.appName)
                LabeledContent("版本", value: AppVersionInfo.current.versionText)
                LabeledContent("构建", value: AppVersionInfo.current.buildNumber)
                LabeledContent("Bundle ID", value: AppVersionInfo.current.bundleIdentifier)
            }
            .textSelection(.enabled)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(16)
        .frame(maxWidth: 760, maxHeight: .infinity, alignment: .topLeading)
        .glassPanel(cornerRadius: 14, material: .regularMaterial)
        .background {
            ShortcutRecorderView(
                isRecording: store.recordingHotKeyAction != nil,
                onRecord: { shortcut in
                    if let action = store.recordingHotKeyAction {
                        store.saveShortcut(shortcut, for: action)
                    }
                },
                onCancel: {
                    store.cancelRecordingShortcut()
                }
            )
            .frame(width: 0, height: 0)
        }
    }
}
