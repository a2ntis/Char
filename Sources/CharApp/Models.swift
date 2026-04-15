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
    case gemini

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
        case .gemini:
            return "Gemini TTS"
        }
    }
}

struct GoogleTTSVoiceOption: Identifiable, Hashable {
    let id: String
    let displayName: String
    let name: String
    let languageCodes: [String]
}

enum GeminiTTSCatalog {
    static let supportedModels: [String] = [
        "gemini-2.5-flash-lite-preview-tts",
        "gemini-2.5-flash-preview-tts",
        "gemini-2.5-pro-preview-tts",
    ]

    static let voices: [GoogleTTSVoiceOption] = [
        .init(id: "Zephyr", displayName: "Zephyr — Bright", name: "Zephyr", languageCodes: ["auto"]),
        .init(id: "Puck", displayName: "Puck — Upbeat", name: "Puck", languageCodes: ["auto"]),
        .init(id: "Charon", displayName: "Charon — Informative", name: "Charon", languageCodes: ["auto"]),
        .init(id: "Kore", displayName: "Kore — Firm", name: "Kore", languageCodes: ["auto"]),
        .init(id: "Fenrir", displayName: "Fenrir — Excitable", name: "Fenrir", languageCodes: ["auto"]),
        .init(id: "Leda", displayName: "Leda — Youthful", name: "Leda", languageCodes: ["auto"]),
        .init(id: "Orus", displayName: "Orus — Firm", name: "Orus", languageCodes: ["auto"]),
        .init(id: "Aoede", displayName: "Aoede — Breezy", name: "Aoede", languageCodes: ["auto"]),
        .init(id: "Callirrhoe", displayName: "Callirrhoe — Easy-going", name: "Callirrhoe", languageCodes: ["auto"]),
        .init(id: "Autonoe", displayName: "Autonoe — Bright", name: "Autonoe", languageCodes: ["auto"]),
        .init(id: "Enceladus", displayName: "Enceladus — Breathy", name: "Enceladus", languageCodes: ["auto"]),
        .init(id: "Iapetus", displayName: "Iapetus — Clear", name: "Iapetus", languageCodes: ["auto"]),
        .init(id: "Umbriel", displayName: "Umbriel — Easy-going", name: "Umbriel", languageCodes: ["auto"]),
        .init(id: "Algieba", displayName: "Algieba — Smooth", name: "Algieba", languageCodes: ["auto"]),
        .init(id: "Despina", displayName: "Despina — Smooth", name: "Despina", languageCodes: ["auto"]),
        .init(id: "Erinome", displayName: "Erinome — Clear", name: "Erinome", languageCodes: ["auto"]),
        .init(id: "Algenib", displayName: "Algenib — Gravelly", name: "Algenib", languageCodes: ["auto"]),
        .init(id: "Rasalgethi", displayName: "Rasalgethi — Informative", name: "Rasalgethi", languageCodes: ["auto"]),
        .init(id: "Laomedeia", displayName: "Laomedeia — Upbeat", name: "Laomedeia", languageCodes: ["auto"]),
        .init(id: "Achernar", displayName: "Achernar — Soft", name: "Achernar", languageCodes: ["auto"]),
        .init(id: "Alnilam", displayName: "Alnilam — Firm", name: "Alnilam", languageCodes: ["auto"]),
        .init(id: "Schedar", displayName: "Schedar — Even", name: "Schedar", languageCodes: ["auto"]),
        .init(id: "Gacrux", displayName: "Gacrux — Mature", name: "Gacrux", languageCodes: ["auto"]),
        .init(id: "Pulcherrima", displayName: "Pulcherrima — Forward", name: "Pulcherrima", languageCodes: ["auto"]),
        .init(id: "Achird", displayName: "Achird — Friendly", name: "Achird", languageCodes: ["auto"]),
        .init(id: "Zubenelgenubi", displayName: "Zubenelgenubi — Casual", name: "Zubenelgenubi", languageCodes: ["auto"]),
        .init(id: "Vindemiatrix", displayName: "Vindemiatrix — Gentle", name: "Vindemiatrix", languageCodes: ["auto"]),
        .init(id: "Sadachbia", displayName: "Sadachbia — Lively", name: "Sadachbia", languageCodes: ["auto"]),
        .init(id: "Sadaltager", displayName: "Sadaltager — Knowledgeable", name: "Sadaltager", languageCodes: ["auto"]),
        .init(id: "Sulafat", displayName: "Sulafat — Warm", name: "Sulafat", languageCodes: ["auto"]),
    ]
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
    var googleTTSEndpoint: URL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!
    var googleTTSModel: String = "gemini-2.5-flash-lite-preview-tts"
    var googleTTSLanguageCode: String = "ru-RU"
    var googleTTSVoiceName: String = "Leda"
    var googleTTSSpeakingRate: Double = 0.96
    var googleTTSPitch: Double = 2.0
    var googleTTSStyleInstructions: String = "Speak in a soft, light, feminine, warm, conversational tone. Sound gentle, youthful, and natural. Avoid a robotic or announcer-like delivery."
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
        case googleTTSEndpoint
        case googleTTSModel
        case googleTTSLanguageCode
        case googleTTSVoiceName
        case googleTTSSpeakingRate
        case googleTTSPitch
        case googleTTSStyleInstructions
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
        googleTTSEndpoint = try container.decodeIfPresent(URL.self, forKey: .googleTTSEndpoint) ?? URL(string: "https://generativelanguage.googleapis.com/v1beta")!
        googleTTSModel = try container.decodeIfPresent(String.self, forKey: .googleTTSModel) ?? "gemini-2.5-flash-lite-preview-tts"
        googleTTSLanguageCode = try container.decodeIfPresent(String.self, forKey: .googleTTSLanguageCode) ?? "ru-RU"
        googleTTSVoiceName = try container.decodeIfPresent(String.self, forKey: .googleTTSVoiceName) ?? "Leda"
        googleTTSSpeakingRate = try container.decodeIfPresent(Double.self, forKey: .googleTTSSpeakingRate) ?? 0.96
        googleTTSPitch = try container.decodeIfPresent(Double.self, forKey: .googleTTSPitch) ?? 2.0
        googleTTSStyleInstructions = try container.decodeIfPresent(String.self, forKey: .googleTTSStyleInstructions) ?? "Speak in a soft, light, feminine, warm, conversational tone. Sound gentle, youthful, and natural. Avoid a robotic or announcer-like delivery."
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

enum CompanionAvatarRuntime: String, Hashable, Codable {
    case live2d
    case vrm
    case vroidProject

