import CoreImage
import SwiftUI

@Observable
final class LockLyrics {
    var lines: [LyricLine] = [] {
        didSet { displayLines = LyricLine.withInterludes(lines) }
    }
    /// `lines` plus interlude rows for instrumental stretches; what the lock screen shows.
    private(set) var displayLines: [LyricLine] = []
    /// False for lyrics that come without timing; their lines are spread over the song so
    /// the column still drifts along, but no line is highlighted as "now".
    private(set) var isSynced = true
    var text = "Loading lyrics…"
    private static let statusMessages: Set<String> = [
        "Loading lyrics…", "Play a song to see lyrics", "No lyrics found", "No lyrics available", "Unable to load lyrics"
    ]
    /// Real lyrics are loaded (synced lines or plain text), not a status message.
    var hasLyrics: Bool { !lines.isEmpty || !Self.statusMessages.contains(text) }
    private var task: Task<Void, Never>?
    private var cache: [String: (lines: [LyricLine], text: String, synced: Bool)] = [:]

    private func show(_ lines: [LyricLine], text: String, synced: Bool, key: String) {
        isSynced = synced
        self.lines = lines
        self.text = text
        cache[key] = (lines, text, synced)
    }

    /// Unsynced words spread evenly over the song, so the column can follow along roughly.
    static func spread(_ words: [String], duration: TimeInterval) -> [LyricLine] {
        let words = words.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !words.isEmpty else { return [] }
        let start = duration * 0.06, span = max(duration * 0.88, 1)
        return words.enumerated().map {
            LyricLine(id: $0.offset, time: start + span * Double($0.offset) / Double(words.count), text: $0.element)
        }
    }

    func load(_ track: TrackInfo) {
        task?.cancel()
        lines = []
        isSynced = true
        guard track.hasTrack else { text = "Play a song to see lyrics"; return }
        let key = Self.cacheKey(for: track)
        if let cached = cache[key] {
            isSynced = cached.synced
            lines = cached.lines
            text = cached.text
            return
        }
        text = "Loading lyrics…"
        task = Task { @MainActor in
            // Prefer timed lyrics from any source over words without timing:
            // Apple Music synced → lrclib synced → Apple Music words → lrclib words → script.
            var appleWords: [String]?
            if track.bundleID == "com.apple.Music" {
                // Apple Music's local cache may be written a moment after the track starts,
                // so look again briefly.
                for attempt in 0..<3 {
                    if attempt > 0 { try? await Task.sleep(for: .seconds(1.5)) }
                    guard !Task.isCancelled else { return }
                    let found = await Task.detached { AppleMusicLyricsCache.lyrics(title: track.title, artist: track.artist) }.value
                    guard let found, !found.lines.isEmpty else { continue }
                    if found.synced {
                        show(found.lines, text: found.lines.map(\.text).joined(separator: "\n"), synced: true, key: key)
                        return
                    }
                    appleWords = found.lines.map(\.text)
                    break
                }
            }
            let result = try? await Self.fetch(track)
            guard !Task.isCancelled else { return }
            let lrcSynced = LyricLine.parse(result?.syncedLyrics ?? "")
            if !lrcSynced.isEmpty {
                show(lrcSynced, text: result?.plainLyrics ?? lrcSynced.map(\.text).joined(separator: "\n"), synced: true, key: key)
            } else if let appleWords {
                show(Self.spread(appleWords, duration: track.duration), text: appleWords.joined(separator: "\n"), synced: false, key: key)
            } else if let plain = result?.plainLyrics {
                show(Self.spread(plain.components(separatedBy: .newlines), duration: track.duration), text: plain, synced: false, key: key)
            } else if let words = await Self.appleMusicLyrics(for: track) {
                show(Self.spread(words.components(separatedBy: .newlines), duration: track.duration), text: words, synced: false, key: key)
            } else {
                text = "No lyrics found"
            }
        }
    }

