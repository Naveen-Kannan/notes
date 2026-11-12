import AVFoundation
import CoreAudio

public enum CaptureError: Error { case coreAudio(String, OSStatus), format }

/// Any PCM in, 16 kHz mono Int16 wav out.
public final class MonoWriter {
    static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    public let url: URL
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?

    public init(_ url: URL) throws {
        self.url = url
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
        ]
        file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    }

    func write(_ buf: AVAudioPCMBuffer) {
        guard let file, buf.frameLength > 0 else { return }
        if converter?.inputFormat != buf.format {
            converter = AVAudioConverter(from: buf.format, to: Self.format)
            converter?.downmix = true
        }
        guard let c = converter else { return }
        let cap = AVAudioFrameCount(Double(buf.frameLength) * 16_000 / buf.format.sampleRate) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: Self.format, frameCapacity: cap) else { return }
        var fed = false
        c.convert(to: out, error: nil) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true; status.pointee = .haveData; return buf
        }
        if out.frameLength > 0 { try? file.write(from: out) }
    }

    public func close() { file = nil }
}

/// Microphone with voice processing, so speaker bleed is cancelled out of "me".
public final class MicCapture {
    private let engine = AVAudioEngine()
    public init() {}

    public func start(_ w: MonoWriter) throws {
        let input = engine.inputNode
        if ProcessInfo.processInfo.environment["NOTES_NO_AEC"] == nil {
            try? input.setVoiceProcessingEnabled(true)
            input.voiceProcessingOtherAudioDuckingConfiguration = .init(enableAdvancedDucking: false, duckingLevel: .min)
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: input.outputFormat(forBus: 0)) { b, _ in w.write(b) }
        try engine.start()
    }

    public func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}

/// Everything the Mac plays (Zoom, Meet, ...) via a Core Audio process tap. No screen-recording permission.
public final class SystemCapture {
    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var agg = AudioObjectID(kAudioObjectUnknown)
    private var proc: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "com.nkannan.notes.tap", qos: .userInitiated)
    public init() {}

    public func start(_ w: MonoWriter) throws {
        var started = false
        defer { if !started { stop() } }
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.uuid = UUID()
        desc.isPrivate = true
        desc.muteBehavior = .unmuted
        try ok("create tap", AudioHardwareCreateProcessTap(desc, &tap))

        var asbd = AudioStreamBasicDescription()
        try ok("tap format", read(tap, kAudioTapPropertyFormat, &asbd))
        guard let fmt = AVAudioFormat(streamDescription: &asbd) else { throw CaptureError.format }

        let out = try outputUID()
        let d: [String: Any] = [
            kAudioAggregateDeviceNameKey: "notes-tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: out,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: out]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: desc.uuid.uuidString]],
        ]
        try ok("aggregate", AudioHardwareCreateAggregateDevice(d as CFDictionary, &agg))
        try ok("ioproc", AudioDeviceCreateIOProcIDWithBlock(&proc, agg, queue) { _, input, _, _, _ in
            guard let b = AVAudioPCMBuffer(pcmFormat: fmt, bufferListNoCopy: input, deallocator: nil) else { return }
            w.write(b)
        })
        try ok("start", AudioDeviceStart(agg, proc))
        started = true
    }

    public func stop() {
        if let proc { AudioDeviceStop(agg, proc); AudioDeviceDestroyIOProcID(agg, proc) }
        if agg != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(agg) }
        if tap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tap) }
        proc = nil; agg = kAudioObjectUnknown; tap = kAudioObjectUnknown
    }

    private func outputUID() throws -> String {
        var dev = AudioObjectID(kAudioObjectUnknown)
        try ok("output device", read(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultSystemOutputDevice, &dev))
        var uid: Unmanaged<CFString>?
        try ok("output uid", read(dev, kAudioDevicePropertyDeviceUID, &uid))
        guard let uid else { throw CaptureError.format }
        return uid.takeRetainedValue() as String
    }
}

private func read<T>(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector, _ v: inout T) -> OSStatus {
    var addr = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var size = UInt32(MemoryLayout<T>.size)
    return AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &v)
}

private func ok(_ what: String, _ s: OSStatus) throws {
    if s != noErr { throw CaptureError.coreAudio(what, s) }
}
