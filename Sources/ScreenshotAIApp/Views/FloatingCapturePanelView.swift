import AppKit
import SwiftUI
import ScreenshotAIKit

struct FloatingCapturePanelView: View {
    @Bindable var store: DemoTaskStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    screenshotPreview
                    VStack(alignment: .leading, spacing: 12) {
                        promptHeader
                        promptButtons
                        customPromptField
                        batchControls
                        HStack(spacing: 8) {
                            Button {
                                Task {
                                    await store.captureScreenshot()
                                }
                            } label: {
                                Label(captureButtonTitle, systemImage: "camera.viewfinder")
                            }

                            Button {
                                Task {
                                    await store.runLocalOCR()
                                }
                            } label: {
                                Label("本地 OCR", systemImage: "text.viewfinder")
                            }
                        }
                        .controlSize(.large)
                        .disabled(store.isCapturing || store.isRunning)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassPanel(cornerRadius: 14, material: .regularMaterial)
                }

                if let result = store.currentResultText {
                    resultSection(result)
                        .padding(14)
                        .glassPanel(cornerRadius: 14, material: .regularMaterial)
                }

                HStack {
                    Label(store.statusMessage, systemImage: "sparkles")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        store.selectedSection = .timeline
                    } label: {
                        Label("打开时间线", systemImage: "clock.arrow.circlepath")
                    }
                }
                .padding(12)
                .glassPanel(cornerRadius: 12, material: .ultraThinMaterial)
            }
            .padding(2)
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $store.isPromptEditorPresented) {
            PromptEditorSheet(store: store)
        }
    }

    private var screenshotPreview: some View {
        ZStack {
            if let fileURL = store.activePreviewCapture?.fileURL,
               let image = NSImage(contentsOf: fileURL) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 180, height: 130)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.quaternary)
                    .frame(width: 180, height: 130)
            }

            if store.activePreviewCapture == nil {
                VStack(spacing: 8) {
                    Image(systemName: "camera.metering.center.weighted")
                        .font(.title2)
                    Text("还没有截图")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
        .frame(width: 180, height: 130)
        .glassPanel(cornerRadius: 14, material: .regularMaterial, isInteractive: true)
        .overlay(alignment: .bottomLeading) {
            Text(previewBadgeText)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.regularMaterial, in: Capsule())
                .padding(6)
        }
    }

    private var previewBadgeText: String {
        if store.captureMode == .batch {
            return store.batchCount > 0 ? "批量 \(store.batchCount)" : "批量"
        }
        return store.captureMode.title
    }

    private var captureButtonTitle: String {
        store.captureMode == .batch ? "添加截图到批量" : "重新框选截图"
    }

    private var promptButtons: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.savedPrompts) { prompt in
                    HStack(spacing: 4) {
                        Button(prompt.name) {
                            Task {
                                await store.runSavedPrompt(prompt)
                            }
                        }
                        .disabled(store.isCapturing || store.isRunning)

                        Menu {
                            Button("编辑 Prompt") {
                                store.openPromptEditor(for: prompt)
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .imageScale(.medium)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("更多 Prompt 操作")
                    }
                    .fixedSize()
                }
            }
        }
        .frame(height: 34)
    }

    private var promptHeader: some View {
        HStack {
            Text("保存的 Prompt")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                store.openNewPromptEditor()
            } label: {
                Label("保存当前", systemImage: "plus")
            }
            .disabled(store.customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("把输入框里的内容保存成 Prompt")
        }
    }

    private var customPromptField: some View {
        HStack(spacing: 8) {
            TextField("输入 Prompt，按 Return 执行", text: $store.customPrompt)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    Task {
                        await store.runCustomPrompt()
                    }
                }
            Button("执行") {
                Task {
                    await store.runCustomPrompt()
                }
            }
            .disabled(store.isCapturing || store.isRunning)
        }
    }

    @ViewBuilder
    private var batchControls: some View {
        if store.captureMode == .batch {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Label("已加入 \(store.batchCount) 张", systemImage: "rectangle.stack")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        store.clearBatch()
                    } label: {
                        Label("清空批量", systemImage: "trash")
                    }
                    .disabled(store.batchCount == 0 || store.isRunning)
                }

                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    GridRow {
                        Text("输出")
                            .foregroundStyle(.secondary)
                        Picker("输出", selection: $store.batchOutputGranularity) {
                            Text(OutputGranularity.mergedResult.title).tag(OutputGranularity.mergedResult)
                            Text(OutputGranularity.perImageResult.title).tag(OutputGranularity.perImageResult)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }

                    GridRow {
                        Text("Prompt")
                            .foregroundStyle(.secondary)
                        Picker("Prompt", selection: $store.batchPromptMapping) {
                            ForEach(PromptMapping.allCases, id: \.self) { mapping in
                                Text(mapping.title).tag(mapping)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }

                    GridRow {
                        Text("策略")
                            .foregroundStyle(.secondary)
                        Picker("策略", selection: $store.batchExecutionStrategy) {
                            ForEach(ExecutionStrategy.allCases, id: \.self) { strategy in
                                Text(strategy.title).tag(strategy)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .disabled(store.batchOutputGranularity == .perImageResult)
                    }
                }
                .font(.caption)

                if store.batchPromptMapping == .perImagePrompt {
                    batchPromptAssignments
                }
            }
            .padding(10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var batchPromptAssignments: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("逐图 Prompt")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(store.batchSession.images) { image in
                        HStack(spacing: 8) {
                            Text(image.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(width: 120, alignment: .leading)
                            TextField(
                                "留空则使用主 Prompt",
                                text: Binding(
                                    get: { store.batchPrompt(for: image) },
                                    set: { store.setBatchPrompt($0, for: image) }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                        }
                    }
                }
            }
            .frame(maxHeight: 130)
        }
    }

    private func resultSection(_ result: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("结果")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    store.copyCurrentResult()
                } label: {
                    Label("复制结果", systemImage: "doc.on.doc")
                }
            }

            ScrollView {
                Text(result)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 180)

            HStack(spacing: 8) {
                TextField("告诉 AI 怎么调整这版结果", text: $store.revisionInstruction)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task {
                            await store.reviseCurrentResult()
                        }
                    }
                Button {
                    Task {
                        await store.reviseCurrentResult()
                    }
                } label: {
                    Label("调整", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(store.isCapturing || store.isRunning)
            }
        }
    }
}

private struct PromptEditorSheet: View {
    @Bindable var store: DemoTaskStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(store.editingPromptID == nil ? "保存 Prompt" : "编辑 Prompt")
                .font(.title3.weight(.semibold))

            TextField("名称", text: $store.promptNameDraft)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $store.promptTextDraft)
                .font(.body)
                .frame(minHeight: 160)
                .padding(6)
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(.quaternary)
                }

            Toggle("设为自动模式默认 Prompt", isOn: $store.promptDraftIsAutoActive)

            if !store.promptEditorStatus.isEmpty {
                Text(store.promptEditorStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                if store.editingPromptID != nil {
                    Button("删除", role: .destructive) {
                        store.deleteEditingPrompt()
                    }
                }

                Spacer()

                Button("取消") {
                    store.cancelPromptEditor()
                }
                Button("保存") {
                    store.savePromptDraft()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}

private struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: spacing) {
            content
        }
    }
}
