import Foundation
import CoreGraphics

enum CompanionLLMProvider: String, CaseIterable, Codable, Hashable, Identifiable {
    case ollama
    case openAI
    case lmStudio

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ollama:
            return "Ollama"
        case .openAI:
            return "OpenAI"
        case .lmStudio:
            return "LM Studio"
        }
    }
}

enum CompanionResponseLanguage: String, CaseIterable, Codable, Hashable, Identifiable {
    case russian
    case ukrainian
    case english

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .russian:
            return "Русский"
        case .ukrainian:
            return "Українська"
        case .english:
            return "English"
        }
    }

    var systemInstruction: String {
        switch self {
        case .russian:
            return "Always reply in Russian unless the user explicitly asks you to switch languages."
        case .ukrainian:
            return "Always reply in Ukrainian unless the user explicitly asks you to switch languages."
        case .english:
            return "Always reply in English unless the user explicitly asks you to switch languages."
        }
    }
}

struct ChatMessage: Identifiable, Hashable {
    let id = UUID()
    let role: Role
    let text: String
    let createdAt = Date()

    enum Role: String, Hashable {
        case system
        case user
        case assistant
    }
}

struct CompanionProfile: Codable, Hashable {
    var name: String = "Hana"
    var persona: String = """
    You are Hana, a warm anime-style desktop companion living on the user's Mac.
    Keep answers concise, emotionally expressive, playful, and supportive.
    You are not a generic assistant; you are a charming companion who can chat naturally,
    react to the user's mood, and keep the conversation light unless the user asks for detail.
    """
    var responseLanguage: CompanionResponseLanguage = .russian
    var provider: CompanionLLMProvider = .ollama
    var ollamaModel: String = "qwen3:14b"
    var ollamaEndpoint: URL = URL(string: "http://127.0.0.1:11434/api/chat")!
    var openAIModel: String = ""
    var openAIEndpoint: URL = URL(string: "https://api.openai.com/v1/chat/completions")!
    var lmStudioModel: String = ""
    var lmStudioEndpoint: URL = URL(string: "http://127.0.0.1:1234/v1/chat/completions")!

    var activeModel: String {
        switch provider {
        case .ollama:
            return ollamaModel
        case .openAI:
            return openAIModel
        case .lmStudio:
            return lmStudioModel
        }
    }

    var activeEndpoint: URL {
        switch provider {
        case .ollama:
            return ollamaEndpoint
        case .openAI:
            return openAIEndpoint
        case .lmStudio:
            return lmStudioEndpoint
        }
    }

    mutating func setActiveModel(_ model: String) {
        switch provider {
        case .ollama:
            ollamaModel = model
        case .openAI:
            openAIModel = model
        case .lmStudio:
            lmStudioModel = model
        }
    }

    mutating func setActiveEndpoint(_ endpoint: URL) {
        switch provider {
        case .ollama:
            ollamaEndpoint = endpoint
        case .openAI:
            openAIEndpoint = endpoint
        case .lmStudio:
            lmStudioEndpoint = endpoint
        }
    }

    var systemPrompt: String {
        persona + "\n\n" + responseLanguage.systemInstruction
    }
}

struct CompanionModelOption: Identifiable, Hashable {
    let id: String
    let displayName: String
    let assetRootPath: String
    let preset: CompanionModelPreset
    let expressions: [CompanionExpressionOption]
    let motionGroups: [CompanionMotionGroupOption]
}

struct CompanionExpressionOption: Identifiable, Hashable {
    let id: String
    let displayName: String
    let triggerHints: [String]
}

struct CompanionMotionGroupOption: Identifiable, Hashable {
    let id: String
    let displayName: String
    let groupName: String
    let motionCount: Int
}

struct CompanionModelPreset: Hashable, Decodable {
    var passiveIdle: Bool = false
    var emotionExpressions: [String: [String]] = [:]
    var extraEmotionButtons: [CompanionQuickExpressionButton] = []

    static let `default` = CompanionModelPreset()
}

struct CompanionQuickExpressionButton: Hashable, Decodable, Identifiable {
    let id: String
    let label: String
    let hints: [String]
}

enum ModelCatalog {
    private struct Model3JSON: Decodable {
        struct FileReferences: Decodable {
            struct MotionEntry: Decodable {
                let file: String?

                enum CodingKeys: String, CodingKey {
                    case file = "File"
                }
            }

            struct Expression: Decodable {
                let name: String?
                let file: String?

                enum CodingKeys: String, CodingKey {
                    case name = "Name"
                    case file = "File"
                }
            }

            let expressions: [Expression]?
            let motions: [String: [MotionEntry]]?

