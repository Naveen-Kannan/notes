import Flow
import Foundation
import Testing
@testable import Notes

private func tok(_ s: String, _ a: Double, _ b: Double) -> TimedToken { TimedToken(text: s, start: a, end: b) }

@Test func splitsOnPausesAtWordBoundaries() {
    let t = [tok(" Hel", 0, 0.2), tok("lo", 0.2, 0.4), tok(" there", 0.5, 0.8), tok(" Next", 3, 3.2), tok("ish", 4.5, 4.7)]
    let l = Transcript.lines(t, who: "me")
    #expect(l.map(\.text) == ["Hello there", "Nextish"])
    #expect(l.map(\.start) == [0, 3])
}

@Test func mergesChannelsByTime() {
    let a = [Line(who: "me", start: 0, text: "hi"), Line(who: "me", start: 10, text: "bye")]
    let b = [Line(who: "them", start: 4, text: "yo")]
    #expect(Transcript.render(Transcript.merge(a, b)) == "[00:00] me: hi\n[00:04] them: yo\n[00:10] me: bye")
    #expect(Transcript.stamp(3725) == "1:02:05")
}

@Test func forgetSkipsKeptAndFresh() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let old = Date().addingTimeInterval(-30 * 86_400)
    func make(_ name: String, _ body: String, _ m: Date) throws {
        let u = dir.appendingPathComponent(name)
        try body.write(to: u, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: m], ofItemAtPath: u.path)
    }
    try make("a.md", "---\nstatus: raw\n---\nx", old)
    try make("b.md", "---\nkeep: true\n---\nx", old)
    try make("c.md", "---\nstatus: raw\n---\nx", Date())
    #expect(Forget.run(dir: dir, days: 21, dry: true).map(\.lastPathComponent) == ["a.md"])
}

@Test func rendersFrontMatter() {
    let d = DateComponents(calendar: .current, year: 2026, month: 11, day: 11, hour: 14, minute: 5).date!
    let s = Store.render(started: d, duration: 1500, transcript: "[00:00] me: hi")
    #expect(s.hasPrefix("---\ndate: 2026-11-11 14:05\nduration: 25m\nstatus: raw\n---\n\n## Transcript\n[00:00] me: hi\n"))
}

@Test func matchesCallApps() {
    #expect(MeetingDetector.isCallApp("us.zoom.xos"))
    #expect(MeetingDetector.isCallApp("com.google.Chrome.helper"))
    #expect(!MeetingDetector.isCallApp("com.nkannan.hkd"))
}

@Test func recordingNamesDoNotCollideWithinOneMinute() {
    let now = Date()
    #expect(Store.recordingID(now) != Store.recordingID(now))
    #expect(Store.recordingID(now).hasPrefix(Store.stamp(now)))
}
