import Foundation
import Testing
@testable import ScreenshotAIKit

@Test
func revisionPromptIncludesOriginalPromptPreviousResultAndInstruction() {
    let prompt = ResultRevisionPromptBuilder().makeRevisionPrompt(
        originalPrompt: "输出标题和摘要",
        previousResult: "标题：旧标题\n摘要：旧摘要",
        instruction: "标题更贴近单库还原疑问"
    )

    #expect(prompt.contains("原始 Prompt：\n输出标题和摘要"))
    #expect(prompt.contains("上一版输出：\n标题：旧标题\n摘要：旧摘要"))
    #expect(prompt.contains("调整要求：\n标题更贴近单库还原疑问"))
    #expect(prompt.contains("只输出修订后的最终答案"))
}
