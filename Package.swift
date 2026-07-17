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
        .package(url: "https://github.com/hakkabon/Grammar.git", branch: "main"),
        .package(url: "https://github.com/hakkabon/Lexer.git", branch: "main"),
        .package(url: "https://github.com/hakkabon/TerminalColors.git", from: "0.0.1"),
    ],
    targets: [
        .target(
            name: "Parser",
            dependencies: [
                .product(name: "Grammar", package: "Grammar"),
                .product(name: "Lexer", package: "Lexer"),
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
