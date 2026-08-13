import Foundation

// MARK: - AIClient

/// Universal AI client that routes to Anthropic, OpenAI, or OpenRouter
/// depending on the provider, normalising the three different APIs into
/// one streaming interface.
public actor AIClient {

    public let provider: AIProvider
    public let model:    String
    private let apiKey:  String

    // MARK: - Init

    public init(provider: AIProvider, apiKey: String, model: String? = nil) {
        self.provider = provider
        self.apiKey   = apiKey
        self.model    = model ?? provider.defaultModel
    }

    /// Convenience: build from the current Keychain / UserDefaults selection.
    public static func fromCurrentSettings() -> AIClient? {
        let provider = AIProvider.current
        guard let key = KeychainStore.load(for: provider), !key.isEmpty else { return nil }
        return AIClient(provider: provider, apiKey: key, model: provider.currentModel)
    }

    // MARK: - Streaming chat

    /// Stream incremental text deltas.  Calls `onChunk` for each piece;
    /// throws on network or HTTP errors.
    public func streamChat(
        system:    String? = nil,
        messages:  [ClaudeMessage],
        maxTokens: Int = 4096,
        onChunk:   @Sendable @escaping (String) async -> Void
    ) async throws {
        switch provider {
        case .anthropic:
            try await streamAnthropic(system: system, messages: messages,
                                      maxTokens: maxTokens, onChunk: onChunk)
        case .openAI, .openRouter, .custom:
            try await streamOpenAI(system: system, messages: messages,
                                   maxTokens: maxTokens, onChunk: onChunk)
        }
    }

    // MARK: - Single response (test / short requests)

    public func chat(
        system:    String? = nil,
        messages:  [ClaudeMessage],
        maxTokens: Int = 1024
    ) async throws -> String {
        switch provider {
        case .anthropic:
            return try await singleAnthropic(system: system, messages: messages, maxTokens: maxTokens)
        case .openAI, .openRouter, .custom:
            return try await singleOpenAI(system: system, messages: messages, maxTokens: maxTokens)
        }
    }

    // MARK: - Anthropic (Messages API)

    private func streamAnthropic(system: String?, messages: [ClaudeMessage],
                                  maxTokens: Int,
                                  onChunk: @Sendable @escaping (String) async -> Void) async throws {
        var req = anthropicRequest()
        req.httpBody = try JSONEncoder().encode(anthropicBody(system: system, messages: messages,
                                                              maxTokens: maxTokens, stream: true))
        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        try validate(resp)
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            guard payload != "[DONE]",
                  let data  = payload.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(AnthropicChunk.self, from: data),
                  let text  = chunk.delta?.text, !text.isEmpty else { continue }
            await onChunk(text)
        }
    }

    private func singleAnthropic(system: String?, messages: [ClaudeMessage],
                                  maxTokens: Int) async throws -> String {
        var req = anthropicRequest()
        req.httpBody = try JSONEncoder().encode(anthropicBody(system: system, messages: messages,
                                                              maxTokens: maxTokens, stream: false))
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validateWithBody(resp, data: data)
        let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        return decoded.content.first?.text ?? ""
    }

    private func anthropicRequest() -> URLRequest {
        var r = URLRequest(url: provider.endpoint)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(apiKey,             forHTTPHeaderField: "x-api-key")
        r.setValue("2023-06-01",       forHTTPHeaderField: "anthropic-version")
        return r
    }

    private struct AnthropicBody: Encodable {
        let model: String; let maxTokens: Int; let system: String?
        let messages: [ClaudeMessage]; let stream: Bool
        enum CodingKeys: String, CodingKey {
            case model, system, messages, stream
            case maxTokens = "max_tokens"
        }
    }

    private func anthropicBody(system: String?, messages: [ClaudeMessage],
                                maxTokens: Int, stream: Bool) -> AnthropicBody {
        AnthropicBody(model: model, maxTokens: maxTokens, system: system,
                      messages: messages, stream: stream)
    }

    private struct AnthropicChunk: Decodable {
        struct Delta: Decodable { let text: String? }
        let delta: Delta?
    }

    private struct AnthropicResponse: Decodable {
        struct Block: Decodable { let text: String? }
        let content: [Block]
    }

    // MARK: - OpenAI / OpenRouter (Chat Completions API)

    private func streamOpenAI(system: String?, messages: [ClaudeMessage],
                               maxTokens: Int,
                               onChunk: @Sendable @escaping (String) async -> Void) async throws {
        let body = openAIBody(system: system, messages: messages, maxTokens: maxTokens, stream: true)
        var req  = openAIRequest()
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        try validate(resp)
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            guard payload != "[DONE]",
                  let data  = payload.data(using: .utf8),
                  let json  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta   = choices.first?["delta"] as? [String: Any],
                  let text    = delta["content"] as? String, !text.isEmpty else { continue }
            await onChunk(text)
        }
    }

    private func singleOpenAI(system: String?, messages: [ClaudeMessage],
                               maxTokens: Int) async throws -> String {
        let body = openAIBody(system: system, messages: messages, maxTokens: maxTokens, stream: false)
        var req  = openAIRequest()
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validateWithBody(resp, data: data)
        guard let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let msg     = choices.first?["message"] as? [String: Any],
              let content = msg["content"] as? String else { return "" }
        return content
    }

    private func openAIRequest() -> URLRequest {
        var r = URLRequest(url: provider.endpoint)
        r.httpMethod = "POST"
        r.setValue("application/json",     forHTTPHeaderField: "Content-Type")
        r.setValue("Bearer \(apiKey)",     forHTTPHeaderField: "Authorization")
        if provider == .openRouter {
            r.setValue("ForkLiftClone/1.0", forHTTPHeaderField: "HTTP-Referer")
            r.setValue("ForkLiftClone",     forHTTPHeaderField: "X-Title")
        }
        return r
    }

    private func openAIBody(system: String?, messages: [ClaudeMessage],
                             maxTokens: Int, stream: Bool) -> [String: Any] {
        var msgs: [[String: Any]] = []
        // System prompt as first message
        if let sys = system {
            msgs.append(["role": "system", "content": sys])
        }
        // Convert ClaudeMessage blocks to OpenAI content
        for msg in messages {
            let content: Any
            if msg.content.count == 1, case .text(let t) = msg.content[0] {
                content = t   // simple string for text-only messages
            } else {
                content = msg.content.map { block -> [String: Any] in
                    switch block {
                    case .text(let t):
                        return ["type": "text", "text": t]
                    case .image(let media, let b64):
                        return ["type": "image_url",
                                "image_url": ["url": "data:\(media);base64,\(b64)"]]
                    }
                }
            }
            msgs.append(["role": msg.role.rawValue, "content": content])
        }
        let body: [String: Any] = [
            "model":       model,
            "messages":    msgs,
            "max_tokens":  maxTokens,
            "stream":      stream,
            // MiniMax requires temperature in (0.0, 1.0]; 0.7 is safe for all providers.
            "temperature": 0.7,
        ]
        return body
    }

    // MARK: - Shared helpers

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw AIError.httpError(http.statusCode, provider: provider)
        }
    }

    /// Validate + extract the API's own error message from the response body.
    private func validateWithBody(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            // Try to read the API's error message
            var detail = ""
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Anthropic: {"error": {"message": "…"}}
                if let err = json["error"] as? [String: Any],
                   let msg = err["message"] as? String { detail = msg }
                // OpenAI: {"error": {"message": "…"}}  — same shape
                // OpenRouter error field
                if detail.isEmpty, let msg = json["message"] as? String { detail = msg }
            }
            throw AIError.httpErrorDetail(http.statusCode, provider: provider, detail: detail)
        }
    }

    // MARK: - Error

    public enum AIError: LocalizedError {
        case httpError(Int, provider: AIProvider)
        case httpErrorDetail(Int, provider: AIProvider, detail: String)
        case noKey(provider: AIProvider)

        public var errorDescription: String? {
            switch self {
            case .httpError(let code, let p):
                return "\(p.displayName) API 错误 (HTTP \(code))"
            case .httpErrorDetail(let code, let p, let detail):
                let base = "\(p.displayName) API 错误 (HTTP \(code))"
                return detail.isEmpty ? base : "\(base): \(detail)"
            case .noKey(let p):
                return "请先在设置中填写 \(p.displayName) 的 API Key"
            }
        }
    }
}

// MARK: - Backward-compat typealias

/// Old name kept so existing call sites in ChatSession compile without change.
public typealias ClaudeClient = AIClient
