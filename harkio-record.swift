// harkio.swift — record what your Mac is playing to a WAV file, using Apple's
// Core Audio Taps API (macOS 14.2+). No virtual audio driver needed.
//
// BUILD (needs Xcode Command Line Tools: `xcode-select --install`):
//   swiftc -O harkio-record.swift -o harkio-record
//
// USAGE
//   harkio record --list                 list processes using audio (run while the voice is speaking)
//   harkio record out.wav [options]      record (Ctrl-C to stop early)
//
// OPTIONS
//   --process NAME     only record processes whose name or bundle ID contains NAME
//                      (repeatable; default: record everything the Mac plays)
//   --wait             don't start writing until sound begins
//   --stop-after SEC   stop after SEC seconds of silence (counted once sound has started)
//   --max SEC          stop after SEC seconds no matter what (default 600)
//   --threshold DB     level below which audio counts as silence, in dBFS (default -60)
//   --mute             silence the recorded audio on your speakers while still capturing it
//
// PERMISSION
//   The first run should ask to let Terminal record system audio. If you only get silence:
//   System Settings > Privacy & Security > Screen & System Audio Recording >
//   "System Audio Recording Only" — add Terminal there.

import Foundation
import CoreAudio
import AVFoundation

// MARK: - Small helpers

func info(_ msg: String) {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
}

func fail(_ msg: String, code: Int32 = 1) -> Never {
    info("harkio: " + msg)
    exit(code)
}

func check(_ status: OSStatus, _ what: String) {
    if status != noErr { fail("\(what) failed (OSStatus \(status))") }
}

func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector,
                               mScope: kAudioObjectPropertyScopeGlobal,
                               mElement: kAudioObjectPropertyElementMain)
}

func getValue<T>(_ obj: AudioObjectID, _ selector: AudioObjectPropertySelector, _ initial: T) -> T? {
    var addr = address(selector)
    var value = initial
    var size = UInt32(MemoryLayout<T>.size)
    let status = withUnsafeMutablePointer(to: &value) {
        AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, $0)
    }
    return status == noErr ? value : nil
}

func getString(_ obj: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
    var addr = address(selector)
    var value: Unmanaged<CFString>? = nil
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let status = AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &value)
    guard status == noErr, let v = value else { return nil }
    return v.takeRetainedValue() as String
}

func getObjectList(_ obj: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
    var addr = address(selector)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(obj, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
    var list = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &list) == noErr else { return [] }
    return list
}

func processName(_ pid: pid_t) -> String {
    var buf = [CChar](repeating: 0, count: 4096)
    guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return "pid \(pid)" }
    return URL(fileURLWithPath: String(cString: buf)).lastPathComponent
}

// MARK: - Audio processes

struct AudioProcess {
    let objectID: AudioObjectID
    let pid: pid_t
    let name: String
    let bundleID: String
    let isPlaying: Bool
}

@available(macOS 14.2, *)
func audioProcesses() -> [AudioProcess] {
    getObjectList(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList).map { id in
        let pid = getValue(id, kAudioProcessPropertyPID, pid_t(-1)) ?? -1
        let playing = (getValue(id, kAudioProcessPropertyIsRunningOutput, UInt32(0)) ?? 0) != 0
        return AudioProcess(objectID: id,
                            pid: pid,
                            name: processName(pid),
                            bundleID: getString(id, kAudioProcessPropertyBundleID) ?? "",
                            isPlaying: playing)
    }
}

// MARK: - Level metering

func peakLevel(_ buffer: AVAudioPCMBuffer) -> Float {
    guard let data = buffer.floatChannelData else { return 0 }
    let interleaved = buffer.format.isInterleaved
    let channels = interleaved ? 1 : Int(buffer.format.channelCount)
    let samples = Int(buffer.frameLength) * (interleaved ? Int(buffer.format.channelCount) : 1)
    var peak: Float = 0
    for c in 0..<channels {
        let p = data[c]
        for i in 0..<samples { peak = max(peak, abs(p[i])) }
    }
    return peak
}

// MARK: - Main

