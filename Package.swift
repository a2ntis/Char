// swift-tools-version: 6.2
import Foundation
import PackageDescription

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let cubismCoreLib = "\(packageRoot)/ThirdParty/CubismSdkForNative-5-r.5/Core/lib/macos/arm64/libLive2DCubismCore.a"

let package = Package(
    name: "Char",
    defaultLocalization: nil,
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Char", targets: ["CharApp"])
    ],
    dependencies: [
        .package(name: "VRMKit", path: "ThirdParty/VRMKit")
    ],
    targets: [
        .target(
            name: "Live2DBridge",
            path: "Sources/Live2DBridge",
            exclude: [
                ".DS_Store",
                "vendor/.DS_Store",
                "vendor/Framework/CMakeLists.txt",
                "vendor/Framework/Rendering/D3D11",
                "vendor/Framework/Rendering/D3D9",
                "vendor/Framework/Rendering/Vulkan",
                "vendor/Framework/Rendering/Metal",
                "vendor/Common/MouseActionManager_Common.cpp",
                "vendor/Common/MouseActionManager_Common.hpp",
                "vendor/Common/TouchManager_Common.cpp",
                "vendor/Common/TouchManager_Common.hpp"
            ],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("vendor/Framework"),
                .headerSearchPath("vendor/Common"),
                .headerSearchPath("vendor/Sample"),
                .headerSearchPath("../../ThirdParty/CubismSdkForNative-5-r.5/Core/include"),
                .headerSearchPath("../../ThirdParty/CubismSdkForNative-5-r.5/Samples/OpenGL/thirdParty/stb")
            ],
            cxxSettings: [
                .unsafeFlags([
                    "-std=c++14",
                    "-DCSM_TARGET_MAC_GL",
                    "-I/opt/homebrew/opt/glew/include",
                    "-I/opt/homebrew/opt/glfw/include"
                ])
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("OpenGL"),
                .linkedLibrary("GLEW"),
                .linkedLibrary("glfw"),
                .unsafeFlags([
                    "-L/opt/homebrew/opt/glew/lib",
                    "-L/opt/homebrew/opt/glfw/lib",
                    cubismCoreLib
                ])
            ]
        ),
        .executableTarget(
            name: "CharApp",
            dependencies: [
                "Live2DBridge",
                .product(name: "VRMRealityKit", package: "VRMKit")
            ],
            path: "Sources/CharApp"
        )
    ]
)
