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
    private var cacheCheckedAt: [String: Date] = [:]
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
    /// Delivers a cover the moment it is ready, tagged with its track's key, so the UI can
    /// show it without another metadata poll and ignore covers of tracks already skipped.
    var onArtworkReady: ((String, NSImage) -> Void)?

    /// Identity of a track's cover: player, title and album.
    static func artworkKey(bundleID: String, title: String, album: String) -> String {
        bundleID + "|" + title + "|" + album
    }

    private func remember(_ image: NSImage, for key: String) {
        artworkStore[key] = image
        artworkOrder.removeAll { $0 == key }
        artworkOrder.append(key)
        if artworkOrder.count > 40 { artworkStore[artworkOrder.removeFirst()] = nil }
        DispatchQueue.main.async { self.onArtworkReady?(key, image) }
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
                let key = Self.artworkKey(bundleID: id, title: reply.atIndex(1)?.stringValue ?? "", album: reply.atIndex(3)?.stringValue ?? "")
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
                if image == nil, id == "com.apple.Music", self.pendingArtworkKey != key,
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
        let key = Self.artworkKey(bundleID: id, title: title, album: album)
        queue.async {
            guard !title.isEmpty, self.artworkStore[key] == nil, self.pendingArtworkKey != key else { return }
            self.pendingArtworkKey = key
            self.fetchCatalogArtwork(title: title, artist: artist, id: id, key: key)
        }
    }

    /// Finds the cover Apple Music shows: first the artwork URL from Music's own catalog
    /// cache (the exact image), else Apple's public iTunes Search in the same store, taking a
    /// result only if both title and artist match. Only title and artist are sent.
    fileprivate func fetchCatalogArtwork(title: String, artist: String, id: String, key: String) {
        // Reading Music's cache parses a few JSON files; while a cover is still missing, do
        // it at most every 5 s.
        if let last = cacheCheckedAt[key], Date().timeIntervalSince(last) < 5, failedArtworkKeys.contains(key) {
            pendingArtworkKey = nil; return
        }
        cacheCheckedAt[key] = Date()
        if let url = AppleMusicLyricsCache.artworkURL(title: title, artist: artist) {
            downloadArtwork(url, id: id, key: key, searchFallback: nil)
            return
        }
        guard !failedArtworkKeys.contains(key) else { pendingArtworkKey = nil; return }
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: "\(title) \(artist)"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "10")
        ] + (AppleMusicLyricsCache.storefront().map { [URLQueryItem(name: "country", value: $0)] } ?? [])
        guard let url = components?.url else { pendingArtworkKey = nil; return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }
            let results = (response as? HTTPURLResponse)?.statusCode == 200
                ? ((data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any])?["results"] as? [[String: Any]] ?? [])
                : []
            let match = results.first {
                Self.sameTitle($0["trackName"] as? String, title) && Self.sameArtist($0["artistName"] as? String, artist)
            }
            guard let address = (match?["artworkUrl100"] as? String)?.replacingOccurrences(of: "100x100bb", with: "600x600bb"),
                  let imageURL = URL(string: address), imageURL.scheme == "https", imageURL.host?.hasSuffix("mzstatic.com") == true else {
                // No confident match: show no cover rather than a wrong one, and do not ask
                // the network again for this track (Music's cache is still checked).
                self.queue.async {
                    if self.pendingArtworkKey == key { self.pendingArtworkKey = nil }
                    self.failedArtworkKeys.insert(key)
                }
                return
            }
            self.downloadArtwork(imageURL, id: id, key: key, searchFallback: key)
        }.resume()
    }

    private func downloadArtwork(_ url: URL, id: String, key: String, searchFallback: String?) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }
            let image = (response as? HTTPURLResponse)?.statusCode == 200 ? data.flatMap { $0.count <= 10_000_000 ? NSImage(data: $0) : nil } : nil
            self.queue.async {
                if self.pendingArtworkKey == key { self.pendingArtworkKey = nil }
                guard let image else {
                    if let searchFallback { self.failedArtworkKeys.insert(searchFallback) }
                    return
                }
                self.remember(image, for: key)
                if self.artworkKeys[id] == key { self.cachedArtworks[id] = image }
            }
        }.resume()
    }

    /// Titles match ignoring case, accents and a trailing "(feat. …)" / "[…]" part.
    static func sameTitle(_ a: String?, _ b: String) -> Bool {
        guard let a else { return false }
        func core(_ s: String) -> String {
            s.replacingOccurrences(of: #"\s*[\(\[](feat|with|ft)\.?[^\)\]]*[\)\]]"#, with: "", options: [.regularExpression, .caseInsensitive])
                .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
                .trimmingCharacters(in: .whitespaces)
        }
        return core(a) == core(b)
    }

    /// The first credited artist of each side matches.
    static func sameArtist(_ a: String?, _ b: String) -> Bool {
        guard let a else { return false }
        func lead(_ s: String) -> String {
            (s.components(separatedBy: CharacterSet(charactersIn: "&,")).first ?? s)
                .replacingOccurrences(of: #"\s+(feat\.?|ft\.?|x)\s+.*$"#, with: "", options: [.regularExpression, .caseInsensitive])
                .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
                .trimmingCharacters(in: .whitespaces)
        }
        return !lead(b).isEmpty && lead(a) == lead(b)
    }
}
