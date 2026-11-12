import Foundation
import Notes

// notesctl record <sec> [mic|sys] capture mic+system to $NOTES_DIR/.audio, then transcribe + save
// notesctl transcribe <me> <them> save a note from existing wavs (e.g. after a failed run)
// notesctl forget [--dry]         run the retention pass now
// notesctl detect                list processes capturing the mic, then print call start/stop events
let args = Array(CommandLine.arguments.dropFirst())

func save(_ started: Date, _ dur: TimeInterval, _ me: URL, _ them: URL) async {
    do { print(try await Store.finish(started: started, duration: dur, me: me, them: them).path) }
    catch { print("failed: \(error)"); exit(1) }
}

switch args.first {
case "record":
    let sec = Double(args.dropFirst().first ?? "10") ?? 10
    let started = Date()
    let dir = Store.dir.appendingPathComponent(".audio")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let id = UUID().uuidString
    let me = try MonoWriter(dir.appendingPathComponent("\(id).me.wav")), them = try MonoWriter(dir.appendingPathComponent("\(id).them.wav"))
    let mic = MicCapture(), sys = SystemCapture()
    let only = args.dropFirst(2).first
    if only != "mic" { try sys.start(them) }
    if only != "sys" { try mic.start(me) }
    print("recording \(Int(sec))s…")
    Thread.sleep(forTimeInterval: sec)
    if only != "sys" { mic.stop() }
    if only != "mic" { sys.stop() }
    me.close(); them.close()
    await save(started, sec, me.url, them.url)
case "transcribe" where args.count == 3:
    await save(Date(), 0, URL(fileURLWithPath: args[1]), URL(fileURLWithPath: args[2]))
case "forget":
    let dry = args.contains("--dry")
    Forget.run(dry: dry).forEach { print((dry ? "would forget " : "forgot ") + $0.lastPathComponent) }
case "detect":
    setvbuf(stdout, nil, _IOLBF, 0)
    print("capturing now:", MeetingDetector.capturing())
    let d = MeetingDetector()
    d.onChange = { print(Date(), $0 ? "call started" : "call ended", MeetingDetector.capturing()) }
    d.start()
    dispatchMain()
default:
    print("usage: notesctl record <sec> | transcribe <me.wav> <them.wav> | forget [--dry]")
}
