import Foundation
import AppKit
import Observation
import ScreenshotAIKit

enum MainAppSection: String, CaseIterable, Identifiable {
    case capture
    case timeline
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .capture:
            return "截图分析"
        case .timeline:
            return "时间线"
        case .settings:
            return "设置"
        }
    }
}

@MainActor
@Observable
final class DemoTaskStore {
    var captureErrorMessage: String?
    var selectedSection: MainAppSection = .capture
    var captureMode: CaptureMode = .manual {
        didSet {
            guard captureMode != oldValue else { return }
            UserDefaults.standard.set(captureMode.rawValue, forKey: DefaultsKeys.captureMode)
            statusMessage = "当前模式：\(captureMode.title)"
        }
    }
    var savedPrompts: [SavedPrompt] = []
    var tasks: [AITask] = []
    var expandedTaskIDs: Set<UUID> = []
    var batchSession = BatchCaptureSession()
    var batchOutputGranularity: OutputGranularity = .mergedResult
    var batchPromptMapping: PromptMapping = .sharedPrompt
    var batchExecutionStrategy: ExecutionStrategy = .fastMerge
    var batchPerImagePrompts: [UUID: String] = [:]
    var statusMessage: String = "先在设置里填写 API Key，然后点击“框选截图”。"
    var customPrompt: String = ""
    var revisionInstruction: String = ""
    var isPromptEditorPresented = false
    var editingPromptID: UUID?
    var promptNameDraft: String = ""
    var promptTextDraft: String = ""
    var promptDraftIsAutoActive = false
    var promptEditorStatus: String = ""
    var concurrencyLimit: Int = 2
    var historyRetention: String = "7 天"
    var keepOriginalScreenshots: Bool = false
    var silentOperationEnabled: Bool {
        didSet {
            UserDefaults.standard.set(silentOperationEnabled, forKey: DefaultsKeys.silentOperationEnabled)
            statusMessage = silentOperationEnabled ? "已开启静默操作：快捷键执行后不弹出主窗口。" : "已关闭静默操作。"
        }
    }
    var floatingOrbEnabled: Bool {
        didSet {
            UserDefaults.standard.set(floatingOrbEnabled, forKey: DefaultsKeys.floatingOrbEnabled)
            statusMessage = floatingOrbEnabled ? "已显示悬浮球。" : "已隐藏悬浮球。"
        }
    }
    var currentCapture: ImageAsset?
    var currentResultText: String?
    var isCapturing = false
    var isRunning = false
    var apiBaseURLString: String
    var modelName: String
    var apiKeyDraft: String
    var providerStatus: String = "API Key 会保存到 macOS Keychain。"
    var captureDirectory: URL
    var captureDirectoryStatus: String = "截图会保存到此目录，并同时复制到剪切板。"
    var hotKeyShortcuts: [HotKeyAction: KeyboardShortcutDefinition] = [:]
    var recordingHotKeyAction: HotKeyAction?
    var hotKeyStatus: String = "点击“录制”，然后按下新的组合键。"

    @ObservationIgnored private let screenshotService: any ScreenshotCapturing
    @ObservationIgnored private let captureDirectoryService = CaptureDirectoryService()
    @ObservationIgnored private let captureStoragePreferences = CaptureStoragePreferences()
    @ObservationIgnored private let clipboard = ClipboardService()
    @ObservationIgnored private let keychain = KeychainCredentialStore()
    @ObservationIgnored private let localTextRecognition = LocalTextRecognitionService()
    @ObservationIgnored private let visionClient = VisionAPIClient()
    @ObservationIgnored private let resultCleaner = GeneratedResultCleaner()
    @ObservationIgnored private let revisionPromptBuilder = ResultRevisionPromptBuilder()
    @ObservationIgnored private let hotKeyPreferences = HotKeyPreferences()
    @ObservationIgnored private let promptLibrary = SavedPromptLibrary()
    @ObservationIgnored private var lastPromptText: String?
    @ObservationIgnored private var lastAnalyzedImages: [ImageAsset] = []

    init(screenshotService: any ScreenshotCapturing = InteractiveScreenshotService(), loadCredentials: Bool = true) {
        self.screenshotService = screenshotService
        let defaults = UserDefaults.standard
        let storedBaseURL = defaults.string(forKey: DefaultsKeys.apiBaseURL) ?? "https://api.openai.com/v1"
        let initialBaseURL = Self.normalizedAPIBaseURLString(storedBaseURL) ?? storedBaseURL
        if initialBaseURL != storedBaseURL {
            defaults.set(initialBaseURL, forKey: DefaultsKeys.apiBaseURL)
        }
        let initialModelName = defaults.string(forKey: DefaultsKeys.modelName) ?? "gpt-4.1"
        let initialCaptureMode = defaults.string(forKey: DefaultsKeys.captureMode)
            .flatMap(CaptureMode.init(rawValue:)) ?? .manual
        self.apiBaseURLString = initialBaseURL
        self.modelName = initialModelName
        self.apiKeyDraft = loadCredentials ? keychain.readAPIKey() ?? "" : ""
        self.captureMode = initialCaptureMode
        self.silentOperationEnabled = defaults.bool(forKey: DefaultsKeys.silentOperationEnabled)
        self.floatingOrbEnabled = defaults.object(forKey: DefaultsKeys.floatingOrbEnabled) as? Bool ?? true
        self.captureDirectory = captureStoragePreferences.captureDirectory()
        self.hotKeyShortcuts = hotKeyPreferences.allShortcuts()

        let provider = ProviderRef(providerID: "openai-compatible", modelName: initialModelName)
        self.savedPrompts = (try? promptLibrary.load()) ?? SavedPromptLibrary.defaultPrompts(provider: provider)
        refreshPromptProviders(persistChanges: false)
    }

