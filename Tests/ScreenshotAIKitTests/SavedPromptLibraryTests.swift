import Foundation
import Testing
@testable import ScreenshotAIKit

@Test
func savedPromptLibraryPersistsPromptsToJSONFile() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScreenshotAIKitTests-\(UUID().uuidString)", isDirectory: true)
    let fileURL = folder.appendingPathComponent("saved-prompts.json")
    let library = SavedPromptLibrary(fileURL: fileURL)
    let prompt = SavedPrompt(
        name: "工单回复",
        promptText: "根据截图生成可靠回复",
        outputGranularity: .singleImageResult,
        provider: ProviderRef(providerID: "openai-compatible", modelName: "gpt-4.1"),
        executionStrategy: .fastMerge,
        isAutoActive: true
    )

    try library.save([prompt])

    let reloadedLibrary = SavedPromptLibrary(fileURL: fileURL)
    let reloadedPrompts = try reloadedLibrary.load()

    #expect(reloadedPrompts == [prompt])
}

@Test
func savedPromptLibraryReturnsDefaultPromptsWhenFileDoesNotExist() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScreenshotAIKitTests-\(UUID().uuidString)", isDirectory: true)
    let fileURL = folder.appendingPathComponent("saved-prompts.json")
    let library = SavedPromptLibrary(fileURL: fileURL)

    let prompts = try library.load()

    #expect(prompts.map(\.name) == ["总结", "提取文字", "解释"])
    #expect(prompts.first?.isAutoActive == true)
}
