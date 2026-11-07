// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PodControl",
    platforms: [.macOS(.v14)],
    targets: [
        // Lógica pura de reconhecimento de gestos (testável sem AirPods).
        .target(name: "Gestos", path: "Sources/Gestos"),
        .executableTarget(name: "PodControl", dependencies: ["Gestos"], path: "Sources/PodControl"),
        .testTarget(name: "GestosTests", dependencies: ["Gestos"], path: "Tests/GestosTests")
    ]
)
