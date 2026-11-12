import SwiftUI
import AVFoundation
import UIKit

/// Pulstest: Finger oder Oberarm auf Kamera und Blitz, live Kurve und Signalqualität,
/// fertige Messungen werden angesagt und in einer Liste gespeichert.
struct PulseView: View {
    @EnvironmentObject var store: Store
    let onClose: () -> Void

    @StateObject private var engine = PulseEngine()
    @State private var mode: PulseEngine.Mode = .finger
    @State private var speak = true
    @State private var lastResult: PulseReading? = nil
    @State private var taps: [Date] = []
    @State private var synth = AVSpeechSynthesizer()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button(action: onClose) {
                        Text("← ZURÜCK").font(mono(12)).tracking(1).foregroundStyle(Color.muted).frame(minHeight: 44)
                    }
                    Spacer()
                    Text("PULSTEST").font(mono(15, .bold)).tracking(2).foregroundStyle(Color.danger).glow(.danger, 6)
                    Spacer()
                    Color.clear.frame(width: 70, height: 1)
                }

                modePicker

                Text(hint).font(mono(12)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)

                if engine.permissionDenied {
                    Text("Kein Zugriff auf die Kamera. Erlaube ihn unter Einstellungen → push-up → Kamera.")
                        .font(mono(12)).foregroundStyle(Color.amber)
                }

                readout
                waveform
                stats
                tapAlong

                Toggle("ERGEBNIS ANSAGEN", isOn: $speak).font(mono(12)).tint(.phos)

                Block(title: "MESSUNGEN") {
                    if store.state.pulse.isEmpty {
                        Text("Noch keine Messung. Probier Finger im Sitzen, Oberarm im Stehen, im Gehen und auf dem Rad und vergleiche die Signalqualität.")
                            .font(mono(12)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(store.state.pulse.suffix(15).reversed())) { r in readingRow(r) }
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(Color.bg.ignoresSafeArea())
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            engine.mode = mode
            engine.onResult = { bpm, q, motion in finish(bpm, q, motion) }
            engine.start()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            engine.stop()
        }
    }

    // MARK: Teile

    private var hint: String {
        switch mode {
        case .finger:
            return "Zeigefinger locker auf Kamera und Blitz legen, nicht fest drücken. Die Messung startet von selbst und dauert etwa 12 Sekunden."
        case .arm:
            return "Handy im Armband am Oberarm, Kamera und Blitz direkt auf der Haut. Das Armband muss seitliches Licht abhalten."
        }
    }

    private var modePicker: some View {
        HStack(spacing: 4) {
            ForEach(PulseEngine.Mode.allCases) { m in
                let on = mode == m
                Button {
                    mode = m
                    engine.setMode(m)
                } label: {
                    Text(m.label).font(mono(12, on ? .bold : .regular)).tracking(1.8)
                        .foregroundStyle(on ? Color.amber : Color.muted)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .overlay(alignment: .bottom) { Rectangle().fill(on ? Color.amber : Color.line2).frame(height: 1) }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var readout: some View {
        let l = engine.live
        let qColor: Color = l.quality >= 0.6 ? .phos : (l.quality >= 0.4 ? .wire : .amber)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(l.contact ? (l.bpm.map { "\($0)" } ?? "…") : "–")
                    .font(mono(64, .heavy)).monospacedDigit()
                    .foregroundStyle(l.contact ? Color.danger : Color.dim).glow(l.contact ? .danger : .clear, 14)
                Text("BPM").font(mono(14)).foregroundStyle(Color.muted)
                Spacer()
                if let r = lastResult {
                    VStack(alignment: .trailing, spacing: 2) {
                        Label12(text: "LETZTE")
                        Text("\(r.bpm)").font(mono(22, .bold)).foregroundStyle(Color.fg)
                    }
                }
            }
            Text(statusText).font(mono(12)).tracking(1).foregroundStyle(l.contact ? qColor : Color.muted)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.line)
                    Rectangle().fill(Color.danger).frame(width: g.size.width * (l.contact ? l.progress : 0))
                }
            }
            .frame(height: 3)
        }
    }

    private var statusText: String {
        let l = engine.live
        if !l.contact { return mode == .finger ? "WARTE AUF FINGER" : "WARTE AUF HAUTKONTAKT" }
        if l.progress < 1 { return "MESSE … \(Int((l.progress * 100).rounded()))%" }
        return "MESSUNG FERTIG · FÜR NEUE MESSUNG KURZ ABSETZEN"
    }

    private var waveform: some View {
        let wave = engine.live.wave
        return Canvas { ctx, size in
            var grid = Path()
            for i in 0...4 {
                let y = size.height * CGFloat(i) / 4
                grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
            }
            ctx.stroke(grid, with: .color(.line), lineWidth: 1)
            guard wave.count > 2 else { return }
            let lo = wave.min() ?? -1, hi = wave.max() ?? 1
            let span = max(0.001, hi - lo)
            var p = Path()
            for (i, v) in wave.enumerated() {
                let x = size.width * CGFloat(i) / CGFloat(wave.count - 1)
                // Invertiert: mehr Blut = dunkler, so zeigen die Spitzen nach oben wie bei einem EKG
                let y = size.height * CGFloat((v - lo) / span)
                if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(p, with: .color(Color.danger.opacity(0.25)), lineWidth: 6)
            ctx.stroke(p, with: .color(.danger), lineWidth: 1.6)
        }
        .frame(height: 120)
        .background(Color.panel)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var stats: some View {
        let l = engine.live
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
            cell("SIGNAL", l.contact ? "\(Int((l.quality * 100).rounded()))%" : "–")
            cell("BEWEGUNG", motionText(l.motion))
            cell("FILTER", l.contact ? (l.filtered ? "AKTIV" : "AUS") + " · \(l.channel)" : "–")
        }
    }

    /// Zum Gegencheck: Puls am Hals fühlen und bei jedem Schlag hier tippen
    private var tapBPM: Int? {
        let recent = taps.suffix(9)
        guard recent.count >= 5, let first = recent.first, let last = recent.last else { return nil }
        let span = last.timeIntervalSince(first)
        guard span > 0 else { return nil }
        return Int((Double(recent.count - 1) / span * 60).rounded())
    }

    private var tapAlong: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label12(text: "GEGENCHECK: PULS FÜHLEN UND BEI JEDEM SCHLAG TIPPEN")
            HStack(spacing: 12) {
                Button {
                    let now = Date()
                    if let l = taps.last, now.timeIntervalSince(l) > 3 { taps = [] }
                    taps.append(now)
                } label: {
                    Text("TIPP").font(mono(16, .heavy)).tracking(4).foregroundStyle(Color.danger)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(Color.danger.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.danger, lineWidth: 1))
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tapBPM.map { "\($0)" } ?? "–").font(mono(28, .bold)).monospacedDigit().foregroundStyle(Color.fg)
                    Text(taps.count < 5 ? "noch \(5 - taps.count) Tipps" : "getippt").font(mono(10)).foregroundStyle(Color.muted)
                }
                .frame(width: 96, alignment: .leading)
            }
        }
    }

    private func cell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label12(text: label)
            Text(value).font(mono(14, .bold)).foregroundStyle(Color.fg)
        }
    }

    private func motionText(_ m: Double) -> String {
        m < 0.03 ? "RUHIG" : (m < 0.12 ? "LEICHT" : "STARK")
    }

    private func readingRow(_ r: PulseReading) -> some View {
        HStack(spacing: 12) {
            Text("\(r.bpm)").font(mono(18, .bold)).monospacedDigit().foregroundStyle(Color.danger).frame(width: 48, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(r.mode == "arm" ? "Oberarm" : "Finger") · Signal \(Int((r.quality * 100).rounded()))% · \(motionText(r.motion).lowercased())")
                    .font(mono(12)).foregroundStyle(Color.fg)
                Text(fmtTime(r.ts)).font(mono(10.5)).foregroundStyle(Color.muted)
            }
            Spacer()
        }
        .padding(.vertical, 9)
        .overlay(alignment: .top) { Rectangle().fill(Color.line).frame(height: 1) }
    }

    private func finish(_ bpm: Int, _ q: Double, _ motion: Double) {
        let r = PulseReading(id: LogEntry.newId(), ts: nowMs(), bpm: bpm, quality: q, motion: motion, mode: mode.rawValue)
        store.state.pulse.append(r)
        store.save()
        lastResult = r
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if speak {
            let u = AVSpeechUtterance(string: "\(bpm)")
            u.voice = AVSpeechSynthesisVoice(language: "de-DE")
            synth.speak(u)
        }
    }
}
