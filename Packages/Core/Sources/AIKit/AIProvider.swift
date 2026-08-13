import Foundation

/// Supported AI providers.  Each has its own endpoint, auth scheme, and
/// message-format dialect.
public enum AIProvider: String, CaseIterable, Sendable {
    case anthropic  = "anthropic"
    case openAI     = "openai"
    case openRouter = "openrouter"
    /// Any OpenAI-compatible proxy (custom base URL + bearer token).
    case custom     = "custom"

    // MARK: - Display

    public var displayName: String {
        switch self {
        case .anthropic:  return "Claude (Anthropic)"
        case .openAI:     return "OpenAI"
        case .openRouter: return "OpenRouter"
        case .custom:     return "自定义"
        }
    }

    public var keyPlaceholder: String {
        switch self {
        case .anthropic:  return "sk-ant-…"
        case .openAI:     return "sk-…"
        case .openRouter: return "sk-or-…"
        case .custom:     return "API Key（任意格式）"
        }
    }

    public var keyURL: URL? {
        switch self {
        case .anthropic:  return URL(string: "https://console.anthropic.com/settings/keys")
        case .openAI:     return URL(string: "https://platform.openai.com/api-keys")
        case .openRouter: return URL(string: "https://openrouter.ai/settings/keys")
        case .custom:     return nil
        }
    }

    // MARK: - API endpoint

    /// For .custom, the caller must supply a base URL; this returns a fallback.
    public var endpoint: URL {
        switch self {
        case .anthropic:
            return URL(string: "https://api.anthropic.com/v1/messages")!
        case .openAI:
            return URL(string: "https://api.openai.com/v1/chat/completions")!
        case .openRouter:
            return URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        case .custom:
            // Resolved at runtime from the stored custom endpoint
            let stored = AIProvider.customEndpointURL
            return URL(string: stored.isEmpty
                       ? "https://api.openai.com/v1/chat/completions"
                       : stored)
                   ?? URL(string: "https://api.openai.com/v1/chat/completions")!
        }
    }

    // MARK: - Custom endpoint persistence

    public static let customEndpointKey = "ForkLiftClone.aiCustomEndpoint"

    public static var customEndpointURL: String {
        get { UserDefaults.standard.string(forKey: customEndpointKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: customEndpointKey) }
    }

    // MARK: - Default model

    public var defaultModel: String {
        switch self {
        case .anthropic:  return "claude-3-5-sonnet-20241022"
        case .openAI:     return "gpt-4o"
        case .openRouter: return "openai/gpt-4o"
        case .custom:     return "gpt-4o"
        }
    }

    /// Curated model list shown in the picker.
    public var presetModels: [(id: String, label: String)] {
        switch self {
        case .anthropic:
            return [
                ("claude-3-5-sonnet-20241022", "Claude 3.5 Sonnet"),
                ("claude-3-5-haiku-20241022",  "Claude 3.5 Haiku"),
                ("claude-3-opus-20240229",     "Claude 3 Opus"),
                ("claude-opus-4-5",            "Claude Opus 4.5"),
                ("claude-sonnet-4-5",          "Claude Sonnet 4.5"),
            ]
        case .openAI:
            return [
                ("gpt-4o",        "GPT-4o"),
                ("gpt-4o-mini",   "GPT-4o mini"),
                ("gpt-4-turbo",   "GPT-4 Turbo"),
                ("o3",            "o3"),
                ("o4-mini",       "o4-mini"),
            ]
        case .openRouter:
            return [
                ("openai/gpt-4o",                       "GPT-4o"),
                ("anthropic/claude-3.5-sonnet",         "Claude 3.5 Sonnet"),
                ("google/gemini-2.0-flash-001",         "Gemini 2.0 Flash"),
                ("meta-llama/llama-3.3-70b-instruct",  "Llama 3.3 70B"),
                ("deepseek/deepseek-r1",                "DeepSeek R1"),
            ]
        case .custom:
            // No presets — user types the model name manually
            return []
        }
    }

    // MARK: - Persistence

    /// UserDefaults key for the currently selected provider.
    public static let selectedKey = "ForkLiftClone.aiProvider"

    public static var current: AIProvider {
        get {
            let raw = UserDefaults.standard.string(forKey: selectedKey) ?? ""
            return AIProvider(rawValue: raw) ?? .anthropic
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: selectedKey)
        }
    }

    /// UserDefaults key for the selected model for this provider.
    public var modelKey: String { "ForkLiftClone.aiModel.\(rawValue)" }

    public var currentModel: String {
        get { UserDefaults.standard.string(forKey: modelKey) ?? defaultModel }
        set { UserDefaults.standard.set(newValue, forKey: modelKey) }
    }
}
