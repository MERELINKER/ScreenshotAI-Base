import AppKit
import Foundation
import ScreenshotAIKit
import Testing
@testable import ScreenshotAIBase

private struct CanceledCapture: ScreenshotCapturing {
    func capture(saveDirectory: URL) async throws -> CapturedScreenshot {
        throw ScreenshotCaptureError.canceled
    }
}

private struct DeniedCapture: ScreenshotCapturing {
    func capture(saveDirectory: URL) async throws -> CapturedScreenshot {
        throw ScreenshotCaptureError.permissionRequired
    }
}

@MainActor @Test func canceledAutoCaptureDoesNotAnalyzePreviousImage() async {
    let store = DemoTaskStore(screenshotService: CanceledCapture(), loadCredentials: false)
    let prior = ImageAsset(displayName: "synthetic previous capture", fileURL: URL(fileURLWithPath: "/tmp/screenshotai-nonexistent-test.png"), mimeType: "image/png")
    store.currentCapture = prior
    await store.captureAndRunActivePrompt()
    #expect(store.tasks.isEmpty)
    #expect(store.currentCapture?.id == prior.id)
    #expect(store.captureErrorMessage == nil)
    #expect(!store.isCapturing)
}

@MainActor @Test func permissionFailureIsVisibleAndStopsAnalysis() async {
    let store = DemoTaskStore(screenshotService: DeniedCapture(), loadCredentials: false)
    await store.captureAndRunActivePrompt()
    #expect(store.tasks.isEmpty)
    #expect(store.captureErrorMessage?.contains("屏幕录制权限") == true)
    #expect(!store.isCapturing)
}

@MainActor @Test func localOCRRecognizesSyntheticTextWithoutAI() async throws {
    let image = NSImage(size: NSSize(width: 1400, height: 190))
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: 1400, height: 190).fill()
    ("Screenshot OCR Demo" as NSString).draw(at: NSPoint(x: 25, y: 105), withAttributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 36, weight: .regular),
        .foregroundColor: NSColor.black
    ])
    ("Hello 2026" as NSString).draw(at: NSPoint(x: 25, y: 45), withAttributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 29, weight: .regular),
        .foregroundColor: NSColor.black
    ])
    image.unlockFocus()
    let tiff = try #require(image.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: tiff))
    let data = try #require(bitmap.representation(using: .png, properties: [:]))
    let recognized = try await LocalTextRecognitionService().recognize(data)
    let compact = recognized.text.lowercased().replacingOccurrences(of: " ", with: "")
    #expect(compact.contains("screenshotocrdemo"))
    #expect(compact.contains("hello2026"))
}

@Test func floatingPanelDragUsesScreenCoordinateDirection() {
    let start = NSPoint(x: 100, y: 400)
    let moved = FloatingPanelDragMath.origin(from: start, translation: CGSize(width: 35, height: 20))
    #expect(moved == NSPoint(x: 135, y: 380))
}

@Test func floatingOrbRoutesSingleAndDoubleClicksSeparately() {
    #expect(FloatingOrbTapRouter.action(forTapCount: 1) == .cycleMode)
    #expect(FloatingOrbTapRouter.action(forTapCount: 2) == .openPrompt)
}

@Test func promptOpensDirectlyInExistingResultOrFailureState() {
    let result = FloatingPromptInitialState(resultText: "generated result", statusMessage: "done")
    #expect(result.hasSubmittedRequest)
    #expect(result.feedbackText == nil)
    let failure = FloatingPromptInitialState(resultText: "", statusMessage: "分析失败：gateway")
    #expect(failure.hasSubmittedRequest)
    #expect(failure.feedbackText == "分析失败：gateway")
}

@Test func recognitionConfidenceUsesOnlyMatchingTextSegments() {
    let result = LocalRecognizedText(
        text: "irrelevant\nABCD1234-EFGH5678-IJKL9012",
        confidence: 0.99,
        alternatives: [],
        segments: [
            .init(text: "irrelevant", confidence: 0.99),
            .init(text: "ABCD1234-EFGH5678-IJKL9012", confidence: 0.87)
        ]
    )
    #expect(abs(result.confidence(for: "ABCD1234-EFGH5678-IJKL9012") - 0.87) < 0.001)
}
