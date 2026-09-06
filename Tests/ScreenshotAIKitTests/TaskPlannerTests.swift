import Foundation
import Testing
@testable import ScreenshotAIKit

@Test
func singleImageTaskPlansOneSingleImageStep() {
    let image = ImageAsset(displayName: "Capture")
    let task = AITask(
        images: [image],
        configuration: TaskConfiguration(
            imageScope: .single,
            outputGranularity: .singleImageResult,
            promptMapping: .sharedPrompt,
            executionStrategy: .fastMerge,
            provider: ProviderRef(providerID: "openai", modelName: "gpt-4.1"),
            sharedPrompt: "Explain this"
        )
    )

    let plan = TaskPlanner().plan(task)

    #expect(plan.taskID == task.id)
    #expect(plan.steps.count == 1)
    #expect(plan.steps[0].kind == .singleImage)
    #expect(plan.steps[0].imageIDs == [image.id])
    #expect(plan.steps[0].prompt == "Explain this")
}

@Test
func multiImageFastMergePlansOneStepContainingAllImages() {
    let first = ImageAsset(displayName: "First")
    let second = ImageAsset(displayName: "Second")
    let task = AITask(
        images: [first, second],
        configuration: TaskConfiguration(
            imageScope: .multiple,
            outputGranularity: .mergedResult,
            promptMapping: .sharedPrompt,
            executionStrategy: .fastMerge,
            provider: ProviderRef(providerID: "openai", modelName: "gpt-4.1"),
            sharedPrompt: "Compare them"
        )
    )

    let plan = TaskPlanner().plan(task)

    #expect(plan.steps.count == 1)
    #expect(plan.steps[0].kind == .fastMerge)
    #expect(plan.steps[0].imageIDs == [first.id, second.id])
    #expect(plan.steps[0].prompt == "Compare them")
}

@Test
func refinedMergePlansIntermediateStepsBeforeMergeStep() throws {
    let first = ImageAsset(displayName: "Before")
    let second = ImageAsset(displayName: "After")
    let task = AITask(
        images: [first, second],
        configuration: TaskConfiguration(
            imageScope: .multiple,
            outputGranularity: .mergedResult,
            promptMapping: .perImagePrompt,
            executionStrategy: .refinedMerge,
            provider: ProviderRef(providerID: "anthropic", modelName: "claude-sonnet"),
            sharedPrompt: "Compare final differences",
            perImagePrompts: [
                first.id: "Analyze old state",
                second.id: "Analyze new state"
            ]
        )
    )

    let plan = TaskPlanner().plan(task)
    let intermediateSteps = plan.steps.filter { $0.kind == .intermediateImage }
    let mergeStep = try #require(plan.steps.first { $0.kind == .merge })

    #expect(intermediateSteps.count == 2)
    #expect(intermediateSteps.map(\.imageIDs) == [[first.id], [second.id]])
    #expect(intermediateSteps.map(\.prompt) == ["Analyze old state", "Analyze new state"])
    #expect(mergeStep.imageIDs == [first.id, second.id])
    #expect(mergeStep.dependsOnStepIDs == intermediateSteps.map(\.id))
    #expect(mergeStep.prompt == "Compare final differences")
}

@Test
func perImageOutputPlansOneStepPerImageWithSharedPrompt() {
    let first = ImageAsset(displayName: "One")
    let second = ImageAsset(displayName: "Two")
    let task = AITask(
        images: [first, second],
        configuration: TaskConfiguration(
            imageScope: .multiple,
            outputGranularity: .perImageResult,
            promptMapping: .sharedPrompt,
            executionStrategy: .fastMerge,
            provider: ProviderRef(providerID: "gemini", modelName: "gemini-pro-vision"),
            sharedPrompt: "Extract visible text"
        )
    )

    let plan = TaskPlanner().plan(task)

    #expect(plan.steps.count == 2)
    #expect(plan.steps.allSatisfy { $0.kind == .perImage })
    #expect(plan.steps.map(\.imageIDs) == [[first.id], [second.id]])
    #expect(plan.steps.map(\.prompt) == ["Extract visible text", "Extract visible text"])
}
