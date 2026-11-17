import XCTest
@testable import NotchuKit

final class LyricsTests: XCTestCase {
    func testTimedLyrics() {
        let lines = LyricLine.parse("[ar:Artist]\n[01:02.50][00:03.2]Hello\ninvalid\n[00:99]bad\n[00:05]World")
        XCTAssertEqual(lines.map(\.time), [3.2, 5, 62.5])
        XCTAssertEqual(lines.map(\.text), ["Hello", "World", "Hello"])
    }

    func testAppleMusicTTML() {
        let ttml = """
        <tt xmlns="http://www.w3.org/ns/ttml" xmlns:ttm="http://www.w3.org/ns/ttml#metadata"><body><div>\
        <p begin="16.951" end="20.2"><span begin="16.9">Hello</span> <span begin="17.5">world</span>\
        <span ttm:role="x-bg"><span>(ooh)</span></span></p>\
        <p begin="1:02.5" end="1:05">Second line</p></div></body></tt>
        """
        let lines = AppleMusicLyricsCache.parseTTML(ttml)
        XCTAssertEqual(lines.map(\.text), ["Hello world", "Second line"])
        XCTAssertEqual(lines.map(\.time), [16.951, 62.5])
    }

    func testSimplifiedSearchDropsSuffixes() {
        let track = TrackInfo(title: "Song (Slowmotion) - Remastered", artist: "A & B feat. C", album: "", artwork: nil, duration: 0, elapsedTime: 0, isPlaying: true, bundleID: nil)
        let simple = LockLyrics.simplified(track)
        XCTAssertEqual(simple.title, "Song")
        XCTAssertEqual(simple.artist, "A")
    }

    func testInterludesForIntroAndLongGaps() {
        let lines = [
            LyricLine(id: 0, time: 12, text: "First", end: 15),
            LyricLine(id: 1, time: 16, text: "Second", end: 18),
            LyricLine(id: 2, time: 30, text: "After the solo", end: 33)
        ]
        let rows = LyricLine.withInterludes(lines)
        XCTAssertEqual(rows.map(\.text), ["", "First", "Second", "", "After the solo"])
        XCTAssertEqual(rows.map(\.time), [0, 12, 16, 18, 30])
        XCTAssertEqual(rows.map(\.id), [0, 1, 2, 3, 4])
        XCTAssertTrue(rows[3].isInterlude)
    }

    func testUnsyncedTTMLKeepsWordsAndSpreadsThem() {
        let ttml = #"<tt xmlns="http://www.w3.org/ns/ttml" itunes:timing="None"><body><div><p>One</p><p>Two</p></div><div><p>Three</p></div></body></tt>"#
        XCTAssertTrue(AppleMusicLyricsCache.parseTTML(ttml).isEmpty)
        XCTAssertEqual(AppleMusicLyricsCache.plainLines(inTTML: ttml), ["One", "Two", "Three"])
        let spread = LockLyrics.spread(["One", "", "Two", "Three"], duration: 100)
        XCTAssertEqual(spread.map(\.text), ["One", "Two", "Three"])
        XCTAssertEqual(spread.map(\.id), [0, 1, 2])
        XCTAssertTrue(zip(spread, spread.dropFirst()).allSatisfy { $0.time < $1.time })
        XCTAssertLessThan(spread.last!.time, 100)
    }
}
