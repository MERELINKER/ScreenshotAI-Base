# ScreenshotAI Base

把截图、文字识别和 AI 处理放进一个轻量的 macOS 工作流。

ScreenshotAI Base 是一个使用 SwiftUI、AppKit 和 Apple Vision 构建的原生应用。你可以框选屏幕提取文字，也可以选择 Prompt 对截图进行总结、解释或批量处理。它同时是一个可继续开发的开源基础工程。

Native macOS screenshot capture, on-device OCR and optional AI workflows. Built with SwiftUI, AppKit and Apple Vision; designed as a small, hackable starting point.

[作者博客](https://colamono.com) · [项目页](https://colamono.com/projects/) · [开发交接](docs/developer-handoff.zh.md)

## 已包含

- 框选截图，并把图片保存到用户指定目录
- 手动、自动和批量截图模式
- Apple Vision 本地 OCR（无需 API Key；当前快速识别路径以英文为主）
- OpenAI-compatible 视觉分析接口、Prompt 保存与结果调整
- 菜单栏入口、可拖动悬浮球、Prompt 悬浮窗
- 可自定义的全局快捷键
- macOS Keychain 保存 AI API Key
- Swift Testing 单元测试

## 快速开始

环境要求：macOS 14 或更高版本、Xcode Command Line Tools、Swift 6.1 或兼容版本。

```bash
git clone https://github.com/MERELINKER/ScreenshotAI-Base.git
cd ScreenshotAI-Base
swift test
bash script/build_and_run.sh --build-only
open .build/app/ScreenshotAIBase.app
```

构建后的应用位于：

```text
.build/app/ScreenshotAIBase.app
```

首次截图前，需要在“系统设置 → 隐私与安全性 → 屏幕录制”中允许 `ScreenshotAIBase`。

## 默认快捷键

- `⌃⌥⌘S`：按当前模式截图
- `⌃⌥⌘A`：自动截图并执行当前 Prompt
- `⌃⌥⌘T`：打开时间线
- `⌃⌥⌘O`：截图并执行本地 OCR

## 工程结构

```text
Sources/ScreenshotAIKit/       通用模型、任务编排、API 客户端与偏好设置
Sources/ScreenshotAIApp/       SwiftUI/AppKit 应用、截图、OCR、悬浮窗与状态管理
Tests/                         核心与应用层测试
Resources/                     应用图标
script/build_and_run.sh        构建、签名和运行脚本
docs/developer-handoff.zh.md   开发交接入口
```

本地 OCR 的入口是 `LocalTextRecognitionService.swift`，截图入口是 `InteractiveScreenshotService.swift`，界面流程集中在 `DemoTaskStore.swift` 和 `ScreenshotAIApp.swift`。

双击悬浮球可直接打开 Prompt 窗口；右键菜单可以快速开始截图或本地 OCR。主界面的“本地 OCR”识别当前截图，菜单栏和快捷键入口则先截图再识别。成功后的文字会显示在结果区域并复制到剪贴板。

## 数据与安全边界

- 本地 OCR 只在设备上运行。
- AI 分析仅在用户主动执行 Prompt 时向配置的兼容接口发送截图。
- API Key 通过 macOS Keychain 保存，不写入源码或配置文件。
- 此开发包不包含用户截图、查询记录、账号、密码、Cookie、构建缓存或历史任务数据。
- 配置与数据使用独立的 `ScreenshotAIBase` 命名空间。截图默认保存在 `~/Library/Application Support/ScreenshotAIBase/Captures`，Prompt 保存于同级的 `saved-prompts.json`。

## 当前限制

- 当前版本面向源码开发，未提供 Apple 公证安装器。
- 本地 OCR 的快速模式适合清晰的横排英文截图；中文、复杂表格和旋转文字仍需完善识别模式和预处理。
- 时间线当前保存在内存中；“历史保留”等设置还需要接入完整的持久化与清理逻辑。
- 远程 AI 需要自行填写兼容接口和 API Key。请先确认截图内容适合发送给该服务。

## 参与开发

欢迎通过 Issues 提交可复现的问题，或通过 Pull Request 改进 OCR、交互和文档。提交前运行 `swift test`；请勿提交个人截图、API Key 或构建缓存。

## 授权说明

采用 [MIT 许可证](LICENSE)，可以使用、修改、分发和继续开发，保留许可证与版权声明即可。
