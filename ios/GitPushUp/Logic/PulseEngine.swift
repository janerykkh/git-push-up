import AVFoundation
import CoreMotion
import Foundation

/// Puls über Kamera und Blitz (Photoplethysmographie): mit jedem Herzschlag ändert sich die Helligkeit
/// des durchleuchteten Fingers um etwa ein Prozent.
///
/// Ablauf: Finger erkannt → Einschwingen (Finger liegt ruhig, Helligkeit stabil, iPhone bewegt sich nicht)
/// → erst dann beginnt die eigentliche Messung. Wackeln während der Messung startet sie neu.
/// Am Ende zwei unabhängige Schätzungen über das ganze Fenster: Autokorrelation und Abstand der einzelnen Schläge
/// (an der steilen Anstiegsflanke, nicht am Gipfel, damit Doppelgipfel nicht doppelt zählen). Nur wenn beide
/// übereinstimmen, gilt das Ergebnis als sicher; sonst wird bis zu 35 Sekunden weitergemessen.
final class PulseEngine: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    enum Phase: Equatable {
        case noFinger
        case settling(Double)       // 0…1 bis die Messung beginnt
        case measuring(Double)      // 0…1 der Messdauer
        case done(Int, Double)      // Puls, Güte 0…1
    }

    struct Live {
        var phase: Phase = .noFinger
        var bpm: Int? = nil          // vorläufiger Wert während der Messung
        var wave: [Double] = []      // letzte Sekunden des gefilterten Signals
        var beats: [Int] = []        // Schläge (Indizes in wave)
        var note: String? = nil      // z. B. "Bewegung erkannt"
    }

    @Published var live = Live()
    @Published var permissionDenied = false
    /// Auf dem Hauptthread: Puls, Güte
    var onResult: ((Int, Double) -> Void)?

    /// Länge der sauberen Messung in Sekunden
    var measureSeconds: Double = 20

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "pulse.processing")
    private let motion = CMMotionManager()
    private var device: AVCaptureDevice?

    // Nur auf `queue`
    private var lastAccel = 0.0
    private var accelWindow: [Double] = []
    private var contactSince: Double? = nil
    private var settleT: [Double] = [], settleR: [Double] = []
    private var stableSince: Double? = nil
    private var recStart: Double? = nil
    private var times: [Double] = [], red: [Double] = [], green: [Double] = []
    private var lastLive = 0.0
    private var finished = false
    private var noteUntil = 0.0
    private var note: String? = nil

    private let fs = 30.0

    // MARK: Start / Stopp

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { ok in
            guard ok else { DispatchQueue.main.async { self.permissionDenied = true }; return }
            self.queue.async { self.configureAndRun() }
        }
        let opQueue = OperationQueue()
        opQueue.underlyingQueue = queue
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 1.0 / 60
            motion.startDeviceMotionUpdates(to: opQueue) { [weak self] m, _ in
                guard let self, let a = m?.userAcceleration else { return }
                let mag = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
                self.lastAccel = mag
                self.accelWindow.append(mag)
                if self.accelWindow.count > 60 { self.accelWindow.removeFirst(self.accelWindow.count - 60) }
            }
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        queue.async {
            self.setTorch(false)
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    /// Neue Messung (Finger darf liegen bleiben)
    func reset() {
        queue.async {
            self.restartSettling(note: nil, now: 0)
            self.finished = false
        }
    }

    private func configureAndRun() {
        if session.inputs.isEmpty {
            session.beginConfiguration()
            session.sessionPreset = .low
            guard let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: dev), session.canAddInput(input) else {
                session.commitConfiguration(); return
            }
            session.addInput(input)
            let out = AVCaptureVideoDataOutput()
            out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            out.alwaysDiscardsLateVideoFrames = true
            out.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(out) { session.addOutput(out) }
            session.commitConfiguration()
            device = dev
            // Feste 30 Bilder pro Sekunde, sonst verrutscht die Zeitachse
            if (try? dev.lockForConfiguration()) != nil {
                let ok = dev.activeFormat.videoSupportedFrameRateRanges.contains { $0.minFrameRate <= 30 && $0.maxFrameRate >= 30 }
                if ok {
                    dev.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
                    dev.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
                }
                dev.unlockForConfiguration()
            }
        }
        if !session.isRunning { session.startRunning() }
        setTorch(true)
    }

    private func setTorch(_ on: Bool) {
        guard let d = device, d.hasTorch, (try? d.lockForConfiguration()) != nil else { return }
        if on {
            try? d.setTorchModeOn(level: 0.6)
            let bias = max(d.minExposureTargetBias, min(d.maxExposureTargetBias, -1.0))
            d.setExposureTargetBias(bias, completionHandler: nil)
            if d.isFocusModeSupported(.locked) { d.focusMode = .locked }
        } else {
            d.torchMode = .off
        }
        d.unlockForConfiguration()
    }

    // MARK: Bilder

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let px = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        CVPixelBufferLockBaseAddress(px, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(px, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(px) else { return }
        let w = CVPixelBufferGetWidth(px), h = CVPixelBufferGetHeight(px), row = CVPixelBufferGetBytesPerRow(px)
        let p = base.assumingMemoryBound(to: UInt8.self)
        var sr = 0.0, sg = 0.0, sb = 0.0, n = 0.0
        var y = h / 4
        while y < h * 3 / 4 {
            var x = w / 4
            while x < w * 3 / 4 {
                let o = y * row + x * 4
                sb += Double(p[o]); sg += Double(p[o + 1]); sr += Double(p[o + 2]); n += 1
                x += 3
            }
            y += 3
        }
        guard n > 0 else { return }
        process(t: t, r: sr / n, g: sg / n, b: sb / n)
    }

    private func restartSettling(note: String?, now: Double) {
        stableSince = nil
        recStart = nil
        times = []; red = []; green = []
        if let note { self.note = note; noteUntil = now + 2.5 }
    }

    private func process(t: Double, r: Double, g: Double, b: Double) {
        if finished { return }
        // Finger vor der Linse, vom Blitz durchleuchtet → stark rot
        let contact = r > 60 && r > g * 1.6 && r > b * 1.6
        if !contact {
            contactSince = nil
            settleT = []; settleR = []
            restartSettling(note: nil, now: t)
            publish(Live(phase: .noFinger))
            return
        }
        if contactSince == nil { contactSince = t }
        settleT.append(t); settleR.append(r)
        while let f = settleT.first, t - f > 1.0 { settleT.removeFirst(); settleR.removeFirst() }

        let motionRMS = rms(accelWindow.suffix(30))
        let mean = settleR.reduce(0, +) / Double(max(1, settleR.count))
        let range = ((settleR.max() ?? 0) - (settleR.min() ?? 0)) / max(1, mean)
        let calm = motionRMS < 0.04 && range < 0.04 && t - (contactSince ?? t) > 1.5

        if recStart == nil {
            // Einschwingen: erst 1 Sekunde durchgehend ruhig
            if calm {
                if stableSince == nil { stableSince = t }
                let p = min(1, (t - stableSince!) / 1.0)
                if p >= 1 { recStart = t; times = []; red = []; green = [] }
                publish(Live(phase: .settling(p), note: currentNote(t)))
            } else {
                stableSince = nil
                publish(Live(phase: .settling(0), note: currentNote(t)))
            }
            if recStart == nil { return }
        }

        // Während der Messung: Ruck oder Druckänderung → neu einschwingen
        let jump = range > 0.08 || lastAccel > 0.15
        if jump {
            restartSettling(note: "BEWEGUNG ERKANNT · NEU", now: t)
            publish(Live(phase: .settling(0), note: currentNote(t)))
            return
        }
        times.append(t); red.append(r); green.append(g)
        let dur = t - recStart!
        guard t - lastLive > 0.33 else { return }
        lastLive = t

        var live = Live(phase: .measuring(min(1, dur / measureSeconds)), note: currentNote(t))
        if dur >= 3, let s = bestSignal(window: 6) {
            live.wave = s.wave
            live.beats = s.beats
            live.bpm = s.bpm.map { Int($0.rounded()) }
        }
        publish(live)

        if dur >= measureSeconds {
            if let res = finalEstimate(), res.q >= 0.4 || dur >= 35 {
                finished = true
                let bpm = Int(res.bpm.rounded())
                publish(Live(phase: .done(bpm, res.q), bpm: bpm, wave: live.wave, beats: live.beats))
                DispatchQueue.main.async { self.onResult?(bpm, res.q) }
            } else if dur >= 35 {
                // kein klares Signal: von vorn
                restartSettling(note: "SIGNAL UNKLAR · NEU", now: t)
            }
        }
    }

    private func currentNote(_ t: Double) -> String? { t < noteUntil ? note : nil }

    private func publish(_ l: Live) { DispatchQueue.main.async { self.live = l } }

    // MARK: Auswertung

    private struct Est { var bpm: Double; var q: Double }

    /// Für die Anzeige: gefiltertes Signal der letzten Sekunden mit erkannten Schlägen
    private func bestSignal(window: Double) -> (wave: [Double], beats: [Int], bpm: Double?)? {
        guard times.count > 30 else { return nil }
        let grid = makeGrid()
        let sig = clean(resample(red, at: grid))
        let k = min(sig.count, Int(fs * window))
        let tail = Array(sig.suffix(k))
        let ac = autocorr(sig)
        let beats = ac.map { peaks(tail, expectedBPM: $0.bpm) } ?? []
        return (tail, beats, ac?.bpm)
    }

    private func finalEstimate() -> Est? {
        let grid = makeGrid()
        var best: Est? = nil
        for ch in [red, green] {
            let s = clean(resample(ch, at: grid))
            guard var ac = autocorr(s) else { continue }
            let pk = peaks(s, expectedBPM: ac.bpm)
            if pk.count >= 6 {
                var ibi = zip(pk.dropFirst(), pk).map { Double($0 - $1) / fs }
                let m0 = median(ibi)
                ibi = ibi.filter { abs($0 - m0) / m0 < 0.2 }      // Ausreißer raus
                if ibi.count >= 5 {
                    let pbpm = 60 / median(ibi)
                    let diff = abs(pbpm - ac.bpm) / ac.bpm
                    if diff < 0.05 { ac.bpm = (ac.bpm + pbpm) / 2 } else { ac.q *= 0.45 }
                } else { ac.q *= 0.6 }
            } else { ac.q *= 0.6 }
            if best == nil || ac.q > best!.q { best = Est(bpm: ac.bpm, q: ac.q) }
        }
        return best
    }

    private func makeGrid() -> [Double] {
        guard let a = times.first, let b = times.last, b > a else { return [] }
        return stride(from: a, through: b, by: 1 / fs).map { $0 }
    }

    /// Trend abziehen (gleitender Mittelwert ~1 s), leicht glätten, normieren; Vorzeichen umdrehen,
    /// damit ein Herzschlag (mehr Blut = dunkler) nach oben zeigt
    private func clean(_ x: [Double]) -> [Double] {
        guard !x.isEmpty else { return [] }
        let trend = movingAverage(x, Int(fs))
        let detr = zip(x, trend).map { $1 - $0 }
        let smooth = movingAverage(detr, 3)
        let sd = sqrt(smooth.map { $0 * $0 }.reduce(0, +) / Double(smooth.count))
        return sd > 1e-9 ? smooth.map { $0 / sd } : smooth
    }

    private func movingAverage(_ x: [Double], _ win: Int) -> [Double] {
        let n = x.count, half = max(0, win / 2)
        var prefix = [Double](repeating: 0, count: n + 1)
        for i in 0..<n { prefix[i + 1] = prefix[i] + x[i] }
        return (0..<n).map { i in
            let a = max(0, i - half), b = min(n, i + half + 1)
            return (prefix[b] - prefix[a]) / Double(b - a)
        }
    }

    private func resample(_ x: [Double], at grid: [Double]) -> [Double] {
        guard x.count == times.count, x.count > 1, !grid.isEmpty else { return [] }
        var out = [Double](); out.reserveCapacity(grid.count)
        var j = 0
        for t in grid {
            while j < times.count - 2 && times[j + 1] < t { j += 1 }
            let t0 = times[j], t1 = times[j + 1]
            let a = t1 > t0 ? max(0, min(1, (t - t0) / (t1 - t0))) : 0
            out.append(x[j] + (x[j + 1] - x[j]) * a)
        }
        return out
    }

    /// Stärkste Wiederholung zwischen 40 und 190 Schlägen pro Minute
    private func autocorr(_ x: [Double]) -> Est? {
        let n = x.count
        let minLag = Int(fs * 60 / 190), maxLag = min(n / 2, Int(fs * 60 / 40))
        guard minLag >= 2, maxLag > minLag + 2 else { return nil }
        let e0 = x.map { $0 * $0 }.reduce(0, +)
        guard e0 > 0 else { return nil }
        var r = [Double](repeating: 0, count: maxLag + 2)
        for lag in (minLag - 1)...(maxLag + 1) where lag < n {
            var s = 0.0
            for i in 0..<(n - lag) { s += x[i] * x[i + lag] }
            r[lag] = s / e0 * Double(n) / Double(n - lag)
        }
        var bestLag = minLag
        for lag in minLag...maxLag where r[lag] > r[bestLag] { bestLag = lag }
        let half = bestLag / 2
        if half >= minLag && r[half] > 0.8 * r[bestLag] { bestLag = half }
        let q = max(0, min(1, r[bestLag]))
        let a = r[bestLag - 1], b = r[bestLag], c = r[bestLag + 1]
        let denom = a - 2 * b + c
        let shift = denom != 0 ? max(-0.5, min(0.5, 0.5 * (a - c) / denom)) : 0
        return Est(bpm: 60 * fs / (Double(bestLag) + shift), q: q)
    }

    /// Schläge an der steilsten Anstiegsflanke; Mindestabstand 60 % des erwarteten Schlagabstands
    private func peaks(_ x: [Double], expectedBPM: Double) -> [Int] {
        guard x.count > 6 else { return [] }
        var d = [Double](repeating: 0, count: x.count)
        for i in 1..<(x.count - 1) { d[i] = x[i + 1] - x[i - 1] }
        let sd = sqrt(d.map { $0 * $0 }.reduce(0, +) / Double(d.count))
        let minDist = Int(0.6 * fs * 60 / max(40, expectedBPM))
        var out: [Int] = []
        for i in 2..<(d.count - 2) {
            let v = d[i]
            guard v > 0.6 * sd, v >= d[i - 1], v >= d[i + 1], v >= d[i - 2], v >= d[i + 2] else { continue }
            if let last = out.last, i - last < minDist {
                if v > d[last] { out[out.count - 1] = i }
            } else {
                out.append(i)
            }
        }
        return out
    }

    private func rms<C: Collection>(_ x: C) -> Double where C.Element == Double {
        guard !x.isEmpty else { return 0 }
        return sqrt(x.map { $0 * $0 }.reduce(0, +) / Double(x.count))
    }

    private func median(_ x: [Double]) -> Double {
        let s = x.sorted()
        guard !s.isEmpty else { return 0 }
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }
}
