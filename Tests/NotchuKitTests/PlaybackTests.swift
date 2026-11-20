import XCTest
@testable import NotchuKit

final class PlaybackTests: XCTestCase {
    func testPausedPlayerKeepsSelection() {
        XCTAssertFalse(AppState.shouldTuck(hasTrack: true))
        XCTAssertTrue(AppState.shouldTuck(hasTrack: false))
        XCTAssertFalse(AppState.shouldTuck(hasTrack: true, isPlaying: false))
        XCTAssertTrue(AppState.shouldTuck(hasTrack: true, isPlaying: false, pausedLongEnough: true))
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

    func testSubtitleShowsArtistAndAlbum() {
        var track = TrackInfo(title: "Song", artist: "Artist", album: "Album", artwork: nil, duration: 0, elapsedTime: 0, isPlaying: true, bundleID: nil)
        XCTAssertEqual(track.subtitle, "Artist - Album")
        track.playlist = "Road Trip"
        XCTAssertEqual(track.subtitle, "Artist - Album")
        var bare = TrackInfo(title: "Song", artist: "Artist", album: "", artwork: nil, duration: 0, elapsedTime: 0, isPlaying: true, bundleID: nil)
        XCTAssertEqual(bare.subtitle, "Artist")
        bare.playlist = "Road Trip"
        XCTAssertEqual(bare.subtitle, "Artist - Road Trip")
    }

    func testCoverSearchAcceptsOnlyTheSameSong() {
        XCTAssertTrue(PlayerBridge.sameTitle("Perfect (feat. 1MILL)", "Perfect (feat. 1MILL)"))
        XCTAssertTrue(PlayerBridge.sameTitle("Perfect", "Perfect (feat. 1MILL)"))
        XCTAssertFalse(PlayerBridge.sameTitle("Bag of Money (feat. Rick Ross & T-Pain)", "Perfect (feat. 1MILL)"))
        XCTAssertTrue(PlayerBridge.sameArtist("PUN & 1MILL", "PUN"))
        XCTAssertTrue(PlayerBridge.sameArtist("PRYVT, BIG Naughty", "PRYVT & BIG Naughty"))
        XCTAssertFalse(PlayerBridge.sameArtist("Wale & Meek Mill", "PUN"))
    }

    func testCoverSearchTakesTheAlbumThatIsPlaying() {
        XCTAssertTrue(AppleMusicLyricsCache.sameAlbum("NEVERDRY", "neverdry"))
        XCTAssertFalse(AppleMusicLyricsCache.sameAlbum("Head in the Clouds - Single", "NEVERDRY"))
        XCTAssertTrue(AppleMusicLyricsCache.sameAlbum("Head in the Clouds", "Head in the Clouds - Single"))
        XCTAssertFalse(AppleMusicLyricsCache.sameAlbum(nil, "NEVERDRY"))
        XCTAssertFalse(AppleMusicLyricsCache.sameAlbum("", ""))
    }
}
