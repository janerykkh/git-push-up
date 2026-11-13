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

/// Wohin die Laborakte beim Öffnen springen soll
enum ReportJump: Equatable { case top, muscle(Muscle), history }

/// Steuert, welcher Bildschirm gerade oben liegt
struct RootView: View {
    @EnvironmentObject var store: Store
    @Environment(\.scenePhase) private var scenePhase

    @State private var exercise: ActivePick? = nil
    @State private var showPicker = false
    @State private var showRecord = false
    @State private var showSettings = false
    @State private var showPulse = false
    @State private var done: DoneInfo? = nil
    @State private var report: ReportReq? = nil

    struct ReportReq: Identifiable { let id = UUID(); let jump: ReportJump }

    private func pickNext(excluding: String? = nil) -> ActivePick {
        let p = store.pick(excluding: excluding)
        return ActivePick(ex: p.ex, boss: p.boss)
    }

    var body: some View {
        HomeView(
            onGo: { exercise = pickNext() },
            onPickExercise: { showPicker = true },
            onRecord: { showRecord = true },
            onSettings: { showSettings = true },
            onPulse: { showPulse = true },
            onReport: { report = ReportReq(jump: $0) }
        )
        .doneFlash($done)
        .fullScreenCover(item: $exercise) { pick in
            ActivityRunner(
                pick: pick,
                onDone: { d in exercise = nil; done = d },
                onSkip: { exercise = pickNext(excluding: pick.ex.id) },
                onClose: { exercise = nil }
            )
            .environmentObject(store)
        }
        .fullScreenCover(item: $report) { r in
            LabReportView(onClose: { report = nil }, jump: r.jump)
                .environmentObject(store)
        }
        .sheet(isPresented: $showPicker) {
            ExercisePickerView(
                onPick: { ex in
                    showPicker = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { exercise = ActivePick(ex: ex, boss: false) }
                },
                onClose: { showPicker = false }
            )
            .environmentObject(store)
        }
        .fullScreenCover(isPresented: $showRecord) {
            RecordView(
                onClose: { showRecord = false },
                onFinished: {
                    showRecord = false
                    done = DoneInfo(stamp: "KALIBRIERT", text: "Ziele neu berechnet. Nächster Rekordtag in 4 Wochen.", partly: false)
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
}
