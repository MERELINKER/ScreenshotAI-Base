import Foundation

public enum CaptureMode: String, Codable, CaseIterable, Sendable {
    case manual
    case auto
    case batch
}

public enum ImageScope: String, Codable, CaseIterable, Sendable {
    case single
    case multiple
}

public enum OutputGranularity: String, Codable, CaseIterable, Sendable {
    case singleImageResult
    case mergedResult
    case perImageResult
}

public enum PromptMapping: String, Codable, CaseIterable, Sendable {
    case sharedPrompt
    case perImagePrompt
}

public enum ExecutionStrategy: String, Codable, CaseIterable, Sendable {
    case fastMerge
    case refinedMerge
}

public enum TaskState: String, Codable, CaseIterable, Sendable {
    case waiting
    case running
    case done
    case failed
    case canceled
}

public struct ImageAsset: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var displayName: String
    public var createdAt: Date
    public var fileURL: URL?
    public var mimeType: String

    public init(
        id: UUID = UUID(),
        displayName: String,
        createdAt: Date = Date(),
        fileURL: URL? = nil,
        mimeType: String = "image/png"
    ) {
        self.id = id
        self.displayName = displayName
        self.createdAt = createdAt
        self.fileURL = fileURL
        self.mimeType = mimeType
    }
}

public struct ProviderRef: Hashable, Codable, Sendable {
    public var providerID: String
    public var modelName: String

    public init(providerID: String, modelName: String) {
        self.providerID = providerID
        self.modelName = modelName
    }
}

public struct TaskConfiguration: Hashable, Codable, Sendable {
    public var imageScope: ImageScope
    public var outputGranularity: OutputGranularity
    public var promptMapping: PromptMapping
    public var executionStrategy: ExecutionStrategy
    public var provider: ProviderRef
    public var sharedPrompt: String
    public var perImagePrompts: [UUID: String]

    public var finalPrompt: String { sharedPrompt }

    public init(
        imageScope: ImageScope,
        outputGranularity: OutputGranularity,
        promptMapping: PromptMapping,
        executionStrategy: ExecutionStrategy,
        provider: ProviderRef,
        sharedPrompt: String,
        perImagePrompts: [UUID: String] = [:]
    ) {
        self.imageScope = imageScope
        self.outputGranularity = outputGranularity
        self.promptMapping = promptMapping
        self.executionStrategy = executionStrategy
        self.provider = provider
        self.sharedPrompt = sharedPrompt
        self.perImagePrompts = perImagePrompts
    }

    public func prompt(for image: ImageAsset) -> String {
        if promptMapping == .perImagePrompt, let prompt = perImagePrompts[image.id] {
            return prompt
        }
        return sharedPrompt
    }
}

public struct SavedPrompt: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var promptText: String
    public var outputGranularity: OutputGranularity
    public var provider: ProviderRef
    public var executionStrategy: ExecutionStrategy
    public var isAutoActive: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        promptText: String,
        outputGranularity: OutputGranularity,
        provider: ProviderRef,
        executionStrategy: ExecutionStrategy,
        isAutoActive: Bool = false
    ) {
        self.id = id
        self.name = name
        self.promptText = promptText
        self.outputGranularity = outputGranularity
        self.provider = provider
        self.executionStrategy = executionStrategy
        self.isAutoActive = isAutoActive
    }
}

public struct AITask: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var images: [ImageAsset]
    public var configuration: TaskConfiguration
    public var state: TaskState
    public var createdAt: Date
    public var resultText: String?
    public var errorMessage: String?
    public var stepResults: [TaskStepResult]
    public var stepFailures: [TaskStepFailure]
    public var plannedSteps: [TaskExecutionStep]

    public init(
        id: UUID = UUID(),
        images: [ImageAsset],
        configuration: TaskConfiguration,
        state: TaskState = .waiting,
        createdAt: Date = Date(),
        resultText: String? = nil,
        errorMessage: String? = nil,
        stepResults: [TaskStepResult] = [],
        stepFailures: [TaskStepFailure] = [],
        plannedSteps: [TaskExecutionStep] = []
    ) {
        self.id = id
        self.images = images
        self.configuration = configuration
        self.state = state
        self.createdAt = createdAt
        self.resultText = resultText
        self.errorMessage = errorMessage
        self.stepResults = stepResults
        self.stepFailures = stepFailures
        self.plannedSteps = plannedSteps
    }
}
