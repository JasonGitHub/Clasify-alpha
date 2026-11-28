// swift-tools-version: 6.0
import PackageDescription

// The app shell parts that the Mac app and the phone app share (CLA-202, step 6), such as the
// cover loader. Apple frameworks only. What only one platform has stays in that app and comes
// in through a closure or a protocol.
let package = Package(
    name: "ClasifyShell",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "ClasifyShell", targets: ["ClasifyShell"])],
    dependencies: [.package(path: "../ClasifyCore"), .package(path: "../ClasifySkins")],
    targets: [
        .target(name: "ClasifyShell", dependencies: [
            .product(name: "ClasifyCore", package: "ClasifyCore"),
            .product(name: "ClasifySkins", package: "ClasifySkins"),
        ]),
    ]
)
