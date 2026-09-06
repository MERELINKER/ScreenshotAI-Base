import Foundation

public struct SavedPromptLibrary: Sendable {
    public let fileURL: URL

    public init(fileURL: URL = SavedPromptLibrary.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public func load() throws -> [SavedPrompt] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return Self.defaultPrompts()
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([SavedPrompt].self, from: data)
    }

    public func save(_ prompts: [SavedPrompt]) throws {
        let folderURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(prompts)
        try data.write(to: fileURL, options: [.atomic])
    }

    public static func defaultPrompts(
        provider: ProviderRef = ProviderRef(providerID: "openai-compatible", modelName: "gpt-4.1")
    ) -> [SavedPrompt] {
        [
            SavedPrompt(
                name: "总结",
                promptText: "请总结这张截图的重点，直接给出结论。",
                outputGranularity: .singleImageResult,
                provider: provider,
                executionStrategy: .fastMerge,
                isAutoActive: true
            ),
            SavedPrompt(
                name: "提取文字",
                promptText: "请提取截图中所有可见文字，并尽量保留结构。",
                outputGranularity: .singleImageResult,
                provider: provider,
                executionStrategy: .fastMerge
            ),
            SavedPrompt(
                name: "解释",
                promptText: "请解释这张截图中的内容，并指出我应该关注什么。",
                outputGranularity: .singleImageResult,
                provider: provider,
                executionStrategy: .fastMerge
            )
        ]
    }

    public static func defaultFileURL() -> URL {
        let baseURL = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )

        return (baseURL ?? FileManager.default.homeDirectoryForCurrentUser)
            .appendingPathComponent("ScreenshotAIBase", isDirectory: true)
            .appendingPathComponent("saved-prompts.json")
    }
}
