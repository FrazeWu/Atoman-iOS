// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AtomanStudio",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "AtomanStudio", targets: ["AtomanStudio"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "AtomanStudio",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "AtomanStudio"
        ),
        .testTarget(
            name: "AtomanStudioTests",
            dependencies: ["AtomanStudio"],
            path: "AtomanStudioTests"
        ),
    ]
)
