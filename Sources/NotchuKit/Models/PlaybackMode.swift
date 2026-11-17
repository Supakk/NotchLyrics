/// Cycle used by the playback-mode button: shuffle → in order → repeat one.
enum PlaybackMode: CaseIterable {
    case shuffle
    case sequential
    case repeatOne

    var next: PlaybackMode {
        switch self {
        case .shuffle: .sequential
        case .sequential: .repeatOne
        case .repeatOne: .shuffle
        }
    }
}
