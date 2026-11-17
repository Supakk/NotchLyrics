import AppKit
import Foundation

// MARK: - MediaRemote Private API Bridge
// Load the private framework dynamically with dlopen and dlsym.
// Resolve its symbols at runtime without linking at build time.

final class MediaRemoteBridge {
    static let shared = MediaRemoteBridge()

    private var handle: UnsafeMutableRawPointer?
    private var isLoaded = false

    // MARK: - Function pointers
    private var MRMediaRemoteGetNowPlayingInfo:
        (@convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void)?

    private var MRMediaRemoteGetNowPlayingApplicationIsPlaying:
        (@convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void)?

    private var MRMediaRemoteSendCommand:
        (@convention(c) (Int, UnsafeMutableRawPointer?) -> Bool)?

    private var MRMediaRemoteRegisterForNowPlayingNotifications:
        (@convention(c) (DispatchQueue) -> Void)?

    // MARK: - Notification name keys (loaded dynamically)
    private(set) var nowPlayingInfoDidChangeNotification: NSNotification.Name?
    private(set) var nowPlayingApplicationDidChangeNotification: NSNotification.Name?

    // MARK: - Info dictionary keys
    private struct Keys {
        static let title = "kMRMediaRemoteNowPlayingInfoTitle"
        static let artist = "kMRMediaRemoteNowPlayingInfoArtist"
        static let album = "kMRMediaRemoteNowPlayingInfoAlbum"
        static let artwork = "kMRMediaRemoteNowPlayingInfoArtworkData"
        static let duration = "kMRMediaRemoteNowPlayingInfoDuration"
        static let elapsedTime = "kMRMediaRemoteNowPlayingInfoElapsedTime"
        static let timestamp = "kMRMediaRemoteNowPlayingInfoTimestamp"
        static let playbackRate = "kMRMediaRemoteNowPlayingInfoPlaybackRate"
        static let bundleID = "kMRMediaRemoteNowPlayingInfoClientPropertiesDeviceUID"
    }

    // MARK: - Init

    private init() {
        loadFramework()
    }

    private func loadFramework() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        handle = dlopen(path, RTLD_LAZY)

        guard handle != nil else {
            print("[MediaRemote] Failed to load framework: \(String(cString: dlerror()))")
            return
        }

        // Load functions
        MRMediaRemoteGetNowPlayingInfo = loadFunction("MRMediaRemoteGetNowPlayingInfo")
        MRMediaRemoteGetNowPlayingApplicationIsPlaying = loadFunction("MRMediaRemoteGetNowPlayingApplicationIsPlaying")
        MRMediaRemoteSendCommand = loadFunction("MRMediaRemoteSendCommand")
        MRMediaRemoteRegisterForNowPlayingNotifications = loadFunction("MRMediaRemoteRegisterForNowPlayingNotifications")

        // Load notification names
        nowPlayingInfoDidChangeNotification = loadNotificationName(
            "kMRMediaRemoteNowPlayingInfoDidChangeNotification"
        )
        nowPlayingApplicationDidChangeNotification = loadNotificationName(
            "kMRMediaRemoteNowPlayingApplicationDidChangeNotification"
        )

        isLoaded = true
        print("[MediaRemote] Framework loaded successfully")
    }

    private func loadFunction<T>(_ name: String) -> T? {
        guard let handle else { return nil }
        guard let sym = dlsym(handle, name) else {
            print("[MediaRemote] Symbol not found: \(name)")
            return nil
        }
        return unsafeBitCast(sym, to: T.self)
    }

    private func loadNotificationName(_ symbolName: String) -> NSNotification.Name? {
        guard let handle else { return nil }
        guard let sym = dlsym(handle, symbolName) else { return nil }
        let ptr = sym.assumingMemoryBound(to: NSString.self)
        return NSNotification.Name(ptr.pointee as String)
    }

    deinit {
        if let handle { dlclose(handle) }
    }

    // MARK: - Public API

    /// Fetch the current Now Playing information.
    func getNowPlayingInfo(completion: @escaping (TrackInfo) -> Void) {
        guard let fn = MRMediaRemoteGetNowPlayingInfo else {
            completion(.empty)
            return
        }

        fn(DispatchQueue.main) { info in
            let track = self.parseNowPlayingInfo(info)
            completion(track)
        }
    }

    /// Check whether the player is playing.
    func getIsPlaying(completion: @escaping (Bool) -> Void) {
        guard let fn = MRMediaRemoteGetNowPlayingApplicationIsPlaying else {
            completion(false)
            return
        }
        fn(DispatchQueue.main, completion)
    }

    /// Send a playback or track navigation command.
    @discardableResult
    func sendCommand(_ command: MediaCommand) -> Bool {
        guard let fn = MRMediaRemoteSendCommand else { return false }
        return fn(command.rawValue, nil)
    }

    /// Register for track change notifications.
    func registerForNotifications() {
        guard let fn = MRMediaRemoteRegisterForNowPlayingNotifications else { return }
        fn(DispatchQueue.main)
        print("[MediaRemote] Registered for notifications")
    }

    // MARK: - Parse

    private func parseNowPlayingInfo(_ info: [String: Any]) -> TrackInfo {
        let title = info[Keys.title] as? String ?? ""
        let artist = info[Keys.artist] as? String ?? ""
        let album = info[Keys.album] as? String ?? ""
        let duration = info[Keys.duration] as? TimeInterval ?? 0
        let playbackRate = info[Keys.playbackRate] as? Double ?? 0

        // Calculate elapsed time from the timestamp and playback rate.
        var elapsed = info[Keys.elapsedTime] as? TimeInterval ?? 0
        if playbackRate > 0, let timestamp = info[Keys.timestamp] as? Date {
            elapsed += Date().timeIntervalSince(timestamp) * playbackRate
        }
        elapsed = min(elapsed, duration)

        // Parse artwork
        var artwork: NSImage?
        if let artData = info[Keys.artwork] as? Data {
            artwork = NSImage(data: artData)
        }

        return TrackInfo(
            title: title,
            artist: artist,
            album: album,
            artwork: artwork,
            duration: duration,
            elapsedTime: elapsed,
            isPlaying: playbackRate > 0,
            bundleID: info[Keys.bundleID] as? String
        )
    }
}
