import Foundation
import Testing
@testable import ScreenshotAIKit

@Test
func queueRespectsConfiguredConcurrencyLimit() async {
    let images = (1...4).map { ImageAsset(displayName: "Capture \($0)") }
    let task = AITask(
        images: images,
        configuration: TaskConfiguration(
            imageScope: .multiple,
            outputGranularity: .perImageResult,
            promptMapping: .sharedPrompt,
            executionStrategy: .fastMerge,
            provider: ProviderRef(providerID: "openai", modelName: "gpt-4.1"),
            sharedPrompt: "Extract text"
        )
    )
    let plan = TaskPlanner().plan(task)
    let probe = ExecutionProbe()
    let queue = TaskQueue(
        maxConcurrentTasks: 2,
        executor: ProbeExecutor(probe: probe, delayNanoseconds: 25_000_000)
    )

    let outcomes = await queue.run(plan)

    #expect(outcomes.successes.count == 4)
    #expect(await probe.maximumActiveCount() == 2)
}

@Test
func queueRunsMergeStepAfterIntermediateDependencies() async {
    let first = ImageAsset(displayName: "Before")
    let second = ImageAsset(displayName: "After")
    let task = AITask(
        images: [first, second],
        configuration: TaskConfiguration(
            imageScope: .multiple,
            outputGranularity: .mergedResult,
            promptMapping: .sharedPrompt,
            executionStrategy: .refinedMerge,
            provider: ProviderRef(providerID: "anthropic", modelName: "claude-sonnet"),
            sharedPrompt: "Compare changes"
        )
    )
    let plan = TaskPlanner().plan(task)
    let probe = ExecutionProbe()
    let queue = TaskQueue(
        maxConcurrentTasks: 2,
        executor: ProbeExecutor(probe: probe, delayNanoseconds: 10_000_000)
    )

    let outcomes = await queue.run(plan)
    let completedKinds = await probe.completedKinds()

    #expect(outcomes.successes.count == 3)
    #expect(completedKinds.last == .merge)
    #expect(completedKinds.dropLast().allSatisfy { $0 == .intermediateImage })
}

@Test
func queueSkipsMergeWhenIntermediateDependencyFailsAndKeepsSuccessfulResults() async {
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
            sharedPrompt: "Compare changes",
            perImagePrompts: [
                first.id: "Analyze old state",
                second.id: "fail this image"
            ]
        )
    )
    let plan = TaskPlanner().plan(task)
    let queue = TaskQueue(
        maxConcurrentTasks: 2,
        executor: SelectiveFailingExecutor(failingPrompt: "fail this image")
    )

    let outcomes = await queue.run(plan)

    #expect(outcomes.successes.count == 1)
    #expect(outcomes.failures.count == 1)
    #expect(outcomes.skipped.count == 1)
    #expect(outcomes.skipped.first?.reason == "Dependency failed")
}

actor ExecutionProbe {
    private var activeCount = 0
    private var maximumActive = 0
    private var completed: [TaskStepKind] = []

    func started() {
        activeCount += 1
        maximumActive = max(maximumActive, activeCount)
    }

    func finished(kind: TaskStepKind) {
        activeCount -= 1
        completed.append(kind)
    }

    func maximumActiveCount() -> Int {
        maximumActive
    }

    func completedKinds() -> [TaskStepKind] {
        completed
    }
}

struct ProbeExecutor: AIExecuting {
    let probe: ExecutionProbe
    let delayNanoseconds: UInt64

    func execute(_ step: TaskExecutionStep) async throws -> TaskStepResult {
        await probe.started()
        try await Task.sleep(nanoseconds: delayNanoseconds)
        await probe.finished(kind: step.kind)

        return TaskStepResult(
            stepID: step.id,
            taskID: step.taskID,
            kind: step.kind,
            imageIDs: step.imageIDs,
            text: "Result for \(step.prompt)"
        )
    }
}

struct SelectiveFailingExecutor: AIExecuting {
    let failingPrompt: String

    func execute(_ step: TaskExecutionStep) async throws -> TaskStepResult {
        if step.prompt == failingPrompt {
            throw FailingExecutorError.expectedFailure
        }

        return TaskStepResult(
            stepID: step.id,
            taskID: step.taskID,
            kind: step.kind,
            imageIDs: step.imageIDs,
            text: "Result for \(step.prompt)"
        )
    }
}

enum FailingExecutorError: Error {
    case expectedFailure
}

extension [TaskStepOutcome] {
    var successes: [TaskStepResult] {
        compactMap { outcome in
            if case let .success(result) = outcome {
                return result
            }
            return nil
        }
    }

    var failures: [(stepID: UUID, message: String)] {
        compactMap { outcome in
            if case let .failure(stepID, message) = outcome {
                return (stepID, message)
            }
            return nil
        }
    }

    var skipped: [(stepID: UUID, reason: String)] {
        compactMap { outcome in
            if case let .skipped(stepID, reason) = outcome {
                return (stepID, reason)
            }
            return nil
        }
    }
}
