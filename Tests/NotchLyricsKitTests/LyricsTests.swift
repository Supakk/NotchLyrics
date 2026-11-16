import XCTest
@testable import NotchLyricsKit

final class LyricsTests: XCTestCase {
    func testTimedLyrics() {
        let lines = LyricLine.parse("[ar:Artist]\n[01:02.50][00:03.2]Hello\ninvalid\n[00:99]bad\n[00:05]World")
        XCTAssertEqual(lines.map(\.time), [3.2, 5, 62.5])
        XCTAssertEqual(lines.map(\.text), ["Hello", "World", "Hello"])
    }
}
