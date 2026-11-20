import Foundation
import SQLite3

/// Apple Music does not expose lyrics of streamed songs to scripts, but it keeps the catalog
/// responses it downloads, including time-synced TTML lyrics, in its own URL cache. This
/// reads that cache locally (read-only); nothing leaves the machine.
enum AppleMusicLyricsCache {
    static var cacheDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/com.apple.Music")
    }

    struct Lyrics {
        let lines: [LyricLine]
        /// False when Apple Music has only the words, without timing ("unsynced" lyrics).
        let synced: Bool
    }

    /// Synced lines, or else the plain words, for the newest cached catalog entry whose
    /// title and artist match.
    static func lyrics(title: String, artist: String, directory: URL = cacheDirectory) -> Lyrics? {
        for body in recentSongResponses(in: directory, lyricsOnly: true) {
            guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let songs = json["data"] as? [[String: Any]] else { continue }
            for song in songs {
                guard let attributes = song["attributes"] as? [String: Any],
                      Self.same(attributes["name"] as? String, title),
                      Self.same(attributes["artistName"] as? String, artist) || artist.isEmpty,
                      let relationships = song["relationships"] as? [String: Any] else { continue }
                for key in ["syllable-lyrics", "lyrics"] {
                    guard let rel = relationships[key] as? [String: Any],
                          let entries = rel["data"] as? [[String: Any]],
                          let lyricAttributes = entries.first?["attributes"] as? [String: Any],
                          let ttml = Self.ttml(in: lyricAttributes) else { continue }
                    let lines = parseTTML(ttml)
                    if !lines.isEmpty { return Lyrics(lines: lines, synced: true) }
                    let words = plainLines(inTTML: ttml)
                    if !words.isEmpty {
                        return Lyrics(lines: words.enumerated().map { LyricLine(id: $0.offset, time: 0, text: $0.element) }, synced: false)
                    }
                }
            }
        }
        return nil
    }

    /// The cover Apple Music itself shows for a song it has played, from its cached catalog
    /// entry (the artwork URL is a template sized here).
    static func artworkURL(title: String, artist: String, album: String = "", size: Int = 600, directory: URL = cacheDirectory) -> URL? {
        for body in recentSongResponses(in: directory, lyricsOnly: false) {
            guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let songs = json["data"] as? [[String: Any]] else { continue }
            for song in songs {
                guard let attributes = song["attributes"] as? [String: Any],
                      Self.same(attributes["name"] as? String, title),
                      Self.same(attributes["artistName"] as? String, artist) || artist.isEmpty,
                      // The same song can sit on a single, an album and compilations, each with
                      // its own cover: take the release that is playing.
                      album.isEmpty || sameAlbum(attributes["albumName"] as? String, album),
                      let artwork = attributes["artwork"] as? [String: Any],
                      let template = artwork["url"] as? String else { continue }
                let address = template
                    .replacingOccurrences(of: "{w}", with: String(size))
                    .replacingOccurrences(of: "{h}", with: String(size))
                    .replacingOccurrences(of: "{c}", with: "bb")
                    .replacingOccurrences(of: "{f}", with: "jpg")
                guard let url = URL(string: address), url.scheme == "https",
                      url.host?.hasSuffix("mzstatic.com") == true else { continue }
                return url
            }
        }
        return nil
    }

    /// The App Store country Apple Music uses (from its cached catalog requests), e.g. "th".
    static func storefront(directory: URL = cacheDirectory) -> String? {
        let database = directory.appendingPathComponent("Cache.db").path
        var handle: OpaquePointer?
        guard sqlite3_open_v2(database, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(handle); return nil
        }
        defer { sqlite3_close(handle) }
        let sql = "SELECT request_key FROM cfurl_cache_response WHERE request_key LIKE '%music.apple.com/v1/catalog/%' ORDER BY time_stamp DESC LIMIT 1"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { return nil }
        let key = String(cString: text)
        guard let range = key.range(of: "/v1/catalog/") else { return nil }
        let code = key[range.upperBound...].prefix { $0 != "/" && $0 != "?" }
        return code.count == 2 ? String(code) : nil
    }

    private static func ttml(in attributes: [String: Any]) -> String? {
        if let ttml = attributes["ttml"] as? String { return ttml }
        if let list = attributes["ttmlLocalizations"] as? String { return list }
        if let map = attributes["ttmlLocalizations"] as? [String: String] { return map.values.first }
        return nil
    }

    /// Album names match ignoring case and accents; a catalog name may or may not carry the
    /// " - Single" / " - EP" suffix that Music's scripting adds or drops.
    static func sameAlbum(_ a: String?, _ b: String) -> Bool {
        guard let a else { return false }
        func core(_ s: String) -> String {
            s.replacingOccurrences(of: #"\s+-\s+(single|ep)\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
                .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
                .trimmingCharacters(in: .whitespaces)
        }
        return !core(b).isEmpty && core(a) == core(b)
    }

    private static func same(_ a: String?, _ b: String) -> Bool {
        guard let a else { return false }
        return a.compare(b, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) == .orderedSame
    }

    /// Bodies of the newest cached catalog song responses (only those that asked for lyrics,
    /// if `lyricsOnly`).
    private static func recentSongResponses(in directory: URL, lyricsOnly: Bool, limit: Int = 40) -> [Data] {
        let database = directory.appendingPathComponent("Cache.db").path
        var handle: OpaquePointer?
        guard sqlite3_open_v2(database, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(handle); return []
        }
        defer { sqlite3_close(handle) }
        let sql = """
        SELECT d.receiver_data, d.isDataOnFS FROM cfurl_cache_response r
        JOIN cfurl_cache_receiver_data d ON r.entry_ID = d.entry_ID
        WHERE r.request_key LIKE '%music.apple.com/v1/catalog/%/songs/%'\(lyricsOnly ? " AND r.request_key LIKE '%lyrics%'" : "")
        ORDER BY r.time_stamp DESC LIMIT \(limit)
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        var bodies: [Data] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let count = Int(sqlite3_column_bytes(statement, 0))
            guard count > 0, let bytes = sqlite3_column_blob(statement, 0) else { continue }
            let blob = Data(bytes: bytes, count: count)
            if sqlite3_column_int(statement, 1) != 0 {
                // Large bodies live in fsCachedData; the column holds the file name.
                guard let name = String(data: blob, encoding: .utf8), !name.contains("/"),
                      let data = try? Data(contentsOf: directory.appendingPathComponent("fsCachedData").appendingPathComponent(name))
                else { continue }
                bodies.append(data)
            } else {
                bodies.append(blob)
            }
        }
        return bodies
    }

    // MARK: TTML

    /// Every line of the lyrics, in order, ignoring timing (for itunes:timing="None").
    static func plainLines(inTTML ttml: String) -> [String] {
        guard let data = ttml.data(using: .utf8) else { return [] }
        let collector = TTMLCollector()
        let parser = XMLParser(data: data)
        parser.delegate = collector
        parser.parse()
        return collector.allLines.filter { !$0.isEmpty }
    }

    static func parseTTML(_ ttml: String) -> [LyricLine] {
        guard let data = ttml.data(using: .utf8) else { return [] }
        let collector = TTMLCollector()
        let parser = XMLParser(data: data)
        parser.delegate = collector
        parser.parse()
        return collector.rows
            .sorted { $0.0 < $1.0 }
            .enumerated()
            .map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1, end: $0.element.2) }
    }

    /// "16.951", "1:02.345" or "1:02:03.4" → seconds.
    static func seconds(_ value: String) -> Double? {
        var total = 0.0
        for part in value.trimmingCharacters(in: .whitespaces).split(separator: ":") {
            guard let number = Double(part.hasSuffix("s") ? String(part.dropLast()) : String(part)) else { return nil }
            total = total * 60 + number
        }
        return total
    }

    private final class TTMLCollector: NSObject, XMLParserDelegate {
        var rows: [(Double, String, Double?)] = []
        var allLines: [String] = []
        private var begin: Double?
        private var end: Double?
        private var text = ""
        private var inLine = false
        /// One entry per open element inside a line: true for background-vocal spans.
        private var background: [Bool] = []

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            if name == "p" {
                begin = attributes["begin"].flatMap(AppleMusicLyricsCache.seconds)
                end = attributes["end"].flatMap(AppleMusicLyricsCache.seconds)
                text = ""
                inLine = true
                background = []
            } else if inLine {
                background.append(attributes["ttm:role"] == "x-bg")
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inLine && !background.contains(true) { text += string }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if name == "p" {
                let line = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let begin { rows.append((begin, line, end)) }
                allLines.append(line)
                begin = nil
                inLine = false
            } else if inLine, !background.isEmpty {
                background.removeLast()
            }
        }
    }
}