    static func requestURL(for track: TrackInfo) -> URL? {
        guard var components = URLComponents(string: "https://lrclib.net/api/get") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "album_name", value: track.album),
            URLQueryItem(name: "duration", value: String(Int(track.duration.rounded())))
        ]
        return components.url
    }

    /// Title without bracketed or dashed suffixes, and the first credited artist.
    static func simplified(_ track: TrackInfo) -> TrackInfo {
        var copy = track
        copy.title = track.title
            .replacingOccurrences(of: #"\s*[\(\[].*?[\)\]]"#, with: "", options: .regularExpression)
            .components(separatedBy: " - ").first?
            .trimmingCharacters(in: .whitespaces) ?? track.title
        copy.artist = track.artist
            .components(separatedBy: CharacterSet(charactersIn: "&,")).first?
            .replacingOccurrences(of: #"\s+(feat\.?|ft\.?).*$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces) ?? track.artist
        return copy
    }

    static func searchURL(for track: TrackInfo) -> URL? {
        guard var components = URLComponents(string: "https://lrclib.net/api/search") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist)
        ]
        return components.url
    }

    private static func fetch(_ track: TrackInfo) async throws -> Result? {
        if let url = requestURL(for: track),
           let exact: Result = try await request(url, as: Result.self),
           exact.plainLyrics != nil || exact.syncedLyrics != nil {
            return exact
        }
        // Search again with the bare title: players often add "(Slowmotion)", "- Remastered"
        // or "feat." parts that the lyrics database does not have.
        var matches: [Result] = []
        for query in [track, Self.simplified(track)] {
            guard let url = searchURL(for: query) else { continue }
            matches = (try await request(url, as: [Result].self)) ?? []
            if !matches.isEmpty { break }
        }
        return matches
            .filter { $0.plainLyrics != nil || $0.syncedLyrics != nil }
            .sorted {
                if ($0.syncedLyrics != nil) != ($1.syncedLyrics != nil) { return $0.syncedLyrics != nil }
                return abs(($0.duration ?? track.duration) - track.duration) < abs(($1.duration ?? track.duration) - track.duration)
            }
            .first
    }

    private static func request<T: Decodable>(_ url: URL, as type: T.Type) async throws -> T? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Notchu/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func appleMusicLyrics(for track: TrackInfo) async -> String? {
        guard track.bundleID == "com.apple.Music" else { return nil }
        return await Task.detached {
            var error: NSDictionary?
            let reply = NSAppleScript(source: "tell application id \"com.apple.Music\" to get lyrics of current track")?
                .executeAndReturnError(&error)
            guard error == nil, let value = reply?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            return value
        }.value
    }

    private static func cacheKey(for track: TrackInfo) -> String {
        [track.title, track.artist, track.album, String(Int(track.duration.rounded()))]
            .joined(separator: "|")
            .lowercased()
    }

    private struct Result: Decodable {
        let plainLyrics: String?
        let syncedLyrics: String?
        let duration: Double?
    }
}

/// Lock-screen now-playing player: one frosted glass panel that holds either the compact
/// card or the large artwork beside synced lyrics. Clicking the artwork switches modes; the
/// panel resizes while the artwork, titles and controls morph to their new places. Without
/// lyrics it always shows the compact card.
struct LockLyricsView: View {
    let state: AppState
    @AppStorage("lockLyricsExpanded") private var wantsLyrics = false
    /// True for a few seconds after playback pauses, so pausing from the card does not make
    /// it vanish under the pointer.
    @State private var pauseGrace = false
    @State private var graceTask: Task<Void, Never>?
    @Namespace private var morph

    static var modeSwitch: Animation { LockMotion.modeSwitch }

    static func activeLineID(in lines: [LyricLine], elapsedTime: TimeInterval) -> Int? {
        lines.last { $0.time <= elapsedTime }?.id
    }

    private var track: TrackInfo { state.presentationTrack }
    /// Only while music is playing (or just paused from here); nothing to show otherwise.
    private var shown: Bool { state.lockScreenVisible && track.hasTrack && (state.isPlaying || pauseGrace) }
    private var showsLyrics: Bool { wantsLyrics && state.lockLyrics.hasLyrics }
    private var radius: CGFloat { showsLyrics ? 26 : 20 }

