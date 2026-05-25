// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CampComicsCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CampComicsCore", targets: ["CampComicsCore"]),
    ],
    targets: [
        .target(name: "CampComicsCore"),
        .testTarget(name: "CampComicsCoreTests", dependencies: ["CampComicsCore"]),
    ]
)
