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

    static let empty = TrackInfo(
        title: "", artist: "", album: "",
        artwork: nil, duration: 0, elapsedTime: 0,
        isPlaying: false, bundleID: nil
    )

    var hasTrack: Bool { !title.isEmpty }

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

/// Player state.
enum PlaybackState {
    case playing
    case paused
    case stopped

    var isPlaying: Bool { self == .playing }
}

/// Media playback commands.
enum MediaCommand: Int {
    case play = 0
    case pause = 1
    case togglePlayPause = 2
    case stop = 3
    case nextTrack = 4
    case previousTrack = 5
    case advanceRepeat = 6
    case advanceShuffle = 7
}
