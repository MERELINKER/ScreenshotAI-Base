import AppKit
import SwiftUI
import ScreenshotAIKit

struct TaskCenterView: View {
    @Bindable var store: DemoTaskStore

    var body: some View {
        VStack(spacing: 14) {
            header
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(store.tasks) { task in
                        TaskTimelineCard(
                            task: task,
                            isExpanded: Binding(
                                get: { store.expandedTaskIDs.contains(task.id) },
                                set: { _ in store.toggleExpanded(task.id) }
                            ),
                            onRetry: {
                                Task {
                                    await store.retryTask(task)
                                }
                            },
                            onRetryStep: { failure in
                                Task {
                                    await store.retryTaskStep(failure, in: task)
                                }
                            }
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("任务时间线")
                    .font(.title2.weight(.semibold))
                Text("单张截图和批量任务都会进入这里。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("模式", selection: $store.captureMode) {
                ForEach(CaptureMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 260)

            Button("批量") {
                store.addBatchDemo()
                store.selectedSection = .capture
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 14, material: .ultraThinMaterial)
    }
}

private struct TaskTimelineCard: View {
    let task: AITask
    @Binding var isExpanded: Bool
    let onRetry: () -> Void
    let onRetryStep: (TaskStepFailure) -> Void

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                imageStrip
                detailGrid
                if !task.configuration.perImagePrompts.isEmpty {
                    promptAssignments
                }
                if !task.stepResults.isEmpty || !task.stepFailures.isEmpty {
                    stepDetails
                }
                resultPreview
                if task.state == .failed {
                    HStack {
                        Spacer()
                        Button(action: onRetry) {
                            Label("重试任务", systemImage: "arrow.clockwise")
                        }
                    }
                }
            }
            .padding(.top, 10)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: task.images.count > 1 ? "rectangle.stack" : "camera.viewfinder")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                StatusBadge(state: task.state, failureCount: task.stepFailures.count)
            }
            .contentShape(Rectangle())
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 12, material: .regularMaterial, isInteractive: true)
    }

    private var title: String {
        task.images.count == 1 ? task.images[0].displayName : "批量：\(task.images.count) 张截图"
    }

    private var subtitle: String {
        "\(task.configuration.outputGranularity.title) · \(task.configuration.executionStrategy.title) · \(task.configuration.provider.modelName)"
    }

    private var imageStrip: some View {
        HStack(spacing: 8) {
            ForEach(task.images) { image in
                VStack(alignment: .leading, spacing: 6) {
                    thumbnail(for: image)
                    Text(image.displayName)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 112)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func thumbnail(for image: ImageAsset) -> some View {
        if let fileURL = image.fileURL,
           let nsImage = NSImage(contentsOf: fileURL) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFill()
                .frame(width: 112, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.quaternary)
                .frame(width: 112, height: 72)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
        }
    }

    private var detailGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                DetailLabel("Prompt")
                Text(task.configuration.finalPrompt)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            GridRow {
                DetailLabel("Mapping")
                Text(task.configuration.promptMapping.title)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            GridRow {
                DetailLabel("Provider")
                Text(task.configuration.provider.providerID)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var promptAssignments: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("逐图 Prompt")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(task.images) { image in
                if let prompt = task.configuration.perImagePrompts[image.id], !prompt.isEmpty {
                    StepResultRow(
                        title: image.displayName,
                        imageNames: "Prompt",
                        text: prompt,
                        systemImage: "text.bubble"
                    )
                }
            }
        }
    }

    private var stepDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("批量步骤")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(task.stepResults) { result in
                StepResultRow(
                    title: result.kind.title,
                    imageNames: imageNames(for: result.imageIDs),
                    text: result.text,
                    systemImage: "checkmark.circle"
                )
            }

            ForEach(task.stepFailures) { failure in
                StepResultRow(
                    title: failure.isSkipped ? "\(failure.kind.title) 已跳过" : "\(failure.kind.title) 失败",
                    imageNames: imageNames(for: failure.imageIDs),
                    text: failure.message,
                    systemImage: failure.isSkipped ? "forward.end.circle" : "exclamationmark.triangle",
                    retryAction: {
                        onRetryStep(failure)
                    }
                )
            }
        }
    }

    private func imageNames(for imageIDs: [UUID]) -> String {
        let namesByID = Dictionary(uniqueKeysWithValues: task.images.map { ($0.id, $0.displayName) })
        let names = imageIDs.compactMap { namesByID[$0] }
        return names.isEmpty ? "合并步骤" : names.joined(separator: "、")
    }

    private var resultPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("结果")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(previewText)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 10, material: .thinMaterial)
    }

    private var previewText: String {
        switch task.state {
        case .waiting:
            return "等待执行。"
        case .running:
            return "正在分析截图。"
        case .done:
            return task.resultText ?? "已完成。"
        case .failed:
            if let resultText = task.resultText, !resultText.isEmpty {
                return "\(task.errorMessage ?? "任务失败。")\n\n\(resultText)"
            }
            return task.errorMessage ?? "任务失败。"
        case .canceled:
            return "任务已取消。"
        }
    }
}

private struct StatusBadge: View {
    let state: TaskState
    let failureCount: Int

    var body: some View {
        Text(label)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch state {
        case .waiting:
            return .secondary
        case .running:
            return .blue
        case .done:
            return .green
        case .failed:
            return .red
        case .canceled:
            return .orange
        }
    }

    private var label: String {
        failureCount > 0 ? "\(state.title) · \(failureCount)" : state.title
    }
}

private struct StepResultRow: View {
    let title: String
    let imageNames: String
    let text: String
    let systemImage: String
    var retryAction: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(imageNames)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if let retryAction {
                    Button(action: retryAction) {
                        Label("重试", systemImage: "arrow.clockwise")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help("重试这个步骤")
                }
            }

            Text(text)
                .font(.callout)
                .textSelection(.enabled)
                .lineLimit(8)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 10, material: .thinMaterial)
    }
}

private struct DetailLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(width: 72, alignment: .leading)
    }
}

private extension TaskStepKind {
    var title: String {
        switch self {
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
}
