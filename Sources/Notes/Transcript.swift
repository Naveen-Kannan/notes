import Flow
import Foundation

public struct Line: Equatable, Sendable {
    public let who: String
    public let start: TimeInterval
    public var text: String
}

public enum Transcript {
    /// Tokens -> utterances, split on pauses longer than `gap` at word boundaries.
    public static func lines(_ tokens: [TimedToken], who: String, gap: TimeInterval = 1.0) -> [Line] {
        var out: [Line] = []
        var lastEnd = -Double.infinity
        for t in tokens {
            if out.isEmpty || (t.start - lastEnd > gap && t.text.hasPrefix(" ")) {
                out.append(Line(who: who, start: t.start, text: ""))
            }
            out[out.count - 1].text += t.text
            lastEnd = t.end
        }
        return out.compactMap {
            let s = $0.text.trimmingCharacters(in: .whitespaces)
            return s.isEmpty ? nil : Line(who: $0.who, start: $0.start, text: s)
        }
    }

    public static func merge(_ a: [Line], _ b: [Line]) -> [Line] {
        (a + b).enumerated().sorted { ($0.element.start, $0.offset) < ($1.element.start, $1.offset) }.map(\.element)
    }

    public static func render(_ lines: [Line]) -> String {
        lines.map { "[\(stamp($0.start))] \($0.who): \($0.text)" }.joined(separator: "\n")
    }

    static func stamp(_ t: TimeInterval) -> String {
        let s = Int(t)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%02d:%02d", s / 60, s % 60)
    }
}
