// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DropShelf",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "DropShelf",
            path: "Sources/DropShelf"
        )
    ]
)
