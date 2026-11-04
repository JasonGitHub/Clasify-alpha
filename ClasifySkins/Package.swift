// swift-tools-version: 6.0
import PackageDescription

// The skins: SwiftUI views that render AppState and send input actions. They hold no logic.
// A package of its own, so `swift test` runs their snapshot tests on macOS without the app.
let package = Package(
    name: "ClasifySkins",
    platforms: [.macOS(.v14)],
    products: [.library(name: "ClasifySkins", targets: ["ClasifySkins"])],
    dependencies: [.package(path: "../ClasifyCore")],
    targets: [
        .target(name: "ClasifySkins", dependencies: [.product(name: "ClasifyCore", package: "ClasifyCore")]),
        .testTarget(name: "ClasifySkinsTests", dependencies: ["ClasifySkins"]),
    ]
)
