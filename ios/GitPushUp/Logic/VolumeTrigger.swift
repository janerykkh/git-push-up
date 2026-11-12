import AVFoundation
import Foundation

/// Erkennt das Signal "leiser + lauter" (oder umgekehrt) kurz hintereinander an den Lautstärketasten,
/// auch an den Plus-Minus-Tasten der EarPods. Normales Lauter- oder Leiserstellen löst nichts aus,
/// und nach dem Signal ist die Lautstärke wieder genau wie vorher.
final class VolumeTrigger: NSObject, ObservableObject {
    /// Zeitpunkt des ersten Tastendrucks im Signal, auf dem Hauptthread
    var onTrigger: ((Date) -> Void)?
    @Published var volume: Float = 0.5

    private var observation: NSKeyValueObservation?
    private var lastChange: (dir: Int, at: Date)? = nil
    private var lastValue: Float = 0.5
    private let window: TimeInterval = 0.7

    func start() {
        let s = AVAudioSession.sharedInstance()
        // Mischen statt unterbrechen: deine Musik aus einer anderen App läuft weiter
        try? s.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? s.setActive(true)
        lastValue = s.outputVolume
        volume = lastValue
        observation = s.observe(\.outputVolume, options: [.new]) { [weak self] session, _ in
            DispatchQueue.main.async { self?.changed(session.outputVolume) }
        }
    }

    func stop() {
        observation?.invalidate()
        observation = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func changed(_ v: Float) {
        let dir = v > lastValue ? 1 : (v < lastValue ? -1 : 0)
        lastValue = v
        volume = v
        guard dir != 0 else { return }
        let now = Date()
        if let prev = lastChange, prev.dir == -dir, now.timeIntervalSince(prev.at) <= window {
            lastChange = nil
            onTrigger?(prev.at)
        } else {
            lastChange = (dir, now)
        }
    }
}
