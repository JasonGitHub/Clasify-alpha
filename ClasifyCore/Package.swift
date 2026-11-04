// swift-tools-version: 6.0
import PackageDescription

// App state and reducer. Plain Swift: no UI or playback engine imports, so it builds and tests on Linux.
let package = Package(
    name: "ClasifyCore",
    products: [.library(name: "ClasifyCore", targets: ["ClasifyCore"])],
    targets: [
        .target(name: "ClasifyCore"),
        .testTarget(name: "ClasifyCoreTests", dependencies: ["ClasifyCore"]),
    ]
)
