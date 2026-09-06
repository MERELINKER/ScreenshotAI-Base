import Foundation

public struct VisionAPIEndpoint: Hashable, Sendable {
    public var baseURL: URL
    public var apiKey: String
    public var model: String

    public init(baseURL: URL, apiKey: String, model: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
    }
}

public struct VisionImageInput: Hashable, Sendable {
    public var data: Data
    public var mimeType: String

    public init(data: Data, mimeType: String) {
        self.data = data
        self.mimeType = mimeType
    }
}

public enum VisionAPIError: Error, Equatable, LocalizedError, Sendable {
    case invalidEndpoint
    case insecureEndpoint
    case secureConnectionFailed
    case emptyPrompt
    case noImages
    case emptyResponse
    case apiError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "API 地址无效"
        case .insecureEndpoint:
            return "Base URL 必须使用 https://，macOS 会拦截 http:// 请求。"
        case .secureConnectionFailed:
            return "TLS 连接失败：当前地址不像可用的 HTTPS 服务。若服务只支持 HTTP，请使用 http:// 地址；若要使用 HTTPS，请让服务端配置有效 TLS 证书和协议。"
        case .emptyPrompt:
            return "Prompt 不能为空"
        case .noImages:
            return "没有可发送的图片"
        case .emptyResponse:
            return "模型没有返回内容"
        case let .apiError(message):
            return APIErrorMessageFormatter.readableMessage(message)
        }
    }
}

private enum APIErrorMessageFormatter {
    static func readableMessage(_ message: String) -> String {
        let normalizedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercaseMessage = normalizedMessage.lowercased()

        if lowercaseMessage.contains("service temporarily unavailable") {
            return "服务暂时不可用：API 网关上游当前返回 503。请稍后重试，或联系服务管理员检查上游模型、额度或密钥。"
        }

        if lowercaseMessage.contains("upstream authentication failed") {
            return "上游鉴权失败：API 网关无法使用它配置的上游密钥。请联系服务管理员检查上游 API Key。"
        }

        return normalizedMessage
    }
}

public struct VisionAPIRequestFactory: Sendable {
    public static let defaultSystemInstruction = """
    你是截图分析助手。严格遵循用户指定的输出格式；只输出最终答案，不要复述任务要求；不要重复标题、摘要、段落、列表或完整答案。若同一结论已经写过，只保留第一次出现的版本。答案结束后立刻停止，不要在末尾重新追加答案开头或开头段落。除非用户明确要求多版候选，否则不要输出多版答案。如果用户要求简洁，就保持简洁。
    """

    public init() {}

    public func makeChatCompletionsRequest(
        endpoint: VisionAPIEndpoint,
        prompt: String,
        images: [VisionImageInput],
        includeInstructions: Bool = false
    ) throws -> URLRequest {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { throw VisionAPIError.emptyPrompt }
        guard !images.isEmpty else { throw VisionAPIError.noImages }

        let baseURL = endpoint.normalizedOpenAICompatibleBaseURL
        let url = baseURL
            .appendingPathComponent("chat")
            .appendingPathComponent("completions")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(endpoint.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = ChatCompletionsRequest(
            instructions: includeInstructions ? Self.defaultSystemInstruction : nil,
            model: endpoint.model,
            messages: (includeInstructions ? [] : [
                ChatMessage(role: "system", content: .plainText(Self.defaultSystemInstruction))
            ]) + [
                ChatMessage(
                    role: "user",
                    content: .parts([.text(trimmedPrompt)] + images.map { .image($0.dataURLString) })
                )
            ]
        )

        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }
}

private extension VisionAPIEndpoint {
    var normalizedOpenAICompatibleBaseURL: URL {
        let nonRootPathComponents = baseURL.pathComponents.filter { $0 != "/" }
        guard nonRootPathComponents.isEmpty else { return baseURL }
        return baseURL.appendingPathComponent("v1")
    }
}

public struct VisionAPIResponseParser: Sendable {
    public init() {}

    public func parseChatCompletionsResponse(_ data: Data) throws -> String {
        if let errorEnvelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
            throw VisionAPIError.apiError(errorEnvelope.error.message)
        }

