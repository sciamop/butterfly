// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Butterfly",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .executable(
            name: "Butterfly",
            targets: ["Butterfly"]
        )
    ],
    targets: [
        .executableTarget(
            name: "Butterfly",
            dependencies: []
        )
    ]
)




