import Foundation
import Testing
@testable import ScreenshotAIKit

@Test
func chatCompletionsRequestContainsPromptAndBase64Image() throws {
    let endpoint = VisionAPIEndpoint(
        baseURL: URL(string: "https://api.openai.com/v1")!,
        apiKey: "test-key",
        model: "gpt-4.1"
    )
    let imageData = Data([0x01, 0x02, 0x03])

    let request = try VisionAPIRequestFactory().makeChatCompletionsRequest(
        endpoint: endpoint,
        prompt: "What is on screen?",
        images: [
            VisionImageInput(data: imageData, mimeType: "image/png")
        ]
    )

    #expect(request.url?.absoluteString == "https://api.openai.com/v1/chat/completions")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

    let body = try #require(request.httpBody)
    let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
    #expect(json?["model"] as? String == "gpt-4.1")

    let messages = try #require(json?["messages"] as? [[String: Any]])
    #expect(messages.count == 2)
    #expect(messages[0]["role"] as? String == "system")
    #expect(messages[0]["content"] as? String == VisionAPIRequestFactory.defaultSystemInstruction)

    let firstMessage = messages[1]
    #expect(firstMessage["role"] as? String == "user")
    let content = try #require(firstMessage["content"] as? [[String: Any]])
    #expect(content[0]["type"] as? String == "text")
    #expect(content[0]["text"] as? String == "What is on screen?")
    #expect(content[1]["type"] as? String == "image_url")

    let imageURL = try #require(content[1]["image_url"] as? [String: Any])
    #expect(imageURL["url"] as? String == "data:image/png;base64,AQID")
}

@Test
func chatCompletionsRequestAddsV1ForRootBaseURL() throws {
    let endpoint = VisionAPIEndpoint(
        baseURL: URL(string: "https://gateway.example.invalid")!,
        apiKey: "test-key",
        model: "gpt-5.4"
    )

    let request = try VisionAPIRequestFactory().makeChatCompletionsRequest(
        endpoint: endpoint,
        prompt: "What is on screen?",
        images: [
            VisionImageInput(data: Data([0x01]), mimeType: "image/png")
        ]
    )

    #expect(request.url?.absoluteString == "https://gateway.example.invalid/v1/chat/completions")
}

@Test
func chatCompletionsRequestAllowsHTTPBaseURLForUserConfiguredGateway() throws {
    let endpoint = VisionAPIEndpoint(
        baseURL: URL(string: "http://192.0.2.10:8080/v1")!,
        apiKey: "test-key",
        model: "gpt-5.4"
    )

    let request = try VisionAPIRequestFactory().makeChatCompletionsRequest(
        endpoint: endpoint,
        prompt: "What is on screen?",
        images: [
            VisionImageInput(data: Data([0x01]), mimeType: "image/png")
        ]
    )

    #expect(request.url?.absoluteString == "http://192.0.2.10:8080/v1/chat/completions")
}

@Test
func chatCompletionsRequestCanIncludeInstructionsForCompatibleGateways() throws {
    let endpoint = VisionAPIEndpoint(
        baseURL: URL(string: "http://192.0.2.10:8080/v1")!,
        apiKey: "test-key",
        model: "gpt-5.4"
    )

    let request = try VisionAPIRequestFactory().makeChatCompletionsRequest(
        endpoint: endpoint,
        prompt: "What is on screen?",
        images: [
            VisionImageInput(data: Data([0x01]), mimeType: "image/png")
        ],
        includeInstructions: true
    )

    let body = try #require(request.httpBody)
    let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
    #expect(json?["instructions"] as? String == VisionAPIRequestFactory.defaultSystemInstruction)

    let messages = try #require(json?["messages"] as? [[String: Any]])
    #expect(messages.count == 1)
    #expect(messages[0]["role"] as? String == "user")
}

@Test
func chatCompletionsParserReturnsAssistantContent() throws {
    let responseData = Data("""
    {
      "choices": [
        {
          "message": {
            "content": "The screenshot shows a settings window."
          }
        }
      ]
    }
    """.utf8)

    let text = try VisionAPIResponseParser().parseChatCompletionsResponse(responseData)

    #expect(text == "The screenshot shows a settings window.")
}

@Test
func chatCompletionsParserThrowsReadableErrorForUnexpectedHTML() throws {
    let responseData = Data("""
    <!doctype html>
    <html lang="zh-CN">
      <head><title>Example AI Gateway</title></head>
    </html>
    """.utf8)

    do {
        _ = try VisionAPIResponseParser().parseChatCompletionsResponse(responseData)
        #expect(Bool(false))
    } catch let error as VisionAPIError {
        #expect(error.errorDescription == "API 返回格式不是 OpenAI Chat Completions JSON，请检查 Base URL 是否包含 /v1。")
    } catch {
        #expect(Bool(false))
    }
}

@Test
func chatCompletionsParserThrowsReadableAPIError() throws {
    let responseData = Data("""
    {
      "error": {
        "message": "Invalid API key"
      }
    }
    """.utf8)

    #expect(throws: VisionAPIError.self) {
        _ = try VisionAPIResponseParser().parseChatCompletionsResponse(responseData)
    }
}

@Test
func chatCompletionsParserExplainsTemporarilyUnavailableGatewayError() throws {
    let responseData = Data("""
    {
      "error": {
        "message": "Service temporarily unavailable",
        "type": "api_error"
      }
    }
    """.utf8)

    do {
        _ = try VisionAPIResponseParser().parseChatCompletionsResponse(responseData)
        #expect(Bool(false))
    } catch let error as VisionAPIError {
        #expect(error.errorDescription == "服务暂时不可用：API 网关上游当前返回 503。请稍后重试，或联系服务管理员检查上游模型、额度或密钥。")
    } catch {
        #expect(Bool(false))
    }
}
