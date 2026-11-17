// swift-tools-version: 5.9
import Foundation
import PackageDescription

// Tuned motion, notch geometry and control feel live in a private package. When it is
// checked out next to this repository (../NotchuMotion) the app uses it; otherwise it
// builds against the open basic implementation in Sources/NotchuMotionBasic, which
// has the same API. Set NOTCHU_BASIC_MOTION=1 to force the basic one.
let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let privateMotion = packageDirectory.appendingPathComponent("../NotchuMotion").standardizedFileURL
let usePrivateMotion = ProcessInfo.processInfo.environment["NOTCHU_BASIC_MOTION"] == nil
    && FileManager.default.fileExists(atPath: privateMotion.appendingPathComponent("Package.swift").path)

let motionDependency: Target.Dependency = usePrivateMotion
    ? .product(name: "NotchuMotion", package: "NotchuMotion")
    : "NotchuMotion"

var targets: [Target] = [
    // Thin executable: only starts the app.
    .executableTarget(
        name: "Notchu",
        dependencies: ["NotchuKit"]
    ),
    // App logic, views and services.
    .target(name: "NotchuKit", dependencies: [motionDependency]),
    .testTarget(
        name: "NotchuKitTests",
        dependencies: ["NotchuKit"]
    )
]
if !usePrivateMotion {
    targets.append(.target(name: "NotchuMotion", path: "Sources/NotchuMotionBasic"))
}

let package = Package(
    name: "Notchu",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Notchu", targets: ["Notchu"])
    ],
    dependencies: usePrivateMotion ? [.package(path: "../NotchuMotion")] : [],
    targets: targets
)
