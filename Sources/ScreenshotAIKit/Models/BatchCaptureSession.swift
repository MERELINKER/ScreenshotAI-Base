import Foundation

public struct BatchCaptureSession: Hashable, Codable, Sendable {
    public private(set) var images: [ImageAsset]

    public init(images: [ImageAsset] = []) {
        self.images = images
    }

    public var count: Int {
        images.count
    }

    public var latestImage: ImageAsset? {
        images.last
    }

    public mutating func append(_ image: ImageAsset) {
        images.append(image)
    }

    public mutating func clear() {
        images.removeAll()
    }
}