    private static func normalizedAPIBaseURLString(_ rawValue: String) -> String? {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmedValue),
              components.scheme != nil,
              components.host != nil
        else {
            return nil
        }

        if components.path.isEmpty || components.path == "/" {
            components.path = "/v1"
        }

        return components.string
    }

    var activePrompt: SavedPrompt? {
        savedPrompts.first { $0.isAutoActive } ?? savedPrompts.first
    }

    var hasCapture: Bool {
        currentCapture?.fileURL != nil
    }

    var activePreviewCapture: ImageAsset? {
        captureMode == .batch ? batchSession.latestImage : currentCapture
    }

    var batchCount: Int {
        batchSession.count
    }

    var canRunBatch: Bool {
        captureMode == .batch && !batchSession.images.isEmpty
    }

    var canRunCurrentModeImages: Bool {
        captureMode == .batch ? !batchSession.images.isEmpty : hasCapture
    }

    var captureDirectoryPath: String {
        captureDirectory.path
    }

    func batchPrompt(for image: ImageAsset) -> String {
        batchPerImagePrompts[image.id] ?? ""
    }

    func setBatchPrompt(_ prompt: String, for image: ImageAsset) {
        if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            batchPerImagePrompts.removeValue(forKey: image.id)
        } else {
            batchPerImagePrompts[image.id] = prompt
        }
    }

    func setMode(_ mode: CaptureMode) {
        captureMode = mode
        statusMessage = "当前模式：\(mode.title)"
    }

    func cycleCaptureMode() {
        switch captureMode {
        case .manual:
            setMode(.auto)
        case .auto:
            setMode(.batch)
        case .batch:
            setMode(.manual)
        }
    }

    func saveFloatingPrompt(_ promptText: String) {
        let trimmedPrompt = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            statusMessage = "请先输入 Prompt。"
            return
        }

        let provider = ProviderRef(providerID: "openai-compatible", modelName: modelName)
        savedPrompts.append(
            SavedPrompt(
                name: suggestedPromptName(for: trimmedPrompt),
                promptText: trimmedPrompt,
                outputGranularity: .singleImageResult,
                provider: provider,
                executionStrategy: .fastMerge,
                isAutoActive: savedPrompts.isEmpty
            )
        )
        _ = persistSavedPrompts(successMessage: "已保存 Prompt。")
    }

    func saveProviderSettings() {
        let trimmedBaseURL = apiBaseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAPIKey = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let normalizedBaseURL = Self.normalizedAPIBaseURLString(trimmedBaseURL) else {
            providerStatus = "Base URL 无效。"
            return
        }
        guard !trimmedModel.isEmpty else {
            providerStatus = "模型名不能为空。"
            return
        }

        UserDefaults.standard.set(normalizedBaseURL, forKey: DefaultsKeys.apiBaseURL)
        UserDefaults.standard.set(trimmedModel, forKey: DefaultsKeys.modelName)
        apiBaseURLString = normalizedBaseURL
        modelName = trimmedModel

        do {
            if trimmedAPIKey.isEmpty {
                try keychain.deleteAPIKey()
                providerStatus = "已清空 API Key。"
            } else {
                try keychain.saveAPIKey(trimmedAPIKey)
                if URL(string: normalizedBaseURL)?.scheme?.lowercased() == "http" {
                    providerStatus = "已保存 API 设置。注意：当前使用 http://，请求会明文传输。"
                } else {
                    providerStatus = "已保存 API 设置。"
                }
            }
            refreshPromptProviders(persistChanges: true)
        } catch {
            providerStatus = error.localizedDescription
        }
    }

    func chooseCaptureDirectory() {
        guard let directory = captureDirectoryService.chooseDirectory(currentDirectory: captureDirectory) else {
            captureDirectoryStatus = "已取消选择目录。"
            return
        }

        captureDirectory = directory
        captureStoragePreferences.setCaptureDirectory(directory)
        captureDirectoryStatus = "已设置截图保存目录。"
    }

    func openCaptureDirectory() {
        do {
            try captureDirectoryService.openDirectory(captureDirectory)
            captureDirectoryStatus = "已打开截图保存目录。"
        } catch {
            captureDirectoryStatus = "打开目录失败：\(error.localizedDescription)"
        }
    }

    func openNewPromptEditor() {
        let trimmedPrompt = customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        promptNameDraft = suggestedPromptName(for: trimmedPrompt)
        promptTextDraft = trimmedPrompt
        promptDraftIsAutoActive = savedPrompts.isEmpty
        editingPromptID = nil
        promptEditorStatus = ""
        isPromptEditorPresented = true
    }

    func openPromptEditor(for prompt: SavedPrompt) {
        promptNameDraft = prompt.name
        promptTextDraft = prompt.promptText
        promptDraftIsAutoActive = prompt.isAutoActive
        editingPromptID = prompt.id
        promptEditorStatus = ""
        isPromptEditorPresented = true
    }

    func cancelPromptEditor() {
        isPromptEditorPresented = false
        editingPromptID = nil
        promptEditorStatus = ""
    }

    func savePromptDraft() {
        let trimmedName = promptNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = promptTextDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            promptEditorStatus = "请填写 Prompt 名称。"
            return
        }
        guard !trimmedPrompt.isEmpty else {
            promptEditorStatus = "请填写 Prompt 内容。"
            return
        }

        let provider = ProviderRef(providerID: "openai-compatible", modelName: modelName)
        if let editingPromptID,
           let index = savedPrompts.firstIndex(where: { $0.id == editingPromptID }) {
            savedPrompts[index].name = trimmedName
            savedPrompts[index].promptText = trimmedPrompt
            savedPrompts[index].provider = provider
            savedPrompts[index].isAutoActive = promptDraftIsAutoActive
        } else {
            savedPrompts.append(
                SavedPrompt(
                    name: trimmedName,
                    promptText: trimmedPrompt,
                    outputGranularity: .singleImageResult,
                    provider: provider,
                    executionStrategy: .fastMerge,
                    isAutoActive: promptDraftIsAutoActive
                )
            )
        }

        if promptDraftIsAutoActive {
            markOnlyActivePrompt(editingPromptID ?? savedPrompts.last?.id)
        } else if savedPrompts.allSatisfy({ !$0.isAutoActive }) {
            savedPrompts.indices.first.map { savedPrompts[$0].isAutoActive = true }
        }

        if persistSavedPrompts(successMessage: "已保存 Prompt：\(trimmedName)") {
            customPrompt = ""
            cancelPromptEditor()
        }
    }

    func deleteEditingPrompt() {
        guard let editingPromptID else { return }
        savedPrompts.removeAll { $0.id == editingPromptID }
        if savedPrompts.allSatisfy({ !$0.isAutoActive }) {
            savedPrompts.indices.first.map { savedPrompts[$0].isAutoActive = true }
        }
        if persistSavedPrompts(successMessage: "已删除 Prompt。") {
            cancelPromptEditor()
        }
    }

    func shortcutDisplay(for action: HotKeyAction) -> String {
        (hotKeyShortcuts[action] ?? action.defaultShortcut).displayText
    }

    func beginRecordingShortcut(for action: HotKeyAction) {
        recordingHotKeyAction = action
        hotKeyStatus = "正在录制“\(action.title)”快捷键。按 Esc 取消。"
    }

    func cancelRecordingShortcut() {
        recordingHotKeyAction = nil
        hotKeyStatus = "已取消录制。"
    }

    func saveShortcut(_ shortcut: KeyboardShortcutDefinition, for action: HotKeyAction) {
        if let conflictingAction = hotKeyPreferences.action(matching: shortcut, excluding: action) {
            hotKeyStatus = "快捷键 \(shortcut.displayText) 已被“\(conflictingAction.title)”使用。"
            return
        }

        do {
            try hotKeyPreferences.setShortcut(shortcut, for: action)
            hotKeyShortcuts[action] = shortcut
            recordingHotKeyAction = nil
            hotKeyStatus = "已保存 \(action.title)：\(shortcut.displayText)"
            GlobalHotKeyService.shared.reloadShortcuts()
        } catch {
            hotKeyStatus = "保存快捷键失败：\(error.localizedDescription)"
        }
    }

    @discardableResult
    func captureScreenshot() async -> Bool {
        guard !isCapturing, !isRunning else { return false }
        isCapturing = true
        defer { isCapturing = false }
        captureErrorMessage = nil
        statusMessage = "请拖拽框选截图区域。"
        currentResultText = nil

        do {
            let capture = try await screenshotService.capture(saveDirectory: captureDirectory)
            currentCapture = capture.image
            if captureMode == .batch {
                batchSession.append(capture.image)
                batchPerImagePrompts[capture.image.id] = customPrompt
            }
            do {
                if let fileURL = capture.image.fileURL {
                    try clipboard.copyImage(at: fileURL)
                    if captureMode == .batch {
                        statusMessage = "批量模式：已加入第 \(batchSession.count) 张截图，图片已复制到剪切板。"
                    } else {
                        statusMessage = "截图完成，图片已复制到剪切板。请选择 Prompt 或输入新 Prompt。"
                    }
                } else {
                    statusMessage = "截图完成。请选择 Prompt 或输入新 Prompt。"
                }
            } catch {
                statusMessage = "截图完成，但复制图片失败：\(error.localizedDescription)"
            }
            return true
        } catch ScreenshotCaptureError.canceled {
            statusMessage = "截图已取消，没有执行 AI 分析。"
            return false
        } catch {
            statusMessage = error.localizedDescription
            captureErrorMessage = error.localizedDescription
            return false
        }
    }

    func captureAndRunActivePrompt() async {
        guard await captureScreenshot() else { return }
        guard let prompt = activePrompt, hasCapture else { return }
        await runSavedPrompt(prompt)
    }

    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    @discardableResult
    func captureAndRunLocalOCR() async -> Bool {
        guard await captureScreenshot() else { return false }
        return await runLocalOCR()
    }

    @discardableResult
    func runLocalOCR() async -> Bool {
        guard !isCapturing, !isRunning else { return false }

        if !hasCapture {
            guard await captureScreenshot() else { return false }
        }
        guard let image = currentCapture,
              let fileURL = image.fileURL
        else {
            statusMessage = "没有可识别的截图。"
            return false
        }

        isRunning = true
        defer { isRunning = false }
        statusMessage = "正在进行本地 OCR…"
        currentResultText = nil

        do {
            let imageData = try Data(contentsOf: fileURL)
            let recognized = try await localTextRecognition.recognize(imageData)
            let text = recognized.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                statusMessage = "本地 OCR 未识别到文字。"
                return false
            }
            currentResultText = text
            lastPromptText = nil
            lastAnalyzedImages = [image]
            do {
                try clipboard.copyText(text)
                statusMessage = "本地 OCR 完成，文字已复制到剪切板。"
            } catch {
                statusMessage = "本地 OCR 完成，但复制失败：\(error.localizedDescription)"
            }
            return true
        } catch {
            statusMessage = "本地 OCR 失败：\(error.localizedDescription)"
            return false
        }
    }

    func runSavedPrompt(_ prompt: SavedPrompt) async {
        if !canRunCurrentModeImages {
            await captureScreenshot()
        }
        guard canRunCurrentModeImages else { return }
        await analyzeCurrentCapture(
            promptText: prompt.promptText,
            outputGranularity: captureMode == .batch ? batchOutputGranularity : prompt.outputGranularity,
            executionStrategy: captureMode == .batch ? batchExecutionStrategy : prompt.executionStrategy
        )
    }

    func runCustomPrompt() async {
        let trimmedPrompt = customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            statusMessage = "请先输入 Prompt。"
            return
        }

        if !canRunCurrentModeImages {
            await captureScreenshot()
        }
        guard canRunCurrentModeImages else { return }

        customPrompt = ""
        await analyzeCurrentCapture(
            promptText: trimmedPrompt,
            outputGranularity: captureMode == .batch ? batchOutputGranularity : .singleImageResult,
            executionStrategy: captureMode == .batch ? batchExecutionStrategy : .fastMerge
        )
    }

    func clearBatch() {
        batchSession.clear()
        batchPerImagePrompts.removeAll()
        lastAnalyzedImages.removeAll()
        if captureMode == .batch {
            currentCapture = nil
            currentResultText = nil
            statusMessage = "已清空批量截图队列。"
        }
    }

    func copyCurrentResult() {
        guard let currentResultText, !currentResultText.isEmpty else {
            statusMessage = "没有可复制的结果。"
            return
        }

        do {
            try clipboard.copyText(currentResultText)
            statusMessage = "结果已复制到剪切板。"
        } catch {
            statusMessage = "复制结果失败：\(error.localizedDescription)"
        }
    }

    func reviseCurrentResult() async {
        let instruction = revisionInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else {
            statusMessage = "请先输入调整要求。"
            return
        }
        guard let currentResultText, !currentResultText.isEmpty else {
            statusMessage = "还没有可调整的结果。"
            return
        }
        guard let lastPromptText, !lastPromptText.isEmpty else {
            statusMessage = "缺少上一轮 Prompt，无法调整。"
            return
        }

        revisionInstruction = ""
        let revisionPrompt = revisionPromptBuilder.makeRevisionPrompt(
            originalPrompt: lastPromptText,
            previousResult: currentResultText,
            instruction: instruction
        )

        await analyzeCurrentCapture(
            promptText: revisionPrompt,
            outputGranularity: .singleImageResult,
            executionStrategy: .fastMerge,
            displayPromptText: lastPromptText,
            imagesOverride: lastAnalyzedImages.isEmpty ? nil : lastAnalyzedImages,
            promptMappingOverride: .sharedPrompt
        )
    }

    func addBatchDemo() {
        captureMode = .batch
        statusMessage = batchSession.images.isEmpty
            ? "批量模式：继续截图可加入队列，选择 Prompt 后会合并分析。"
            : "批量模式：当前已有 \(batchSession.count) 张截图。"
    }

    func toggleExpanded(_ taskID: UUID) {
        if expandedTaskIDs.contains(taskID) {
            expandedTaskIDs.remove(taskID)
        } else {
            expandedTaskIDs.insert(taskID)
        }
    }

    func retryTask(_ task: AITask) async {
        guard !isRunning else { return }
        guard tasks.contains(where: { $0.id == task.id }) else { return }

        updateTask(
            task.id,
            state: .running,
            resultText: nil,
            errorMessage: nil,
            stepResults: [],
            stepFailures: [],
            plannedSteps: []
        )
        expandedTaskIDs.insert(task.id)
        isRunning = true
        statusMessage = task.images.count > 1 ? "正在重试批量任务..." : "正在重试任务..."
        await executeTask(taskID: task.id, displayPromptText: task.configuration.finalPrompt)
        isRunning = false
    }

    func retryTaskStep(_ failure: TaskStepFailure, in task: AITask) async {
        guard !isRunning else { return }
        guard let currentTask = tasks.first(where: { $0.id == task.id }),
              let step = currentTask.plannedSteps.first(where: { $0.id == failure.stepID })
        else {
            statusMessage = "找不到可重试的批量步骤。"
            return
        }

        let successfulStepIDs = Set(currentTask.stepResults.map(\.stepID))
        let missingDependencyIDs = step.dependsOnStepIDs.filter { !successfulStepIDs.contains($0) }
        guard missingDependencyIDs.isEmpty else {
            statusMessage = "请先重试该步骤依赖的截图。"
            return
        }

        updateTask(
            task.id,
            state: .running,
            resultText: currentTask.resultText,
            errorMessage: nil
        )
        isRunning = true
        statusMessage = "正在重试：\(taskStepTitle(step.kind))"
        await executeSingleStep(step, taskID: task.id)
        if step.kind != .merge {
            await retryReadySkippedMergeIfNeeded(taskID: task.id)
        }
        isRunning = false
    }

    private func analyzeCurrentCapture(
        promptText: String,
        outputGranularity: OutputGranularity,
        executionStrategy: ExecutionStrategy,
        displayPromptText: String? = nil,
        imagesOverride: [ImageAsset]? = nil,
        promptMappingOverride: PromptMapping? = nil
    ) async {
        guard makeEndpoint() != nil else { return }
        let images = imagesOverride ?? imagesForCurrentTask()
        guard !images.isEmpty else {
            statusMessage = "请先截图。"
            return
        }

        let isBatchTask = images.count > 1
        let promptMapping = promptMappingOverride ?? (isBatchTask ? batchPromptMapping : .sharedPrompt)
        let provider = ProviderRef(providerID: "openai-compatible", modelName: modelName)
        let task = AITask(
            images: images,
            configuration: TaskConfiguration(
                imageScope: images.count > 1 ? .multiple : .single,
                outputGranularity: outputGranularity,
                promptMapping: promptMapping,
                executionStrategy: executionStrategy,
                provider: provider,
                sharedPrompt: promptText,
                perImagePrompts: isBatchTask && promptMapping == .perImagePrompt ? normalizedBatchPrompts(for: images) : [:]
            ),
            state: .running
        )

        tasks.insert(task, at: 0)
        expandedTaskIDs.insert(task.id)
        isRunning = true
        statusMessage = images.count > 1
            ? "正在执行批量任务：\(images.count) 张截图，最多 \(concurrencyLimit) 路并发..."
            : "正在发送给模型..."

        await executeTask(taskID: task.id, displayPromptText: displayPromptText ?? promptText)
        if let resultText = currentResultText, !resultText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lastAnalyzedImages = images
            clearCompletedBatchQueueIfNeeded()
        }
        isRunning = false
    }

    private func clearCompletedBatchQueueIfNeeded() {
        guard captureMode == .batch, !batchSession.images.isEmpty else { return }
        batchSession.clear()
        batchPerImagePrompts.removeAll()
        currentCapture = nil
        statusMessage += " 批量队列已自动清空。"
    }

    private func executeTask(taskID: UUID, displayPromptText: String?) async {
        guard let endpoint = makeEndpoint() else {
            updateTask(
                taskID,
                state: .failed,
                resultText: nil,
                errorMessage: statusMessage,
                stepResults: [],
                stepFailures: []
            )
            return
        }
        guard let task = tasks.first(where: { $0.id == taskID }) else { return }

        do {
            let imageInputsByID = try makeImageInputMap(for: task.images)
            let plan = TaskPlanner().plan(task)
            setPlannedSteps(plan.steps, for: taskID)
            let executor = VisionTaskExecutor(
                endpoint: endpoint,
                imageInputsByID: imageInputsByID,
                client: visionClient,
                cleaner: resultCleaner
            )
            let queue = TaskQueue(maxConcurrentTasks: concurrencyLimit, executor: executor)
            let outcomes = await queue.run(plan)
            let summary = summarizeExecutionOutcomes(outcomes, plan: plan, task: task)
            let state: TaskState = summary.failures.isEmpty ? .done : .failed
            let errorMessage = summary.failures.isEmpty ? nil : failureSummaryMessage(summary.failures)

            updateTask(
                taskID,
                state: state,
                resultText: summary.resultText,
                errorMessage: errorMessage,
                stepResults: summary.results,
                stepFailures: summary.failures
            )
            lastPromptText = displayPromptText
            currentResultText = summary.resultText

            if let resultText = summary.resultText, !resultText.isEmpty {
                do {
                    try clipboard.copyText(resultText)
                    statusMessage = summary.failures.isEmpty
                        ? "分析完成，结果已复制到剪切板。"
                        : "批量任务有 \(summary.failures.count) 个步骤失败，成功部分已复制到剪切板。"
                } catch {
                    statusMessage = summary.failures.isEmpty
                        ? "分析完成，但复制结果失败：\(error.localizedDescription)"
                        : "批量任务有 \(summary.failures.count) 个步骤失败，复制成功部分失败：\(error.localizedDescription)"
                }
            } else {
                statusMessage = summary.failures.isEmpty ? "分析完成，但没有生成结果。" : "分析失败：\(errorMessage ?? "未知错误")"
            }
        } catch {
            updateTask(
                taskID,
                state: .failed,
                resultText: nil,
                errorMessage: error.localizedDescription,
                stepResults: [],
                stepFailures: []
            )
            statusMessage = "分析失败：\(error.localizedDescription)"
        }
    }

    private func executeSingleStep(_ step: TaskExecutionStep, taskID: UUID) async {
        guard let endpoint = makeEndpoint() else {
            updateStepFailure(step, taskID: taskID, message: statusMessage)
            return
        }
        guard let task = tasks.first(where: { $0.id == taskID }) else { return }

        do {
            let imageInputsByID = try makeImageInputMap(for: task.images)
            let executor = VisionTaskExecutor(
                endpoint: endpoint,
                imageInputsByID: imageInputsByID,
                client: visionClient,
                cleaner: resultCleaner,
                seedResults: task.stepResults
            )
            let result = try await executor.execute(step)
            applyStepRetrySuccess(result, taskID: taskID)
        } catch {
            updateStepFailure(step, taskID: taskID, message: error.localizedDescription)
        }
    }

    private func retryReadySkippedMergeIfNeeded(taskID: UUID) async {
        guard let task = tasks.first(where: { $0.id == taskID }),
              let mergeStep = task.plannedSteps.first(where: { $0.kind == .merge }),
              task.stepFailures.contains(where: { $0.stepID == mergeStep.id && $0.isSkipped })
        else { return }

        let successfulStepIDs = Set(task.stepResults.map(\.stepID))
        guard Set(mergeStep.dependsOnStepIDs).isSubset(of: successfulStepIDs) else { return }

        statusMessage = "依赖步骤已恢复，正在重试精细合并..."
        await executeSingleStep(mergeStep, taskID: taskID)
    }

    private func imagesForCurrentTask() -> [ImageAsset] {
        if captureMode == .batch {
            return batchSession.images
        }
        return currentCapture.map { [$0] } ?? []
    }

    private func normalizedBatchPrompts(for images: [ImageAsset]) -> [UUID: String] {
        guard batchPromptMapping == .perImagePrompt else { return [:] }

        return images.reduce(into: [UUID: String]()) { prompts, image in
            let prompt = (batchPerImagePrompts[image.id] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !prompt.isEmpty {
                prompts[image.id] = prompt
            }
        }
    }

    private func makeImageInputMap(for images: [ImageAsset]) throws -> [UUID: VisionImageInput] {
        try images.reduce(into: [UUID: VisionImageInput]()) { inputs, image in
            guard let fileURL = image.fileURL else {
                throw ScreenshotCaptureError.captureFailed("截图文件不存在：\(image.displayName)")
            }
            inputs[image.id] = VisionImageInput(
                data: try Data(contentsOf: fileURL),
                mimeType: image.mimeType
            )
        }
    }

    private func summarizeExecutionOutcomes(
        _ outcomes: [TaskStepOutcome],
        plan: TaskPlan,
        task: AITask
    ) -> TaskExecutionSummary {
        let stepsByID = Dictionary(uniqueKeysWithValues: plan.steps.map { ($0.id, $0) })
        let outcomesByStepID = Dictionary(uniqueKeysWithValues: outcomes.map { ($0.stepID, $0) })
        let results = plan.steps.compactMap { step -> TaskStepResult? in
            outcomesByStepID[step.id]?.result
        }
        let failures = outcomes.compactMap { outcome -> TaskStepFailure? in
            guard let step = stepsByID[outcome.stepID] else { return nil }
            switch outcome {
            case .success:
                return nil
            case let .failure(_, message):
                return TaskStepFailure(
                    stepID: step.id,
                    taskID: step.taskID,
                    kind: step.kind,
                    imageIDs: step.imageIDs,
                    message: message
                )
            case let .skipped(_, reason):
                return TaskStepFailure(
                    stepID: step.id,
                    taskID: step.taskID,
                    kind: step.kind,
                    imageIDs: step.imageIDs,
                    message: reason,
                    isSkipped: true
                )
            }
        }

        return TaskExecutionSummary(
            resultText: resultText(for: task, results: results),
            results: results,
            failures: failures
        )
    }

    private func failureSummaryMessage(_ failures: [TaskStepFailure]) -> String {
        let actionableFailure = failures.first { !$0.isSkipped } ?? failures.first
        guard let actionableFailure else { return "未知错误" }
        if failures.count == 1 {
            return actionableFailure.message
        }
        return "\(failures.count) 个步骤失败：\(actionableFailure.message)"
    }

    private func resultText(for task: AITask, results: [TaskStepResult]) -> String? {
        guard !results.isEmpty else { return nil }

        switch task.configuration.outputGranularity {
        case .singleImageResult, .mergedResult:
            if let finalResult = results.last(where: { result in
                result.kind == .singleImage || result.kind == .fastMerge || result.kind == .merge
            }) {
                return finalResult.text
            }
        case .perImageResult:
            break
        }

        return results.map { result in
            let imageNames = imageNames(for: result.imageIDs, in: task.images)
            return "【\(imageNames)】\n\(result.text)"
        }
        .joined(separator: "\n\n")
    }

    private func imageNames(for imageIDs: [UUID], in images: [ImageAsset]) -> String {
        let namesByID = Dictionary(uniqueKeysWithValues: images.map { ($0.id, $0.displayName) })
        let names = imageIDs.compactMap { namesByID[$0] }
        return names.isEmpty ? "合并结果" : names.joined(separator: "、")
    }

    private func applyStepRetrySuccess(_ result: TaskStepResult, taskID: UUID) {
        guard let task = tasks.first(where: { $0.id == taskID }) else { return }

        let results = orderedResults(
            task.stepResults.filter { $0.stepID != result.stepID } + [result],
            plannedSteps: task.plannedSteps
        )
        let failures = task.stepFailures.filter { $0.stepID != result.stepID }
        let updatedTask = AITask(
            id: task.id,
            images: task.images,
            configuration: task.configuration,
            state: failures.isEmpty ? .done : .failed,
            createdAt: task.createdAt,
            resultText: resultText(for: task, results: results),
            errorMessage: failures.isEmpty ? nil : "\(failures.count) 个步骤失败",
            stepResults: results,
            stepFailures: failures,
            plannedSteps: task.plannedSteps
        )
        replaceTask(updatedTask)
        currentResultText = updatedTask.resultText
        statusMessage = failures.isEmpty ? "步骤重试成功，任务已恢复。" : "步骤重试成功，仍有 \(failures.count) 个步骤失败。"
    }

    private func updateStepFailure(_ step: TaskExecutionStep, taskID: UUID, message: String) {
        guard let task = tasks.first(where: { $0.id == taskID }) else { return }

        let failure = TaskStepFailure(
            stepID: step.id,
            taskID: step.taskID,
            kind: step.kind,
            imageIDs: step.imageIDs,
            message: message
        )
        let failures = task.stepFailures.filter { $0.stepID != step.id } + [failure]
        updateTask(
            taskID,
            state: .failed,
            resultText: task.resultText,
            errorMessage: "\(failures.count) 个步骤失败",
            stepFailures: failures
        )
        statusMessage = "步骤重试失败：\(message)"
    }

    private func orderedResults(
        _ results: [TaskStepResult],
        plannedSteps: [TaskExecutionStep]
    ) -> [TaskStepResult] {
        let orderByStepID = Dictionary(uniqueKeysWithValues: plannedSteps.enumerated().map { ($0.element.id, $0.offset) })
        return results.sorted { first, second in
            (orderByStepID[first.stepID] ?? Int.max) < (orderByStepID[second.stepID] ?? Int.max)
        }
    }

    private func taskStepTitle(_ kind: TaskStepKind) -> String {
        switch kind {
        case .singleImage:
            return "单图分析"
        case .fastMerge:
            return "快速合并"
        case .intermediateImage:
            return "中间分析"
        case .merge:
            return "精细合并"
        case .perImage:
            return "逐图结果"
        }
    }

    private func makeEndpoint() -> VisionAPIEndpoint? {
        let trimmedBaseURL = apiBaseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAPIKey = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let normalizedBaseURL = Self.normalizedAPIBaseURLString(trimmedBaseURL),
              let baseURL = URL(string: normalizedBaseURL)
        else {
            statusMessage = "Base URL 无效，请打开设置修改。"
            return nil
        }
        guard !trimmedModel.isEmpty else {
            statusMessage = "模型名不能为空，请打开设置填写。"
            return nil
        }
        guard !trimmedAPIKey.isEmpty else {
            statusMessage = "请先在设置里填写 API Key。"
            return nil
        }

        if normalizedBaseURL != apiBaseURLString {
            apiBaseURLString = normalizedBaseURL
            UserDefaults.standard.set(normalizedBaseURL, forKey: DefaultsKeys.apiBaseURL)
        }

        return VisionAPIEndpoint(baseURL: baseURL, apiKey: trimmedAPIKey, model: trimmedModel)
    }

    private func updateTask(
        _ taskID: UUID,
        state: TaskState,
        resultText: String?,
        errorMessage: String?,
        stepResults: [TaskStepResult]? = nil,
        stepFailures: [TaskStepFailure]? = nil,
        plannedSteps: [TaskExecutionStep]? = nil
    ) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].state = state
        tasks[index].resultText = resultText
        tasks[index].errorMessage = errorMessage
        if let stepResults {
            tasks[index].stepResults = stepResults
        }
        if let stepFailures {
            tasks[index].stepFailures = stepFailures
        }
        if let plannedSteps {
            tasks[index].plannedSteps = plannedSteps
        }
    }

    private func setPlannedSteps(_ plannedSteps: [TaskExecutionStep], for taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].plannedSteps = plannedSteps
    }

    private func replaceTask(_ task: AITask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index] = task
    }

    private func refreshPromptProviders(persistChanges: Bool) {
        let provider = ProviderRef(providerID: "openai-compatible", modelName: modelName)
        for index in savedPrompts.indices {
            savedPrompts[index].provider = provider
        }
        if persistChanges {
            _ = persistSavedPrompts(successMessage: "已同步 Prompt 的模型设置。")
        }
    }

    private func markOnlyActivePrompt(_ activeID: UUID?) {
        guard let activeID else { return }
        for index in savedPrompts.indices {
            savedPrompts[index].isAutoActive = savedPrompts[index].id == activeID
        }
    }

    @discardableResult
    private func persistSavedPrompts(successMessage: String) -> Bool {
        do {
            try promptLibrary.save(savedPrompts)
            promptEditorStatus = successMessage
            statusMessage = successMessage
            return true
        } catch {
            promptEditorStatus = "保存 Prompt 失败：\(error.localizedDescription)"
            statusMessage = promptEditorStatus
            return false
        }
    }

    private func suggestedPromptName(for prompt: String) -> String {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return "新 Prompt" }
        return String(trimmedPrompt.prefix(12))
    }
}

