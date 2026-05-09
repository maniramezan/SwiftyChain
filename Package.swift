// swift-tools-version: 6.3

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "SwiftyChain",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "SwiftyChain", targets: ["SwiftyChain"])
    ],
    traits: [
        .default(enabledTraits: []),
        "macros",
        "cryptography",
        "observation",
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "603.0.1"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", exact: "1.5.0"),
    ],
    targets: [
        .target(
            name: "SwiftyChain",
            dependencies: [
                .target(name: "SwiftyChainMacros", condition: .when(traits: ["macros"]))
            ]
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
            dependencies: ["SwiftyChain"]
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
