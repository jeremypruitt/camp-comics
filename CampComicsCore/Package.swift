// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CampComicsCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CampComicsCore", targets: ["CampComicsCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
    ],
    targets: [
        .target(
            name: "CampComicsCore",
            dependencies: ["Yams"]
        ),
        .testTarget(
            name: "CampComicsCoreTests",
            dependencies: ["CampComicsCore"]
        ),
    ]
)
