// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HarpoOutreachWeb",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.89.0"),
        .package(path: "../HarpoOutreachCore"),
    ],
    targets: [
        .executableTarget(
            name: "HarpoOutreachWeb",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "HarpoOutreachCore", package: "HarpoOutreachCore"),
            ],
            path: "Sources",
            resources: [.copy("Public")]
        ),
    ]
)
