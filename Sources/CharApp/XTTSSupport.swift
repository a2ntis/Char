import Foundation

struct XTTSResolvedPaths {
    let pythonPath: String?
    let referencesDirectory: String?
    let referencePath: String?
}

enum XTTSSupport {
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

    static func resolvePaths(configuredPython: String, configuredReference: String) -> XTTSResolvedPaths {
        XTTSResolvedPaths(
            pythonPath: resolvePythonPath(configuredPython),
            referencesDirectory: resolveReferencesDirectory(),
            referencePath: resolveReferencePath(configuredReference)
        )
    }

    static func resolvePythonPath(_ configuredPath: String) -> String? {
        let trimmed = configuredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let expanded = NSString(string: trimmed).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: expanded) {
                return expanded
            }
        }

        for root in projectRootCandidates() {
            let candidate = root.appendingPathComponent(".venv-xtts/bin/python").path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    static func resolveReferencePath(_ configuredPath: String) -> String? {
        let trimmed = configuredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let expanded = NSString(string: trimmed).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expanded) {
                return expanded
            }
        }

        let bundledReference = AppEnvironment.assetsRootURL
            .appendingPathComponent("TTS/Reference/xtts_reference.wav")
            .path
        if FileManager.default.fileExists(atPath: bundledReference) {
            return bundledReference
        }

        for root in projectRootCandidates() {
            let candidate = root.appendingPathComponent("Assets/TTS/Reference/xtts_reference.wav").path
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    static func resolveReferencesDirectory() -> String? {
        let bundledDirectory = AppEnvironment.assetsRootURL
            .appendingPathComponent("TTS/Reference")
            .path
        if FileManager.default.fileExists(atPath: bundledDirectory) {
            return bundledDirectory
        }

        for root in projectRootCandidates() {
            let candidate = root.appendingPathComponent("Assets/TTS/Reference").path
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    static func discoverReferences(in directoryPath: String) -> [XTTSReferenceOption] {
        let expanded = NSString(string: directoryPath).expandingTildeInPath
        let directoryURL = URL(fileURLWithPath: expanded, isDirectory: true)
        let allowedExtensions = Set(["wav", "mp3", "m4a", "aac", "flac"])

        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var references: [XTTSReferenceOption] = []

        for case let fileURL as URL in enumerator {
            guard allowedExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }

            let stem = fileURL.deletingPathExtension().lastPathComponent
            let displayName = stem
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")

            references.append(
                XTTSReferenceOption(
                    id: fileURL.path,
                    displayName: displayName,
                    filePath: fileURL.path
                )
            )
        }

        return references.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }
}
