import SwiftUI
import AVFoundation
import UIKit
import Combine

/// Pulsmessung, zwei Wege:
/// KAMERA: Finger auf Kamera und Blitz. Gemessen wird erst, wenn alles ruhig liegt; man sieht die Pulswelle live.
/// ZÄHLEN: beim ersten Schlag beide Lautstärketasten, still zehn Schläge zählen, beim zehnten wieder beide.
/// Der Anlass (Ruhepuls, Meditation, Erholung) bestimmt Dauer und Ablauf; beim Erholungspuls wird zweimal gemessen.
struct PulseView: View {
    @EnvironmentObject var store: Store
    var context: PulseContext = .free
    let onClose: () -> Void

    enum Source { case camera, keys }
    @State private var source: Source = .camera
    @StateObject private var engine = PulseEngine()
    @StateObject private var trigger = VolumeTrigger()
    @State private var startedAt: Date? = nil
    @State private var lastResult: Int? = nil
    @State private var lastQuality: Double = 1
    @State private var speak = true
    @State private var synth = AVSpeechSynthesizer()
    // Erholungspuls: erste Messung, dann warten, dann zweite
    @State private var openedAt = Date()
    @State private var first: Int? = nil
    @State private var waitUntil: Date? = nil
    @State private var saved = false

    private let beats = 10.0
    private let timeout: TimeInterval = 20

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button(action: close) {
                        Text("← ZURÜCK").font(mono(12)).tracking(1).foregroundStyle(Color.muted).frame(minHeight: 44)
                    }
                    Spacer()
                    if context != .free {
                        Button(action: close) {
                            Text("ÜBERSPRINGEN").font(mono(12)).foregroundStyle(Color.muted).frame(minHeight: 44)
                        }
                    }
                }
                Text(context.title).font(display(28)).tracking(1).foregroundStyle(Color.fg)
                Text(context.hint).font(mono(12)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)

                tabs
                if context.isRecovery { recoveryStatus }
                if source == .camera { cameraPanel } else { keysPanel }

                Toggle("ERGEBNIS ANSAGEN", isOn: $speak).font(mono(12)).tint(.signal)

                if context == .free {
                    Block(title: "MESSUNGEN") {
                        if store.state.pulse.isEmpty {
                            Text("Noch keine Messung.").font(mono(12)).foregroundStyle(Color.muted)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(store.state.pulse.suffix(20).reversed())) { r in readingRow(r) }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(LabBackdrop())
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            openedAt = Date()
            engine.measureSeconds = context.seconds
            engine.onResult = { bpm, q in got(bpm, q: q, from: .camera) }
            trigger.onTrigger = { at in mark(at) }
            activate(source)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            engine.stop()
            trigger.stop()
        }
        .onChange(of: source) { s in activate(s) }
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { now in
            // Erholungspuls: Zeit für die zweite Messung
            if let w = waitUntil, now >= w {
                waitUntil = nil
                if source == .camera { engine.reset() }
                trigger.beep()
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            }
        }
    }

    private func activate(_ s: Source) {
        if s == .camera { trigger.stop(); engine.start(); engine.reset() } else { engine.stop(); trigger.start() }
    }

    private func close() {
        engine.stop()
        onClose()
    }

    private var tabs: some View {
        HStack(spacing: PX * 2) {
            ForEach([(Source.camera, "KAMERA"), (Source.keys, "ZÄHLEN")], id: \.1) { s, label in
                let on = source == s
                Button { source = s } label: {
                    Text(label).font(labelFont(11)).tracking(1)
                        .foregroundStyle(on ? Color.bg : Color.fg)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(PixelBlock().fill(on ? Color.fg : Color.panel))
                        .overlay(PixelFrame().fill(Color.line2))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Kamera

    private var cameraPanel: some View {
        let L = engine.live
        let status: String = {
            if engine.permissionDenied { return "KEIN KAMERAZUGRIFF · IN DEN EINSTELLUNGEN ERLAUBEN" }
            if let w = waitUntil, w > Date() { return "FINGER LIEGEN LASSEN · ZWEITE MESSUNG GLEICH" }
            switch L.phase {
            case .noFinger: return "FINGER AUF KAMERA UND BLITZ LEGEN"
            case .settling(let p): return L.note ?? "STILL HALTEN · KALIBRIERE \(Int(p * 100)) %"
            case .measuring(let p): return L.note ?? "MESSUNG · \(String(format: "%02d", Int(p * context.seconds)))/\(Int(context.seconds)) S"
            case .done(_, let q): return q < 0.55 ? "ERFASST · SIGNAL UNSICHER" : "ERFASST"
            }
        }()
        let big: String = {
            if case .done(let b, _) = L.phase { return "\(b)" }
            if case .measuring = L.phase, let b = L.bpm { return "\(b)" }
            return lastResult.map { "\($0)" } ?? "--"
        }()
        let measuring: Bool = { if case .measuring = L.phase { return true } else { return false } }()
        let progress: Double = {
            switch L.phase {
            case .settling(let p): return p * 0.15
            case .measuring(let p): return 0.15 + 0.85 * p
            case .done: return 1
            default: return 0
            }
        }()
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(status).font(mono(11, .bold)).foregroundStyle(L.note != nil ? Color.signal : Color.fg)
                Spacer()
            }
            HStack(spacing: PX * 3) {
                // Live-Bild der Kamera als grobe Pixel
                ZStack {
                    Color(hex: 0x10171a)
                    if engine.thumb.count == PulseEngine.thumbW * PulseEngine.thumbH * 4,
                       let img = makeImage(engine.thumb, PulseEngine.thumbW, PulseEngine.thumbH) {
                        Image(decorative: img, scale: 1).resizable().interpolation(.none)
                    }
                    // Fadenkreuz
                    Rectangle().fill(Color.white.opacity(0.25)).frame(width: PX / 2)
                    Rectangle().fill(Color.white.opacity(0.25)).frame(height: PX / 2)
                }
                .frame(width: CGFloat(PulseEngine.thumbW) * PX * 2, height: CGFloat(PulseEngine.thumbH) * PX * 2)
                .clipped()
                .pixelBorder()
                ScanWave(wave: L.wave, beats: L.beats, active: measuring)
                    .frame(height: CGFloat(PulseEngine.thumbH) * PX * 2)
                    .background(PixelBlock().fill(Color(hex: 0x10171a)))
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(big).font(display(64)).monospacedDigit().foregroundStyle(measuring ? Color.muted : Color.danger)
                Text("BPM").font(mono(13)).foregroundStyle(Color.muted)
                Spacer()
                if case .done = L.phase {
                    Button("NOCHMAL") { engine.reset() }.font(mono(12, .bold)).foregroundStyle(Color.fg)
                }
            }
            PixelBar(value: progress, color: .danger, height: 4)
        }
        .padding(12)
        .background(PixelBlock().fill(Color.panel))
        .pixelBorder()
    }

    // MARK: Erholung

    private var recoveryStatus: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DIREKT DANACH").font(labelFont(9)).tracking(0.8)
                    Text(first.map { "\($0)" } ?? "--").font(display(26)).foregroundStyle(Color.fg)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text("NACH 1 MINUTE").font(labelFont(9)).tracking(0.8)
                    if let w = waitUntil {
                        Text("IN \(max(0, Int(w.timeIntervalSince(tl.date).rounded()))) S").font(display(26)).foregroundStyle(Color.signal)
                    } else {
                        Text(saved ? (lastResult.map { "\($0)" } ?? "--") : "--").font(display(26)).foregroundStyle(Color.fg)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ABFALL").font(labelFont(9)).tracking(0.8)
                    let drop = (saved && first != nil && lastResult != nil) ? "−\(first! - lastResult!)" : "--"
                    Text(drop).font(display(26)).foregroundStyle(Color.fg)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .pixelBorder()
        }
    }

    // MARK: Ergebnis

    private func got(_ bpm: Int, q: Double, from: Source) {
        lastResult = bpm
        lastQuality = q
        if speak {
            let u = AVSpeechUtterance(string: "\(bpm)")
            u.voice = AVSpeechSynthesisVoice(language: "de-DE")
            synth.speak(u)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if context.isRecovery && first == nil {
            first = bpm
            // zweite Messung so, dass sie etwa eine Minute nach Ende der Übung liegt
            let target = openedAt.addingTimeInterval(from == .camera ? 52 : 58)
            waitUntil = max(target, Date().addingTimeInterval(5))
            return
        }
        var r = PulseReading(id: LogEntry.newId(), ts: nowMs(), bpm: first ?? bpm, quality: q, motion: 0, mode: context.code,
                             source: from == .camera ? "kamera" : "tasten")
        if context.isRecovery { r.bpm2 = bpm }
        store.state.pulse.append(r)
        store.save()
        saved = true
        if context != .free {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { close() }
        }
    }

    // MARK: Zählen mit den Lautstärketasten

    private var keysPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                step("1", "Puls am Hals oder Handgelenk fühlen.")
                step("2", "Beim nächsten Schlag BEIDE LAUTSTÄRKETASTEN gleichzeitig drücken und dabei „null“ denken. Es piept.")
                step("3", "Still bis zehn zählen, beim zehnten Schlag wieder beide Tasten.")
            }
            if trigger.volume <= 0.07 || trigger.volume >= 0.93 {
                Text("Lautstärke steht ganz \(trigger.volume <= 0.07 ? "unten" : "oben"). Stell sie etwas in die Mitte, sonst merkt das iPhone einen der beiden Drücker nicht.")
                    .font(mono(12)).foregroundStyle(Color.signal).fixedSize(horizontal: false, vertical: true)
            }
            readout
            Button(startedAt == nil ? "START (ERSTER SCHLAG)" : "STOPP (ZEHNTER SCHLAG)") { mark(Date()) }
                .buttonStyle(HangarButtonStyle(color: .danger, filled: true))
        }
    }

    private func step(_ n: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(n).font(mono(13, .bold)).foregroundStyle(Color.danger)
            Text(text).font(mono(13)).foregroundStyle(Color.fg).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var readout: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { tl in
            let running = startedAt.map { tl.date.timeIntervalSince($0) }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if let s = running {
                        Text(String(format: "%.1f", s)).font(display(64)).monospacedDigit().foregroundStyle(Color.signal)
                        Text("S · ZÄHLEN").font(mono(14)).foregroundStyle(Color.muted)
                    } else {
                        Text(lastResult.map { "\($0)" } ?? "--").font(display(64)).monospacedDigit()
                            .foregroundStyle(lastResult == nil ? Color.dim : Color.danger)
                        Text("BPM").font(mono(14)).foregroundStyle(Color.muted)
                    }
                }
                Label12(text: running == nil ? "BEREIT · BEIDE TASTEN ZUM STARTEN" : "BEIM ZEHNTEN SCHLAG WIEDER BEIDE TASTEN",
                        color: running == nil ? .muted : .signal)
            }
            .onChange(of: running.map { $0 > timeout } ?? false) { tooLong in
                if tooLong { startedAt = nil }
            }
        }
    }

    private func mark(_ at: Date) {
        if let s = startedAt {
            startedAt = nil
            let dt = at.timeIntervalSince(s)
            let bpm = Int((beats / dt * 60).rounded())
            guard dt > 0, bpm >= 30, bpm <= 230 else {
                trigger.beep()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { trigger.beep() }
                return
            }
            got(bpm, q: 1, from: .keys)
        } else {
            startedAt = at
            trigger.beep()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    private func readingRow(_ r: PulseReading) -> some View {
        HStack(spacing: 12) {
            Text(r.bpm2.map { "\(r.bpm)→\($0)" } ?? "\(r.bpm)").font(mono(16, .bold)).monospacedDigit().foregroundStyle(Color.danger)
                .frame(width: 84, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.label + (r.source == "kamera" ? " · Kamera" : "")).font(mono(12)).foregroundStyle(Color.fg)
                Text(fmtTime(r.ts)).font(mono(10.5)).foregroundStyle(Color.muted)
            }
            Spacer()
        }
        .padding(.vertical, 9)
        .overlay(alignment: .top) { Rectangle().fill(Color.line).frame(height: PX / 2) }
    }
}

