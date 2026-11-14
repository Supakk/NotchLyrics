import XCTest
import SwiftUI
@testable import NotchLyrics

final class LyricsTests: XCTestCase {
    func testArtworkAndFrameShareOneTransitionRoute() {
        for progress in stride(from: CGFloat(0), through: 1, by: 0.05) {
            let layout = NotchTransitionLayout(compact: CGSize(width: 254, height: 32), expanded: CGSize(width: 340, height: 175), compactArtwork: 20, compactLeading: 7, progress: progress)
            XCTAssertTrue(CGRect(origin: .zero, size: layout.size).contains(layout.artwork))
            XCTAssertEqual(layout.artwork.width, 20 + 24 * progress, accuracy: 0.001)
            XCTAssertEqual(layout.size.height, 32 + 143 * progress, accuracy: 0.001)
        }
        let midpoint = NotchTransitionLayout(compact: CGSize(width: 254, height: 32), expanded: CGSize(width: 340, height: 175), compactArtwork: 20, compactLeading: 7, progress: 0.5)
        XCTAssertEqual(midpoint.artwork, CGRect(x: 13.5, y: 22, width: 32, height: 32))
        XCTAssertEqual(midpoint.size, CGSize(width: 297, height: 103.5))
    }
    func testHoverGeometryKeepsCameraEdgeAndContainsCompactRegion() {
        let compact = CGSize(width: 254, height: 32)
        let hover = AppState.hoverSize(compact)
        let base = CGRect(x: -compact.width / 2, y: 0, width: compact.width, height: compact.height)
        let enlarged = CGRect(x: -hover.width / 2, y: 0, width: hover.width, height: hover.height)
        XCTAssertEqual(hover.width, 273.05, accuracy: 0.001)
        XCTAssertEqual(hover.height, 36.8, accuracy: 0.001)
        XCTAssertEqual(enlarged.minY, base.minY)
        XCTAssertTrue(enlarged.contains(base))
    }
    func testNativeBaseGeometry() {
        XCTAssertEqual(AppState.compactSize(cameraWidth: 180, topInset: 32, hasActivity: true, hasPhysicalNotch: true), CGSize(width: 254, height: 32))
        XCTAssertEqual(AppState.compactSize(cameraWidth: 74, topInset: 24, hasActivity: true, hasPhysicalNotch: false), CGSize(width: 136, height: 24))
        XCTAssertEqual(AppState.compactSize(cameraWidth: 180, topInset: 32, hasActivity: false, hasPhysicalNotch: true), CGSize(width: 180, height: 32))
        XCTAssertEqual(AppState.expandedSize(cameraWidth: 180, topInset: 32), CGSize(width: 340, height: 175))
        XCTAssertEqual(AppState.expandedSize(cameraWidth: 220, topInset: 40), CGSize(width: 345, height: 182))
        XCTAssertEqual(NotchWindowController.canvas, CGSize(width: 624, height: 320))
        let idle = AppState.cornerRadii(hasActivity: false, expanded: false)
        let compact = AppState.cornerRadii(hasActivity: true, expanded: false)
        let expanded = AppState.cornerRadii(hasActivity: true, expanded: true)
        XCTAssertEqual(idle.top, 5)
        XCTAssertEqual(idle.bottom, 10)
        XCTAssertEqual(compact.top, 8)
        XCTAssertEqual(compact.bottom, 11.5)
        XCTAssertEqual(expanded.top, 20)
        XCTAssertEqual(expanded.bottom, 35.5)
        XCTAssertEqual(AppState.cornerRadii(hasActivity: true, expanded: false, hasPhysicalNotch: false, notchHeight: 24).bottom, 12)
        XCTAssertEqual(AppState.cornerRadii(hasActivity: true, expanded: true, hasPhysicalNotch: false).bottom, 36)
    }
    func testNativeNotchContour() {
        for size in [CGSize(width: 244, height: 32), CGSize(width: 380, height: 222)] {
            let rect = CGRect(origin: CGPoint(x: 10, y: 20), size: size)
            let path = NotchShape(topRadius: 6, bottomRadius: 12).path(in: rect)
            // Continuous corners extend farther than a circular radius, but
            // the shoulder subtraction must stay within its 2r square.
            XCTAssertGreaterThanOrEqual(path.boundingRect.minX, rect.minX - 12)
            XCTAssertLessThan(path.boundingRect.minX, rect.minX - 6)
            XCTAssertLessThanOrEqual(path.boundingRect.maxX, rect.maxX + 12)
            XCTAssertGreaterThan(path.boundingRect.maxX, rect.maxX + 6)
            XCTAssertEqual(path.boundingRect.minY, rect.minY, accuracy: 0.01)
            XCTAssertEqual(path.boundingRect.maxY, rect.maxY, accuracy: 0.01)
            XCTAssertTrue(path.contains(CGPoint(x: rect.minX + 1, y: rect.midY)))
            XCTAssertTrue(path.contains(CGPoint(x: rect.minX - 3, y: rect.minY + 0.1)))
            XCTAssertFalse(path.contains(CGPoint(x: rect.minX - 3, y: rect.minY + 6)))
        }
    }
    func testPausedPlayerKeepsSelection() {
        XCTAssertEqual(PlayerBridge.orderedPlayers(running: ["com.apple.Music", "com.spotify.client"], preferred: "com.spotify.client").first, "com.spotify.client")
        XCTAssertEqual(PlayerBridge.orderedPlayers(running: ["com.apple.Music"], preferred: "com.spotify.client"), ["com.apple.Music"])
    }
    func testTimedLyrics() {
        let lines = LyricLine.parse("[ar:Artist]\n[01:02.50][00:03.2]Hello\ninvalid\n[00:99]bad\n[00:05]World")
        XCTAssertEqual(lines.map(\.time), [3.2, 5, 62.5])
        XCTAssertEqual(lines.map(\.text), ["Hello", "World", "Hello"])
    }
}
