import SwiftUI
import UIKit

@main
struct GitPushUpApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.light)
        }
    }
}

/// Steuert, welcher Bildschirm gerade oben liegt
struct RootView: View {
    @EnvironmentObject var store: Store
    @Environment(\.scenePhase) private var scenePhase

    @State private var exercise: ActivePick? = nil
    @State private var showManual = false
    @State private var showRecord = false
    @State private var showSettings = false
    @State private var showPulse = false
    @State private var done: DoneInfo? = nil
    @State private var report: ReportReq? = nil

    struct DoneInfo: Equatable { let stamp: String; let text: String; let partly: Bool }
    struct ActivePick: Identifiable { let id = UUID(); let ex: Exercise; let boss: Bool }
    struct ReportReq: Identifiable { let id = UUID(); let muscle: Muscle? }

    private func pickNext(excluding: String? = nil) -> ActivePick {
        let p = store.pick(excluding: excluding)
        return ActivePick(ex: p.ex, boss: p.boss)
    }

    var body: some View {
        ZStack {
            HomeView(
                onGo: { exercise = pickNext() },
                onManual: { showManual = true },
                onRecord: { showRecord = true },
                onSettings: { showSettings = true },
                onPulse: { showPulse = true },
                onReport: { report = ReportReq(muscle: $0) }
            )
            if let d = done {
                DoneOverlay(stamp: d.stamp, text: d.text, partly: d.partly)
                    .transition(.opacity)
                    .onTapGesture { withAnimation { done = nil } }
                    .zIndex(1)
            }
        }
        .fullScreenCover(item: $exercise) { pick in
            let ex = pick.ex
            if ex.kind == .mind {
                MeditationView(
                    onFinish: { secs, complete in
                        store.logResult(ex, target: 300, actual: secs, done: complete)
                        exercise = nil
                        flash("NEURO-SYNC", "\(secs / 60) Minuten Meditation", partly: !complete)
                    },
                    onSkip: { exercise = pickNext(excluding: ex.id) },
                    onClose: { exercise = nil }
                )
            } else {
            ExerciseView(
                ex: ex,
                boss: pick.boss,
                onFinish: { ok, target, actual in
                    store.logResult(ex, target: target, actual: actual, done: ok, boss: pick.boss)
                    let u = ex.unit == .sec ? " s" : ""
                    let side = ex.side ? " pro Seite" : ""
                    exercise = nil
                    if pick.boss {
                        let record = store.checkBossRecord(ex, actual: actual)
                        flash(record ? "NEUER REKORD" : "BOSS BESIEGT", "\(actual)\(u) \(ex.name)\(side)", partly: false)
                    } else {
                        flash(ok ? (ex.kind == .stretch ? "GEWEBE GELÖST" : "PROBE ERFASST") : "TEILPROBE",
                              ok ? "\(target)\(u) \(ex.name)\(side)" : "\(actual) von \(target)\(u) \(ex.name)",
                              partly: !ok)
                    }
                },
                onSkip: { exercise = pickNext(excluding: ex.id) },
                onClose: { exercise = nil }
            )
            .environmentObject(store)
            }
        }
        .fullScreenCover(item: $report) { r in
            LabReportView(
                onExercise: { ex in
                    report = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { exercise = ActivePick(ex: ex, boss: false) }
                },
                onClose: { report = nil },
                selected: r.muscle
            )
            .environmentObject(store)
        }
        .sheet(isPresented: $showManual) {
            ManualEntryView(onDone: { showManual = false })
                .environmentObject(store)
        }
        .fullScreenCover(isPresented: $showRecord) {
            RecordView(
                onClose: { showRecord = false },
                onFinished: {
                    showRecord = false
                    flash("KALIBRIERT", "Ziele neu berechnet. Nächster Rekordtag in 4 Wochen.", partly: false)
                }
            )
            .environmentObject(store)
        }
        .fullScreenCover(isPresented: $showSettings) {
            SettingsView(
                onClose: { showSettings = false },
                onRecordDay: {
                    showSettings = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { showRecord = true }
                }
            )
            .environmentObject(store)
        }
        .fullScreenCover(isPresented: $showPulse) {
            PulseView(onClose: { showPulse = false })
                .environmentObject(store)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { store.weeklyReview() }
        }
    }

    private func flash(_ stamp: String, _ text: String, partly: Bool) {
        UINotificationFeedbackGenerator().notificationOccurred(partly ? .warning : .success)
        withAnimation(.easeOut(duration: 0.2)) { done = DoneInfo(stamp: stamp, text: text, partly: partly) }
        let current = done
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if done == current { withAnimation(.easeIn(duration: 0.25)) { done = nil } }
        }
    }
}
