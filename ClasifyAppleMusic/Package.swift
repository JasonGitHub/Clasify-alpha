// swift-tools-version: 6.0
import PackageDescription

// Apple Music with MusicKit, shared by the Mac app and the phone app (CLA-202, step 4). It
// depends on ClasifyCore only. What only one platform has (the Mac's iTunesLibrary covers and
// Core Audio volume) stays in that app and comes in through the protocols in Seams.swift.
let package = Package(
    name: "ClasifyAppleMusic",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "ClasifyAppleMusic", targets: ["ClasifyAppleMusic"])],
    dependencies: [.package(path: "../ClasifyCore")],
    targets: [
        .target(name: "ClasifyAppleMusic", dependencies: [.product(name: "ClasifyCore", package: "ClasifyCore")]),
    ]
)
