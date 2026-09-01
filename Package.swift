// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Parser",
    platforms: [.macOS(.v11), .iOS(.v14)],
    products: [
        .library(name: "Parser", targets: ["Parser"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/hakkabon/Grammar.git",
            revision: "69f85d7a493e1862412c34493e3656e94331df06"
        ),
        .package(url: "https://github.com/hakkabon/TerminalColors.git", from: "0.0.1"),
    ],
    targets: [
        .target(
            name: "Parser",
            dependencies: [
                .product(name: "Grammar", package: "Grammar"),
                .product(name: "TerminalColors", package: "TerminalColors"),
            ]
        ),
        .testTarget(
            name: "ParserTests",
            dependencies: [
                "Parser",
            ]
        ),
    ]
)
