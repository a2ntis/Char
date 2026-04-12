import Foundation

enum AppEnvironment {
    static var resourceRootURL: URL {
        if let bundleResourceURL = Bundle.main.resourceURL {
            let bundledAssets = bundleResourceURL.appendingPathComponent("Assets", isDirectory: true)
            if FileManager.default.fileExists(atPath: bundledAssets.path) {
                return bundleResourceURL
            }
        }

        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }

    static var assetsRootURL: URL {
        resourceRootURL.appendingPathComponent("Assets", isDirectory: true)
    }

    static var shadersRootURL: URL {
        resourceRootURL.appendingPathComponent("FrameworkShaders", isDirectory: true)
    }
}
