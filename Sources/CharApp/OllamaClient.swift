import Foundation

actor OllamaClient {
    func send(messages: [ChatMessage], profile: CompanionProfile) async throws -> String {
        var request = URLRequest(url: profile.activeEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = OllamaChatRequest(
            model: profile.activeModel,
            messages: messages.map {
                OllamaChatRequest.Message(role: $0.role.rawValue, content: $0.text)
            },
            stream: false
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CompanionError.invalidResponse
        }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw CompanionError.server(body)
        }

        let decoded = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
        return decoded.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func listModels(endpoint: URL) async throws -> [String] {
        let tagsURL = endpoint.deletingLastPathComponent().appendingPathComponent("tags")
        let (data, response) = try await URLSession.shared.data(from: tagsURL)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CompanionError.invalidResponse
        }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw CompanionError.server(body)
        }

        let decoded = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
        return decoded.models.map(\.name).sorted()
    }
}

actor OpenAIClient {
    func send(messages: [ChatMessage], profile: CompanionProfile, apiKey: String) async throws -> String {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw CompanionError.missingAPIKey("OpenAI")
        }

        let trimmedModel = profile.activeModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else {
            throw CompanionError.missingModel("OpenAI")
        }

        var request = URLRequest(url: profile.activeEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            OpenAIChatRequest(
                model: trimmedModel,
                messages: messages.map {
                    OpenAIChatRequest.Message(role: $0.role.rawValue, content: $0.text)
                }
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CompanionError.invalidResponse
        }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw CompanionError.server(body)
        }

        let decoded = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw CompanionError.invalidResponse
        }
        return content
    }

    func sendWithoutAuthorization(messages: [ChatMessage], profile: CompanionProfile) async throws -> String {
        let trimmedModel = profile.activeModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else {
            throw CompanionError.missingModel("LM Studio")
        }

        let normalizedMessages = normalizeMessagesForAlternatingTemplate(messages)

        var request = URLRequest(url: profile.activeEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            OpenAIChatRequest(
                model: trimmedModel,
                messages: normalizedMessages.map {
                    OpenAIChatRequest.Message(role: $0.role.rawValue, content: $0.text)
                }
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CompanionError.invalidResponse
        }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw CompanionError.server(body)
        }

        let decoded = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw CompanionError.invalidResponse
        }
        return content
    }

    func listModels(endpoint: URL, apiKey: String) async throws -> [String] {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw CompanionError.missingAPIKey("OpenAI")
        }

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.path = "/v1/models"
        components?.query = nil
        components?.fragment = nil

        guard let url = components?.url else {
            throw CompanionError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CompanionError.invalidResponse
        }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw CompanionError.server(body)
        }

        let decoded = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        return decoded.data
            .map(\.id)
            .filter { modelID in
                modelID.hasPrefix("gpt-") || modelID.hasPrefix("o")
            }
            .sorted()
    }

    func listModelsWithoutAuthorization(endpoint: URL) async throws -> [String] {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.path = "/v1/models"
        components?.query = nil
        components?.fragment = nil

        guard let url = components?.url else {
            throw CompanionError.invalidResponse
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CompanionError.invalidResponse
        }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw CompanionError.server(body)
        }

        let decoded = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        return decoded.data.map(\.id).sorted()
    }

    private func normalizeMessagesForAlternatingTemplate(_ messages: [ChatMessage]) -> [ChatMessage] {
        var normalized: [ChatMessage] = []
        var pendingSystemBlocks: [String] = []

        for message in messages {
            let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            switch message.role {
            case .system:
                pendingSystemBlocks.append(trimmed)

            case .user, .assistant:
                var content = trimmed
                if !pendingSystemBlocks.isEmpty {
                    let systemPrefix = pendingSystemBlocks.joined(separator: "\n\n")
                    content = "[System instructions]\n\(systemPrefix)\n\n[User message]\n\(content)"
                    pendingSystemBlocks.removeAll()
                }

                let rebuilt = ChatMessage(role: message.role, text: content)
                if let last = normalized.last, last.role == rebuilt.role {
                    let mergedText = last.text + "\n\n" + rebuilt.text
                    normalized.removeLast()
                    normalized.append(ChatMessage(role: rebuilt.role, text: mergedText))
                } else {
                    normalized.append(rebuilt)
                }
            }
        }

        if !pendingSystemBlocks.isEmpty {
            let systemPrefix = pendingSystemBlocks.joined(separator: "\n\n")
            if let last = normalized.last, last.role == .user {
                normalized.removeLast()
                normalized.append(ChatMessage(role: .user, text: "[System instructions]\n\(systemPrefix)\n\n[User message]\n\(last.text)"))
            } else {
                normalized.insert(ChatMessage(role: .user, text: "[System instructions]\n\(systemPrefix)"), at: 0)
            }
        }

        if let first = normalized.first, first.role == .assistant {
            normalized.insert(ChatMessage(role: .user, text: "Stay in character and continue the conversation naturally."), at: 0)
        }

        return normalized
    }
}