private struct TaskExecutionSummary {
    var resultText: String?
    var results: [TaskStepResult]
    var failures: [TaskStepFailure]
}

private final class VisionTaskExecutor: AIExecuting, @unchecked Sendable {
    private let endpoint: VisionAPIEndpoint
    private let imageInputsByID: [UUID: VisionImageInput]
    private let client: VisionAPIClient
    private let cleaner: GeneratedResultCleaner
    private let resultStore: StepResultStore

    init(
        endpoint: VisionAPIEndpoint,
        imageInputsByID: [UUID: VisionImageInput],
        client: VisionAPIClient,
        cleaner: GeneratedResultCleaner,
        seedResults: [TaskStepResult] = []
    ) {
        self.endpoint = endpoint
        self.imageInputsByID = imageInputsByID
        self.client = client
        self.cleaner = cleaner
        self.resultStore = StepResultStore(results: seedResults)
    }

    func execute(_ step: TaskExecutionStep) async throws -> TaskStepResult {
        let prompt = await prompt(for: step)
        let imageInputs = step.imageIDs.compactMap { imageInputsByID[$0] }
        guard imageInputs.count == step.imageIDs.count else {
            throw ScreenshotCaptureError.captureFailed("批量步骤缺少截图文件")
        }

        let rawText = try await client.analyze(
            endpoint: endpoint,
            prompt: prompt,
            images: imageInputs
        )
        let result = TaskStepResult(
            stepID: step.id,
            taskID: step.taskID,
            kind: step.kind,
            imageIDs: step.imageIDs,
            text: cleaner.clean(rawText)
        )
        await resultStore.record(result)
        return result
    }

