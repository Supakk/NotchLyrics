import XCTest
@testable import NotchuKit

final class LockLyricsTests: XCTestCase {
    func testActiveLineTracksElapsedTime() {
        let lines = [
            LyricLine(id: 0, time: 2, text: "First"),
            LyricLine(id: 1, time: 5, text: "Second"),
            LyricLine(id: 2, time: 9, text: "Third")
        ]

        XCTAssertNil(LockLyricsView.activeLineID(in: lines, elapsedTime: 1.9))
        XCTAssertEqual(LockLyricsView.activeLineID(in: lines, elapsedTime: 5), 1)
        XCTAssertEqual(LockLyricsView.activeLineID(in: lines, elapsedTime: 12), 2)
    }

    func testLyricsRequestUsesTrackIdentity() throws {
        let track = TrackInfo(
            title: "A&B",
            artist: "Artist Name",
            album: "Album",
            artwork: nil,
            duration: 241.4,
            elapsedTime: 0,
            isPlaying: true,
            bundleID: "com.apple.Music"
        )
        let url = try XCTUnwrap(LockLyrics.requestURL(for: track))
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") }), [
            "track_name": "A&B",
            "artist_name": "Artist Name",
            "album_name": "Album",
            "duration": "241"
        ])

        let searchURL = try XCTUnwrap(LockLyrics.searchURL(for: track))
        let searchItems = try XCTUnwrap(URLComponents(url: searchURL, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: searchItems.map { ($0.name, $0.value ?? "") }), [
            "track_name": "A&B",
            "artist_name": "Artist Name"
        ])
    }

    func testLockPanelStaysCenteredAcrossScreenSizes() {
        for screen in [
            NSRect(x: 0, y: 0, width: 1440, height: 900),
            NSRect(x: 1440, y: -120, width: 800, height: 600)
        ] {
            let panel = AppDelegate.lockPanelFrame(in: screen)
            XCTAssertEqual(panel.midX, screen.midX)
            XCTAssertGreaterThanOrEqual(panel.minX, screen.minX + 20)
            XCTAssertLessThanOrEqual(panel.maxX, screen.maxX - 20)
            XCTAssertEqual(panel.height, 410)
            XCTAssertLessThan(panel.midY, screen.midY)
        }
    }

    func testSessionLockFlag() {
        XCTAssertTrue(AppDelegate.isLocked(session: ["CGSSessionScreenIsLocked": true]))
        XCTAssertFalse(AppDelegate.isLocked(session: ["CGSSessionScreenIsLocked": false]))
        XCTAssertFalse(AppDelegate.isLocked(session: [:]))
        XCTAssertFalse(AppDelegate.isLocked(session: nil))
    }
}
