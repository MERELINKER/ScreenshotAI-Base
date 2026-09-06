import AppKit
import Foundation

@MainActor
final class CaptureDirectoryService {
    func chooseDirectory(currentDirectory: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.title = "选择截图保存目录"
        panel.prompt = "选择"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = currentDirectory

        return panel.runModal() == .OK ? panel.url : nil
    }

    func openDirectory(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }
}
