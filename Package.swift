// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftCardanoTxValidator",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "SwiftCardanoTxValidator",
            targets: ["SwiftCardanoTxValidator"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/Kingpin-Apps/swift-cardano-core.git", from: "0.4.6"),
        .package(url: "https://github.com/Kingpin-Apps/swift-cardano-chain.git", from: "0.6.0"),
        .package(url: "https://github.com/Kingpin-Apps/swift-cardano-uplc.git", from: "0.3.2"),
        .package(url: "https://github.com/Kingpin-Apps/swift-nacl.git", .upToNextMinor(from: "1.0.2")),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.12.0"),
    ],
    targets: [
        .target(
            name: "SwiftCardanoTxValidator",
            dependencies: [
                .product(name: "SwiftCardanoCore", package: "swift-cardano-core"),
                .product(name: "SwiftCardanoChain", package: "swift-cardano-chain"),
                .product(name: "SwiftCardanoUPLC", package: "swift-cardano-uplc"),
                .product(name: "SwiftNaCl", package: "swift-nacl"),
                .product(name: "Logging", package: "swift-log"),
            ]
            // No resources: the target ships no real assets. (A stray `Resources/cz.json` — the
            // Commitizen config, duplicated from the repo root — was previously `.copy`'d, which
            // produced a nested-`Resources/` bundle that iOS codesign rejects as "unsuitable".)
        ),
        .testTarget(
            name: "SwiftCardanoTxValidatorTests",
            dependencies: [
                "SwiftCardanoTxValidator",
                .product(name: "SwiftCardanoCore", package: "swift-cardano-core"),
                .product(name: "SwiftCardanoChain", package: "swift-cardano-chain"),
                .product(name: "SwiftCardanoUPLC", package: "swift-cardano-uplc"),
            ],
            resources: [.copy("Resources")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
