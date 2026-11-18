// swift-tools-version: 6.2
import PackageDescription

// KeptCore (and its SQLite module) builds everywhere, so its tests run on Linux.
// The app and its macOS-only dependency are added below under `#if os(macOS)`.
let package = Package(
    name: "Kept",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KeptCore", targets: ["KeptCore"]),
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite",
            providers: [.apt(["libsqlite3-dev"])]
        ),
        .target(
            name: "KeptCore",
            dependencies: ["CSQLite"]
        ),
        .testTarget(
            name: "KeptCoreTests",
            dependencies: ["KeptCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)

#if os(macOS)
package.products.append(.executable(name: "Kept", targets: ["Kept"]))
package.dependencies.append(
    .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.1.0")
)
package.targets.append(
    .executableTarget(
        name: "Kept",
        dependencies: [
            "KeptCore",
            .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
        ]
    )
)
#endif
