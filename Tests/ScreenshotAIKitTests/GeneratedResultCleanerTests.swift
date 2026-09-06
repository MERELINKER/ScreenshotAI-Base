import Foundation
import Testing
@testable import ScreenshotAIKit

@Test
func cleanerCollapsesRepeatedTitleSummaryBlocks() {
    let raw = """
    标题：完整备份中部分学习库未出现在备份资料夹摘要：用户反馈使用“完整备份（资料附加全部文件）”后，只有部分学习库出现在完整备份资料夹内；MN4 显示总容量约 18.66G，但用户统计所有资料库容量约 15.6G。
    标题：完整备份中部分学习库未出现在备份资料夹

    摘要：用户反馈使用“完整备份（资料附加全部文件）”后，只有部分学习库出现在完整备份资料夹内；MN4 显示总容量约 18.66G，但用户统计所有资料库容量约 15.6G。
    """

    let cleaned = GeneratedResultCleaner().clean(raw)

    #expect(cleaned == """
    标题：完整备份中部分学习库未出现在备份资料夹
    摘要：用户反馈使用“完整备份（资料附加全部文件）”后，只有部分学习库出现在完整备份资料夹内；MN4 显示总容量约 18.66G，但用户统计所有资料库容量约 15.6G。
    """)
}

@Test
func cleanerNormalizesSingleLineTitleSummary() {
    let raw = "标题：完整备份后资料夹不完整及单库还原疑问摘要：用户需确认所有资料是否已成功备份，并询问单库还原操作。"

    let cleaned = GeneratedResultCleaner().clean(raw)

    #expect(cleaned == """
    标题：完整备份后资料夹不完整及单库还原疑问
    摘要：用户需确认所有资料是否已成功备份，并询问单库还原操作。
    """)
}

@Test
func cleanerPreservesNonStructuredOutput() {
    let raw = "  这是一段普通分析结果。  "

    let cleaned = GeneratedResultCleaner().clean(raw)

    #expect(cleaned == "这是一段普通分析结果。")
}

@Test
func cleanerCollapsesRepeatedWholeAnswerSections() {
    let raw = """
    图片中展示的 bug主要有两个：

    1. **Mermaid 自动渲染失败**
     - 页面显示解析错误：
       `Parse error on line72`

    2. **LaTeX 自动渲染异常**
     - `aligned` 环境没有被整体识别。

    图片中展示的 bug 主要有两个：

    1. **Mermaid 自动渲染失败**
       - 页面显示解析错误：
         `Parse error on line 72`

    2. **LaTeX 自动渲染异常**
       - `aligned` 环境没有被整体识别。

    图片中展示的 bug 主要有两个：

    1. **Mermaid 自动渲染失败**
       - 页面显示解析错误：
         `Parse error on line 72`

    2. **LaTeX 自动渲染异常**
       - `aligned` 环境没有被整体识别。
    """

    let cleaned = GeneratedResultCleaner().clean(raw)

    #expect(cleaned == """
    图片中展示的 bug主要有两个：

    1. **Mermaid 自动渲染失败**
     - 页面显示解析错误：
       `Parse error on line72`

    2. **LaTeX 自动渲染异常**
     - `aligned` 环境没有被整体识别。
    """)
}

@Test
func cleanerCollapsesRepeatedOpeningTail() {
    let raw = """
    您好，初步判断是通过 QQ 打开/导入到 MN 的书籍，QQ侧仍保留了原文件或缓存记录，导致备份工具/ iCloud 在扫描 QQ 沙盒数据时把这些文件也算入备份体积；iPad「储存空间」里显示的 QQ 大小可能不会完整展示这部分可清理缓存，所以会出现显示8G、备份读取接近100G 的情况。

    建议您按以下方式处理：

    1. 打开 QQ 设置，清理缓存、文件、聊天文件等占用；
    2. 在「文件」App 中检查「我的 iPad」或 QQ相关目录，删除已导入 MN 后不再需要的原始书籍文件；
    3. 如使用 iCloud备份，可在 iCloud备份列表中暂时关闭 QQ 的备份；
    4. 若仍异常，可在确认聊天记录已备份后，卸载并重装 QQ，以清空残留缓存；
    5. 后续从 QQ 导入书籍到 MN 后，建议及时删除 QQ 内的原文件/接收文件，避免重复占用。

    如果清理后备份体积仍异常，请提供 QQ 储存空间截图、iCloud/备份工具显示的占用截图，以及导入书籍的大致路径，我们再进一步排查。您好，初步判断是通过 QQ 打开/导入到 MN 的书籍，QQ 侧仍保留了原文件或缓存记录，导致备份工具/ iCloud 在扫描 QQ 沙盒数据时把这些文件也算入备份体积；iPad「储存空间」里显示的 QQ 大小可能不会完整展示这部分可清理缓存，所以会出现显示 8G、备份读取接近 100G 的情况。
    """

    let cleaned = GeneratedResultCleaner().clean(raw)

    #expect(cleaned == """
    您好，初步判断是通过 QQ 打开/导入到 MN 的书籍，QQ侧仍保留了原文件或缓存记录，导致备份工具/ iCloud 在扫描 QQ 沙盒数据时把这些文件也算入备份体积；iPad「储存空间」里显示的 QQ 大小可能不会完整展示这部分可清理缓存，所以会出现显示8G、备份读取接近100G 的情况。

    建议您按以下方式处理：

    1. 打开 QQ 设置，清理缓存、文件、聊天文件等占用；
    2. 在「文件」App 中检查「我的 iPad」或 QQ相关目录，删除已导入 MN 后不再需要的原始书籍文件；
    3. 如使用 iCloud备份，可在 iCloud备份列表中暂时关闭 QQ 的备份；
    4. 若仍异常，可在确认聊天记录已备份后，卸载并重装 QQ，以清空残留缓存；
    5. 后续从 QQ 导入书籍到 MN 后，建议及时删除 QQ 内的原文件/接收文件，避免重复占用。

    如果清理后备份体积仍异常，请提供 QQ 储存空间截图、iCloud/备份工具显示的占用截图，以及导入书籍的大致路径，我们再进一步排查。
    """)
}
