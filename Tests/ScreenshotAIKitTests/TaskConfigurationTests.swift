import Foundation
import Testing
@testable import ScreenshotAIKit

@Test
func singleImageConfigurationCreatesOneMainResultTask() {
    let image = ImageAsset(displayName: "Capture 1")
    let provider = ProviderRef(providerID: "openai", modelName: "gpt-4.1")
    let config = TaskConfiguration(
        imageScope: .single,
        outputGranularity: .singleImageResult,
        promptMapping: .sharedPrompt,
        executionStrategy: .fastMerge,
        provider: provider,
        sharedPrompt: "Summarize this screenshot"
    )

    let task = AITask(images: [image], configuration: config)

    #expect(task.images == [image])
    #expect(task.configuration.outputGranularity == .singleImageResult)
    #expect(task.state == .waiting)
    #expect(config.prompt(for: image) == "Summarize this screenshot")
}

@Test
func multiImageConfigurationCanAssignPerImagePromptsForMergedOutput() {
    let first = ImageAsset(displayName: "Before")
    let second = ImageAsset(displayName: "After")
    let config = TaskConfiguration(
        imageScope: .multiple,
        outputGranularity: .mergedResult,
        promptMapping: .perImagePrompt,
        executionStrategy: .refinedMerge,
        provider: ProviderRef(providerID: "anthropic", modelName: "claude-sonnet"),
        sharedPrompt: "Compare these screenshots",
        perImagePrompts: [
            first.id: "Extract the old state",
            second.id: "Extract the new state"
        ]
    )

    #expect(config.prompt(for: first) == "Extract the old state")
    #expect(config.prompt(for: second) == "Extract the new state")
    #expect(config.finalPrompt == "Compare these screenshots")
}

@Test
func savedPromptStoresTaskPresetFields() {
    let prompt = SavedPrompt(
        name: "Extract Text",
        promptText: "Extract all visible text",
        outputGranularity: .perImageResult,
        provider: ProviderRef(providerID: "gemini", modelName: "gemini-pro-vision"),
        executionStrategy: .fastMerge,
        isAutoActive: true
    )

    #expect(prompt.name == "Extract Text")
    #expect(prompt.outputGranularity == .perImageResult)
    #expect(prompt.isAutoActive)
}

@Test
func imageAssetStoresOptionalCapturedFileMetadata() {
    let fileURL = URL(fileURLWithPath: "/tmp/capture.png")
    let image = ImageAsset(
        displayName: "Real capture",
        fileURL: fileURL,
        mimeType: "image/png"
    )

    #expect(image.fileURL == fileURL)
    #expect(image.mimeType == "image/png")
}

@Test
func taskCanStoreResultAndErrorTextForTimelineDisplay() {
    let image = ImageAsset(displayName: "Capture")
    let config = TaskConfiguration(
        imageScope: .single,
        outputGranularity: .singleImageResult,
        promptMapping: .sharedPrompt,
        executionStrategy: .fastMerge,
        provider: ProviderRef(providerID: "openai", modelName: "gpt-4.1"),
        sharedPrompt: "Explain"
    )

    let task = AITask(
        images: [image],
        configuration: config,
        state: .done,
        resultText: "It shows a menu.",
        errorMessage: nil
    )

    #expect(task.resultText == "It shows a menu.")
    #expect(task.errorMessage == nil)
}

@Test
func taskCanStoreStepResultsAndFailuresForBatchTimeline() {
    let first = ImageAsset(displayName: "Before")
    let second = ImageAsset(displayName: "After")
    let config = TaskConfiguration(
        imageScope: .multiple,
        outputGranularity: .mergedResult,
        promptMapping: .sharedPrompt,
        executionStrategy: .refinedMerge,
        provider: ProviderRef(providerID: "openai", modelName: "gpt-4.1"),
        sharedPrompt: "Compare"
    )
    let stepResult = TaskStepResult(
        stepID: UUID(),
        taskID: UUID(),
        kind: .intermediateImage,
        imageIDs: [first.id],
        text: "Old state"
    )
    let stepFailure = TaskStepFailure(
        stepID: UUID(),
        taskID: UUID(),
        kind: .intermediateImage,
        imageIDs: [second.id],
        message: "Timed out"
    )

    let task = AITask(
        images: [first, second],
        configuration: config,
        state: .failed,
        resultText: "Old state",
        errorMessage: "1 个步骤失败",
        stepResults: [stepResult],
        stepFailures: [stepFailure]
    )

    #expect(task.stepResults == [stepResult])
    #expect(task.stepFailures == [stepFailure])
}
