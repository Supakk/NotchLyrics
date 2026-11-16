// swift-tools-version: 5.9
import Foundation
import PackageDescription

// Tuned motion, notch geometry and control feel live in a private package. When it is
// checked out next to this repository (../NotchLyricsMotion) the app uses it; otherwise it
// builds against the open basic implementation in Sources/NotchLyricsMotionBasic, which
// has the same API. Set NOTCHLYRICS_BASIC_MOTION=1 to force the basic one.
let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let privateMotion = packageDirectory.appendingPathComponent("../NotchLyricsMotion").standardizedFileURL
let usePrivateMotion = ProcessInfo.processInfo.environment["NOTCHLYRICS_BASIC_MOTION"] == nil
    && FileManager.default.fileExists(atPath: privateMotion.appendingPathComponent("Package.swift").path)

let motionDependency: Target.Dependency = usePrivateMotion
    ? .product(name: "NotchLyricsMotion", package: "NotchLyricsMotion")
    : "NotchLyricsMotion"

var targets: [Target] = [
    // Thin executable: only starts the app.
    .executableTarget(
        name: "NotchLyrics",
        dependencies: ["NotchLyricsKit"]
    ),
    // App logic, views and services.
    .target(name: "NotchLyricsKit", dependencies: [motionDependency]),
    .testTarget(
        name: "NotchLyricsKitTests",
        dependencies: ["NotchLyricsKit"]
    )
]
if !usePrivateMotion {
    targets.append(.target(name: "NotchLyricsMotion", path: "Sources/NotchLyricsMotionBasic"))
}

let package = Package(
    name: "NotchLyrics",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "NotchLyrics", targets: ["NotchLyrics"])
    ],
    dependencies: usePrivateMotion ? [.package(path: "../NotchLyricsMotion")] : [],
    targets: targets
)
