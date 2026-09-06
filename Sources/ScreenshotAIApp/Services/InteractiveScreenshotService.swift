import Foundation
import CoreGraphics
import AppKit
import ScreenshotAIKit

struct CapturedScreenshot: Sendable {
    var image: ImageAsset
    var data: Data
}

enum ScreenshotCaptureError: Error, LocalizedError {
    case canceled
    case permissionRequired
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .canceled:
            return "截图已取消"
        case .permissionRequired:
            return "未获得屏幕录制权限。请到系统设置 → 隐私与安全性 → 屏幕与系统音频录制中允许 ScreenshotAI，然后退出并重新打开应用。"
        case let .captureFailed(message):
            return message
        }
    }
}

protocol ScreenshotCapturing: Sendable {
    @MainActor func capture(saveDirectory: URL) async throws -> CapturedScreenshot
}

struct InteractiveScreenshotService: ScreenshotCapturing {
    @MainActor
    func capture(saveDirectory: URL) async throws -> CapturedScreenshot {
        guard CGPreflightScreenCaptureAccess() else {
            // Request only when the user explicitly initiates a capture.
            _ = CGRequestScreenCaptureAccess()
            throw ScreenshotCaptureError.permissionRequired
        }
        let fileURL = try makeCaptureFileURL(in: saveDirectory)
        let visibleWindows = NSApp.windows.filter(\.isVisible)
        visibleWindows.forEach { $0.orderOut(nil) }
        defer { visibleWindows.forEach { $0.orderFront(nil) } }
        // Let our windows and menu disappear before the system captures the desktop.
        try await Task.sleep(for: .milliseconds(180))
        let process = Process()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-r", "-t", "png", fileURL.path]
        process.standardError = errorPipe

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { finishedProcess in
                if finishedProcess.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    if (message?.isEmpty ?? true), !FileManager.default.fileExists(atPath: fileURL.path) {
                        continuation.resume(throwing: ScreenshotCaptureError.canceled)
                    } else {
                        continuation.resume(throwing: ScreenshotCaptureError.captureFailed(message?.isEmpty == false ? message! : "截图失败，请检查屏幕录制权限和截图保存目录。"))
                    }
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ScreenshotCaptureError.canceled
        }

        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            throw ScreenshotCaptureError.canceled
        }

        return CapturedScreenshot(
            image: ImageAsset(
                displayName: "Capture \(Self.timestamp.string(from: Date()))",
                fileURL: fileURL,
                mimeType: "image/png"
            ),
            data: data
        )
    }

    private func makeCaptureFileURL(in directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = "ScreenshotAI-\(Self.fileTimestamp.string(from: Date())).png"
        return directory.appendingPathComponent(filename)
    }

    private static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let fileTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter
    }()
}
