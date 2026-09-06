import SwiftUI
import ScreenshotAIKit

struct MainWindowView: View {
    @Bindable var store: DemoTaskStore

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()

            VStack(spacing: 0) {
                toolbar
                Divider()
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 980, minHeight: 640)
        .alert("截图未完成", isPresented: Binding(
            get: { store.captureErrorMessage != nil },
            set: { if !$0 { store.captureErrorMessage = nil } }
        )) {
            Button("打开屏幕录制设置") { store.openScreenRecordingSettings() }
            Button("知道了", role: .cancel) {}
        } message: {
            Text(store.captureErrorMessage ?? "截图失败")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(AppVersionInfo.current.appName)
                    .font(.headline)
                Text(AppVersionInfo.current.versionText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(AppVersionInfo.current.buildText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .textSelection(.enabled)
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            ForEach(MainAppSection.allCases) { section in
                Button {
                    store.selectedSection = section
                } label: {
                    Label(section.title, systemImage: section.systemImage)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                .foregroundStyle(store.selectedSection == section ? .primary : .secondary)
                .background {
                    if store.selectedSection == section {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(.quaternary)
                    }
                }
                .padding(.horizontal, 8)
            }

            Spacer()
        }
        .frame(width: 188)
        .frame(maxHeight: .infinity)
        .layoutPriority(1)
        .background(.bar)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text(store.selectedSection.title)
                .font(.title3.weight(.semibold))

            Spacer()

            Picker("模式", selection: $store.captureMode) {
                ForEach(CaptureMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 210)

            Button {
                Task {
                    await store.captureScreenshot()
                }
            } label: {
                Label("截图", systemImage: "camera.viewfinder")
            }
            .disabled(store.isCapturing || store.isRunning)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder
    private var content: some View {
        switch store.selectedSection {
        case .capture:
            FloatingCapturePanelView(store: store)
                .padding(16)
        case .timeline:
            TaskCenterView(store: store)
                .padding(16)
        case .settings:
            SettingsView(store: store)
                .padding(16)
        }
    }
}

private extension MainAppSection {
    var systemImage: String {
        switch self {
        case .capture:
            return "camera.viewfinder"
        case .timeline:
            return "clock.arrow.circlepath"
        case .settings:
            return "gearshape"
        }
    }
}
