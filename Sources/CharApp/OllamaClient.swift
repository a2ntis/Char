import Foundation

actor OllamaClient {
    func send(messages: [ChatMessage], profile: CompanionProfile) async throws -> String {
        var request = URLRequest(url: profile.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = OllamaChatRequest(
            model: profile.model,
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
}

enum CompanionError: LocalizedError {
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "No valid response came back from the local model."
        case .server(let body):
            return "Ollama returned an error: \(body)"
        }
    }
}
