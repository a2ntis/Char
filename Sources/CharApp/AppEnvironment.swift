import Foundation

enum AppEnvironment {
    /// Project root derived at compile time from this source file's path.
    /// Sources/CharApp/AppEnvironment.swift → go up 3 levels → project root.
    private static let compileTimeProjectRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static var resourceRootURL: URL {
        let fm = FileManager.default

        if let bundleResourceURL = Bundle.main.resourceURL {
            let bundledAssets = bundleResourceURL.appendingPathComponent("Assets", isDirectory: true)
            if fm.fileExists(atPath: bundledAssets.path) {
                return bundleResourceURL
            }
        }

        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
        if fm.fileExists(atPath: cwd.appendingPathComponent("Assets").path) {
            return cwd
        }

        if fm.fileExists(atPath: compileTimeProjectRoot.appendingPathComponent("Assets").path) {
            return compileTimeProjectRoot
        }

        return cwd
    }

    static var assetsRootURL: URL {
        resourceRootURL.appendingPathComponent("Assets", isDirectory: true)
    }

    static var shadersRootURL: URL {
        let fm = FileManager.default
        let bundled = resourceRootURL.appendingPathComponent("FrameworkShaders", isDirectory: true)
        if fm.fileExists(atPath: bundled.path) {
            return bundled
        }
        let fromSource = compileTimeProjectRoot
            .appendingPathComponent("ThirdParty/CubismSdkForNative-5-r.5/Framework/src/Rendering/OpenGL/Shaders/Standard", isDirectory: true)
        if fm.fileExists(atPath: fromSource.path) {
            return fromSource
        }
        return bundled
    }
}
