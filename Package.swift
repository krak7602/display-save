// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DisplaySave",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DisplayCore", targets: ["DisplayCore"]),
        .executable(name: "DisplaySave", targets: ["DisplaySave"]),
    ],
    targets: [
        .target(
            name: "DisplayHardware",
            publicHeadersPath: "include",
            linkerSettings: [.linkedFramework("Foundation"), .linkedFramework("CoreGraphics")]
        ),
        .target(name: "DisplayCore", dependencies: ["DisplayHardware"]),
        .executableTarget(
            name: "DisplaySave",
            dependencies: ["DisplayCore"],
            resources: [.process("Assets")]
        ),
        .testTarget(name: "DisplayCoreTests", dependencies: ["DisplayCore"]),
    ],
    swiftLanguageVersions: [.v5]
)