            enum CodingKeys: String, CodingKey {
                case expressions = "Expressions"
                case motions = "Motions"
            }
        }

        let fileReferences: FileReferences?

        enum CodingKeys: String, CodingKey {
            case fileReferences = "FileReferences"
        }
    }

    private static func loadPreset(for assetRoot: URL) -> CompanionModelPreset {
        let candidates = [
            assetRoot.appendingPathComponent("companion-preset.json"),
            assetRoot.deletingLastPathComponent().appendingPathComponent("companion-preset.json"),
        ]

        let decoder = JSONDecoder()
        for candidate in candidates {
            guard let data = try? Data(contentsOf: candidate),
                  let preset = try? decoder.decode(CompanionModelPreset.self, from: data) else {
                continue
            }
            return preset
        }

        return .default
    }

    private static func discoverExpressions(assetRoot: URL, modelFileURL: URL) -> [CompanionExpressionOption] {
        var expressionsByID: [String: CompanionExpressionOption] = [:]
        let decoder = JSONDecoder()

        if let data = try? Data(contentsOf: modelFileURL),
           let model = try? decoder.decode(Model3JSON.self, from: data),
           let listedExpressions = model.fileReferences?.expressions {
            for expression in listedExpressions {
                guard let file = expression.file, !file.isEmpty else { continue }
                let fileName = URL(fileURLWithPath: file).lastPathComponent
                let stem = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
                let displayName = (expression.name?.isEmpty == false ? expression.name! : stem)
                let rawHints: [String?] = [fileName, stem, expression.name]
                let hints = Array(Set<String>(rawHints.compactMap { value in
                    guard let value, !value.isEmpty else { return nil }
                    return value
                }))

                expressionsByID[fileName] = CompanionExpressionOption(
                    id: fileName,
                    displayName: displayName,
                    triggerHints: hints
                )
            }
        }

        let fileManager = FileManager.default
        if let enumerator = fileManager.enumerator(
            at: assetRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "json", fileURL.lastPathComponent.hasSuffix(".exp3.json") else {
                    continue
                }

                let fileName = fileURL.lastPathComponent
                let stem = fileURL.deletingPathExtension().deletingPathExtension().lastPathComponent
                let existing = expressionsByID[fileName]
                let hints = Array(Set((existing?.triggerHints ?? []) + [fileName, stem]))
                expressionsByID[fileName] = CompanionExpressionOption(
                    id: fileName,
                    displayName: existing?.displayName ?? stem,
                    triggerHints: hints
                )
            }
        }

        return expressionsByID.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private static func discoverMotionGroups(modelFileURL: URL) -> [CompanionMotionGroupOption] {
        let decoder = JSONDecoder()
        guard let data = try? Data(contentsOf: modelFileURL),
              let model = try? decoder.decode(Model3JSON.self, from: data),
              let motions = model.fileReferences?.motions else {
            return []
        }

        return motions.compactMap { groupName, entries in
            guard !entries.isEmpty else { return nil }
            return CompanionMotionGroupOption(
                id: groupName,
                displayName: groupName,
                groupName: groupName,
                motionCount: entries.count
            )
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    static func discoverModels(in assetsRoot: URL) -> [CompanionModelOption] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: assetsRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var models: [CompanionModelOption] = []

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "json", fileURL.lastPathComponent.hasSuffix(".model3.json") else {
                continue
            }

            let assetRoot = fileURL.deletingLastPathComponent()
            let displayBase: String
            if assetRoot.lastPathComponent == "runtime" {
                displayBase = assetRoot.deletingLastPathComponent().lastPathComponent
            } else {
                displayBase = assetRoot.lastPathComponent
            }

            let displayName = displayBase
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .capitalized

            models.append(
                CompanionModelOption(
                    id: assetRoot.path,
                    displayName: displayName,
                    assetRootPath: assetRoot.path,
                    preset: loadPreset(for: assetRoot),
                    expressions: discoverExpressions(assetRoot: assetRoot, modelFileURL: fileURL),
                    motionGroups: discoverMotionGroups(modelFileURL: fileURL)
                )
            )
        }

        return models.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
}

struct AvatarLayout {
    let viewportSize: CGSize
    let panelSize: CGSize
}

enum CompanionPresenceState: Int {
    case idle = 0
    case listening = 1
    case speaking = 2
    case thinking = 3
}

enum CompanionEmotionState: Int {
    case neutral = 0
    case happy = 1
    case excited = 2
    case shy = 3
    case thinking = 4
    case sleepy = 5
    case angry = 6
}

struct OllamaChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let stream: Bool
}

struct OllamaChatResponse: Decodable {
    struct Message: Decodable {
        let role: String
        let content: String
    }

    let message: Message
}