/// Pulswelle wie auf einem Scanner: dunkles Feld, Pixelraster, die Welle in Rot, jeder erkannte Schlag ein Signalpixel
struct ScanWave: View {
    let wave: [Double]
    let beats: [Int]
    let active: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 12)) { tl in
            Canvas { ctx, size in
                // Raster
                var grid = Path()
                var x: CGFloat = 0
                while x < size.width { grid.addRect(CGRect(x: snap(x), y: 0, width: PX / 2, height: size.height)); x += PX * 10 }
                var y: CGFloat = 0
                while y < size.height { grid.addRect(CGRect(x: 0, y: snap(y), width: size.width, height: PX / 2)); y += PX * 10 }
                ctx.fill(grid, with: .color(Color(hex: 0x2a3a3c)))
                guard wave.count > 2 else {
                    // Suchlauf: eine Linie wandert hin und her
                    let t = tl.date.timeIntervalSinceReferenceDate
                    let sx = (0.5 + 0.5 * sin(t * 1.8)) * Double(size.width)
                    ctx.fill(Path(CGRect(x: snap(CGFloat(sx)), y: 0, width: PX, height: size.height)), with: .color(Color(hex: 0x3f5a5c)))
                    return
                }
                let n = wave.count
                let maxA = max(1.5, wave.map { abs($0) }.max() ?? 1.5)
                var pp = PixelPath()
                for (i, v) in wave.enumerated() {
                    let p = CGPoint(x: CGFloat(i) / CGFloat(n - 1) * size.width, y: size.height / 2 - CGFloat(v / maxA) * size.height * 0.4)
                    if i == 0 { pp.move(to: p) } else { pp.addLine(to: p) }
                }
                ctx.pixelStroke(pp, Color(hex: 0xff5a4a), size: PX)
                for b in beats where b < n {
                    let bx = CGFloat(b) / CGFloat(n - 1) * size.width
                    ctx.fill(Path(CGRect(x: snap(bx), y: PX * 2, width: PX * 2, height: PX * 2)), with: .color(Color.signal))
                }
            }
        }
    }
}
