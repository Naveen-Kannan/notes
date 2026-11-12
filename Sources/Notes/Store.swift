import AVFoundation
import Flow
import Foundation

public enum Store {
    public static var dir: URL {
        let env = ProcessInfo.processInfo.environment["NOTES_DIR"]
        return env.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Notes/meetings", isDirectory: true)
    }
    static var audio: URL { dir.appendingPathComponent(".audio", isDirectory: true) }

    static func stamp(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return f.string(from: d)
    }

    static func recordingID(_ d: Date) -> String { "\(stamp(d))-\(UUID().uuidString)" }

    public static func render(started: Date, duration: TimeInterval, transcript: String) -> String {
        let date = stamp(started)
        return """
        ---
        date: \(date.prefix(10)) \(date.suffix(4).prefix(2)):\(date.suffix(2))
        duration: \(Int((duration / 60).rounded()))m
        status: raw
        ---

        ## Transcript
        \(transcript)

        """
    }

    /// Transcribes both channels, writes `<stamp>.md`, deletes the audio. Audio is kept if anything fails.
    public static func finish(started: Date, duration: TimeInterval, me: URL, them: URL,
                              transcriber: ParakeetTranscriber = .shared) async throws -> URL {
        let a = Transcript.lines(try await tokens(me, system: false, transcriber), who: "me")
        let b = Transcript.lines(try await tokens(them, system: true, transcriber), who: "them")
        let text = render(started: started, duration: duration, transcript: Transcript.render(Transcript.merge(a, b)))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let out = dir.appendingPathComponent("\(recordingID(started)).md")
        try text.write(to: out, atomically: true, encoding: .utf8)
        if ProcessInfo.processInfo.environment["NOTES_KEEP_AUDIO"] == nil {
            try? FileManager.default.removeItem(at: me)
            try? FileManager.default.removeItem(at: them)
        }
        return out
    }

    // Silent or sub-second channels (e.g. no one else on the call) are empty, not errors.
    private static func tokens(_ url: URL, system: Bool, _ t: ParakeetTranscriber) async throws -> [TimedToken] {
        guard let n = try? AVAudioFile(forReading: url).length, n >= 16_000 else { return [] }
        return try await t.transcribeTimed(url, system: system)
    }
}
