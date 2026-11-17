import Foundation

struct LyricLine: Identifiable, Equatable {
    let id: Int
    let time: Double
    let text: String
    /// When the line ends, if the source says so (Apple Music's TTML does; LRC does not).
    var end: Double? = nil

    /// An instrumental stretch, drawn as animated dots like Apple Music.
    var isInterlude: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Gaps at least this long between sung lines become an interlude row.
    static let interludeGap: Double = 4.5

    /// The lines with interlude rows added for the intro and for long instrumental gaps,
    /// renumbered so ids stay sequential.
    static func withInterludes(_ lines: [LyricLine]) -> [LyricLine] {
        guard let first = lines.first else { return [] }
        var rows: [(time: Double, text: String, end: Double?)] = []
        if first.time >= interludeGap, !first.isInterlude { rows.append((0, "", first.time)) }
        for (index, line) in lines.enumerated() {
            rows.append((line.time, line.text, line.end))
            guard let end = line.end, !line.isInterlude else { continue }
            let next = index + 1 < lines.count ? lines[index + 1].time : nil
            if let next, next - end >= interludeGap, !lines[index + 1].isInterlude {
                rows.append((end, "", next))
            }
        }
        return rows.enumerated().map { LyricLine(id: $0.offset, time: $0.element.time, text: $0.element.text, end: $0.element.end) }
    }

    static func parse(_ source: String) -> [LyricLine] {
        let pattern = try! NSRegularExpression(pattern: #"\[(\d+):(\d+(?:\.\d+)?)\]"#)
        var rows: [(Double, String)] = []
        for line in source.components(separatedBy: .newlines) {
            let value = line as NSString
            let matches = pattern.matches(in: line, range: NSRange(location: 0, length: value.length))
            guard let last = matches.last else { continue }
            let text = value.substring(from: NSMaxRange(last.range)).trimmingCharacters(in: .whitespaces)
            for match in matches {
                guard let minutes = Double(value.substring(with: match.range(at: 1))), let seconds = Double(value.substring(with: match.range(at: 2))), seconds < 60 else { continue }
                rows.append((minutes * 60 + seconds, text))
            }
        }
        return rows.sorted { $0.0 < $1.0 }.enumerated().map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1) }
    }
}
