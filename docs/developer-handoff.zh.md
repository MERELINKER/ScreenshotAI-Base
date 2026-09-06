# ScreenshotAI Base 开发交接

## 1. 建议先跑的命令

```bash
swift test
bash script/build_and_run.sh --build-only
```

应用产物默认在 `.build/app/ScreenshotAIBase.app`。脚本会优先使用本机 Apple Development 证书；没有证书时会采用 ad-hoc 签名，因此不同构建之间可能需要重新授予屏幕录制权限。

## 2. 运行主线

1. `ScreenshotAIApp.swift` 注册窗口、菜单栏和全局快捷键。
2. `InteractiveScreenshotService.swift` 调用系统截图工具完成区域框选。
3. `DemoTaskStore.swift` 保存当前截图并分派本地 OCR 或远程视觉分析。
4. `LocalTextRecognitionService.swift` 使用 Vision 在本机识别文字，当前 `.fast` 路径以英文为主。
5. `VisionAPIClient.swift` 负责 OpenAI-compatible 视觉请求。
6. `FloatingCapturePanelView.swift`、`FloatingPromptInputView.swift` 和 `FloatingOrbView.swift` 提供主界面及悬浮交互。

## 3. 扩展建议

- 新增 OCR 后处理时，建议在本地 OCR 服务之后单独增加纯函数，不要把业务判断写入 Vision 识别层。
- 新增第三方服务时，把认证、网络请求与界面状态分别放在独立服务、Store 和 View 中。
- 新增快捷键时，在 `HotKeyAction`、应用分发 switch 和快捷键测试中同时补齐。
- 新增持久化数据时，明确存储位置、清除入口和升级兼容策略。

## 4. 当前边界

- 这是源码开发包，不包含已公证安装器或商店签名。
- 本地 OCR 使用 `.fast` 识别级别，优先保证交互响应；对小字号、旋转文字或复杂表格可继续增加图像预处理和识别模式切换。
- 远程 AI 能否成功取决于接收方填写的 Base URL、模型名和 API Key。
- 工程没有业务后台的页面自动化、登录态或数据修改能力。
- 主程序 Bundle ID、Keychain service 和 Application Support 目录均使用 `ScreenshotAIBase`，避免与其他版本共享凭据和 Prompt。
- 任务时间线尚未持久化，历史保留选项尚未接入清理服务。

## 5. 交付前检查

```bash
swift test
rg -n "TODO|FIXME" Sources Tests
rg -n "api[_-]?key|password|cookie" . --glob '!README.md' --glob '!docs/**'
```

不要把 `.build/`、`dist/`、个人截图或本机 Keychain 数据加入后续分发包。
