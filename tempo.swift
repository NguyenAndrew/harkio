// tempo.swift — change the speed of an audio file without changing its pitch,
// using Apple's built-in time-stretching (AVAudioUnitTimePitch).
//
// Build:  swiftc -O tempo.swift -o tempo
// Usage:  ./tempo in.wav out.wav SPEED      (SPEED 0.5 = half speed, 1.2 = 20% faster)

import Foundation
import AVFoundation

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(("tempo: " + msg + "\n").data(using: .utf8)!)
    exit(1)
}

let args = CommandLine.arguments
guard args.count == 4, let speed = Float(args[3]), speed >= 0.25, speed <= 4 else {
    fail("usage: tempo in.wav out.wav SPEED   (SPEED between 0.25 and 4)")
}

do {
    let input = try AVAudioFile(forReading: URL(fileURLWithPath: args[1]))
    let format = input.processingFormat

    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    let timePitch = AVAudioUnitTimePitch()
    timePitch.rate = speed
    timePitch.overlap = 16        // higher quality for speech (default is 8)

    engine.attach(player)
    engine.attach(timePitch)
    engine.connect(player, to: timePitch, format: format)
    engine.connect(timePitch, to: engine.mainMixerNode, format: format)
    try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
    try engine.start()
    player.scheduleFile(input, at: nil)
    player.play()

    let output = try AVAudioFile(forWriting: URL(fileURLWithPath: args[2]),
                                 settings: input.fileFormat.settings,
                                 commonFormat: format.commonFormat,
                                 interleaved: format.isInterleaved)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat,
                                        frameCapacity: engine.manualRenderingMaximumFrameCount) else {
        fail("couldn't allocate an audio buffer")
    }

    // Expected output length, plus a little tail so the last word isn't cut off.
    let target = AVAudioFramePosition(Double(input.length) / Double(speed)) + AVAudioFramePosition(format.sampleRate * 0.2)
    while engine.manualRenderingSampleTime < target {
        let remaining = AVAudioFrameCount(target - engine.manualRenderingSampleTime)
        let status = try engine.renderOffline(min(buffer.frameCapacity, remaining), to: buffer)
        switch status {
        case .success:
            try output.write(from: buffer)
        case .insufficientDataFromInputNode, .cannotDoInCurrentContext:
            continue
        case .error:
            fail("rendering failed")
        @unknown default:
            fail("rendering failed (unknown status)")
        }
    }
    player.stop()
    engine.stop()
} catch {
    fail(error.localizedDescription)
}
