// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NotchLyrics",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "NotchLyrics",
            path: "Sources/NotchLyrics"
        ),
        .testTarget(name: "NotchLyricsTests", dependencies: ["NotchLyrics"])
    ]
)
