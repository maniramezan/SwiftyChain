// swift-tools-version: 6.3

import CompilerPluginSupport
import PackageDescription

let traitDefines: [SwiftSetting] = [
    .define("Cryptography", .when(traits: ["cryptography"])),
    .define("Observation", .when(traits: ["observation"])),
]

let applePlatforms: [Platform] = [.macOS, .macCatalyst, .iOS, .tvOS, .watchOS, .visionOS]

let package = Package(
    name: "SwiftyChain",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .tvOS(.v18),
        .watchOS(.v11),
        .visionOS(.v2),
    ],
    products: [
        .library(name: "SwiftyChain", targets: ["SwiftyChain"]),
        .library(name: "SwiftyChainTesting", targets: ["SwiftyChainTesting"]),
    ],
    traits: [
        .default(enabledTraits: []),
        "cryptography",
        "observation",
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "603.0.1"..<"605.0.0"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "SwiftyChainCore",
            swiftSettings: traitDefines
        ),
        .target(
            name: "SwiftyChainAppleKeychain",
            dependencies: ["SwiftyChainCore"],
            swiftSettings: traitDefines
        ),
        .target(
            name: "SwiftyChain",
            dependencies: [
                "SwiftyChainCore",
                .target(name: "SwiftyChainAppleKeychain", condition: .when(platforms: applePlatforms)),
                .target(name: "SwiftyChainMacros"),
            ],
            exclude: ["Documentation.docc"],
            swiftSettings: traitDefines
        ),
        .target(
            name: "SwiftyChainTesting",
            dependencies: ["SwiftyChain"],
            exclude: ["Documentation.docc"],
            swiftSettings: traitDefines
        ),
        .macro(
            name: "SwiftyChainMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .testTarget(
            name: "SwiftyChainTests",
            dependencies: [
                "SwiftyChain",
                "SwiftyChainTesting",
                .target(name: "SwiftyChainAppleKeychain", condition: .when(platforms: applePlatforms)),
            ],
            swiftSettings: traitDefines
        ),
        .testTarget(
            name: "SwiftyChainContractTests",
            dependencies: [
                "SwiftyChain",
                "SwiftyChainTesting",
                .target(name: "SwiftyChainAppleKeychain", condition: .when(platforms: applePlatforms)),
            ],
            swiftSettings: traitDefines
        ),
        .testTarget(
            name: "SwiftyChainTestingTests",
            dependencies: ["SwiftyChain", "SwiftyChainTesting"],
            swiftSettings: traitDefines
        ),
        .testTarget(
            name: "SwiftyChainMacrosTests",
            dependencies: [
                "SwiftyChainMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
    ]
)
