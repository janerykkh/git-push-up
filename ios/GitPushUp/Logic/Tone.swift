import AVFoundation
import Foundation

/// Töne für die Meditation: ein Gong (auch im Stumm-Modus hörbar) und ein unhörbarer Dauerton,
/// damit der Timer bei gesperrtem Bildschirm weiterläuft (Hintergrund-Audio ist erlaubt).
final class Tone {
    private var keepAlive: AVAudioPlayer?
    private var gongPlayer: AVAudioPlayer?

    init() {
        if let d = Self.bell() { gongPlayer = try? AVAudioPlayer(data: d); gongPlayer?.prepareToPlay() }
    }

    func activate() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? s.setActive(true)
    }

    func startKeepAlive() {
        activate()
        guard let d = Self.wav(samples: [Int16](repeating: 0, count: 44_100)) else { return }
        keepAlive = try? AVAudioPlayer(data: d)
        keepAlive?.numberOfLoops = -1
        keepAlive?.volume = 0.01
        keepAlive?.play()
    }

    func stopKeepAlive() {
        keepAlive?.stop(); keepAlive = nil
    }

    func gong() {
        activate()
        gongPlayer?.currentTime = 0
        gongPlayer?.play()
    }

    func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    /// Klangschalen-ähnlicher Ton: Grundton mit unharmonischen Obertönen, langsam ausklingend
    private static func bell() -> Data? {
        let rate = 44_100.0, seconds = 4.5
        let n = Int(rate * seconds)
        let partials: [(f: Double, a: Double, decay: Double)] = [(196, 0.55, 1.6), (196 * 2.76, 0.25, 1.0), (196 * 5.4, 0.12, 0.6), (198.5, 0.3, 1.8)]
        var out = [Int16](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / rate
            var v = 0.0
            for p in partials { v += p.a * sin(2 * .pi * p.f * t) * exp(-t / p.decay) }
            let attack = min(1, t / 0.008)
            out[i] = Int16(max(-32767, min(32767, v * attack * 0.8 * 32767)))
        }
        return wav(samples: out)
    }

    static func wav(samples: [Int16], rate: Int = 44_100) -> Data? {
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        let bytes = UInt32(samples.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes)
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate * 2)); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(bytes)
        samples.withUnsafeBufferPointer { buf in
            d.append(Data(buffer: buf))
        }
        return d
    }
}
