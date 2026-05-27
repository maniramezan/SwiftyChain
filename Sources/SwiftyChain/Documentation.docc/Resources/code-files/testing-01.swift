// Package.swift — add SwiftyChainTesting to your test target only
.testTarget(
    name: "MyFeatureTests",
    dependencies: [
        .product(name: "SwiftyChain", package: "SwiftyChain"),
        .product(name: "SwiftyChainTesting", package: "SwiftyChain"),
    ]
)
