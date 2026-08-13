// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ForkLiftClone",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ForkLiftClone", targets: ["ForkLiftClone"])
    ],
    dependencies: [
        .package(path: "Packages/Core")
    ],
    targets: [
        .executableTarget(
            name: "ForkLiftClone",
            dependencies: [
                .product(name: "FileSystemKit", package: "Core"),
                .product(name: "TransferEngine", package: "Core"),
                .product(name: "PreviewKit", package: "Core"),
                .product(name: "AppearanceKit", package: "Core"),
                .product(name: "AIKit",         package: "Core"),
            ],
            path: "App",
            exclude: ["Info.plist", "Resources"]
        )
    ]
)
