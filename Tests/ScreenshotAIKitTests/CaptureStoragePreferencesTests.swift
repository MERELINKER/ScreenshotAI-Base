import Foundation
import Testing
@testable import ScreenshotAIKit

@Test
func captureStorageUsesApplicationSupportCapturesByDefault() {
    let preferences = CaptureStoragePreferences(defaults: .ephemeralCaptureDefaults())

    let directory = preferences.captureDirectory()

    #expect(directory.path.hasSuffix("ScreenshotAIBase/Captures"))
}

@Test
func customCaptureDirectoryPersists() {
    let defaults = UserDefaults.ephemeralCaptureDefaults()
    let preferences = CaptureStoragePreferences(defaults: defaults)
    let customDirectory = URL(fileURLWithPath: "/tmp/ScreenshotAI-Custom-Captures", isDirectory: true)

    preferences.setCaptureDirectory(customDirectory)

    let reloadedPreferences = CaptureStoragePreferences(defaults: defaults)
    #expect(reloadedPreferences.captureDirectory() == customDirectory)
}

private extension UserDefaults {
    static func ephemeralCaptureDefaults() -> UserDefaults {
        let suiteName = "ScreenshotAIKitTests-\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }
}
