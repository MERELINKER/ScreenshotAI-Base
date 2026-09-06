import Foundation

struct AppVersionInfo: Equatable {
    var appName: String
    var shortVersion: String
    var buildNumber: String
    var bundleIdentifier: String

    static let current = AppVersionInfo(bundle: .main)

    init(bundle: Bundle) {
        let info = bundle.infoDictionary ?? [:]
        appName = info["CFBundleDisplayName"] as? String
            ?? info["CFBundleName"] as? String
            ?? "ScreenshotAI Base"
        shortVersion = info["CFBundleShortVersionString"] as? String ?? "Dev"
        buildNumber = info["CFBundleVersion"] as? String ?? "local"
        bundleIdentifier = bundle.bundleIdentifier ?? "local.swiftpm"
    }

    var versionText: String {
        "v\(shortVersion)"
    }

    var buildText: String {
        "build \(buildNumber)"
    }

    var fullVersionText: String {
        "\(versionText) (\(buildText))"
    }
}