    var body: some View {
        ZStack {
            if showsLyrics { lyricsContent } else { compactContent }
        }
        // One artwork view for both layouts: it glides and resizes to whichever slot is
        // present instead of cross-fading between two copies.
        .overlay { artwork }
        .padding(showsLyrics ? 20 : 12)
        .background { glass }
        .animation(LockMotion.coverChange, value: track.artwork.map(ObjectIdentifier.init))
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
        .animation(Self.modeSwitch, value: showsLyrics)
        // Both modes share one bottom edge: the compact card sits where the lyrics panel's
        // bottom is, and the panel grows upward from it.
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .opacity(shown ? 1 : 0)
        .scaleEffect(shown ? 1 : LockMotion.hiddenScale)
        .blur(radius: shown ? 0 : LockMotion.hiddenBlur)
        // In on a soft spring; out as a quick ease, e.g. while the lock screen is unlocking.
        .animation(shown ? LockMotion.appear : LockMotion.disappear, value: shown)
        .onChange(of: state.isPlaying) { wasPlaying, playing in
            graceTask?.cancel()
            if playing { pauseGrace = false; return }
            guard wasPlaying else { return }
            pauseGrace = true
            graceTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                pauseGrace = false
            }
        }
        .foregroundStyle(.white)
    }

    // MARK: Layouts

    private var compactContent: some View {
        HStack(spacing: 12) {
            artworkSlot(size: 60)
            VStack(alignment: .leading, spacing: 6) {
                titles(alignment: .leading, titleSize: 15)
                progress
                controls(symbolSize: 14)
            }
            .frame(width: 186)
        }
    }

    private var lyricsContent: some View {
        HStack(alignment: .center, spacing: 28) {
            VStack(spacing: 12) {
                artworkSlot(size: 160)
                titles(alignment: .center, titleSize: 17)
                progress
                controls(symbolSize: 15)
            }
            .frame(width: 180)
            syncedLyrics
                .frame(width: 460, height: 320)
                .transition(LockMotion.lyricsTransition)
        }
    }

    // MARK: Pieces

    /// The cover itself, scaled up and heavily blurred, darkened so white text stays readable,
    /// under Liquid Glass (frosted material before macOS 26).
    private var glass: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return ZStack {
            if #available(macOS 26.0, *) {
                // .clear is the more see-through Liquid Glass variant.
                Color.clear.glassEffect(.clear, in: shape)
            } else {
                shape.fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
            }
            coverBlur
                .opacity(LockMotion.coverOpacity)
                .clipShape(shape)
            shape.fill(.black.opacity(LockMotion.panelDim))
        }
    }

    @ViewBuilder private var coverBlur: some View {
        if let source = track.artwork, let image = BlurredCover.image(for: source) {
            // Size comes from the panel; the image fills it and is cut to it.
            Color.clear
                .overlay {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
                .clipped()
                .id(ObjectIdentifier(source))
                .transition(.opacity)
        } else {
            let colors = state.presentationColors
            LinearGradient(colors: colors.map { $0.opacity(0.5) }, startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private func toggle() { withAnimation(Self.modeSwitch) { wantsLyrics.toggle() } }

    /// Where the artwork goes in a layout; the artwork itself is drawn once, above.
    private func artworkSlot(size: CGFloat) -> some View {
        Color.clear
            .frame(width: size, height: size)
            .matchedGeometryEffect(id: "artwork", in: morph, isSource: true)
    }

    private var artwork: some View {
        let radius: CGFloat = showsLyrics ? 14 : 10
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return Button(action: toggle) {
            ArtworkSwap(image: track.artwork, placeholderSymbolSize: 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(shape)
            .contentShape(shape)
        }
        .buttonStyle(MediaControlStyle(cornerRadius: radius))
        .shadow(color: .black.opacity(showsLyrics ? 0.3 : 0.15), radius: showsLyrics ? 14 : 6, y: showsLyrics ? 6 : 3)
        .matchedGeometryEffect(id: "artwork", in: morph, properties: .frame, isSource: false)
        .accessibilityLabel(showsLyrics ? "Hide lyrics" : "Show lyrics")
    }

    private func titles(alignment: HorizontalAlignment, titleSize: CGFloat) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(track.title)
                .font(.system(size: titleSize, weight: .semibold))
            Text(track.artist)
                .font(.system(size: titleSize - 2))
                .foregroundStyle(.white.opacity(0.65))
        }
        .lineLimit(1)
        .multilineTextAlignment(alignment == .center ? .center : .leading)
        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
        .matchedGeometryEffect(id: "titles", in: morph)
    }

    /// Same artwork gradient as the notch's progress line.
    private var progress: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                Capsule()
                    .fill(LinearGradient(colors: state.presentationColors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, geometry.size.width * state.mediaEngine.progress))
                    .animation(.linear(duration: 0.5), value: state.mediaEngine.progress)
            }
        }
        .frame(height: 4)
        .matchedGeometryEffect(id: "progress", in: morph)
    }

    private var bridge: PlayerBridge { state.mediaEngine.playerBridge }

    /// Same controls as the open notch: playback mode, previous, play or pause, next, mute.
    private func controls(symbolSize: CGFloat) -> some View {
        HStack(spacing: 0) {
            controlButton(modeSymbol, size: symbolSize - 2, label: modeLabel) {
                withAnimation(NotchMotion.iconSwap) { _ = bridge.send(.advancePlaybackMode) }
            }
            Spacer(minLength: 0)
            controlButton("backward.fill", size: symbolSize, label: "Previous track") { state.mediaEngine.previousTrack() }
            Spacer(minLength: 0)
            controlButton(state.isPlaying ? "pause.fill" : "play.fill", size: symbolSize + 3, label: state.isPlaying ? "Pause" : "Play") {
                state.mediaEngine.togglePlayPause()
            }
            Spacer(minLength: 0)
            controlButton("forward.fill", size: symbolSize, label: "Next track") { state.mediaEngine.nextTrack() }
            Spacer(minLength: 0)
            controlButton(bridge.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", size: symbolSize - 2,
                          label: bridge.isMuted ? "Unmute" : "Mute") {
                withAnimation(NotchMotion.iconSwap) { _ = bridge.send(.toggleMute) }
            }
        }
        .padding(.horizontal, 2)
        .matchedGeometryEffect(id: "controls", in: morph)
    }

    private var modeSymbol: String {
        switch bridge.playbackMode {
        case .shuffle: "shuffle"
        case .sequential: "repeat"
        case .repeatOne: "repeat.1"
        }
    }

    private var modeLabel: String {
        switch bridge.playbackMode {
        case .shuffle: "Shuffle"
        case .sequential: "Play in order"
        case .repeatOne: "Repeat current track"
        }
    }

    private func controlButton(_ symbol: String, size: CGFloat, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SwappingSymbol(name: symbol, size: size, weight: .semibold)
        }
        .buttonStyle(MediaControlStyle(playbackControl: true))
        .accessibilityLabel(label)
    }

    /// Re-evaluates the active line ten times a second from an interpolated playback time,
    /// instead of jumping on the player's half-second ticks. The clock stops whenever the
    /// card is not on screen or nothing is playing, so the hidden panel costs nothing.
    private var syncedLyrics: some View {
        let live = shown && state.isPlaying
        return TimelineView(.animation(minimumInterval: 0.1, paused: !live)) { context in
            let time = state.mediaEngine.playbackTime(at: context.date) + LockMotion.lyricLead
            LyricsColumn(lines: state.lockLyrics.displayLines,
                         synced: state.lockLyrics.isSynced,
                         live: live,
                         placeholder: state.lockLyrics.text,
                         activeLine: Self.activeLineID(in: state.lockLyrics.displayLines, elapsedTime: time))
        }
    }
}

