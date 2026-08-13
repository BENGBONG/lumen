import SwiftUI
import AppearanceKit
import AIKit

struct SettingsView: View {
    @Bindable var themeStore: ThemeStore

    var body: some View {
        TabView {
            AppearanceSettingsView(themeStore: themeStore)
                .tabItem { Label("外观", systemImage: "paintbrush") }
                .padding(20)

            AISettingsView()
                .tabItem { Label("AI", systemImage: "sparkles") }
                .padding(20)
        }
        .frame(width: 560, height: 480)
    }
}

private struct AppearanceSettingsView: View {
    @Bindable var themeStore: ThemeStore

    private let columns = [GridItem(.flexible(), spacing: 14),
                           GridItem(.flexible(), spacing: 14),
                           GridItem(.flexible(), spacing: 14)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("主题")
                .font(.headline)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(ThemeStore.allThemes, id: \.id) { theme in
                        ThemeCard(
                            theme: theme,
                            isSelected: theme.id == themeStore.theme.id,
                            onSelect: { themeStore.setTheme(id: theme.id) }
                        )
                    }
                }
            }

            Text("当前选择会立刻应用到所有窗口，重启后保留。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - AI Settings

private struct AISettingsView: View {
    @State private var selectedProvider = AIProvider.current
    @State private var keyDrafts: [AIProvider: String] = {
        var d: [AIProvider: String] = [:]
        for p in AIProvider.allCases { d[p] = KeychainStore.load(for: p) ?? "" }
        return d
    }()
    @State private var selectedModel: String = AIProvider.current.currentModel
    @State private var customModel: String = ""
    @State private var customEndpoint: String = AIProvider.customEndpointURL
    @State private var isTesting  = false
    @State private var testResult : String?
    @State private var testOK     = false
    @State private var saved      = false

    private var keyDraft: Binding<String> {
        Binding(
            get: { keyDrafts[selectedProvider] ?? "" },
            set: { keyDrafts[selectedProvider] = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            // ── Provider picker ─────────────────────────────────────────
            Text("AI 服务商").font(.headline)

            Picker("", selection: $selectedProvider) {
                ForEach(AIProvider.allCases, id: \.self) { p in
                    Text(p.displayName).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedProvider) { _, p in
                AIProvider.current = p
                selectedModel = p.currentModel
            }

            // ── Custom endpoint (only for .custom provider) ──────────────
            if selectedProvider == .custom {
                Text("API Endpoint").font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    TextField("https://your-proxy.com/v1/chat/completions",
                              text: $customEndpoint)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                    Button("保存") {
                        AIProvider.customEndpointURL = customEndpoint
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                Text("兼容 OpenAI Chat Completions 格式的任意接口，例如国内代理服务。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            // ── API Key ──────────────────────────────────────────────────
            Text("API Key").font(.subheadline).foregroundStyle(.secondary)

            HStack(spacing: 6) {
                SecureField(selectedProvider.keyPlaceholder, text: keyDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))

                Button("保存") { saveKey() }
                    .disabled(keyDraft.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)

                if KeychainStore.hasKey(for: selectedProvider) {
                    Button("删除", role: .destructive) {
                        try? KeychainStore.delete(for: selectedProvider)
                        keyDrafts[selectedProvider] = ""
                        testResult = nil
                    }
                }
            }

            if saved {
                Label("已保存", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.system(size: 12))
            }

            // ── Model ────────────────────────────────────────────────────
            Text("模型").font(.subheadline).foregroundStyle(.secondary)

            if selectedProvider == .custom || selectedProvider.presetModels.isEmpty {
                // Custom provider: free-form input + common suggestions
                HStack(spacing: 6) {
                    TextField("例如 MiniMax-M2.7 / gpt-4o", text: $customModel)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .onAppear {
                            if customModel.isEmpty {
                                customModel = selectedProvider.currentModel
                            }
                        }
                    Button("保存") {
                        let m = customModel.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !m.isEmpty else { return }
                        selectedProvider.currentModel = m
                    }
                    .disabled(customModel.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                // Quick-fill suggestions for common self-hosted / proxy models
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach([
                            "MiniMax-M2.7", "MiniMax-M2.7-highspeed",
                            "MiniMax-M2.5", "MiniMax-M2.1",
                            "gpt-4o", "gpt-4o-mini",
                        ], id: \.self) { m in
                            Button(m) { customModel = m }
                                .buttonStyle(.bordered)
                                .font(.system(size: 10, design: .monospaced))
                                .controlSize(.mini)
                        }
                    }
                }
            } else {
                HStack(spacing: 6) {
                    Picker("", selection: $selectedModel) {
                        ForEach(selectedProvider.presetModels, id: \.id) { m in
                            Text(m.label).tag(m.id)
                        }
                        Divider()
                        Text("自定义…").tag("custom")
                    }
                    .frame(maxWidth: .infinity)
                    .onChange(of: selectedModel) { _, m in
                        if m != "custom" { selectedProvider.currentModel = m }
                    }

                    if selectedModel == "custom" {
                        TextField("模型 ID", text: $customModel)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 160)
                        Button("确定") {
                            selectedProvider.currentModel = customModel
                            selectedModel = customModel
                        }
                        .disabled(customModel.isEmpty)
                    }
                }
            }

            // ── Test ─────────────────────────────────────────────────────
            HStack(spacing: 8) {
                Button(action: testKey) {
                    if isTesting {
                        ProgressView().scaleEffect(0.7).frame(height: 16)
                    } else {
                        Text("验证连接")
                    }
                }
                .disabled(isTesting || keyDraft.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)

                if let result = testResult {
                    Label(result,
                          systemImage: testOK ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(testOK ? .green : .red)
                        .font(.system(size: 12))
                }
            }

            Spacer()

            // ── Get key link ─────────────────────────────────────────────
            if let url = selectedProvider.keyURL {
                Link("获取 API Key → \(url.host ?? "")", destination: url)
                    .font(.system(size: 11))
                    .foregroundStyle(.blue)
            } else if selectedProvider == .custom {
                Text("填写你的代理服务提供的 Endpoint 和 API Key")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    /// Sanitise a pasted API key: strip surrounding whitespace/newlines and
    /// remove an accidental "Bearer " prefix that some users copy together
    /// with the token.
    private func cleanKey(_ raw: String) -> String {
        var k = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if k.lowercased().hasPrefix("bearer ") {
            k = String(k.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return k
    }

    private func saveKey() {
        let key = cleanKey(keyDraft.wrappedValue)
        guard !key.isEmpty else { return }
        // Write back the cleaned value so the user sees what was stored
        keyDrafts[selectedProvider] = key
        try? KeychainStore.save(key, for: selectedProvider)
        AIProvider.current = selectedProvider
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
    }

    private func testKey() {
        let key = cleanKey(keyDraft.wrappedValue)
        guard !key.isEmpty else { return }
        // Persist the cleaned key first
        keyDrafts[selectedProvider] = key
        try? KeychainStore.save(key, for: selectedProvider)
        AIProvider.current = selectedProvider
        isTesting  = true
        testResult = nil
        let provider = selectedProvider
        // For the .custom provider the user always types the model in customModel.
        // For preset providers, use selectedModel (falling back to customModel when "custom" tag).
        let model: String
        if selectedProvider == .custom {
            model = customModel.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if selectedModel == "custom" {
            model = customModel.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            model = selectedModel
        }
        Task {
            let client = AIClient(provider: provider, apiKey: key, model: model)
            do {
                let reply = try await client.chat(
                    messages: [ClaudeMessage(role: .user, text: "Reply with exactly: OK")],
                    maxTokens: 32
                )
                testOK     = reply.lowercased().contains("ok")
                testResult = testOK ? "连接成功 ✓" : "连接成功，但响应异常（\(reply.prefix(40))）"
            } catch {
                testOK     = false
                testResult = "连接失败：\(error.localizedDescription)"
            }
            isTesting = false
        }
    }
}

private struct ThemeCard: View {
    let theme: any AppearanceTheme
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                ThemePreview(theme: theme)
                    .frame(height: 92)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isSelected ? theme.accent : .clear, lineWidth: 2)
                    )
                Text(theme.displayName)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ThemePreview: View {
    let theme: any AppearanceTheme

    var body: some View {
        ZStack {
            // 材质在小预览里渲染不出效果，用等效纯色（previewPane/previewSidebar）
            Rectangle().fill(theme.previewPane)
            HStack(spacing: 0) {
                Rectangle()
                    .fill(theme.previewSidebar)
                    .frame(width: 36)
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        Capsule().fill(theme.accent).frame(width: 14, height: 4)
                        Capsule().fill(theme.secondaryText.opacity(0.5)).frame(width: 24, height: 4)
                        Spacer()
                    }
                    .padding(6)
                    Rectangle().fill(theme.rowSelected).frame(height: 8)
                    Rectangle().fill(theme.rowHover).frame(height: 6)
                    Rectangle().fill(theme.rowHover).frame(height: 6)
                    Spacer()
                }
            }
        }
    }
}
