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
    private var failedArtworkKeys: Set<String> = []
    /// Tracks whose embedded Music artwork has been asked for once already.
    private var scriptArtworkTried: Set<String> = []
    /// Compiled once and reused: compiling every poll is slow and makes the system scan the
    /// script again each time. Only used on `queue`.
    private var compiledScripts: [String: NSAppleScript] = [:]

    private func runScript(_ source: String, error: inout NSDictionary?) -> NSAppleEventDescriptor? {
        let script: NSAppleScript
        if let cached = compiledScripts[source] {
            script = cached
        } else {
            guard let created = NSAppleScript(source: source) else { return nil }
            created.compileAndReturnError(&error)
            if error != nil { return nil }
            compiledScripts[source] = created
            script = created
        }
        return script.executeAndReturnError(&error)
    }
    private var artworkKeys: [String: String] = [:]
    private var cachedArtworks: [String: NSImage] = [:]
    /// Covers already seen, so a repeated track shows its cover immediately.
    private var artworkStore: [String: NSImage] = [:]
    private var artworkOrder: [String] = []
    /// Called on the main queue when a cover finishes loading, so the UI need not wait for the next poll.
    var onArtworkReady: (() -> Void)?

    private func remember(_ image: NSImage, for key: String) {
        artworkStore[key] = image
        artworkOrder.removeAll { $0 == key }
        artworkOrder.append(key)
        if artworkOrder.count > 40 { artworkStore[artworkOrder.removeFirst()] = nil }
        DispatchQueue.main.async { self.onArtworkReady?() }
    }
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
                // Music's artwork is image data; it is fetched separately, once per track.
                let artwork = id == "com.apple.Music" ? "" : "set art to artwork url of t"
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
                guard let reply = self.runScript(source, error: &error), error == nil, reply.numberOfItems == 11 else {
                    if let error { DispatchQueue.main.async { self.lastError = error.description; NSLog("Player metadata failed: %@", error) } }
                    continue
                }
                let key = id + "|" + (reply.atIndex(1)?.stringValue ?? "") + "|" + (reply.atIndex(3)?.stringValue ?? "")
                var image = self.artworkStore[key] ?? (key == self.artworkKeys[id] ? self.cachedArtworks[id] : nil)
                if image == nil, id == "com.apple.Music", !self.scriptArtworkTried.contains(key) {
                    self.scriptArtworkTried.insert(key)
                    var artError: NSDictionary?
                    let art = self.runScript("tell application id \"com.apple.Music\"\ntry\nreturn raw data of artwork 1 of current track\nend try\nreturn \"\"\nend tell", error: &artError)
                    if let data = art?.data, !data.isEmpty, let found = NSImage(data: data) {
                        image = found
                        self.remember(found, for: key)
                    }
                }
                if image == nil, id == "com.spotify.client", self.pendingArtworkKey != key,
                   let address = reply.atIndex(7)?.stringValue, let url = URL(string: address), url.scheme == "https" {
                    self.pendingArtworkKey = key
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 5
                    URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
                        guard let self else { return }
                        self.queue.async {
                            if self.pendingArtworkKey == key { self.pendingArtworkKey = nil }
                            guard let data, data.count <= 10_000_000,
                                  (response as? HTTPURLResponse)?.statusCode == 200, let image = NSImage(data: data) else { return }
                            self.remember(image, for: key)
                            if self.artworkKeys[id] == key { self.cachedArtworks[id] = image }
                        }
                    }.resume()
                }
                // Streaming tracks in Music expose no artwork to scripts; look the cover up by
                // title and artist (cached per track, one request at a time).
                if image == nil, id == "com.apple.Music", self.pendingArtworkKey != key, !self.failedArtworkKeys.contains(key),
                   let title = reply.atIndex(1)?.stringValue, let artist = reply.atIndex(2)?.stringValue, !title.isEmpty {
                    self.pendingArtworkKey = key
                    self.fetchCatalogArtwork(title: title, artist: artist, id: id, key: key)
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


extension PlayerBridge {
    /// Starts the cover lookup for a Music track announced by its notification, before the
    /// metadata poll has even run. The key matches the one a poll builds for the same track.
    func prefetchCatalogArtwork(title: String, artist: String, album: String) {
        let id = "com.apple.Music"
        let key = id + "|" + title + "|" + album
        queue.async {
            guard !title.isEmpty, self.artworkStore[key] == nil, self.pendingArtworkKey != key,
                  !self.failedArtworkKeys.contains(key) else { return }
            self.pendingArtworkKey = key
            self.fetchCatalogArtwork(title: title, artist: artist, id: id, key: key)
        }
    }

    /// Looks a cover up in Apple's public iTunes Search API. Only title and artist are sent.
    fileprivate func fetchCatalogArtwork(title: String, artist: String, id: String, key: String) {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: "\(title) \(artist)"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "5")
        ]
        guard let url = components?.url else { pendingArtworkKey = nil; return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }
            func finish(_ image: NSImage?) {
                self.queue.async {
                    if self.pendingArtworkKey == key { self.pendingArtworkKey = nil }
                    guard let image else { self.failedArtworkKeys.insert(key); return }
                    self.remember(image, for: key)
                    if self.artworkKeys[id] == key { self.cachedArtworks[id] = image }
                }
            }
            guard (response as? HTTPURLResponse)?.statusCode == 200, let data, data.count < 1_000_000,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]] else { return finish(nil) }
            let match = results.first { ($0["artistName"] as? String)?.localizedCaseInsensitiveContains(artist) == true
                || artist.localizedCaseInsensitiveContains($0["artistName"] as? String ?? "\u{0}") } ?? results.first
            guard var address = match?["artworkUrl100"] as? String else { return finish(nil) }
            address = address.replacingOccurrences(of: "100x100bb", with: "600x600bb")
            guard let imageURL = URL(string: address), imageURL.scheme == "https", imageURL.host?.hasSuffix("mzstatic.com") == true else { return finish(nil) }
            var imageRequest = URLRequest(url: imageURL)
            imageRequest.timeoutInterval = 6
            URLSession.shared.dataTask(with: imageRequest) { data, response, _ in
                guard (response as? HTTPURLResponse)?.statusCode == 200, let data, data.count <= 10_000_000 else { return finish(nil) }
                finish(NSImage(data: data))
            }.resume()
        }.resume()
    }
}
