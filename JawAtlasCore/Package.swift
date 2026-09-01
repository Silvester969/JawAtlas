// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JawAtlasCore",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "JawAtlasCore", targets: ["JawAtlasCore"])
    ],
    targets: [
        .target(name: "JawAtlasCore")
    ]
)
