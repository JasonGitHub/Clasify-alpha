// swift-tools-version: 6.0
import PackageDescription

// SPIKE ONLY. Never merge. Tests three ways to play Apple Music with no other app window on screen.
let package = Package(
    name: "AppleMusicSpike",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AppleMusicSpike",
            linkerSettings: [
                .linkedFramework("MusicKit"),
                .linkedFramework("iTunesLibrary"),
                .linkedFramework("WebKit"),
            ]
        )
    ]
)
