import SwiftUI

/// Eine Übung: Animation, Ziel, Hinweise, Timer für Halteübungen, Geschafft / Nicht geschafft.
struct ExerciseView: View {
    @EnvironmentObject var store: Store
    let ex: Exercise
    var boss: Bool = false
    let onFinish: (_ done: Bool, _ target: Int, _ actual: Int) -> Void
    let onSkip: () -> Void
    let onClose: () -> Void

    @State private var showPartial = false
    @State private var partialText = ""
    @State private var timerStart: Date? = nil
    @State private var timerValue = 0
    @FocusState private var inputFocused: Bool

    private var target: Int { boss ? store.bossTarget(ex) : store.perTime(ex) }
    private var unitText: String {
        (ex.unit == .sec ? "SEKUNDEN HALTEN" : "WIEDERHOLUNGEN") + (ex.side ? " PRO SEITE" : "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(ex.cat.label.uppercased()).font(mono(11, .bold)).tracking(2)
                        .foregroundStyle(ex.cat.color)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(ex.cat.color, lineWidth: 1))
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 16, weight: .medium)).foregroundStyle(Color.muted)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Zurück")
                }

                Text(ex.name.uppercased()).font(mono(28, .bold)).foregroundStyle(Color.fg)

                if boss {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("BOSS-SATZ").font(mono(13, .heavy)).tracking(4).foregroundStyle(Color.amber).glow(.amber, 8)
                        Text("Diesmal richtig: so viele saubere Wiederholungen wie möglich, bis noch etwa zwei gehen würden. Genau diese Sätze bauen Muskeln auf. Höchstens einer pro Tag.")
                            .font(mono(12)).foregroundStyle(Color.fg).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.amber.opacity(0.07))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.amber, lineWidth: 1))
                }

                StickFigure(ex: ex)

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(boss ? "~\(target)" : "\(target)").font(mono(48, .heavy)).foregroundStyle(boss ? Color.amber : ex.cat.color)
                        .glow(boss ? .amber : ex.cat.color, 12)
                        .monospacedDigit()
                    Text(boss ? unitText + " · SCHÄTZUNG" : unitText).font(mono(12)).tracking(0.8).foregroundStyle(Color.muted)
                }

                Text(ex.cue).font(mono(14)).foregroundStyle(Color.fg).fixedSize(horizontal: false, vertical: true)
                if let note = ex.note {
                    Text(note).font(mono(12)).foregroundStyle(Color.amber).fixedSize(horizontal: false, vertical: true)
                }
                Text(store.why(ex)).font(mono(11)).tracking(1).foregroundStyle(Color.wire.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)

                if ex.unit == .sec { timerRow }

                if showPartial {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(ex.unit == .sec ? "Wie viele Sekunden hast du gehalten?" : "Wie viele Wiederholungen hast du geschafft?")
                            .font(mono(13)).foregroundStyle(Color.muted)
                        HStack(spacing: 10) {
                            TextField("0", text: $partialText)
                                .keyboardType(.numberPad)
                                .focused($inputFocused)
                                .font(mono(22)).foregroundStyle(Color.fg)
                                .padding(.horizontal, 14).frame(height: 52)
                                .background(Color.panel)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.line2, lineWidth: 1))
                            Button("SPEICHERN") {
                                let v = max(0, Int(partialText) ?? 0)
                                onFinish(boss ? Double(v) >= Double(target) * 0.9 : false, target, v)
                            }
                            .buttonStyle(HangarButtonStyle(color: .phos, filled: true))
                            .frame(width: 140)
                        }
                    }
                } else {
                    HStack(spacing: 10) {
                        Button(boss ? "GENAU \(target)" : "GESCHAFFT") { onFinish(true, target, target) }
                            .buttonStyle(HangarButtonStyle(color: .phos, filled: true))
                        Button(boss ? "ANDERE ZAHL" : "NICHT GESCHAFFT") {
                            stopTimer()
                            if partialText.isEmpty && timerValue > 0 { partialText = "\(timerValue)" }
                            showPartial = true
                            inputFocused = true
                        }
                        .buttonStyle(HangarButtonStyle())
                    }
                    Button(action: onSkip) {
                        Text("passt gerade nicht").font(mono(12)).tracking(0.8).foregroundStyle(Color.muted)
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.bg.ignoresSafeArea())
    }

    private var timerRow: some View {
        HStack(spacing: 14) {
            Button(timerStart == nil ? "TIMER STARTEN" : "STOPP") {
                if timerStart == nil { timerStart = Date() } else { stopTimer() }
            }
            .buttonStyle(HangarButtonStyle())
            .frame(width: 170)
            TimelineView(.periodic(from: .now, by: 0.25)) { tl in
                let s = timerStart.map { Int(tl.date.timeIntervalSince($0)) } ?? timerValue
                Text(s >= target ? "\(s) s ✓" : "\(s) s").font(mono(24, .bold)).monospacedDigit()
                    .foregroundStyle(ex.cat.color)
            }
        }
    }

    private func stopTimer() {
        if let t = timerStart { timerValue = Int(Date().timeIntervalSince(t)) }
        timerStart = nil
    }
}

/// Kurze Bestätigung nach einer Übung, dann zurück zum Dashboard
struct DoneOverlay: View {
    let stamp: String
    let text: String
    let partly: Bool
    @State private var shown = false

    var body: some View {
        let c: Color = partly ? .amber : .phos
        VStack(spacing: 16) {
            Text(stamp).font(mono(26, .heavy)).tracking(7).foregroundStyle(c).glow(c, 12)
                .padding(.vertical, 16).padding(.horizontal, 22)
                .overlay(Rectangle().stroke(c, lineWidth: 1))
                .scaleEffect(shown ? 1 : 0.85).opacity(shown ? 1 : 0)
            Text(text).font(mono(14)).foregroundStyle(Color.muted).multilineTextAlignment(.center).padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bg.ignoresSafeArea())
        .onAppear { withAnimation(.easeOut(duration: 0.3)) { shown = true } }
    }
}
