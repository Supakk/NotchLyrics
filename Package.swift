// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NotchLyrics",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "NotchLyrics", targets: ["NotchLyrics"])
    ],
    targets: [
        // Thin executable: only starts the app.
        .executableTarget(
            name: "NotchLyrics",
            dependencies: ["NotchLyricsKit"]
        ),
        // App logic, views and services.
        .target(name: "NotchLyricsKit"),
        .testTarget(
            name: "NotchLyricsKitTests",
            dependencies: ["NotchLyricsKit"]
        )
    ]
)
