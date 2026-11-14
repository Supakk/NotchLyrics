import AppKit

/// Direct player integration when MediaRemote does not return metadata.
@Observable
final class PlayerBridge {
    private let queue = DispatchQueue(label: "NotchLyrics.player")
    var shuffled = false
    var repeatMode = "off"
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

    static func orderedPlayers(running: [String], preferred: String?) -> [String] {
        let supported = ["com.apple.Music", "com.spotify.client"]
        return supported.filter { running.contains($0) }.sorted { ($0 == preferred ? 0 : 1) < ($1 == preferred ? 0 : 1) }
    }

    func refresh(completion: @escaping (TrackInfo?) -> Void) {
        guard !busy else { return }
        let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        let candidates = Self.orderedPlayers(running: running, preferred: bundleID).filter { selectedSource == "automatic" || $0 == selectedSource }
        guard !candidates.isEmpty else { completion(nil); return }
        busy = true
        queue.async {
            var selected: TrackInfo?
            var shuffle = false
            var repeatState = "off"
            for id in candidates {
                let duration = id == "com.spotify.client" ? "(duration of t) / 1000" : "duration of t"
                let artwork = id == "com.apple.Music" ? "try\nset art to raw data of artwork 1 of t\nend try" : "set art to artwork url of t"
                let modes = id == "com.apple.Music" ? "set shuffleState to shuffle enabled\nset repeatState to song repeat as string" : "set shuffleState to shuffling\nset repeatState to repeating as string"
                let source = """
                tell application id "\(id)"
                    if player state is stopped then return {}
                    set t to current track
                    set art to ""
                    \(artwork)
                    \(modes)
                    return {name of t, artist of t, album of t, \(duration), player position, (player state is playing), art, shuffleState, repeatState}
                end tell
                """
                var error: NSDictionary?
                guard let reply = NSAppleScript(source: source)?.executeAndReturnError(&error), error == nil, reply.numberOfItems == 9 else {
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
                let track = TrackInfo(title: reply.atIndex(1)?.stringValue ?? "", artist: reply.atIndex(2)?.stringValue ?? "", album: reply.atIndex(3)?.stringValue ?? "", artwork: image, duration: max(0, reply.atIndex(4)?.doubleValue ?? 0), elapsedTime: max(0, reply.atIndex(5)?.doubleValue ?? 0), isPlaying: reply.atIndex(6)?.booleanValue ?? false, bundleID: id)
                if selected == nil || track.isPlaying {
                    selected = track
                    shuffle = reply.atIndex(8)?.booleanValue ?? false
                    repeatState = reply.atIndex(9)?.stringValue ?? "off"
                }
                if track.isPlaying { break }
            }
            DispatchQueue.main.async {
                self.shuffled = shuffle
                self.repeatMode = repeatState
                self.busy = false
                self.bundleID = selected?.bundleID
                completion(selected)
            }
        }
    }

    func send(_ command: MediaCommand) -> Bool {
        guard let id = bundleID else { return false }
        let action: String
        switch command {
        case .togglePlayPause: action = "playpause"
        case .nextTrack: action = "next track"
        case .previousTrack: action = "previous track"
        case .play: action = "play"
        case .pause: action = "pause"
        case .stop: action = "stop"
        case .advanceShuffle:
            action = id == "com.spotify.client" ? "set shuffling to not shuffling" : "set shuffle enabled to not shuffle enabled"
        case .advanceRepeat:
            action = id == "com.spotify.client" ? "set repeating to not repeating" : "if song repeat is off then\nset song repeat to all\nelse\nset song repeat to off\nend if"
        }
        queue.async {
            var error: NSDictionary?
            NSAppleScript(source: "tell application id \"\(id)\"\n\(action)\nend tell")?.executeAndReturnError(&error)
            if let error { NSLog("Player control failed: %@", error) }
        }
        return true
    }
}
