import Foundation

struct SubtitleEntry {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
    let attributedText: NSAttributedString?
}

class SubtitleParser {
    static func parse(url: URL) -> [SubtitleEntry] {
        let ext = url.pathExtension.lowercased()
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            if let data = try? Data(contentsOf: url) {
                if let str = String(data: data, encoding: .isoLatin1) {
                    return parseContent(str, format: ext)
                }
            }
            return []
        }
        return parseContent(content, format: ext)
    }

    static func parseContent(_ content: String, format: String) -> [SubtitleEntry] {
        switch format {
        case "srt":
            return parseSRT(content)
        case "vtt", "webvtt":
            return parseVTT(content)
        case "ass", "ssa":
            return parseASS(content)
        default:
            return []
        }
    }

    // MARK: - SRT Parser

    private static func parseSRT(_ content: String) -> [SubtitleEntry] {
        var entries: [SubtitleEntry] = []
        let blocks = content.components(separatedBy: "\n\n")

        for block in blocks {
            let lines = block.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
            guard lines.count >= 3 else { continue }

            let timeLine = lines[1]
            guard let (start, end) = parseSRTTimeLine(timeLine) else { continue }

            let text = lines[2...].joined(separator: "\n")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

            entries.append(SubtitleEntry(startTime: start, endTime: end, text: text, attributedText: nil))
        }

        return entries.sorted { $0.startTime < $1.startTime }
    }

    private static func parseSRTTimeLine(_ line: String) -> (TimeInterval, TimeInterval)? {
        let parts = line.components(separatedBy: " --> ")
        guard parts.count == 2 else { return nil }
        guard let start = parseSRTTime(parts[0].trimmingCharacters(in: .whitespaces)),
              let end = parseSRTTime(parts[1].trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first ?? "") else {
            return nil
        }
        return (start, end)
    }

    private static func parseSRTTime(_ str: String) -> TimeInterval? {
        let clean = str.replacingOccurrences(of: ",", with: ".")
        let parts = clean.components(separatedBy: ":")
        guard parts.count == 3 else { return nil }
        guard let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(parts[2]) else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }

    // MARK: - WebVTT Parser

    private static func parseVTT(_ content: String) -> [SubtitleEntry] {
        var entries: [SubtitleEntry] = []
        let lines = content.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            if lines[i].contains("-->") {
                guard let (start, end) = parseSRTTimeLine(lines[i]) else {
                    i += 1
                    continue
                }

                var textLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    textLines.append(lines[i])
                    i += 1
                }

                let text = textLines.joined(separator: "\n")
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

                entries.append(SubtitleEntry(startTime: start, endTime: end, text: text, attributedText: nil))
            } else {
                i += 1
            }
        }

        return entries.sorted { $0.startTime < $1.startTime }
    }

    // MARK: - ASS/SSA Parser

    private static func parseASS(_ content: String) -> [SubtitleEntry] {
        var entries: [SubtitleEntry] = []
        let lines = content.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("Dialogue:") else { continue }

            let parts = trimmed.dropFirst("Dialogue:".count).trimmingCharacters(in: .whitespaces)
            let fields = parts.components(separatedBy: ",")
            guard fields.count >= 10 else { continue }

            guard let start = parseASSTime(fields[1].trimmingCharacters(in: .whitespaces)),
                  let end = parseASSTime(fields[2].trimmingCharacters(in: .whitespaces)) else {
                continue
            }

            let text = fields[9...].joined(separator: ",")
                .replacingOccurrences(of: "\\\\N", with: "\n")
                .replacingOccurrences(of: "\\\\n", with: "\n")
                .replacingOccurrences(of: "\\{[^}]*\\}", with: "", options: .regularExpression)

            entries.append(SubtitleEntry(startTime: start, endTime: end, text: text, attributedText: nil))
        }

        return entries.sorted { $0.startTime < $1.startTime }
    }

    private static func parseASSTime(_ str: String) -> TimeInterval? {
        let parts = str.components(separatedBy: ":")
        guard parts.count == 3 else { return nil }
        guard let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(parts[2]) else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }
}