@available(macOS 14.2, *)
func run() {
    var args = Array(CommandLine.arguments.dropFirst())

    if args.first == "--list" {
        let procs = audioProcesses()
        if procs.isEmpty { print("No processes are using audio right now."); return }
        print("PLAYING  PID     NAME                           BUNDLE ID")
        for p in procs.sorted(by: { ($0.isPlaying ? 0 : 1, $0.name) < ($1.isPlaying ? 0 : 1, $1.name) }) {
            let name = p.name.padding(toLength: 30, withPad: " ", startingAt: 0)
            print("\(p.isPlaying ? "  yes  " : "       ")  \(String(p.pid).padding(toLength: 6, withPad: " ", startingAt: 0))  \(name) \(p.bundleID)")
        }
        return
    }

    guard let outPath = args.first, !outPath.hasPrefix("--") else {
        fail("usage: harkio out.wav [--process NAME] [--wait] [--stop-after SEC] [--max SEC] [--threshold DB] [--mute]\n       harkio --list")
    }
    args.removeFirst()

    var processFilters: [String] = []
    var waitForSound = false
    var stopAfter: Double? = nil
    var maxSeconds: Double = 600
    var thresholdDB: Double = -60
    var mute = false

    func number(_ s: String?, _ flag: String) -> Double {
        guard let s = s, let v = Double(s) else { fail("\(flag) needs a number") }
        return v
    }
    var i = 0
    while i < args.count {
        let a = args[i]
        let next: String? = i + 1 < args.count ? args[i + 1] : nil
        switch a {
        case "--process":    guard let n = next else { fail("--process needs a name") }
                             processFilters.append(n.lowercased()); i += 1
        case "--wait":       waitForSound = true
        case "--mute":       mute = true
        case "--stop-after": stopAfter = number(next, a); i += 1
        case "--max":        maxSeconds = number(next, a); i += 1
        case "--threshold":  thresholdDB = number(next, a); i += 1
        default:             fail("unknown option \(a)")
        }
        i += 1
    }

    // 1. Describe the tap: everything, or only the chosen processes.
    let tapDesc: CATapDescription
    if processFilters.isEmpty {
        tapDesc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
    } else {
        let matches = audioProcesses().filter { p in
            processFilters.contains { f in p.name.lowercased().contains(f) || p.bundleID.lowercased().contains(f) }
        }
        if matches.isEmpty {
            fail("no audio process matches \(processFilters). Run `harkio --list` while the voice is speaking to find its name.")
        }
        info("Recording from: " + matches.map { "\($0.name) (\($0.pid))" }.joined(separator: ", "))
        tapDesc = CATapDescription(stereoMixdownOfProcesses: matches.map { $0.objectID })
    }
    tapDesc.uuid = UUID()
    tapDesc.name = "harkio"
    tapDesc.isPrivate = true
    tapDesc.muteBehavior = mute ? .muted : .unmuted

    var tapID = AudioObjectID(kAudioObjectUnknown)
    check(AudioHardwareCreateProcessTap(tapDesc, &tapID), "Creating the audio tap")

    // 2. Wrap the tap in a private aggregate device so we can read from it.
    guard let outputDevice = getValue(AudioObjectID(kAudioObjectSystemObject),
                                      kAudioHardwarePropertyDefaultSystemOutputDevice,
                                      AudioObjectID(kAudioObjectUnknown)),
          let outputUID = getString(outputDevice, kAudioDevicePropertyDeviceUID) else {
        fail("couldn't find the default output device")
    }
    let aggDesc: [String: Any] = [
        kAudioAggregateDeviceNameKey: "harkio",
        kAudioAggregateDeviceUIDKey: UUID().uuidString,
        kAudioAggregateDeviceMainSubDeviceKey: outputUID,
        kAudioAggregateDeviceIsPrivateKey: true,
        kAudioAggregateDeviceIsStackedKey: false,
        kAudioAggregateDeviceTapAutoStartKey: true,
        kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
        kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                           kAudioSubTapUIDKey: tapDesc.uuid.uuidString]],
    ]
    var aggID = AudioObjectID(kAudioObjectUnknown)
    check(AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &aggID), "Creating the aggregate device")

    // 3. Open the output file in the tap's format (written as 24-bit WAV).
    guard var asbd = getValue(tapID, kAudioTapPropertyFormat, AudioStreamBasicDescription()),
          let format = AVAudioFormat(streamDescription: &asbd) else {
        fail("couldn't read the tap's audio format")
    }
    let url = URL(fileURLWithPath: outPath)
    let fileSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: format.sampleRate,
        AVNumberOfChannelsKey: format.channelCount,
        AVLinearPCMBitDepthKey: 24,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]
    var file: AVAudioFile?
    do {
        file = try AVAudioFile(forWriting: url, settings: fileSettings,
                               commonFormat: format.commonFormat, interleaved: format.isInterleaved)
    } catch {
        fail("couldn't create \(outPath): \(error.localizedDescription)")
    }

    // 4. Read audio as it arrives and write it out.
    let ioQueue = DispatchQueue(label: "harkio.io")
    let done = DispatchSemaphore(value: 0)
    let threshold = Float(pow(10, thresholdDB / 20))
    let sampleRate = format.sampleRate
    var started = !waitForSound
    var finished = false
    var silentSeconds = 0.0
    var writeError: Error? = nil

    var procID: AudioDeviceIOProcID?
    check(AudioDeviceCreateIOProcIDWithBlock(&procID, aggID, ioQueue) { _, inputData, _, _, _ in
        guard !finished, let f = file,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: inputData, deallocator: nil),
              buffer.frameLength > 0 else { return }
        let loud = peakLevel(buffer) > threshold
        if !started {
            guard loud else { return }
            started = true
            info("Sound detected — recording.")
        }
        do { try f.write(from: buffer) } catch {
            writeError = error; finished = true; done.signal(); return
        }
        silentSeconds = loud ? 0 : silentSeconds + Double(buffer.frameLength) / sampleRate
        if let limit = stopAfter, silentSeconds >= limit {
            finished = true
            done.signal()
        }
    }, "Creating the audio callback")

    // Ctrl-C stops cleanly.
    signal(SIGINT, SIG_IGN)
    let sigSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
    sigSource.setEventHandler { done.signal() }
    sigSource.resume()

    check(AudioDeviceStart(aggID, procID), "Starting capture")
    if !waitForSound { info("Recording… (Ctrl-C to stop)") }

    if done.wait(timeout: .now() + maxSeconds) == .timedOut {
        info("Reached the \(Int(maxSeconds))s limit.")
    }

    // 5. Tear everything down.
    AudioDeviceStop(aggID, procID)
    var didStart = false
    ioQueue.sync {
        finished = true
        didStart = started
    }
    if let p = procID { AudioDeviceDestroyIOProcID(aggID, p) }
    AudioHardwareDestroyAggregateDevice(aggID)
    AudioHardwareDestroyProcessTap(tapID)
    ioQueue.sync { file = nil }   // closes the WAV file

    if let e = writeError { fail("write failed: \(e.localizedDescription)") }
    if !didStart {
        try? FileManager.default.removeItem(at: url)
        fail("no sound was detected, so nothing was saved. (If audio was playing, check the System Audio Recording permission.)", code: 2)
    }
    info("Saved \(outPath)")
}

if #available(macOS 14.2, *) {
    run()
} else {
    fail("needs macOS 14.2 or newer (Core Audio Taps).")
}
