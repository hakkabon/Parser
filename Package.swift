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
            .upToNextMinor(from: "0.2.0")
        ),
        .package(url: "https://github.com/hakkabon/TerminalColors.git", .upToNextMinor(from: "0.1.0")),
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
