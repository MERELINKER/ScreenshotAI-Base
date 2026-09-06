import AppKit
import Foundation

enum ClipboardServiceError: LocalizedError {
    case unreadableImage(URL)
    case imageWriteFailed
    case textWriteFailed

    var errorDescription: String? {
        switch self {
        case let .unreadableImage(url):
            return "无法读取图片：\(url.path)"
        case .imageWriteFailed:
            return "图片写入剪切板失败。"
        case .textWriteFailed:
            return "文字写入剪切板失败。"
        }
    }
}

final class ClipboardService {
    func copyImage(at fileURL: URL) throws {
        guard let image = NSImage(contentsOf: fileURL) else {
            throw ClipboardServiceError.unreadableImage(fileURL)
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.writeObjects([image]) else {
            throw ClipboardServiceError.imageWriteFailed
        }
    }

    func copyText(_ text: String) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw ClipboardServiceError.textWriteFailed
        }
    }
}