        do {
            let response = try JSONDecoder().decode(ChatCompletionsResponse.self, from: data)
            guard let text = response.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty
            else {
                throw VisionAPIError.emptyResponse
            }
            return text
        } catch let error as VisionAPIError {
            throw error
        } catch {
            throw VisionAPIError.apiError("API 返回格式不是 OpenAI Chat Completions JSON，请检查 Base URL 是否包含 /v1。")
        }
    }
}

public final class VisionAPIClient: Sendable {
    private let factory: VisionAPIRequestFactory
    private let parser: VisionAPIResponseParser
    private let session: URLSession

    public init(
        factory: VisionAPIRequestFactory = VisionAPIRequestFactory(),
        parser: VisionAPIResponseParser = VisionAPIResponseParser(),
        session: URLSession = .shared
    ) {
        self.factory = factory
        self.parser = parser
        self.session = session
    }

    public func analyze(
        endpoint: VisionAPIEndpoint,
        prompt: String,
        images: [VisionImageInput]
    ) async throws -> String {
        let request = try factory.makeChatCompletionsRequest(
            endpoint: endpoint,
            prompt: prompt,
            images: images
        )
        let result = try await data(for: request)

        if shouldRetryWithInstructions(data: result.data, response: result.response) {
            let retryRequest = try factory.makeChatCompletionsRequest(
                endpoint: endpoint,
                prompt: prompt,
                images: images,
                includeInstructions: true
            )
            let retryResult = try await data(for: retryRequest)
            return try parse(data: retryResult.data, response: retryResult.response)
        }

        return try parse(data: result.data, response: result.response)
    }

    private func data(for request: URLRequest) async throws -> (data: Data, response: URLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .appTransportSecurityRequiresSecureConnection {
            throw VisionAPIError.insecureEndpoint
        } catch let error as URLError where error.code == .secureConnectionFailed {
            throw VisionAPIError.secureConnectionFailed
        }
        return (data, response)
    }

    private func parse(data: Data, response: URLResponse) throws -> String {
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            if let apiError = try? parser.parseChatCompletionsResponse(data) {
                throw VisionAPIError.apiError(apiError)
            }
            if let errorEnvelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
                throw VisionAPIError.apiError(errorEnvelope.error.message)
            }
            throw VisionAPIError.apiError("HTTP \(httpResponse.statusCode)")
        }

        return try parser.parseChatCompletionsResponse(data)
    }

    private func shouldRetryWithInstructions(data: Data, response: URLResponse) -> Bool {
        guard let httpResponse = response as? HTTPURLResponse,
              !(200...299).contains(httpResponse.statusCode),
              let errorEnvelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
        else {
            return false
        }
        return errorEnvelope.error.message
            .localizedCaseInsensitiveContains("Instructions are required")
    }
}

private struct ChatCompletionsRequest: Encodable {
    var instructions: String?
    var model: String
    var messages: [ChatMessage]
}

private struct ChatMessage: Encodable {
    var role: String
    var content: ChatMessageContent
}

private enum ChatMessageContent: Encodable {
    case plainText(String)
    case parts([ChatContentPart])

    func encode(to encoder: Encoder) throws {
        switch self {
        case let .plainText(text):
            var container = encoder.singleValueContainer()
            try container.encode(text)
        case let .parts(parts):
            var container = encoder.singleValueContainer()
            try container.encode(parts)
        }
    }
}

private enum ChatContentPart: Encodable {
    case text(String)
    case image(String)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case let .image(dataURL):
            try container.encode("image_url", forKey: .type)
            try container.encode(["url": dataURL], forKey: .imageURL)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }
}

private extension VisionImageInput {
    var dataURLString: String {
        "data:\(mimeType);base64,\(data.base64EncodedString())"
    }
}

private struct ChatCompletionsResponse: Decodable {
    var choices: [Choice]

    struct Choice: Decodable {
        var message: Message
    }

    struct Message: Decodable {
        var content: String
    }
}

private struct APIErrorEnvelope: Decodable {
    var error: APIError

    struct APIError: Decodable {
        var message: String
    }
}
