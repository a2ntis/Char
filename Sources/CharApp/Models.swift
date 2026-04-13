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

enum CompanionTTSProvider: String, CaseIterable, Codable, Hashable, Identifiable {
    case system
    case piper
    case xtts
    case openAI

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            return "Системный голос"
        case .piper:
            return "Piper (локально)"
        case .xtts:
            return "XTTS v2 (локально)"
        case .openAI:
            return "OpenAI TTS"
        }
    }
}

enum OpenAITTSCatalog {
    static let supportedModels: [String] = [
        "gpt-4o-mini-tts",
        "tts-1-hd",
        "tts-1",
    ]

    static let allVoices: [String] = [
        "alloy",
        "ash",
        "ballad",
        "cedar",
        "coral",
        "echo",
        "fable",
        "marin",
        "nova",
        "onyx",
        "sage",
        "shimmer",
        "verse",
    ]

    static let legacyVoices: Set<String> = [
        "alloy",
        "ash",
        "coral",
        "echo",
        "fable",
        "nova",
        "onyx",
        "sage",
        "shimmer",
    ]

    static func voices(for model: String) -> [String] {
        if model == "tts-1" || model == "tts-1-hd" {
            return allVoices.filter { legacyVoices.contains($0) }
        }
        return allVoices
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
    var ttsProvider: CompanionTTSProvider = .system
    var piperExecutablePath: String = "piper"
    var piperVoicesDirectory: String = ""
    var piperModelPath: String = ""
    var xttsPythonPath: String = ""
    var xttsReferencesDirectory: String = ""
    var xttsReferencePath: String = ""
    var openAITTSModel: String = "gpt-4o-mini-tts"
    var openAITTSVoice: String = "coral"
    var openAITTSSpeed: Double = 0.96
    var openAITTSInstructions: String = "Speak in a soft, friendly, conversational tone with a light feminine feel. Keep the delivery warm and natural, not robotic."
    var openAITTSEndpoint: URL = URL(string: "https://api.openai.com/v1/audio/speech")!
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

    enum CodingKeys: String, CodingKey {
        case name
        case persona
        case responseLanguage
        case ttsProvider
        case piperExecutablePath
        case piperVoicesDirectory
        case piperModelPath
        case xttsPythonPath
        case xttsReferencesDirectory
        case xttsReferencePath
        case openAITTSModel
        case openAITTSVoice
        case openAITTSSpeed
        case openAITTSInstructions
        case openAITTSEndpoint
        case provider
        case ollamaModel
        case ollamaEndpoint
        case openAIModel
        case openAIEndpoint
        case lmStudioModel
        case lmStudioEndpoint
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Hana"
        persona = try container.decodeIfPresent(String.self, forKey: .persona) ?? """
        You are Hana, a warm anime-style desktop companion living on the user's Mac.
        Keep answers concise, emotionally expressive, playful, and supportive.
        You are not a generic assistant; you are a charming companion who can chat naturally,
        react to the user's mood, and keep the conversation light unless the user asks for detail.
        """
        responseLanguage = try container.decodeIfPresent(CompanionResponseLanguage.self, forKey: .responseLanguage) ?? .russian
        ttsProvider = try container.decodeIfPresent(CompanionTTSProvider.self, forKey: .ttsProvider) ?? .system
        piperExecutablePath = try container.decodeIfPresent(String.self, forKey: .piperExecutablePath) ?? "piper"
        piperVoicesDirectory = try container.decodeIfPresent(String.self, forKey: .piperVoicesDirectory) ?? ""
        piperModelPath = try container.decodeIfPresent(String.self, forKey: .piperModelPath) ?? ""
        xttsPythonPath = try container.decodeIfPresent(String.self, forKey: .xttsPythonPath) ?? ""
        xttsReferencesDirectory = try container.decodeIfPresent(String.self, forKey: .xttsReferencesDirectory) ?? ""
        xttsReferencePath = try container.decodeIfPresent(String.self, forKey: .xttsReferencePath) ?? ""
        openAITTSModel = try container.decodeIfPresent(String.self, forKey: .openAITTSModel) ?? "gpt-4o-mini-tts"
        openAITTSVoice = try container.decodeIfPresent(String.self, forKey: .openAITTSVoice) ?? "coral"
        openAITTSSpeed = try container.decodeIfPresent(Double.self, forKey: .openAITTSSpeed) ?? 0.96
        openAITTSInstructions = try container.decodeIfPresent(String.self, forKey: .openAITTSInstructions) ?? "Speak in a soft, friendly, conversational tone with a light feminine feel. Keep the delivery warm and natural, not robotic."
        openAITTSEndpoint = try container.decodeIfPresent(URL.self, forKey: .openAITTSEndpoint) ?? URL(string: "https://api.openai.com/v1/audio/speech")!
        provider = try container.decodeIfPresent(CompanionLLMProvider.self, forKey: .provider) ?? .ollama
        ollamaModel = try container.decodeIfPresent(String.self, forKey: .ollamaModel) ?? "qwen3:14b"
        ollamaEndpoint = try container.decodeIfPresent(URL.self, forKey: .ollamaEndpoint) ?? URL(string: "http://127.0.0.1:11434/api/chat")!
        openAIModel = try container.decodeIfPresent(String.self, forKey: .openAIModel) ?? ""
        openAIEndpoint = try container.decodeIfPresent(URL.self, forKey: .openAIEndpoint) ?? URL(string: "https://api.openai.com/v1/chat/completions")!
        lmStudioModel = try container.decodeIfPresent(String.self, forKey: .lmStudioModel) ?? ""
        lmStudioEndpoint = try container.decodeIfPresent(URL.self, forKey: .lmStudioEndpoint) ?? URL(string: "http://127.0.0.1:1234/v1/chat/completions")!
    }
}

struct PiperVoiceOption: Identifiable, Hashable {
    let id: String
    let displayName: String
    let modelPath: String
}

struct XTTSReferenceOption: Identifiable, Hashable {
    let id: String
    let displayName: String
    let filePath: String
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
