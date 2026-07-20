// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AtomanStudio",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "AtomanCore", targets: ["AtomanCore"]),
        .library(name: "AtomanMusic", targets: ["AtomanMusic"]),
        .library(name: "AtomanStudio", targets: ["AtomanStudio"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "AtomanCore",
            path: "AtomanCore"
        ),
        .target(
            name: "AtomanMusic",
            dependencies: ["AtomanCore"],
            path: "AtomanMusic"
        ),
        .target(
            name: "AtomanStudio",
            dependencies: [
                "AtomanCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "AtomanStudio"
        ),
        .testTarget(
            name: "AtomanStudioTests",
            dependencies: ["AtomanStudio", "AtomanCore", "AtomanMusic"],
            path: "AtomanStudioTests"
        ),
    ]
)
