import Foundation
import Testing
@testable import ScreenshotAIKit

@Test
func batchCaptureSessionAppendsImagesInOrder() {
    var session = BatchCaptureSession()
    let first = ImageAsset(displayName: "First")
    let second = ImageAsset(displayName: "Second")

    session.append(first)
    session.append(second)

    #expect(session.images == [first, second])
    #expect(session.latestImage == second)
    #expect(session.count == 2)
}

@Test
func batchCaptureSessionCanBeCleared() {
    var session = BatchCaptureSession(images: [ImageAsset(displayName: "Capture")])

    session.clear()

    #expect(session.images.isEmpty)
    #expect(session.latestImage == nil)
    #expect(session.count == 0)
}
