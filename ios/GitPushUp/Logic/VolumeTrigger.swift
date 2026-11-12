import AVFoundation
import Foundation

/// Erkennt ein Signal an den Lautstärketasten (auch an den Plus-Minus-Tasten der EarPods):
/// beide Tasten gleichzeitig, oder leiser + lauter kurz hintereinander. Normales Lauter- oder Leiserstellen
/// löst nichts aus, und nach dem Signal ist die Lautstärke wieder wie vorher.
/// Solange aktiv, läuft ein unhörbarer Ton, damit iOS die App auch bei gesperrtem Bildschirm weiterlaufen lässt.
final class VolumeTrigger: NSObject, ObservableObject {
    /// Zeitpunkt des ersten Tastendrucks im Signal, auf dem Hauptthread
    var onTrigger: ((Date) -> Void)?
    @Published var volume: Float = 0.5

    private var observation: NSKeyValueObservation?
    private var lastChange: (dir: Int, at: Date)? = nil
    private var lastValue: Float = 0.5
    private let window: TimeInterval = 0.7
    private var keepAlive: AVAudioPlayer?
    private var beeper: AVAudioPlayer?

    func start() {
        let s = AVAudioSession.sharedInstance()
        // Mischen statt unterbrechen: Musik aus einer anderen App läuft weiter
        try? s.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? s.setActive(true)
        lastValue = s.outputVolume
        volume = lastValue
        observation = s.observe(\.outputVolume, options: [.new]) { [weak self] session, _ in
            let v = session.outputVolume
            DispatchQueue.main.async { self?.changed(v) }
        }
        if let silence = Self.wav(seconds: 1, frequency: 0, amplitude: 0) {
            keepAlive = try? AVAudioPlayer(data: silence)
            keepAlive?.numberOfLoops = -1
            keepAlive?.volume = 0.01
            keepAlive?.play()
        }
        if let tone = Self.wav(seconds: 0.18, frequency: 1320, amplitude: 0.6) {
            beeper = try? AVAudioPlayer(data: tone)
            beeper?.prepareToPlay()
        }
    }

    func stop() {
        keepAlive?.stop(); keepAlive = nil
        observation?.invalidate(); observation = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    /// Kurzer Piepton, hörbar auch im Stumm-Modus und über die EarPods
    func beep() {
        beeper?.currentTime = 0
        beeper?.play()
    }

    private func changed(_ v: Float) {
        let dir = v > lastValue ? 1 : (v < lastValue ? -1 : 0)
        lastValue = v
        volume = v
        guard dir != 0 else { return }
        let now = Date()
        // Beide Tasten gleichzeitig oder kurz hintereinander: zwei gegenläufige Änderungen innerhalb von 0,7 s
        if let prev = lastChange, prev.dir == -dir, now.timeIntervalSince(prev.at) <= window {
            lastChange = nil
            onTrigger?(prev.at)
        } else {
            lastChange = (dir, now)
        }
    }

    /// Erzeugt eine kleine WAV-Datei im Speicher (16 Bit, mono). frequency 0 = Stille.
    private static func wav(seconds: Double, frequency: Double, amplitude: Double) -> Data? {
        let rate = 44_100
        let n = Int(Double(rate) * seconds)
        var samples = [Int16](repeating: 0, count: n)
        if frequency > 0 {
            let fade = Int(Double(rate) * 0.01)
            for i in 0..<n {
                var a = amplitude
                if i < fade { a *= Double(i) / Double(fade) }
                if i > n - fade { a *= Double(n - i) / Double(fade) }
                samples[i] = Int16(max(-32767, min(32767, sin(2 * .pi * frequency * Double(i) / Double(rate)) * a * 32767)))
            }
        }
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        let dataBytes = UInt32(n * 2)
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + dataBytes)
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate * 2)); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(dataBytes)
        samples.withUnsafeBufferPointer { buf in
            for s in buf { var x = s.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        }
        return d
    }
}
