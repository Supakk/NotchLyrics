import SwiftUI

@Observable
final class LockLyrics {
    var lines: [LyricLine] = []
    var text = "Loading lyrics…"
    private var task: Task<Void, Never>?
    func load(_ track: TrackInfo) {
        task?.cancel()
        lines = []
        guard track.hasTrack else { text = "Play a song to see lyrics"; return }
        text = "Loading lyrics…"
        task = Task { @MainActor in
            do {
                var url = URLComponents(string: "https://lrclib.net/api/get")!
                url.queryItems = [URLQueryItem(name: "track_name", value: track.title), URLQueryItem(name: "artist_name", value: track.artist)]
                var request = URLRequest(url: url.url!)
                request.timeoutInterval = 15
                let (data, response) = try await URLSession.shared.data(for: request)
                try Task.checkCancellation()
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { text = "No lyrics found"; return }
                let result = try JSONDecoder().decode(Result.self, from: data)
                lines = LyricLine.parse(result.syncedLyrics ?? "")
                text = result.plainLyrics ?? "No lyrics available"
            } catch { if !Task.isCancelled { text = "Unable to load lyrics" } }
        }
    }
    private struct Result: Decodable { let plainLyrics: String?; let syncedLyrics: String? }
}

struct LockLyricsView: View {
    let state: AppState
    @AppStorage("lockLyricsMode") private var lyricsMode = false
    private var activeLine: Int? { state.lockLyrics.lines.last { $0.time <= state.mediaEngine.elapsedTime }?.id }
    var body: some View {
        VStack(spacing: 12) {
            Button { lyricsMode.toggle() } label: {
                Group {
                    if lyricsMode {
                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(spacing: 16) {
                                    if state.lockLyrics.lines.isEmpty { Text(state.lockLyrics.text) }
                                    ForEach(state.lockLyrics.lines) { line in
                                        Text(line.text.isEmpty ? "♪" : line.text)
                                            .font(.system(size: 19, weight: line.id == activeLine ? .bold : .regular))
                                            .opacity(line.id == activeLine ? 1 : 0.4).id(line.id)
                                    }
                                }.padding()
                            }
                            .onChange(of: activeLine, initial: true) { _, line in
                                withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(line, anchor: .center) }
                            }
                        }
                    } else {
                        AlbumArtView(image: state.currentTrack.artwork, size: 180)
                    }
                }.frame(width: 300, height: 220).contentShape(Rectangle())
            }.buttonStyle(MediaControlStyle()).accessibilityLabel("Switch artwork and lyrics")
            Text(state.currentTrack.title).font(.headline)
            Text(state.currentTrack.artist).foregroundStyle(.secondary)
        }.foregroundStyle(.white).padding(20).background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 24))
    }
}
