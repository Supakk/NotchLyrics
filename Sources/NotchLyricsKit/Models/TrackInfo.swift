import AppKit

/// Information about the current track.
struct TrackInfo: Equatable {
    let title: String
    let artist: String
    let album: String
    let artwork: NSImage?
    let duration: TimeInterval
    var elapsedTime: TimeInterval
    let isPlaying: Bool
    let bundleID: String?
    /// Playlist the track is playing from, when the player reports one.
    var playlist: String = ""

    static let empty = TrackInfo(
        title: "", artist: "", album: "",
        artwork: nil, duration: 0, elapsedTime: 0,
        isPlaying: false, bundleID: nil
    )

    var hasTrack: Bool { !title.isEmpty }

    /// "Artist - Playlist"; just the artist when the track is not playing from a playlist.
    var subtitle: String {
        [artist, playlist].filter { !$0.isEmpty }.joined(separator: " - ")
    }

    /// Compare track identity independently of elapsed time and playback state.
    func isSameTrack(as other: TrackInfo) -> Bool {
        title == other.title && artist == other.artist && album == other.album
    }

    static func == (lhs: TrackInfo, rhs: TrackInfo) -> Bool {
        lhs.title == rhs.title &&
        lhs.artist == rhs.artist &&
        lhs.album == rhs.album &&
        lhs.isPlaying == rhs.isPlaying &&
        abs(lhs.elapsedTime - rhs.elapsedTime) < 1.0
    }
}