    var displayName: String {
        switch self {
        case .live2d:
            return "Live2D"
        case .vrm:
            return "VRM"
        case .vroidProject:
            return "VRoid"
        }
    }

    var supportsRendering: Bool {
        switch self {
        case .live2d, .vrm:
            return true
        case .vroidProject:
            return false
        }
    }
}

struct CompanionModelOption: Identifiable, Hashable {
    let id: String
    let displayName: String
    let runtime: CompanionAvatarRuntime
    let assetRootPath: String
    let entryPath: String
    let technicalFormat: String?
    let preset: CompanionModelPreset
    let expressions: [CompanionExpressionOption]
    let motionGroups: [CompanionMotionGroupOption]

    var isVRM0x: Bool {
        guard runtime == .vrm, let fmt = technicalFormat else { return false }
        return fmt.contains("0.x") || fmt == "VRM"
    }
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
    private static func detectVRMFormat(at fileURL: URL) -> String? {
        guard let data = try? Data(contentsOf: fileURL), data.count > 24 else {
            return nil
        }

        func littleEndianUInt32(at offset: Int) -> UInt32? {
            guard data.count >= offset + 4 else { return nil }
            return data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { rawBuffer in
                rawBuffer.load(as: UInt32.self).littleEndian
            }
        }

        guard let jsonLength = littleEndianUInt32(at: 12),
              let chunkTypeData = "JSON".data(using: .utf8),
              data.subdata(in: 16..<20) == chunkTypeData else {
            return nil
        }

        let jsonStart = 20
        let jsonEnd = jsonStart + Int(jsonLength)
        guard jsonEnd <= data.count else {
            return nil
        }

        guard let object = try? JSONSerialization.jsonObject(with: data.subdata(in: jsonStart..<jsonEnd)) as? [String: Any] else {
            return nil
        }

        if let extensions = object["extensions"] as? [String: Any],
           let vrmcVRM = extensions["VRMC_vrm"] as? [String: Any],
           let specVersion = vrmcVRM["specVersion"] as? String {
            return "VRM \(specVersion)"
        }

        if let extensions = object["extensions"] as? [String: Any],
           extensions["VRM"] != nil {
            return "VRM 0.x"
        }

        return "VRM"
    }

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
        var vrmBaseNames: Set<String> = []

        if let vrmEnumerator = fileManager.enumerator(
            at: assetsRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in vrmEnumerator {
                guard fileURL.pathExtension.lowercased() == "vrm" else { continue }
                vrmBaseNames.insert(fileURL.deletingPathExtension().lastPathComponent.lowercased())
            }
        }

        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "json", fileURL.lastPathComponent.hasSuffix(".model3.json") {
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
                        runtime: .live2d,
                        assetRootPath: assetRoot.path,
                        entryPath: fileURL.path,
                        technicalFormat: "Live2D Cubism",
                        preset: loadPreset(for: assetRoot),
                        expressions: discoverExpressions(assetRoot: assetRoot, modelFileURL: fileURL),
                        motionGroups: discoverMotionGroups(modelFileURL: fileURL)
                    )
                )
                continue
            }

            let lowercasedPathExtension = fileURL.pathExtension.lowercased()
            guard lowercasedPathExtension == "vrm" || lowercasedPathExtension == "vroid" else {
                continue
            }

            let baseName = fileURL.deletingPathExtension().lastPathComponent
            if lowercasedPathExtension == "vroid", vrmBaseNames.contains(baseName.lowercased()) {
                continue
            }

            let assetRoot = fileURL.deletingLastPathComponent()
            let runtime = lowercasedPathExtension == "vrm" ? CompanionAvatarRuntime.vrm : CompanionAvatarRuntime.vroidProject
            let technicalFormat = runtime == .vrm ? detectVRMFormat(at: fileURL) : "VRoid Project"
            let displayName = fileURL.deletingPathExtension().lastPathComponent
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .capitalized + " (\(technicalFormat ?? runtime.displayName))"

            models.append(
                CompanionModelOption(
                    id: fileURL.path,
                    displayName: displayName,
                    runtime: runtime,
                    assetRootPath: assetRoot.path,
                    entryPath: fileURL.path,
                    technicalFormat: technicalFormat,
                    preset: loadPreset(for: assetRoot),
                    expressions: [],
                    motionGroups: []
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

enum CompanionVRMExpressionPreset: String, CaseIterable, Identifiable, Hashable {
    case neutral
    case smiling
    case sad
    case angry
    case happy
    case surprised

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .neutral:
            return "Neutral"
        case .smiling:
            return "Smiling"
        case .sad:
            return "Sad"
        case .angry:
            return "Angry"
        case .happy:
            return "Happy"
        case .surprised:
            return "Surprised"
        }
    }
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