/// The lyrics column, scrolled by hand rather than with a ScrollView: every line is offset
/// to bring the active one to the reading position, and lines below it follow a beat later,
/// so a line change ripples down the column like Apple Music. Only the active line index
/// drives the animations, so the timeline ticking does not restart them.
private struct LyricsColumn: View {
    let lines: [LyricLine]
    /// Without timing every line stays equally readable; only the scroll follows the song.
    let synced: Bool
    /// On screen and playing; animated decorations rest otherwise.
    let live: Bool
    let placeholder: String
    let activeLine: Int?

    @State private var heights: [Int: CGFloat] = [:]
    @State private var positioned = false

    static let wrapWidth: CGFloat = 440
    static let spacing: CGFloat = 24

    var body: some View {
        GeometryReader { geometry in
            let shift = offset(columnHeight: geometry.size.height)
            VStack(alignment: .leading, spacing: Self.spacing) {
                if lines.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.top, geometry.size.height * LockMotion.readingLine)
                }
                ForEach(lines) { line in
                    row(line)
                        .offset(y: shift)
                        .animation(positioned ? LockMotion.lyricScroll.delay(delay(for: line.id)) : nil, value: shift)
                }
            }
            .frame(width: geometry.size.width, alignment: .leading)
            .onPreferenceChange(LineHeights.self) { heights = $0 }
        }
        .clipped()
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.16),
                    .init(color: .black, location: 0.74),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .onChange(of: heights.count) { _, count in
            // Start animating once every line has been measured, so the first placement
            // is a jump rather than a long scroll from the top.
            if count == lines.count, !positioned {
                DispatchQueue.main.async { positioned = true }
            }
        }
        .onChange(of: lines.map(\.id)) { _, _ in positioned = false }
    }

    private func row(_ line: LyricLine) -> some View {
        let active = synced && line.id == activeLine
        let distance = synced ? abs(line.id - (activeLine ?? -10)) : 0
        return Group {
            if line.isInterlude {
                InterludeDots(active: active && live)
            } else {
                Text(line.text)
            }
        }
            .font(.system(size: 22, weight: .bold))
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            // Wrap at a fixed width, slightly narrower than the column, so the focus scale
            // never pushes a long line past the edge.
            .frame(width: Self.wrapWidth, alignment: .leading)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: LineHeights.self, value: [line.id: proxy.size.height])
            })
            // Scale instead of changing the font size, so lines never re-wrap.
            .scaleEffect(active ? LockMotion.focusScale : 1, anchor: .leading)
            .foregroundStyle(.white.opacity(active ? 1 : (synced ? 0.42 : 0.82)))
            // Lines further from the active one soften a little more.
            .blur(radius: active ? 0 : LockMotion.lineBlur(distance: distance))
            .animation(LockMotion.lineFocus.delay(delay(for: line.id) * 0.5), value: activeLine)
    }

    /// Vertical shift that puts the active line's top on the reading line.
    private func offset(columnHeight: CGFloat) -> CGFloat {
        let target = activeLine ?? 0
        var top: CGFloat = 0
        for line in lines where line.id < target {
            top += (heights[line.id] ?? 0) + Self.spacing
        }
        return columnHeight * LockMotion.readingLine - top
    }

    private func delay(for id: Int) -> Double {
        guard let activeLine, id > activeLine else { return 0 }
        return Double(min(id - activeLine, LockMotion.rippleLines)) * LockMotion.ripple
    }
}

