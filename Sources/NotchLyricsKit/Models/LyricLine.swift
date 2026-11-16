import Foundation

struct LyricLine: Identifiable, Equatable {
    let id: Int
    let time: Double
    let text: String

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