    private func prompt(for step: TaskExecutionStep) async -> String {
        guard step.kind == .merge, !step.dependsOnStepIDs.isEmpty else {
            return step.prompt
        }

        let dependencyResults = await resultStore.results(for: step.dependsOnStepIDs)
        guard !dependencyResults.isEmpty else { return step.prompt }

        let sections = dependencyResults.enumerated().map { index, result in
            "中间结果 \(index + 1)：\n\(result.text)"
        }
        return """
        \(step.prompt)

        下面是上一阶段对每张截图的中间分析。请基于这些中间结果和原始截图，输出最终合并结果：
        \(sections.joined(separator: "\n\n"))
        """
    }
}

private actor StepResultStore {
    private var resultsByStepID: [UUID: TaskStepResult] = [:]

    init(results: [TaskStepResult] = []) {
        self.resultsByStepID = Dictionary(uniqueKeysWithValues: results.map { ($0.stepID, $0) })
    }

    func record(_ result: TaskStepResult) {
        resultsByStepID[result.stepID] = result
    }

    func results(for stepIDs: [UUID]) -> [TaskStepResult] {
        stepIDs.compactMap { resultsByStepID[$0] }
    }
}

private enum DefaultsKeys {
    static let apiBaseURL = "apiBaseURL"
    static let modelName = "modelName"
    static let captureMode = "captureMode"
    static let silentOperationEnabled = "silentOperationEnabled"
    static let floatingOrbEnabled = "floatingOrbEnabled"
}

extension CaptureMode {
    var title: String {
        switch self {
        case .manual:
            return "手动"
        case .auto:
            return "自动"
        case .batch:
            return "批量"
        }
    }
}

extension OutputGranularity {
    var title: String {
        switch self {
        case .singleImageResult:
            return "单张结果"
        case .mergedResult:
            return "合并结果"
        case .perImageResult:
            return "逐图结果"
        }
    }
}

extension ExecutionStrategy {
    var title: String {
        switch self {
        case .fastMerge:
            return "快速"
        case .refinedMerge:
            return "精细"
        }
    }
}

extension PromptMapping {
    var title: String {
        switch self {
        case .sharedPrompt:
            return "共享 Prompt"
        case .perImagePrompt:
            return "逐图 Prompt"
        }
    }
}

extension TaskState {
    var title: String {
        switch self {
        case .waiting:
            return "等待"
        case .running:
            return "运行中"
        case .done:
            return "完成"
        case .failed:
            return "失败"
        case .canceled:
            return "已取消"
        }
    }
}
