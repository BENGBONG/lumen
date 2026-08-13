// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Core",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FileSystemKit", targets: ["FileSystemKit"]),
        .library(name: "TransferEngine", targets: ["TransferEngine"]),
        .library(name: "PreviewKit",    targets: ["PreviewKit"]),
        .library(name: "AppearanceKit", targets: ["AppearanceKit"]),
        .library(name: "AIKit",         targets: ["AIKit"]),
    ],
    targets: [
        .target(name: "FileSystemKit"),
        .target(name: "TransferEngine", dependencies: ["FileSystemKit"]),
        .target(name: "PreviewKit"),
        .target(name: "AppearanceKit"),
        .target(name: "AIKit",          dependencies: ["FileSystemKit"]),
        .testTarget(name: "FileSystemKitTests", dependencies: ["FileSystemKit"]),
        .testTarget(name: "TransferEngineTests", dependencies: ["TransferEngine", "FileSystemKit"]),
    ]
)
