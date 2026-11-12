import Foundation
import os

private let log = Logger(subsystem: "com.nkannan.notes", category: "meeting")

/// hkd module: auto-records while a call app holds the mic; `notes.toggle` is the manual override.
/// Also runs `Forget` daily.
@MainActor
public final class NotesSession {
    private struct Live { let auto: Bool; let started: Date; let me: MonoWriter; let them: MonoWriter; let mic: MicCapture; let sys: SystemCapture }
    private var live: Live?
    private var forgetTimer: DispatchSourceTimer?
    private let detector = MeetingDetector()
    private var pending: DispatchWorkItem?
    // Start only after the mic has been held a few seconds (skips mic tests); stop after a grace period
    // so a brief mic release (mute, device switch) doesn't split one meeting into two files.
    static let startDelay = 3.0, stopDelay = 30.0

    public init() {}

    public func watchMeetings() {
        guard ProcessInfo.processInfo.environment["NOTES_AUTO"] != "0" else { return }
        detector.onChange = { [weak self] on in DispatchQueue.main.async { MainActor.assumeIsolated { self?.meeting(on) } } }
        detector.start()
    }

    private func meeting(_ on: Bool) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.detector.active == on else { return }
                if on { self.start(auto: true) } else if self.live?.auto == true { self.stop() }
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (on ? Self.startDelay : Self.stopDelay), execute: work)
    }

    public var isLive: Bool { live != nil }

    public func toggle() { live == nil ? start() : stop() }

    public func start(auto: Bool = false) {
        guard live == nil else { return }
        let started = Date()
        let base = Store.audio.appendingPathComponent(Store.recordingID(started))
        do {
            try FileManager.default.createDirectory(at: Store.audio, withIntermediateDirectories: true)
            let me = try MonoWriter(base.appendingPathExtension("me.wav"))
            let them = try MonoWriter(base.appendingPathExtension("them.wav"))
            let mic = MicCapture(), sys = SystemCapture()
            try sys.start(them)
            do { try mic.start(me) } catch { sys.stop(); throw error }
            live = Live(auto: auto, started: started, me: me, them: them, mic: mic, sys: sys)
            log.notice("meeting started (\(auto ? "auto" : "manual", privacy: .private))")
        } catch {
            log.error("start failed: \(String(describing: error), privacy: .private)")
        }
    }

    public func stop() {
        guard let l = live else { return }
        live = nil
        l.mic.stop(); l.sys.stop()
        l.me.close(); l.them.close()
        let duration = Date().timeIntervalSince(l.started)
        Task.detached {
            do {
                let out = try await Store.finish(started: l.started, duration: duration, me: l.me.url, them: l.them.url)
                log.notice("meeting saved: \(out.path, privacy: .private)")
            } catch {
                log.error("transcribe failed, audio kept: \(String(describing: error), privacy: .private)")
            }
        }
    }

    public func scheduleForget() {
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        t.schedule(deadline: .now() + 60, repeating: 86_400)
        t.setEventHandler {
            let gone = Forget.run()
            if !gone.isEmpty { log.notice("forgot \(gone.count) note(s)") }
        }
        t.resume()
        forgetTimer = t
    }
}

public struct NotesCommands {
    public let name = "notes"
    public let commands: [String: () -> Void]

    @MainActor
    public init(session: NotesSession? = nil) {
        let session = session ?? NotesSession()
        session.scheduleForget()
        session.watchMeetings()
        commands = [
            "notes.toggle": { DispatchQueue.main.async { MainActor.assumeIsolated { session.toggle() } } },
        ]
    }
}
