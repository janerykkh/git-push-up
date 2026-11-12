import AVFoundation
import CoreMotion
import Foundation

/// Puls über Kamera und Blitz (Photoplethysmographie): Mit jedem Herzschlag ändert sich die Helligkeit
/// der durchleuchteten Haut um etwa ein Prozent. Die Engine misst die mittlere Farbe jedes Kamerabilds,
/// filtert Bewegung über den Beschleunigungssensor heraus und schätzt den Puls per Autokorrelation.
final class PulseEngine: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    enum Mode: String, CaseIterable, Identifiable {
        case finger, arm
        var id: String { rawValue }
        var label: String { self == .finger ? "FINGER" : "OBERARM" }
    }

    struct Live {
        var contact = false
        var bpm: Int? = nil
        var quality: Double = 0      // 0…1, wie klar der Puls im Signal steckt
        var motion: Double = 0       // Bewegung in g (RMS)
        var filtered = false         // Bewegungsfilter hat ein besseres Signal geliefert
        var progress: Double = 0     // 0…1 bis zur fertigen Messung
        var wave: [Double] = []      // letzte Sekunden des gefilterten Signals zum Anzeigen
        var channel = "–"
    }

    @Published var live = Live()
    @Published var permissionDenied = false
    /// Wird auf dem Hauptthread aufgerufen, wenn eine Messung fertig ist
    var onResult: ((Int, Double, Double) -> Void)?

    var mode: Mode = .finger
    var measureSeconds: Double = 12

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "pulse.processing")
    private let motion = CMMotionManager()
    private var device: AVCaptureDevice?

    // Nur auf `queue` benutzt
    private var times: [Double] = []
    private var red: [Double] = []
    private var green: [Double] = []
    private var accel: [Double] = []
    private var lastAccel: Double = 0
    private var accelWindow: [Double] = []
    private var contactSince: Double? = nil
    private var lastEstimate: Double = 0
    private var estimates: [(bpm: Double, q: Double)] = []
    private var finished = false

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
                if self.accelWindow.count > 120 { self.accelWindow.removeFirst(self.accelWindow.count - 120) }
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

    func setMode(_ m: Mode) {
        mode = m
        queue.async {
            self.setTorch(true)
            self.times = []; self.red = []; self.green = []; self.accel = []
            self.contactSince = nil; self.estimates = []; self.finished = false
        }
    }

    func reset() {
        queue.async {
            self.times = []; self.red = []; self.green = []; self.accel = []
            self.contactSince = nil; self.estimates = []; self.finished = false
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
            // Feste 30 Bilder pro Sekunde, sonst passt die Kamera die Rate ans Licht an und die Zeitachse verrutscht
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
            try? d.setTorchModeOn(level: mode == .arm ? 1.0 : 0.6)
            // Weniger hell belichten, damit der Rotkanal nicht übersteuert
            let bias = max(d.minExposureTargetBias, min(d.maxExposureTargetBias, -1.0))
            d.setExposureTargetBias(bias, completionHandler: nil)
            if d.isFocusModeSupported(.locked) { d.focusMode = .locked }
        } else {
            d.torchMode = .off
        }
        d.unlockForConfiguration()
    }

    // MARK: Bilder auswerten

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let px = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        CVPixelBufferLockBaseAddress(px, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(px, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(px) else { return }
        let w = CVPixelBufferGetWidth(px), h = CVPixelBufferGetHeight(px), row = CVPixelBufferGetBytesPerRow(px)
        let p = base.assumingMemoryBound(to: UInt8.self)
        var sr = 0.0, sg = 0.0, sb = 0.0, n = 0.0
        // Mittlere Hälfte des Bildes, jedes dritte Pixel reicht
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

    private func process(t: Double, r: Double, g: Double, b: Double) {
        // Kontakt: Haut vor der Linse, durchleuchtet vom Blitz → stark rot
        let ratio = mode == .finger ? 1.6 : 1.25
        let contact = r > 60 && r > g * ratio && r > b * ratio
        if !contact {
            if contactSince != nil { times = []; red = []; green = []; accel = []; estimates = [] }
            contactSince = nil; finished = false
            let m = rms(accelWindow)
            DispatchQueue.main.async { self.live = Live(contact: false, motion: m) }
            return
        }
        if contactSince == nil { contactSince = t }
        times.append(t); red.append(r); green.append(g); accel.append(lastAccel)
        // Nur die letzten 10 Sekunden behalten
        while let first = times.first, t - first > 10 {
            times.removeFirst(); red.removeFirst(); green.removeFirst(); accel.removeFirst()
        }
        guard t - lastEstimate > 0.4 else { return }
        lastEstimate = t
        estimate(now: t)
    }

    private func estimate(now: Double) {
        let span = (times.last ?? 0) - (times.first ?? 0)
        let m = rms(accelWindow)
        let since = now - (contactSince ?? now)
        var out = Live(contact: true, bpm: nil, quality: 0, motion: m, filtered: false,
                       progress: min(1, since / measureSeconds), wave: [], channel: "–")
        guard span >= 4, times.count >= 60 else {
            DispatchQueue.main.async { self.live = out }
            return
        }
        // Auf ein festes 30-Hz-Raster umrechnen, damit Lücken oder schwankende Bildraten nichts verfälschen
        let fs = 30.0
        let grid = stride(from: times[0], through: times[times.count - 1], by: 1 / fs).map { $0 }
        let ref = clean(resample(accel, at: grid), fs: fs)
        var best: (bpm: Double, q: Double, sig: [Double], name: String, filt: Bool)? = nil
        for (name, ch) in [("ROT", red), ("GRÜN", green)] {
            let sig = clean(resample(ch, at: grid), fs: fs)
            for (filt, s) in [(false, sig), (true, nlms(sig, ref: ref))] {
                guard var r = autocorrBPM(s, fs: fs) else { continue }
                // Gegenprobe: Abstand der einzelnen Herzschläge. Weichen beide Methoden ab, ist das Signal unsicher.
                if let p = peakBPM(s, fs: fs) {
                    let diff = Swift.abs(p - r.bpm) / r.bpm
                    if diff > 0.08 { r.q *= 0.5 }
                } else {
                    r.q *= 0.7
                }
                if best == nil || r.q > best!.q { best = (r.bpm, r.q, s, name, filt) }
            }
        }
        if let b = best {
            out.bpm = Int(b.bpm.rounded())
            out.quality = b.q
            out.filtered = b.filt
            out.channel = b.name
            let k = Int(fs * 6)
            out.wave = Array(b.sig.suffix(k))
            if b.q >= 0.45 { estimates.append((b.bpm, b.q)) }
            if estimates.count > 12 { estimates.removeFirst(estimates.count - 12) }
        }
        DispatchQueue.main.async { self.live = out }

        // Fertig: genug Zeit mit Kontakt und mehrere gute Schätzungen
        if !finished && since >= measureSeconds && estimates.count >= 4 {
            finished = true
            let recent = estimates.suffix(6)
            let bpm = median(recent.map { $0.bpm })
            let q = recent.map { $0.q }.reduce(0, +) / Double(recent.count)
            DispatchQueue.main.async { self.onResult?(Int(bpm.rounded()), q, m) }
        }
    }

    // MARK: Signalverarbeitung

    /// Langsamen Trend abziehen (gleitender Mittelwert ~1 s), dann leicht glätten und normieren
    private func clean(_ x: [Double], fs: Double) -> [Double] {
        guard !x.isEmpty else { return [] }
        let trend = movingAverage(x, Int(max(3, fs * 1.0)))
        let detr = zip(x, trend).map { $0 - $1 }
        let smooth = movingAverage(detr, Int(max(1, fs / 10)))
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

    /// Bewegungsfilter: zieht den Anteil des Signals ab, der sich aus der Beschleunigung vorhersagen lässt (NLMS)
    private func nlms(_ x: [Double], ref: [Double], order: Int = 8, mu: Double = 0.08) -> [Double] {
        guard x.count == ref.count, x.count > order else { return x }
        var w = [Double](repeating: 0, count: order)
        var e = x
        for _ in 0..<2 {   // zwei Durchläufe, damit die Gewichte eingeschwungen sind
            for n in order..<x.count {
                var yhat = 0.0, pow2 = 1e-6
                for k in 0..<order { let r = ref[n - k]; yhat += w[k] * r; pow2 += r * r }
                let err = x[n] - yhat
                for k in 0..<order { w[k] += mu * err * ref[n - k] / pow2 }
                e[n] = err
            }
        }
        return e
    }

    /// Puls aus der stärksten Wiederholung zwischen 40 und 200 Schlägen pro Minute
    private func autocorrBPM(_ x: [Double], fs: Double) -> (bpm: Double, q: Double)? {
        let n = x.count
        let minLag = Int(fs * 60 / 200), maxLag = min(n / 2, Int(fs * 60 / 40))
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
        // Wenn auch die halbe Periode stark ist, war es vermutlich eine Doppelzählung
        let half = bestLag / 2
        if half >= minLag && r[half] > 0.8 * r[bestLag] { bestLag = half }
        let q = max(0, min(1, r[bestLag]))
        // Parabel durch die Nachbarn für einen genaueren Wert
        let a = r[bestLag - 1], b = r[bestLag], c = r[bestLag + 1]
        let denom = a - 2 * b + c
        let shift = denom != 0 ? max(-0.5, min(0.5, 0.5 * (a - c) / denom)) : 0
        let lag = Double(bestLag) + shift
        return (60 * fs / lag, q)
    }

    /// Lineare Interpolation der Messwerte auf das gleichmäßige Zeitraster
    private func resample(_ x: [Double], at grid: [Double]) -> [Double] {
        guard x.count == times.count, x.count > 1 else { return x }
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

    /// Puls aus den Abständen der einzelnen Spitzen (Median), als zweite, unabhängige Schätzung
    private func peakBPM(_ x: [Double], fs: Double) -> Double? {
        let minDist = Int(fs * 60 / 200)
        var peaks: [Int] = []
        guard x.count > 4 else { return nil }
        for i in 2..<(x.count - 2) {
            let v = x[i]
            guard v > 0.3, v >= x[i - 1], v >= x[i + 1], v >= x[i - 2], v >= x[i + 2] else { continue }
            if let last = peaks.last, i - last < minDist {
                if v > x[last] { peaks[peaks.count - 1] = i }
            } else {
                peaks.append(i)
            }
        }
        guard peaks.count >= 4 else { return nil }
        let ibi = zip(peaks.dropFirst(), peaks).map { Double($0 - $1) / fs }
        let m = median(ibi)
        return m > 0 ? 60 / m : nil
    }

    private func rms(_ x: [Double]) -> Double {
        guard !x.isEmpty else { return 0 }
        return sqrt(x.map { $0 * $0 }.reduce(0, +) / Double(x.count))
    }

    private func median(_ x: [Double]) -> Double {
        let s = x.sorted()
        guard !s.isEmpty else { return 0 }
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }
}
