// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "2026-09-23-Webcard",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "WebcardCore", targets: ["WebcardCore"]),
        .executable(name: "Webcard", targets: ["Webcard"])
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
        .package(url: "https://github.com/ainame/Swift-WebP.git", from: "0.5.0")
    ],
    targets: [
        .target(
            name: "WebcardCore",
            dependencies: [
                "ZIPFoundation",
                .product(name: "WebP", package: "swift-webp")
            ]
        ),
        .executableTarget(
            name: "Webcard",
            dependencies: ["WebcardCore"],
            exclude: ["Info.plist", "Resources"]
        ),
        .testTarget(
            name: "WebcardCoreTests",
            dependencies: ["WebcardCore", "ZIPFoundation"]
        ),
        .testTarget(
            name: "WebcardTests",
            dependencies: ["Webcard"]
        )
    ]
)
