// swift-tools-version: 6.2
import PackageDescription

/// Typed values your app reads by key (flags), changed without shipping a new build, with rules on
/// device values and experiments that split a value into variants. Everything is decided on the
/// device: the set is the same JSON for everyone.
///
/// **No external dependencies.** Foundation only.
let package = Package(
    name: "swift-app-config",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        // Reading values, rules, variant assignment, the set source port, the bundled set and the
        // records (`config_exposed`, `config_rejected`). Foundation only.
        .library(name: "ConfigCore", targets: ["ConfigCore"]),
        // Test doubles: a fake source, an in-memory storage and a recording sink.
        .library(name: "ConfigTesting", targets: ["ConfigTesting"])
    ],
    targets: [
        .target(name: "ConfigCore"),
        .target(name: "ConfigTesting", dependencies: ["ConfigCore"]),
        .testTarget(
            name: "ConfigCoreTests",
            dependencies: ["ConfigCore", "ConfigTesting"],
            resources: [.copy("Cases")]
        )
    ]
)
