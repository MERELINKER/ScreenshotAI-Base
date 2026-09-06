import Foundation

public struct ResultRevisionPromptBuilder: Sendable {
    public init() {}

    public func makeRevisionPrompt(
        originalPrompt: String,
        previousResult: String,
        instruction: String
    ) -> String {
        """
        请根据下面信息修订上一版输出。只输出修订后的最终答案，不要解释修改过程，不要重复多版答案。

        原始 Prompt：
        \(originalPrompt.trimmingCharacters(in: .whitespacesAndNewlines))

        上一版输出：
        \(previousResult.trimmingCharacters(in: .whitespacesAndNewlines))

        调整要求：
        \(instruction.trimmingCharacters(in: .whitespacesAndNewlines))
        """
    }
}
