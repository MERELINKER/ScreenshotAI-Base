import Foundation

public struct CaptureStoragePreferences {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func captureDirectory() -> URL {
        guard let path = defaults.string(forKey: Self.captureDirectoryKey),
              !path.isEmpty
        else {
            return Self.defaultCaptureDirectory()
        }

        return URL(fileURLWithPath: path, isDirectory: true)
    }

    public func setCaptureDirectory(_ directory: URL) {
        defaults.set(directory.path, forKey: Self.captureDirectoryKey)
    }

    public static func defaultCaptureDirectory() -> URL {
        let baseURL = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )

        return (baseURL ?? FileManager.default.homeDirectoryForCurrentUser)
            .appendingPathComponent("ScreenshotAIBase", isDirectory: true)
            .appendingPathComponent("Captures", isDirectory: true)
    }

    private static let captureDirectoryKey = "captureDirectoryPath"
}
