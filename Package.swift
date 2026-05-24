// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "lofii",
    platforms: [
        .macOS(.v26),
    ],
    products: [],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.4"),
    ],
    targets: [
        .target(
            name: "CubismFrameworkSource",
            path: "Vendor/CubismNativeSDK/Framework/src",
            exclude: [
                "Rendering/D3D9",
                "Rendering/D3D11",
                "Rendering/OpenGL",
                "Rendering/Vulkan",
            ],
            publicHeadersPath: ".",
            cxxSettings: [
                .headerSearchPath("../../Core/include"),
                .unsafeFlags(["-fno-objc-arc", "-Wno-dynamic-class-memaccess"]),
            ]
        ),
        .target(
            name: "CubismNativeBridge",
            dependencies: ["CubismFrameworkSource"],
            path: "Sources/CubismNativeBridge",
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("../../Vendor/CubismNativeSDK/Core/include"),
                .headerSearchPath("../../Vendor/CubismNativeSDK/Framework/src"),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-LVendor/CubismNativeSDK/Core/dll/macos",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@loader_path/../../../Vendor/CubismNativeSDK/Core/dll/macos",
                ], .when(platforms: [.macOS])),
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
                .linkedFramework("Metal", .when(platforms: [.macOS])),
                .linkedFramework("MetalKit", .when(platforms: [.macOS])),
                .linkedFramework("QuartzCore", .when(platforms: [.macOS])),
                .linkedLibrary("Live2DCubismCore", .when(platforms: [.macOS])),
            ]
        ),
        .executableTarget(
            name: "lofii",
            dependencies: [
                "CubismNativeBridge",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Lofii",
            exclude: [
                // Linked via linkerSettings (__TEXT,__info_plist); not a Swift resource.
                "Info.plist",
            ],
            resources: [
                // Bundled "TV snow" frames used as the channel-change
                // overlay between scenes/variants. Shipped in-binary so the
                // transition is always available even before the network
                // cache has anything in it. ~7 MB total — kept in-app on
                // purpose so the retro effect is never gated on connectivity.
                .copy("Resources/Statics"),
                // Pixel/grid text fonts (Doto primary, BoutiqueBitmap CJK
                // fallback) plus pixel icon font used throughout the widget.
                .copy("Resources/Fonts"),
                // Bongo mode: bundled Live2D assets (native Metal renderer).
                .copy("Resources/BongoCat"),
                // Overlay and mask textures for the shattered-glass post effect.
                .copy("Resources/ShatteredGlass"),
                // Cubism native Metal backend runtime-compiles its fallback
                // shader library from this bundled source text when a
                // prebuilt metallib is unavailable on the local machine.
                .copy("Resources/FrameworkMetallibs"),
                .copy("Resources/AppIcon.icns"),
                // Single-stage Metal player used for video/GIF background
                // rendering and native post-processing.
                .process("StageMetalShaders.metal"),
            ],
            linkerSettings: [
                // Embed Info.plist for Sparkle (SUFeedURL, SUPublicEDKey, CFBundleShortVersionString).
                .unsafeFlags([
                    "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/Lofii/Info.plist",
                ], .when(platforms: [.macOS])),
            ]
        ),
        .testTarget(
            name: "LofiiTests",
            dependencies: ["lofii"],
            path: "Tests/LofiiTests",
            linkerSettings: [
                // xctest lives deeper than the Lofii binary; add rpath so @rpath/libLive2DCubismCore.dylib resolves.
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@loader_path/../../../../../../Vendor/CubismNativeSDK/Core/dll/macos",
                ], .when(platforms: [.macOS])),
            ]
        ),
    ],
    swiftLanguageModes: [.v6],
    cxxLanguageStandard: .cxx17
)
