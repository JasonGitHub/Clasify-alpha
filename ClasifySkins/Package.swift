// swift-tools-version: 6.0
import PackageDescription

// The skins: SwiftUI views that render AppState and send input actions. They hold no logic.
// A package of its own, so `swift test` runs their snapshot tests on macOS without the app.
let package = Package(
    name: "ClasifySkins",
    platforms: [.macOS(.v15)],
    products: [.library(name: "ClasifySkins", targets: ["ClasifySkins"])],
    dependencies: [.package(path: "../ClasifyCore")],
    targets: [
        // Resources: the About screen's capybara, CappyAI's own art, bundled (card BF). Skins load
        // nothing from the network or disk.
        .target(
            name: "ClasifySkins", dependencies: [.product(name: "ClasifyCore", package: "ClasifyCore")],
            resources: ["stand", "wave", "think", "boba", "sleep"].map { Resource.copy("Resources/about-hp-\($0).png") }),
        .testTarget(name: "ClasifySkinsTests", dependencies: ["ClasifySkins"]),
    ]
)
