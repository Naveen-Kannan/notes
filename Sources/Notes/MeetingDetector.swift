import CoreAudio
import Foundation

/// Fires when a call app starts/stops capturing the mic. Core Audio process objects (macOS 14.4+),
/// event-driven listeners, no polling.
public final class MeetingDetector {
    // Prefix match: browsers capture from helper processes (e.g. com.google.Chrome.helper).
    static let apps = [
        "us.zoom.xos", "com.microsoft.teams", "com.apple.FaceTime", "com.apple.avconferenced", "com.tinyspeck.slackmacgap", "com.hnc.Discord",
        "com.google.Chrome", "company.thebrowser.Browser", "com.brave.Browser", "com.microsoft.edgemac",
        "org.mozilla.firefox", "com.apple.Safari", "com.apple.WebKit",
    ]

    public var onChange: ((Bool) -> Void)?
    public private(set) var active = false
    private let queue = DispatchQueue(label: "com.nkannan.notes.detect")
    private var watched = Set<AudioObjectID>()
    private lazy var listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.refresh() }

    public init() {}

    public func start() {
        var a = address(kAudioHardwarePropertyProcessObjectList)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, queue, listener)
        queue.async { self.refresh() }
    }

    /// Bundle IDs of every process currently capturing audio input (for `notesctl detect`).
    public static func capturing() -> [String] {
        processes().filter(runningInput).map { bundleID($0) ?? "?" }
    }

    static func isCallApp(_ id: String) -> Bool { apps.contains { id.hasPrefix($0) } }

    private func refresh() {
        let procs = Self.processes()
        for p in procs where !watched.contains(p) {
            var a = address(kAudioProcessPropertyIsRunningInput)
            AudioObjectAddPropertyListenerBlock(p, &a, queue, listener)
            watched.insert(p)
        }
        watched.formIntersection(procs)
        let now = procs.contains { Self.runningInput($0) && Self.bundleID($0).map(Self.isCallApp) == true }
        if now != active { active = now; onChange?(now) }
    }

    private static func processes() -> Set<AudioObjectID> {
        var a = address(kAudioHardwarePropertyProcessObjectList)
        let sys = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(sys, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(sys, &a, 0, nil, &size, &ids) == noErr else { return [] }
        return Set(ids)
    }

    private static func runningInput(_ p: AudioObjectID) -> Bool {
        var a = address(kAudioProcessPropertyIsRunningInput)
        var v: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(p, &a, 0, nil, &size, &v) == noErr && v != 0
    }

    private static func bundleID(_ p: AudioObjectID) -> String? {
        var a = address(kAudioProcessPropertyBundleID)
        var v: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(p, &a, 0, nil, &size, &v) == noErr, let v else { return nil }
        return v.takeRetainedValue() as String
    }
}

private func address(_ sel: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
}
