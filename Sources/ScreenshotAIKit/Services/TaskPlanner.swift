import Foundation

public enum TaskStepKind: String, Codable, CaseIterable, Sendable {
    case singleImage
    case fastMerge
    case intermediateImage
    case merge
    case perImage
}

public struct TaskExecutionStep: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let taskID: UUID
    public var kind: TaskStepKind
    public var imageIDs: [UUID]
    public var prompt: String
    public var dependsOnStepIDs: [UUID]

    public init(
        id: UUID = UUID(),
        taskID: UUID,
        kind: TaskStepKind,
        imageIDs: [UUID],
        prompt: String,
        dependsOnStepIDs: [UUID] = []
    ) {
        self.id = id
        self.taskID = taskID
        self.kind = kind
        self.imageIDs = imageIDs
        self.prompt = prompt
        self.dependsOnStepIDs = dependsOnStepIDs
    }
}

public struct TaskPlan: Hashable, Codable, Sendable {
    public let taskID: UUID
    public var steps: [TaskExecutionStep]

    public init(taskID: UUID, steps: [TaskExecutionStep]) {
        self.taskID = taskID
        self.steps = steps
    }
}

public struct TaskPlanner: Sendable {
    public init() {}

    public func plan(_ task: AITask) -> TaskPlan {
        if task.images.count == 1, let image = task.images.first {
            return TaskPlan(
                taskID: task.id,
                steps: [
                    TaskExecutionStep(
                        taskID: task.id,
                        kind: .singleImage,
                        imageIDs: [image.id],
                        prompt: task.configuration.prompt(for: image)
                    )
                ]
            )
        }

        switch task.configuration.outputGranularity {
        case .perImageResult:
            return TaskPlan(
                taskID: task.id,
                steps: task.images.map { image in
                    TaskExecutionStep(
                        taskID: task.id,
                        kind: .perImage,
                        imageIDs: [image.id],
                        prompt: task.configuration.prompt(for: image)
                    )
                }
            )

        case .mergedResult, .singleImageResult:
            switch task.configuration.executionStrategy {
            case .fastMerge:
                return TaskPlan(
                    taskID: task.id,
                    steps: [
                        TaskExecutionStep(
                            taskID: task.id,
                            kind: .fastMerge,
                            imageIDs: task.images.map(\.id),
                            prompt: fastMergePrompt(for: task)
                        )
                    ]
                )

            case .refinedMerge:
                let intermediateSteps = task.images.map { image in
                    TaskExecutionStep(
                        taskID: task.id,
                        kind: .intermediateImage,
                        imageIDs: [image.id],
                        prompt: task.configuration.prompt(for: image)
                    )
                }
                let mergeStep = TaskExecutionStep(
                    taskID: task.id,
                    kind: .merge,
                    imageIDs: task.images.map(\.id),
                    prompt: task.configuration.finalPrompt,
                    dependsOnStepIDs: intermediateSteps.map(\.id)
                )
                return TaskPlan(taskID: task.id, steps: intermediateSteps + [mergeStep])
            }
        }
    }

    private func fastMergePrompt(for task: AITask) -> String {
        guard task.configuration.promptMapping == .perImagePrompt else {
            return task.configuration.finalPrompt
        }

        let imagePrompts = task.images.map { image in
            "\(image.displayName): \(task.configuration.prompt(for: image))"
        }

        return ([task.configuration.finalPrompt] + imagePrompts).joined(separator: "\n")
    }
}
