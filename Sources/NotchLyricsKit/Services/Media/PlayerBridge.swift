import AppKit

/// Direct player integration when MediaRemote does not return metadata.
@Observable
final class PlayerBridge {
    private let queue = DispatchQueue(label: "NotchLyrics.player")
    /// Commands get their own queue so a slow metadata poll never delays a button press.
    private let commandQueue = DispatchQueue(label: "NotchLyrics.player.commands")
    private var queuedRefresh: ((TrackInfo?) -> Void)?
    var shuffled = false
    var repeatMode = "off"
    var isMuted = false
    var selectedSource: String {
        get { UserDefaults.standard.string(forKey: "musicSource") ?? "automatic" }
        set { UserDefaults.standard.set(newValue, forKey: "musicSource") }
    }
    var lastError: String?
    private var busy = false
    private var pendingArtworkKey: String?
    private var artworkKeys: [String: String] = [:]
    private var cachedArtworks: [String: NSImage] = [:]
    private(set) var bundleID: String?
    private var previousVolume = 100
    /// Bumped on every user control so an in-flight poll can't revert optimistic UI state.
    private(set) var controlGeneration = 0

    static func orderedPlayers(running: [String], preferred: String?) -> [String] {
        let supported = ["com.apple.Music", "com.spotify.client"]
        return supported.filter { running.contains($0) }.sorted { ($0 == preferred ? 0 : 1) < ($1 == preferred ? 0 : 1) }
    }

    static func playbackMode(shuffled: Bool, repeatMode: String) -> PlaybackMode {
        if shuffled { return .shuffle }
        return ["one", "true"].contains(repeatMode.lowercased()) ? .repeatOne : .sequential
    }

    var playbackMode: PlaybackMode { Self.playbackMode(shuffled: shuffled, repeatMode: repeatMode) }

