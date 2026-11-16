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
        // nothing from the network or disk. SPIKE (CLA-101): the K.3D.7 textures, copied as they
        // are, because the front's alpha is a material id.
        .target(
            name: "ClasifySkins", dependencies: [.product(name: "ClasifyCore", package: "ClasifyCore")],
            resources: ["stand", "wave", "think", "boba", "sleep"].map { Resource.copy("Resources/about-hp-\($0).png") }
                + ["front", "back"].map { Resource.copy("Resources/k3d-\($0).png") }
                // Card BM, change 264: the service logos of Pick Your Music.
                + ["spotify", "apple-music"].map { Resource.copy("Resources/logo-\($0).png") }),
        .testTarget(name: "ClasifySkinsTests", dependencies: ["ClasifySkins"]),
    ]
)
