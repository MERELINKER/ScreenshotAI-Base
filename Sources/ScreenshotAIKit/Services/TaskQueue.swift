import Foundation

public struct TaskStepResult: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID { stepID }
    public let stepID: UUID
    public let taskID: UUID
    public var kind: TaskStepKind
    public var imageIDs: [UUID]
    public var text: String

    public init(
        stepID: UUID,
        taskID: UUID,
        kind: TaskStepKind,
        imageIDs: [UUID],
        text: String
    ) {
        self.stepID = stepID
        self.taskID = taskID
        self.kind = kind
        self.imageIDs = imageIDs
        self.text = text
    }
}

public struct TaskStepFailure: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID { stepID }
    public let stepID: UUID
    public let taskID: UUID
    public var kind: TaskStepKind
    public var imageIDs: [UUID]
    public var message: String
    public var isSkipped: Bool

    public init(
        stepID: UUID,
        taskID: UUID,
        kind: TaskStepKind,
        imageIDs: [UUID],
        message: String,
        isSkipped: Bool = false
    ) {
        self.stepID = stepID
        self.taskID = taskID
        self.kind = kind
        self.imageIDs = imageIDs
        self.message = message
        self.isSkipped = isSkipped
    }
}

public enum TaskStepOutcome: Hashable, Sendable {
    case success(TaskStepResult)
    case failure(stepID: UUID, message: String)
    case skipped(stepID: UUID, reason: String)

    public var stepID: UUID {
        switch self {
        case let .success(result):
            return result.stepID
        case let .failure(stepID, _), let .skipped(stepID, _):
            return stepID
        }
    }

    public var result: TaskStepResult? {
        if case let .success(result) = self {
            return result
        }
        return nil
    }
}

public protocol AIExecuting: Sendable {
    func execute(_ step: TaskExecutionStep) async throws -> TaskStepResult
}

public final class TaskQueue: @unchecked Sendable {
    private let maxConcurrentTasks: Int
    private let executor: any AIExecuting

    public init(maxConcurrentTasks: Int, executor: any AIExecuting) {
        self.maxConcurrentTasks = max(1, maxConcurrentTasks)
        self.executor = executor
    }

    public func run(_ plan: TaskPlan) async -> [TaskStepOutcome] {
        var pending = plan.steps
        var outcomes: [TaskStepOutcome] = []
        var successfulStepIDs = Set<UUID>()
        var failedStepIDs = Set<UUID>()

        while !pending.isEmpty {
            let blockedSteps = pending.filter { step in
                step.dependsOnStepIDs.contains { failedStepIDs.contains($0) }
            }

            if !blockedSteps.isEmpty {
                outcomes.append(contentsOf: blockedSteps.map { step in
                    .skipped(stepID: step.id, reason: "Dependency failed")
                })
                let blockedIDs = Set(blockedSteps.map(\.id))
                pending.removeAll { blockedIDs.contains($0.id) }
                continue
            }

            let runnableSteps = pending.filter { step in
                Set(step.dependsOnStepIDs).isSubset(of: successfulStepIDs)
            }

            if runnableSteps.isEmpty {
                outcomes.append(contentsOf: pending.map { step in
                    .skipped(stepID: step.id, reason: "Dependencies were not satisfied")
                })
                break
            }

            let waveOutcomes = await runLimited(runnableSteps)
            outcomes.append(contentsOf: waveOutcomes)

            for outcome in waveOutcomes {
                switch outcome {
                case let .success(result):
                    successfulStepIDs.insert(result.stepID)
                case let .failure(stepID, _), let .skipped(stepID, _):
                    failedStepIDs.insert(stepID)
                }
            }

            let completedIDs = Set(runnableSteps.map(\.id))
            pending.removeAll { completedIDs.contains($0.id) }
        }

        return outcomes
    }

    private func runLimited(_ steps: [TaskExecutionStep]) async -> [TaskStepOutcome] {
        await withTaskGroup(of: TaskStepOutcome.self, returning: [TaskStepOutcome].self) { group in
            var outcomes: [TaskStepOutcome] = []
            var nextIndex = 0

            func enqueueNextStep() {
                guard nextIndex < steps.count else { return }
                let step = steps[nextIndex]
                nextIndex += 1

                group.addTask { [executor] in
                    do {
                        let result = try await executor.execute(step)
                        return .success(result)
                    } catch {
                        return .failure(stepID: step.id, message: error.localizedDescription)
                    }
                }
            }

            for _ in 0..<min(maxConcurrentTasks, steps.count) {
                enqueueNextStep()
            }

            while let outcome = await group.next() {
                outcomes.append(outcome)
                enqueueNextStep()
            }

            return outcomes
        }
    }
}
