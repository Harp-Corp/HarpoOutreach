// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HarpoOutreachCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(
            name: "HarpoOutreachCore",
            targets: ["HarpoOutreachCore"]
        ),
    ],
    targets: [
        .target(
            name: "HarpoOutreachCore",
            path: "Sources"
        ),
    ]
)
