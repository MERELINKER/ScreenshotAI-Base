import SwiftUI
import ScreenshotAIKit

struct FloatingPromptInputView: View {
    @Bindable var store: DemoTaskStore
    let runPrompt: (String) -> Void
    let runRevision: (String) -> Void
    let openMainWindow: () -> Void
    let close: () -> Void
    let setPanelSize: (FloatingPromptPanelSize) -> Void

    @State private var promptText = ""
    @State private var activeImageIndex = 0
    @State private var showsActionPopover = false
    @State private var feedbackText: String?
    @State private var feedbackIsSuccess = true
    @State private var hasSubmittedRequest = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: isResultMode ? 12 : 8) {
            inputRow
            promptSuggestions
            statusLine
            if isResultMode {
                resultPanel
            }
        }
        .padding(.horizontal, isResultMode ? 14 : 12)
        .padding(.vertical, isResultMode ? 12 : 8)
        .frame(width: isResultMode ? 540 : 360, alignment: .leading)
        .glassPanel(cornerRadius: 18, material: .ultraThinMaterial, isInteractive: true)
        .onAppear {
            promptText = store.customPrompt
            activeImageIndex = firstMissingBatchPromptIndex()
            let initialState = FloatingPromptInitialState(resultText: resultText, statusMessage: store.statusMessage)
            hasSubmittedRequest = initialState.hasSubmittedRequest
            if let initialFeedback = initialState.feedbackText {
                feedbackText = initialFeedback
                feedbackIsSuccess = false
            }
            updatePanelSize(animated: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isFocused = true
            }
        }
        .onChange(of: showsPromptSuggestions) { _, isExpanded in
            updatePanelSize()
        }
        .onChange(of: feedbackText) { _, _ in
            updatePanelSize()
        }
        .onChange(of: store.isRunning) { wasRunning, isRunning in
            if wasRunning, !isRunning, hasSubmittedRequest {
                if resultText.isEmpty {
                    showFeedback(store.statusMessage, isSuccess: false)
                }
            }
            updatePanelSize()
        }
        .onChange(of: resultText) { _, _ in
            updatePanelSize()
        }
    }

    private var inputRow: some View {
        HStack(spacing: 7) {
            FloatingPanelDragHandle().frame(width: 26, height: 28)

            Image(systemName: isResultMode ? "wand.and.stars" : "sparkles")
                .foregroundStyle(.secondary)
                .frame(width: 15)

            TextField(placeholderText, text: $promptText)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit {
                    submitCurrentInput()
                }
                .frame(minWidth: 0)

            if !isResultMode {
                Button {
                    submitCurrentInput()
                } label: {
                    Image(systemName: "return")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.borderless)
                .frame(width: 22, height: 22)
                .help("执行")

                Button {
                    showsActionPopover.toggle()
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.borderless)
                .frame(width: 22, height: 22)
                .help("更多")
                .popover(isPresented: $showsActionPopover, arrowEdge: .bottom) {
                    promptActionsPopover
                }
            }
        }
    }

    @ViewBuilder
    private var promptSuggestions: some View {
        if showsPromptSuggestions, !isResultMode {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(store.savedPrompts) { prompt in
                        Button(prompt.name) {
                            promptText = prompt.promptText
                            isFocused = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            .frame(height: 28)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if shouldReserveStatusLine {
            HStack(spacing: 7) {
                if store.isRunning, hasSubmittedRequest {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在执行...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let feedbackText {
                    Label(feedbackText, systemImage: feedbackIsSuccess ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(feedbackIsSuccess ? .green : .orange)
                        .lineLimit(1)
                } else {
                    Text(" ")
                        .font(.caption)
                        .hidden()
                }
                Spacer(minLength: 0)
            }
            .frame(height: 18, alignment: .leading)
        }
    }

    private var resultPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("结果", systemImage: "checkmark.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("可继续调整")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                Text(resultText)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 230)
            .padding(10)
            .glassPanel(cornerRadius: 12, material: .thinMaterial)

            HStack(spacing: 8) {
                Button {
                    store.copyCurrentResult()
                    showFeedback("已复制结果")
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }

                Button {
                    submitRevision()
                } label: {
                    Label("继续调整", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isRunning)

                Spacer()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var promptActionsPopover: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                savePrompt()
                showsActionPopover = false
            } label: {
                Label("保存当前 Prompt", systemImage: "plus.square.on.square")
            }

            Button {
                showsActionPopover = false
                openMainWindow()
            } label: {
                Label("打开主窗口", systemImage: "macwindow")
            }

            if store.batchCount > 0 {
                Button {
                    store.clearBatch()
                    showFeedback("已清空当前队列")
                    showsActionPopover = false
                } label: {
                    Label("清空当前队列", systemImage: "trash")
                }
            }

            Divider()

            Button {
                showsActionPopover = false
                close()
            } label: {
                Label("关闭", systemImage: "xmark.circle")
            }
        }
        .buttonStyle(.plain)
        .labelStyle(.titleAndIcon)
        .padding(10)
        .frame(width: 168, alignment: .leading)
    }

    private var showsPromptSuggestions: Bool {
        promptText.contains("@")
    }

    private var resultText: String {
        store.currentResultText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var isResultMode: Bool {
        hasSubmittedRequest && !resultText.isEmpty
    }

    private var shouldReserveStatusLine: Bool {
        isResultMode || feedbackText != nil || (store.isRunning && hasSubmittedRequest)
    }

    private var isBatchPerImagePromptEntry: Bool {
        store.captureMode == .batch
            && store.batchPromptMapping == .perImagePrompt
            && !store.batchSession.images.isEmpty
    }

    private var placeholderText: String {
        if isResultMode {
            return "输入调整要求，按 Return 继续"
        }

        if isBatchPerImagePromptEntry,
           store.batchSession.images.indices.contains(activeImageIndex) {
            return "第 \(activeImageIndex + 1) 张：\(store.batchSession.images[activeImageIndex].displayName) 的 Prompt，Return 下一张"
        }

        if store.captureMode == .batch {
            return "输入共享 Prompt，Return 执行；输入 @ 选择保存的 Prompt"
        }

        return "输入 Prompt，Return 执行；输入 @ 选择保存的 Prompt"
    }

    private func submitCurrentInput() {
        if isResultMode {
            submitRevision()
        } else {
            submitPrompt()
        }
    }

    private func submitPrompt() {
        let trimmedPrompt = promptText
            .replacingOccurrences(of: "@", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            showFeedback("Prompt 为空", isSuccess: false)
            return
        }

        if submitPerImagePrompt(trimmedPrompt) {
            return
        }

        promptText = ""
        hasSubmittedRequest = true
        showFeedback("已提交，正在执行...")
        runPrompt(trimmedPrompt)
    }

    @discardableResult
    private func submitPerImagePrompt(_ prompt: String) -> Bool {
        guard isBatchPerImagePromptEntry,
              store.batchSession.images.indices.contains(activeImageIndex)
        else {
            return false
        }

        let image = store.batchSession.images[activeImageIndex]
        store.setBatchPrompt(prompt, for: image)

        if activeImageIndex + 1 < store.batchSession.images.count {
            let savedIndex = activeImageIndex + 1
            activeImageIndex += 1
            promptText = ""
            showFeedback("已保存第 \(savedIndex) 张，继续输入第 \(activeImageIndex + 1) 张")
            DispatchQueue.main.async {
                isFocused = true
            }
        } else {
            let fallbackPrompt = store.customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            promptText = ""
            hasSubmittedRequest = true
            showFeedback("逐图 Prompt 已提交，正在执行...")
            runPrompt(fallbackPrompt.isEmpty ? "按每张截图对应的 Prompt 完成任务。" : fallbackPrompt)
        }
        return true
    }

    private func submitRevision() {
        let instruction = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else {
            showFeedback("请输入调整要求", isSuccess: false)
            return
        }
        guard !store.isRunning else { return }
        promptText = ""
        hasSubmittedRequest = true
        showFeedback("已提交调整，正在执行...")
        runRevision(instruction)
    }

    private func savePrompt() {
        let trimmedPrompt = promptText
            .replacingOccurrences(of: "@", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return }
        store.saveFloatingPrompt(trimmedPrompt)
        showFeedback("已保存 Prompt")
    }

    private func firstMissingBatchPromptIndex() -> Int {
        guard store.captureMode == .batch else { return 0 }
        return store.batchSession.images.firstIndex { image in
            store.batchPrompt(for: image).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? max(store.batchSession.images.count - 1, 0)
    }

    private func showFeedback(_ message: String, isSuccess: Bool = true) {
        feedbackText = message
        feedbackIsSuccess = isSuccess
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            if feedbackText == message {
                feedbackText = nil
            }
        }
    }

    private func updatePanelSize(animated: Bool = true) {
        if isResultMode {
            setPanelSize(.result)
        } else if showsPromptSuggestions || feedbackText != nil || (store.isRunning && hasSubmittedRequest) {
            setPanelSize(.feedback)
        } else {
            setPanelSize(.compact)
        }
    }

}

struct FloatingPromptInitialState: Equatable {
    let hasSubmittedRequest: Bool
    let feedbackText: String?

    init(resultText: String, statusMessage: String) {
        let hasResult = !resultText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        hasSubmittedRequest = hasResult || statusMessage.contains("失败")
        feedbackText = !hasResult && statusMessage.contains("失败") ? statusMessage : nil
    }
}
