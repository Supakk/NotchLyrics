import XCTest
@testable import NotchLyricsKit

final class PlaybackTests: XCTestCase {
    func testPausedPlayerKeepsSelection() {
        XCTAssertFalse(AppState.shouldTuck(hasTrack: true))
        XCTAssertTrue(AppState.shouldTuck(hasTrack: false))
        XCTAssertEqual(PlayerBridge.orderedPlayers(running: ["com.apple.Music", "com.spotify.client"], preferred: "com.spotify.client").first, "com.spotify.client")
        XCTAssertEqual(PlayerBridge.orderedPlayers(running: ["com.apple.Music"], preferred: "com.spotify.client"), ["com.apple.Music"])
    }

    func testPlaybackModeCyclesInRequestedOrder() {
        XCTAssertEqual(PlayerBridge.playbackMode(shuffled: true, repeatMode: "off"), .shuffle)
        XCTAssertEqual(PlayerBridge.playbackMode(shuffled: false, repeatMode: "off"), .sequential)
        XCTAssertEqual(PlayerBridge.playbackMode(shuffled: false, repeatMode: "one"), .repeatOne)
        XCTAssertEqual(PlayerBridge.playbackMode(shuffled: false, repeatMode: "true"), .repeatOne)
        XCTAssertEqual(PlaybackMode.shuffle.next, .sequential)
        XCTAssertEqual(PlaybackMode.sequential.next, .repeatOne)
        XCTAssertEqual(PlaybackMode.repeatOne.next, .shuffle)
    }

    func testSubtitleShowsArtistAndPlaylistOnly() {
        var track = TrackInfo(title: "Song", artist: "Artist", album: "Album", artwork: nil, duration: 0, elapsedTime: 0, isPlaying: true, bundleID: nil)
        XCTAssertEqual(track.subtitle, "Artist")
        track.playlist = "Road Trip"
        XCTAssertEqual(track.subtitle, "Artist - Road Trip")
        let bare = TrackInfo(title: "Song", artist: "Artist", album: "", artwork: nil, duration: 0, elapsedTime: 0, isPlaying: true, bundleID: nil)
        XCTAssertEqual(bare.subtitle, "Artist")
    }
}
