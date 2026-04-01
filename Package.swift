// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-cardano-txvalidator",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "swift-cardano-txvalidator",
            targets: ["swift-cardano-txvalidator"]
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "swift-cardano-txvalidator"
        ),
        .testTarget(
            name: "swift-cardano-txvalidatorTests",
            dependencies: ["swift-cardano-txvalidator"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
