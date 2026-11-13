import SwiftUI
import UIKit

/// Eine Übung, die gerade läuft
struct ActivePick: Identifiable { let id = UUID(); let ex: Exercise; let boss: Bool }

/// Rückmeldung nach einer Übung (kurzer Stempel über dem Bildschirm)
struct DoneInfo: Equatable {
    let stamp: String; let text: String; let partly: Bool
    /// Welche Übung (für die Pulsmessung danach)
    var exId: String? = nil
    var strength = false
}

/// Pulsmessung direkt nach einer Übung
struct PulseAfter: Identifiable { let id = UUID(); let exId: String }

/// Führt eine Übung durch und trägt sie ein: Kraft und Dehnen über ExerciseView, Meditation über den Timer.
/// Wird vom Startbildschirm (GO, +) und aus der Laborakte heraus benutzt.
struct ActivityRunner: View {
    @EnvironmentObject var store: Store
    let pick: ActivePick
    let onDone: (DoneInfo) -> Void
    let onSkip: () -> Void
    let onClose: () -> Void

    var body: some View {
        let ex = pick.ex
        if ex.kind == .mind {
            MeditationView(
                onFinish: { secs, complete in
                    store.logResult(ex, target: 300, actual: secs, done: complete)
                    onDone(DoneInfo(stamp: "NEURO-SYNC", text: "\(secs / 60) Minuten Meditation", partly: !complete, exId: ex.id))
                },
                onSkip: onSkip,
                onClose: onClose
            )
        } else {
            ExerciseView(
                ex: ex,
                boss: pick.boss,
                onFinish: { ok, target, actual in
                    store.logResult(ex, target: target, actual: actual, done: ok, boss: pick.boss)
                    let u = ex.unit == .sec ? " s" : ""
                    let side = ex.side ? " pro Seite" : ""
                    if pick.boss {
                        let record = store.checkBossRecord(ex, actual: actual)
                        onDone(DoneInfo(stamp: record ? "NEUER REKORD" : "BOSS BESIEGT", text: "\(actual)\(u) \(ex.name)\(side)", partly: false,
                                        exId: ex.id, strength: true))
                    } else {
                        onDone(DoneInfo(stamp: ok ? (ex.kind == .stretch ? "GEWEBE GELÖST" : "PROBE ERFASST") : "TEILPROBE",
                                        text: ok ? "\(target)\(u) \(ex.name)\(side)" : "\(actual) von \(target)\(u) \(ex.name)",
                                        partly: !ok, exId: ex.id, strength: ex.kind == .strength))
                    }
                },
                onSkip: onSkip,
                onClose: onClose
            )
        }
    }
}

/// Zeigt den Stempel nach einer Übung kurz an und blendet ihn wieder aus
struct DoneFlash: ViewModifier {
    @Binding var item: DoneInfo?
    func body(content: Content) -> some View {
        ZStack {
            content
            if let d = item {
                DoneOverlay(stamp: d.stamp, text: d.text, partly: d.partly)
                    .transition(.opacity)
                    .onTapGesture { withAnimation { item = nil } }
                    .zIndex(1)
            }
        }
        .onChange(of: item) { d in
            guard let d else { return }
            UINotificationFeedbackGenerator().notificationOccurred(d.partly ? .warning : .success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                if item == d { withAnimation(.easeIn(duration: 0.25)) { item = nil } }
            }
        }
    }
}

extension View {
    func doneFlash(_ item: Binding<DoneInfo?>) -> some View { modifier(DoneFlash(item: item)) }

    /// Nach einer Kraftübung (wenn eingeschaltet) kurz nach dem Stempel die Pulsmessung öffnen.
    /// Schließen geht jederzeit, dann wird nichts gespeichert.
    func pulseAfterExercise(_ item: Binding<PulseAfter?>, store: Store) -> some View {
        fullScreenCover(item: item) { p in
            PulseView(onClose: { item.wrappedValue = nil }, afterExercise: p.exId)
                .environmentObject(store)
        }
    }
}

extension Store {
    /// Nach dieser Rückmeldung den Puls anbieten?
    func offerPulse(after d: DoneInfo) -> PulseAfter? {
        guard state.pulseAfter, d.strength, let id = d.exId else { return nil }
        return PulseAfter(exId: id)
    }
}

/// Der +-Knopf: jede Übung direkt auswählen und sofort machen
struct ExercisePickerView: View {
    @EnvironmentObject var store: Store
    let onPick: (Exercise) -> Void
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("ÜBUNG WÄHLEN").font(display(24)).tracking(1).foregroundStyle(Color.fg)
                        Label12(text: "ANTIPPEN UND SOFORT LOSLEGEN", color: .dim, size: 9)
                    }
                    Spacer()
                    Button(action: onClose) { PixelIcon(rows: PixelIcon.close, color: .muted).frame(width: 44, height: 44) }
                }
                section("KRAFT", .strength)
                section("DEHNEN", .stretch)
                section("GEIST", .mind)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(LabBackdrop())
    }

    private func section(_ title: String, _ k: ActivityKind) -> some View {
        let list = store.pool.filter { $0.kind == k }
        return Block(title: title, accent: k == .strength ? .signal : (k == .stretch ? .wire : .mind)) {
            VStack(spacing: 0) {
                ForEach(list) { ex in
                    Button { onPick(ex) } label: {
                        HStack(spacing: 10) {
                            Rectangle().fill(ex.cat.color).frame(width: PX * 3, height: PX * 3)
                            Text(ex.name).font(mono(14)).foregroundStyle(Color.fg)
                            Spacer()
                            Text(detail(ex)).font(mono(11)).foregroundStyle(Color.muted)
                            PixelIcon(rows: PixelIcon.arrow, color: .muted)
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .top) { Rectangle().fill(Color.line).frame(height: PX / 2) }
                }
            }
        }
    }

    private func detail(_ ex: Exercise) -> String {
        if ex.kind == .mind { return "5 MIN" }
        if ex.kind == .stretch { return ex.cat.label.uppercased() }
        let u = ex.unit == .sec ? " s" : ""
        return "\(store.perTime(ex))\(u)\(ex.side ? "/S" : "")"
    }
}