/// Three dots for an instrumental stretch. While it is the current row they breathe one
/// after another, like Apple Music; otherwise they rest dimmed.
private struct InterludeDots: View {
    let active: Bool

    var body: some View {
        // 30 fps is plenty for a slow breathing motion and halves the redraws on 120 Hz screens.
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 9) {
                ForEach(0..<3) { index in
                    // Each dot swells in turn, a third of a cycle apart.
                    let wave = active ? LockMotion.interludeWave(time: t, index: index) : 0
                    Circle()
                        .frame(width: 11, height: 11)
                        .scaleEffect(0.8 + 0.35 * wave)
                        .opacity(0.45 + 0.55 * wave)
                }
            }
            .frame(height: 30, alignment: .leading)
            .padding(.leading, 2)
        }
        .accessibilityLabel("Instrumental")
    }
}

private struct LineHeights: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

/// The cover blurred once per artwork with Core Image (cheap at this size and identical on
/// every frame, unlike a live blur filter).
enum BlurredCover {
    private static var cache: (key: ObjectIdentifier, image: NSImage)?
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func image(for source: NSImage) -> NSImage? {
        let key = ObjectIdentifier(source)
        if let cache, cache.key == key { return cache.image }
        guard let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var input = CIImage(cgImage: cg)
        let scale = 160 / max(input.extent.width, input.extent.height)
        input = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let extent = input.extent
        let output = input.clampedToExtent()
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: LockMotion.coverSaturation])
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: LockMotion.coverBlurRadius])
            .cropped(to: extent)
        guard let result = context.createCGImage(output, from: extent) else { return nil }
        let image = NSImage(cgImage: result, size: .zero)
        cache = (key, image)
        return image
    }
}
