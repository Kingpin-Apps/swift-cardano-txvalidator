// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-cardano-txvalidator",
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
        .package(url: "https://github.com/Kingpin-Apps/swift-cardano-core.git", from: "0.3.6"),
        .package(url: "https://github.com/Kingpin-Apps/swift-cardano-chain.git", from: "0.2.16"),
        .package(url: "https://github.com/Kingpin-Apps/swift-cardano-uplc.git", from: "0.1.2"),
        .package(url: "https://github.com/Kingpin-Apps/swift-ncal.git", from: "0.2.2"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "SwiftCardanoTxValidator",
            dependencies: [
                .product(name: "SwiftCardanoCore", package: "swift-cardano-core"),
                .product(name: "SwiftCardanoChain", package: "swift-cardano-chain"),
                .product(name: "SwiftCardanoUPLC", package: "swift-cardano-uplc"),
                .product(name: "SwiftNcal", package: "swift-ncal"),
                .product(name: "Logging", package: "swift-log"),
            ],
            resources: [
                .copy("Resources")
            ]
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
