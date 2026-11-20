// swift-tools-version: 6.2
// ParalluxKit holds everything the app and the packet tunnel share that is not
// UI chrome: navigation model, settings model, App Group identifiers. Keeping it
// a plain Swift package lets `swift test` cover it without code signing or a
// running system extension (keel.toml gate step "swift-test").
import PackageDescription

let package = Package(
    name: "ParalluxKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ParalluxKit", targets: ["ParalluxKit"]),
    ],
    targets: [
        .target(name: "ParalluxKit"),
        .testTarget(name: "ParalluxKitTests", dependencies: ["ParalluxKit"]),
    ]
)
