import SwiftUI
import AVFoundation
import UIKit

/// Puls zählen: beim ersten Schlag beide Lautstärketasten drücken (dabei "null" denken), still zehn Schläge zählen,
/// beim zehnten wieder beide. Aus der Zeit dazwischen ergibt sich der Puls. Geht auch gesperrt und über den Knopf.
struct PulseView: View {
    @EnvironmentObject var store: Store
    let onClose: () -> Void

    @StateObject private var trigger = VolumeTrigger()
    @State private var startedAt: Date? = nil
    @State private var lastResult: Int? = nil
    @State private var speak = true
    @State private var synth = AVSpeechSynthesizer()

    private let beats = 10.0
    private let timeout: TimeInterval = 20

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Button(action: onClose) {
                        Text("← ZURÜCK").font(mono(12)).tracking(1).foregroundStyle(Color.muted).frame(minHeight: 44)
                    }
                    Spacer()
                    Text("PULS").font(mono(15, .bold)).tracking(2).foregroundStyle(Color.danger).glow(.danger, 6)
                    Spacer()
                    Color.clear.frame(width: 70, height: 1)
                }

                VStack(alignment: .leading, spacing: 8) {
                    step("1", "Puls am Hals oder Handgelenk fühlen.")
                    step("2", "Beim nächsten Schlag BEIDE LAUTSTÄRKETASTEN gleichzeitig drücken und dabei „null“ denken. Es piept.")
                    step("3", "Still bis zehn zählen, beim zehnten Schlag wieder beide Tasten. Die App sagt die Zahl an.")
                }

                Text("Geht mit den Tasten am iPhone oder den Plus-Minus-Tasten der EarPods, auch bei gesperrtem Bildschirm, solange dieser Bildschirm offen ist. Leiser und lauter kurz hintereinander geht auch. Normales Lauter- oder Leiserstellen löst nichts aus.")
                    .font(mono(11)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)

                if trigger.volume <= 0.07 || trigger.volume >= 0.93 {
                    Text("Lautstärke steht ganz \(trigger.volume <= 0.07 ? "unten" : "oben"). Stell sie etwas in die Mitte, sonst merkt das iPhone einen der beiden Drücker nicht.")
                        .font(mono(12)).foregroundStyle(Color.amber).fixedSize(horizontal: false, vertical: true)
                }

                readout

                Button(startedAt == nil ? "START (ERSTER SCHLAG)" : "STOPP (ZEHNTER SCHLAG)") { mark(Date()) }
                    .buttonStyle(HangarButtonStyle(color: .danger, filled: true))

                Toggle("ERGEBNIS ANSAGEN", isOn: $speak).font(mono(12)).tint(.phos)

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
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(LabBackdrop())
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            trigger.onTrigger = { at in mark(at) }
            trigger.start()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            trigger.stop()
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
                        Text(String(format: "%.1f", s)).font(mono(64, .heavy)).monospacedDigit().foregroundStyle(Color.amber)
                        Text("S · ZÄHLEN").font(mono(14)).foregroundStyle(Color.muted)
                    } else {
                        Text(lastResult.map { "\($0)" } ?? "–").font(mono(64, .heavy)).monospacedDigit()
                            .foregroundStyle(lastResult == nil ? Color.dim : Color.danger).glow(lastResult == nil ? .clear : .danger, 14)
                        Text("BPM").font(mono(14)).foregroundStyle(Color.muted)
                    }
                }
                Label12(text: running == nil ? "BEREIT · BEIDE TASTEN ZUM STARTEN" : "BEIM ZEHNTEN SCHLAG WIEDER BEIDE TASTEN",
                        color: running == nil ? .muted : .amber)
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
            save(bpm)
        } else {
            startedAt = at
            trigger.beep()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    private func save(_ bpm: Int) {
        let r = PulseReading(id: LogEntry.newId(), ts: nowMs(), bpm: bpm, quality: 1, motion: 0, mode: "count")
        store.state.pulse.append(r)
        store.save()
        lastResult = bpm
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if speak {
            let u = AVSpeechUtterance(string: "\(bpm)")
            u.voice = AVSpeechSynthesisVoice(language: "de-DE")
            synth.speak(u)
        }
    }

    private func readingRow(_ r: PulseReading) -> some View {
        HStack(spacing: 12) {
            Text("\(r.bpm)").font(mono(18, .bold)).monospacedDigit().foregroundStyle(Color.danger).frame(width: 48, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.mode == "count" ? "gezählt" : (r.mode == "arm" ? "Kamera · Oberarm" : "Kamera · Finger"))
                    .font(mono(12)).foregroundStyle(Color.fg)
                Text(fmtTime(r.ts)).font(mono(10.5)).foregroundStyle(Color.muted)
            }
            Spacer()
        }
        .padding(.vertical, 9)
        .overlay(alignment: .top) { Rectangle().fill(Color.line).frame(height: 1) }
    }
}
