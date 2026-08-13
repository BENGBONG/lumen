import Foundation

// MARK: - Message model

public struct ClaudeMessage: Codable, Sendable {
    public let role: Role
    public var content: [ContentBlock]

    public enum Role: String, Codable, Sendable {
        case user, assistant
    }

    public enum ContentBlock: Codable, Sendable {
        case text(String)
        case image(mediaType: String, base64: String)

        // MARK: Codable
        private enum CodingKeys: String, CodingKey { case type, text, source }
        private enum SourceKeys: String, CodingKey { case type, mediaType = "media_type", data }

        public init(from decoder: Decoder) throws {
            let c    = try decoder.container(keyedBy: CodingKeys.self)
            let type = try c.decode(String.self, forKey: .type)
            if type == "text" {
                self = .text(try c.decode(String.self, forKey: .text))
            } else {
                let src   = try c.nestedContainer(keyedBy: SourceKeys.self, forKey: .source)
                let media = try src.decode(String.self, forKey: .mediaType)
                let data  = try src.decode(String.self, forKey: .data)
                self = .image(mediaType: media, base64: data)
            }
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let t):
                try c.encode("text", forKey: .type)
                try c.encode(t, forKey: .text)
            case .image(let media, let b64):
                try c.encode("image", forKey: .type)
                var src = c.nestedContainer(keyedBy: SourceKeys.self, forKey: .source)
                try src.encode("base64",     forKey: .type)
                try src.encode(media,        forKey: .mediaType)
                try src.encode(b64,          forKey: .data)
            }
        }
    }

    public init(role: Role, text: String) {
        self.role    = role
        self.content = [.text(text)]
    }

    public init(role: Role, blocks: [ContentBlock]) {
        self.role    = role
        self.content = blocks
    }

    /// Plain-text representation of all text blocks (for display / history).
    public var plainText: String {
        content.compactMap {
            if case .text(let t) = $0 { return t } else { return nil }
        }.joined()
    }
}
