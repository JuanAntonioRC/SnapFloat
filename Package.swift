// swift-tools-version:5.9
//
// This manifest builds the Linux side of SnapFloat only. The macOS app keeps
// building via SnapFloat.xcodeproj, untouched — `swift build` here has no
// effect on it and vice versa.
import PackageDescription

let package = Package(
    name: "SnapFloat",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SnapFloatCore", targets: ["SnapFloatCore"]),
        .executable(name: "snapfloat-linux", targets: ["SnapFloatLinux"]),
    ],
    targets: [
        .target(
            name: "SnapFloatCore"
        ),
        .systemLibrary(
            name: "CGtk4Shim",
            pkgConfig: "gtk4",
            providers: [.apt(["libgtk-4-dev"])]
        ),
        .executableTarget(
            name: "SnapFloatLinux",
            dependencies: ["SnapFloatCore", "CGtk4Shim"]
        ),
    ]
)
