import Foundation

struct PiperResolvedPaths {
    let executablePath: String?
    let voicesDirectory: String?
    let modelPath: String?
}

enum PiperSupport {
    static let bundledVoiceRelativePath = "Assets/TTS/Piper/ru_RU-irina-medium/ru_RU-irina-medium.onnx"
    static let bundledConfigRelativePath = "Assets/TTS/Piper/ru_RU-irina-medium/ru_RU-irina-medium.onnx.json"

    static func projectRootCandidates() -> [URL] {
        var candidates: [URL] = []
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        candidates.append(cwd)

        let bundleURL = Bundle.main.bundleURL
        candidates.append(bundleURL.deletingLastPathComponent().deletingLastPathComponent())
        candidates.append(bundleURL.deletingLastPathComponent())

        var unique: [URL] = []
        var seen = Set<String>()
        for candidate in candidates {
            let normalized = candidate.standardizedFileURL.path
            if seen.insert(normalized).inserted {
                unique.append(candidate.standardizedFileURL)
            }
        }
        return unique
    }

    static func resolvePaths(configuredExecutable: String, configuredModel: String) -> PiperResolvedPaths {
        let voicesDirectory = resolveVoicesDirectory()
        let executable = resolveExecutablePath(configuredExecutable)
        let model = resolveModelPath(configuredModel, voicesDirectory: voicesDirectory)
        return PiperResolvedPaths(executablePath: executable, voicesDirectory: voicesDirectory, modelPath: model)
    }

    static func resolveExecutablePath(_ configuredPath: String) -> String? {
        let trimmed = configuredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != "piper" {
            let expanded = NSString(string: trimmed).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: expanded) {
                return expanded
            }
        }

        for root in projectRootCandidates() {
            let candidate = root.appendingPathComponent(".venv-piper/bin/piper").path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    static func resolveVoicesDirectory() -> String? {
        let bundledCandidate = AppEnvironment.assetsRootURL
            .appendingPathComponent("TTS/Piper")
            .path
        if FileManager.default.fileExists(atPath: bundledCandidate) {
            return bundledCandidate
        }

        for root in projectRootCandidates() {
            let candidate = root.appendingPathComponent("Assets/TTS/Piper").path
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    static func resolveModelPath(_ configuredPath: String, voicesDirectory: String? = nil) -> String? {
        let trimmed = configuredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let expanded = NSString(string: trimmed).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expanded) {
                return expanded
            }
        }

        let searchRoots = [voicesDirectory].compactMap { $0 }
        for rootPath in searchRoots {
            let discovered = discoverVoices(in: rootPath)
            if let preferred = discovered.first(where: { $0.modelPath.contains("ru_RU-irina-medium") }) ?? discovered.first {
                return preferred.modelPath
            }
        }

        return nil
    }

    static func discoverVoices(in directoryPath: String) -> [PiperVoiceOption] {
        let expanded = NSString(string: directoryPath).expandingTildeInPath
        let rootURL = URL(fileURLWithPath: expanded, isDirectory: true)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: rootURL.path) else { return [] }

        var voices: [PiperVoiceOption] = []
        if let enumerator = fileManager.enumerator(at: rootURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator {
                guard url.pathExtension == "onnx" else { continue }
                let displayName = url.deletingPathExtension().lastPathComponent
                    .replacingOccurrences(of: "_", with: " ")
                voices.append(
                    PiperVoiceOption(
                        id: url.path,
                        displayName: displayName,
                        modelPath: url.path
                    )
                )
            }
        }

        return voices.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    static func installLocalPiper() throws -> PiperResolvedPaths {
        guard let projectRoot = projectRootCandidates().first else {
            throw PiperError.projectRootNotFound
        }

        let venvPython = projectRoot.appendingPathComponent(".venv-piper/bin/python").path
        let venvPiper = projectRoot.appendingPathComponent(".venv-piper/bin/piper").path
        let voiceDir = projectRoot.appendingPathComponent("Assets/TTS/Piper/ru_RU-irina-medium", isDirectory: true)
        let voiceModel = voiceDir.appendingPathComponent("ru_RU-irina-medium.onnx").path
        let voiceConfig = voiceDir.appendingPathComponent("ru_RU-irina-medium.onnx.json").path

        try FileManager.default.createDirectory(at: voiceDir, withIntermediateDirectories: true)

        try run("/usr/bin/env", ["python3", "-m", "venv", projectRoot.appendingPathComponent(".venv-piper").path], cwd: projectRoot.path)
        try run("/usr/bin/env", [venvPython, "-m", "pip", "install", "--upgrade", "pip"], cwd: projectRoot.path)
        try run("/usr/bin/env", ["brew", "install", "espeak-ng"], cwd: projectRoot.path)
        try run("/usr/bin/env", [venvPython, "-m", "pip", "install", "piper-tts"], cwd: projectRoot.path)
        try run("/usr/bin/env", ["curl", "-L", "https://huggingface.co/rhasspy/piper-voices/resolve/main/ru/ru_RU/irina/medium/ru_RU-irina-medium.onnx", "-o", voiceModel], cwd: projectRoot.path)
        try run("/usr/bin/env", ["curl", "-L", "https://huggingface.co/rhasspy/piper-voices/resolve/main/ru/ru_RU/irina/medium/ru_RU-irina-medium.onnx.json", "-o", voiceConfig], cwd: projectRoot.path)

        return PiperResolvedPaths(
            executablePath: FileManager.default.isExecutableFile(atPath: venvPiper) ? venvPiper : nil,
            voicesDirectory: projectRoot.appendingPathComponent("Assets/TTS/Piper").path,
            modelPath: FileManager.default.fileExists(atPath: voiceModel) ? voiceModel : nil
        )
    }

    @discardableResult
    private static func run(_ launchPath: String, _ arguments: [String], cwd: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: cwd, isDirectory: true)

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let message = error.trimmingCharacters(in: .whitespacesAndNewlines)
            throw PiperError.commandFailed(message.isEmpty ? output : message)
        }

        return output
    }
}

enum PiperError: LocalizedError {
    case projectRootNotFound
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .projectRootNotFound:
            return "Не удалось определить корень проекта для установки Piper."
        case let .commandFailed(message):
            return message.isEmpty ? "Установка Piper завершилась с ошибкой." : message
        }
    }
}