    func refresh(completion: @escaping (TrackInfo?) -> Void) {
        // Remember the latest request instead of dropping it, so a refresh asked for
        // right after a button press runs as soon as the current poll finishes.
        guard !busy else { queuedRefresh = completion; return }
        let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        let candidates = Self.orderedPlayers(running: running, preferred: bundleID).filter { selectedSource == "automatic" || $0 == selectedSource }
        guard !candidates.isEmpty else { completion(nil); return }
        busy = true
        let generation = controlGeneration
        queue.async {
            var selected: TrackInfo?
            var shuffle = false
            var repeatState = "off"
            var selectedVolume = 0
            for id in candidates {
                let duration = id == "com.spotify.client" ? "(duration of t) / 1000" : "duration of t"
                let artwork = id == "com.apple.Music" ? "try\nset art to raw data of artwork 1 of t\nend try" : "set art to artwork url of t"
                // Music exposes the playlist being played; skip library sources such as "Music".
                // Spotify's scripting dictionary has no playlist/context, so it stays empty.
                let playlist = id == "com.apple.Music" ? "try\nif (special kind of current playlist as string) is \"none\" then set pl to name of current playlist\nend try" : ""
                let modes = id == "com.apple.Music" ? "set shuffleState to shuffle enabled\nset repeatState to song repeat as string" : "set shuffleState to shuffling\nset repeatState to repeating as string"
                let source = """
                tell application id "\(id)"
                    if player state is stopped then return {}
                    set t to current track
                    set art to ""
                    set pl to ""
                    \(artwork)
                    \(playlist)
                    \(modes)
                    return {name of t, artist of t, album of t, \(duration), player position, (player state is playing), art, shuffleState, repeatState, sound volume, pl}
                end tell
                """
                var error: NSDictionary?
                guard let reply = NSAppleScript(source: source)?.executeAndReturnError(&error), error == nil, reply.numberOfItems == 11 else {
                    if let error { DispatchQueue.main.async { self.lastError = error.description; NSLog("Player metadata failed: %@", error) } }
                    continue
                }
                let key = id + "|" + (reply.atIndex(1)?.stringValue ?? "") + "|" + (reply.atIndex(3)?.stringValue ?? "")
                var image = key == self.artworkKeys[id] ? self.cachedArtworks[id] : nil
                if image == nil, id == "com.apple.Music", let data = reply.atIndex(7)?.data { image = NSImage(data: data) }
                if image == nil, id == "com.spotify.client", self.pendingArtworkKey != key,
                   let address = reply.atIndex(7)?.stringValue, let url = URL(string: address), url.scheme == "https" {
                    self.pendingArtworkKey = key
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 5
                    URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
                        guard let self else { return }
                        self.queue.async {
                            if self.pendingArtworkKey == key { self.pendingArtworkKey = nil }
                            guard self.artworkKeys[id] == key, let data, data.count <= 10_000_000,
                                  (response as? HTTPURLResponse)?.statusCode == 200 else { return }
                            self.cachedArtworks[id] = NSImage(data: data)
                        }
                    }.resume()
                }
                self.artworkKeys[id] = key
                self.cachedArtworks[id] = image
                let track = TrackInfo(title: reply.atIndex(1)?.stringValue ?? "", artist: reply.atIndex(2)?.stringValue ?? "", album: reply.atIndex(3)?.stringValue ?? "", artwork: image, duration: max(0, reply.atIndex(4)?.doubleValue ?? 0), elapsedTime: max(0, reply.atIndex(5)?.doubleValue ?? 0), isPlaying: reply.atIndex(6)?.booleanValue ?? false, bundleID: id, playlist: reply.atIndex(11)?.stringValue ?? "")
                if selected == nil || track.isPlaying {
                    selected = track
                    shuffle = reply.atIndex(8)?.booleanValue ?? false
                    repeatState = reply.atIndex(9)?.stringValue ?? "off"
                    selectedVolume = Int(reply.atIndex(10)?.int32Value ?? 0)
                }
                if track.isPlaying { break }
            }
            DispatchQueue.main.async {
                // A control was sent while this poll was running; its reply predates the change.
                if generation == self.controlGeneration {
                    self.shuffled = shuffle
                    self.repeatMode = repeatState
                    if selectedVolume > 0 { self.previousVolume = selectedVolume }
                    self.isMuted = selected != nil && selectedVolume == 0
                }
                self.busy = false
                self.bundleID = selected?.bundleID
                completion(selected)
                if let next = self.queuedRefresh {
                    self.queuedRefresh = nil
                    self.refresh(completion: next)
                }
            }
        }
    }

    func send(_ command: MediaCommand) -> Bool {
        guard let id = bundleID else { return false }
        controlGeneration &+= 1
        let action: String
        switch command {
        case .togglePlayPause: action = "playpause"
        case .nextTrack: action = "next track"
        case .previousTrack:
            // With no earlier track the player may stay put; restart the current one instead.
            action = "set currentName to name of current track\nprevious track\ndelay 0.4\nif (name of current track) is currentName then set player position to 0"
        case .play: action = "play"
        case .pause: action = "pause"
        case .stop: action = "stop"
        case .advanceShuffle:
            action = id == "com.spotify.client" ? "set shuffling to not shuffling" : "set shuffle enabled to not shuffle enabled"
        case .advanceRepeat:
            action = id == "com.spotify.client" ? "set repeating to not repeating" : "if song repeat is off then\nset song repeat to all\nelse\nset song repeat to off\nend if"
        case .toggleMute:
            let targetMuted = !isMuted
            action = "set sound volume to \(targetMuted ? 0 : previousVolume)"
            isMuted = targetMuted
        case .advancePlaybackMode:
            let nextMode = playbackMode.next
            if id == "com.spotify.client" {
                switch nextMode {
                case .shuffle: action = "set repeating to false\nset shuffling to true"
                case .sequential: action = "set shuffling to false\nset repeating to false"
                case .repeatOne: action = "set shuffling to false\nset repeating to true"
                }
            } else {
                switch nextMode {
                case .shuffle: action = "set song repeat to off\nset shuffle enabled to true"
                case .sequential: action = "set shuffle enabled to false\nset song repeat to off"
                case .repeatOne: action = "set shuffle enabled to false\nset song repeat to one"
                }
            }
            shuffled = nextMode == .shuffle
            repeatMode = nextMode == .repeatOne ? (id == "com.spotify.client" ? "true" : "one") : "off"
        }
        commandQueue.async {
            var error: NSDictionary?
            NSAppleScript(source: "tell application id \"\(id)\"\n\(action)\nend tell")?.executeAndReturnError(&error)
            if let error { NSLog("Player control failed: %@", error) }
        }
        return true
    }

}