actor CompanionChatClient {
    private let ollama = OllamaClient()
    private let openAI = OpenAIClient()

    func send(messages: [ChatMessage], profile: CompanionProfile, openAIKey: String) async throws -> String {
        switch profile.provider {
        case .ollama:
            return try await ollama.send(messages: messages, profile: profile)
        case .openAI:
            return try await openAI.send(messages: messages, profile: profile, apiKey: openAIKey)
        case .lmStudio:
            return try await openAI.sendWithoutAuthorization(messages: messages, profile: profile)
        }
    }

    func listOllamaModels(endpoint: URL) async throws -> [String] {
        try await ollama.listModels(endpoint: endpoint)
    }

    func listOpenAIModels(endpoint: URL, apiKey: String) async throws -> [String] {
        try await openAI.listModels(endpoint: endpoint, apiKey: apiKey)
    }

    func listLMStudioModels(endpoint: URL) async throws -> [String] {
        try await openAI.listModelsWithoutAuthorization(endpoint: endpoint)
    }

    func validate(profile: CompanionProfile, openAIKey: String) async throws -> String {
        switch profile.provider {
        case .ollama:
            let models = try await ollama.listModels(endpoint: profile.ollamaEndpoint)
            let suffix = models.isEmpty ? "сервер доступен, но список моделей пуст." : "сервер доступен, найдено моделей: \(models.count)."
            return "Ollama: \(suffix)"
        case .openAI:
            let models = try await openAI.listModels(endpoint: profile.openAIEndpoint, apiKey: openAIKey)
            let current = profile.openAIModel.isEmpty ? "Модель не выбрана." : "Текущая модель: \(profile.openAIModel)."
            return "OpenAI: доступ подтвержден, найдено моделей: \(models.count). \(current)"
        case .lmStudio:
            let models = try await openAI.listModelsWithoutAuthorization(endpoint: profile.lmStudioEndpoint)
            let current = profile.lmStudioModel.isEmpty ? "Модель не выбрана." : "Текущая модель: \(profile.lmStudioModel)."
            return "LM Studio: локальный сервер доступен, найдено моделей: \(models.count). \(current)"
        }
    }

    func generateGreeting(profile: CompanionProfile, openAIKey: String) async throws -> String {
        let prompt = startupGreetingPrompt(for: profile.responseLanguage)
        let messages = [
            ChatMessage(role: .system, text: profile.systemPrompt),
            ChatMessage(role: .user, text: prompt)
        ]
        return try await send(messages: messages, profile: profile, openAIKey: openAIKey)
    }

    private func startupGreetingPrompt(for language: CompanionResponseLanguage) -> String {
        switch language {
        case .russian:
            return "Скажи одну короткую живую приветственную реплику от лица аниме-компаньона. Только одна фраза, без списков, без пояснений, без markdown."
        case .ukrainian:
            return "Скажи одну коротку живу вітальну репліку від імені аніме-компаньйона. Лише одна фраза, без списків, без пояснень, без markdown."
        case .english:
            return "Say one short lively greeting line as an anime desktop companion. Only one sentence, no lists, no explanations, no markdown."
        }
    }
}

enum CompanionError: LocalizedError {
    case invalidResponse
    case server(String)
    case missingAPIKey(String)
    case missingModel(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "No valid response came back from the local model."
        case .server(let body):
            return "Server returned an error: \(body)"
        case .missingAPIKey(let provider):
            return "\(provider) API key is missing."
        case .missingModel(let provider):
            return "\(provider) model is not configured yet."
        }
    }
}

private struct OllamaTagsResponse: Decodable {
    struct Model: Decodable {
        let name: String
    }

    let models: [Model]
}

private struct OpenAIChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
}

private struct OpenAIChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let role: String?
            let content: String?
        }

        let message: Message
    }

    let choices: [Choice]
}

private struct OpenAIModelsResponse: Decodable {
    struct Model: Decodable {
        let id: String
    }

    let data: [Model]
}
