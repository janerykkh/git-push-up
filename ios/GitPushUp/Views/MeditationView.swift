import SwiftUI
import Combine
import UIKit

/// Fünf Minuten sitzen. Keine Anleitung, nur Gong, ein langsam schließender Ring und am Ende wieder Gong.
/// Läuft auch bei gesperrtem Bildschirm weiter.
struct MeditationView: View {
    let onFinish: (_ seconds: Int, _ complete: Bool) -> Void
    let onSkip: () -> Void
    let onClose: () -> Void

    private let total: TimeInterval = 300
    @State private var start: Date? = nil
    @State private var now = Date()
    @State private var finished = false
    @State private var tone = Tone()
    private let ticker = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    private var elapsed: TimeInterval { start.map { min(total, now.timeIntervalSince($0)) } ?? 0 }
    private var progress: Double { elapsed / total }

    var body: some View {
        VStack(spacing: 22) {
            HStack {
                Label12(text: "NEURO-SYNC · GEIST", color: .mind, size: 12)
                Spacer()
                Button {
                    stop(); onClose()
                } label: {
                    Image(systemName: "xmark").foregroundStyle(Color.muted).frame(width: 44, height: 44)
                }
            }

            Text("MEDITATION").font(display(42)).tracking(3).foregroundStyle(Color.fg)
                .frame(maxWidth: .infinity, alignment: .leading)

            ZStack {
                Circle().stroke(Color.line2, lineWidth: 2)
                Circle().trim(from: 0, to: 1 - progress)
                    .stroke(Color.mind, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .glow(.mind, 10)
                NeuroScanView(score: start == nil ? 0.2 : 0.3 + 0.7 * progress)
                    .padding(48)
                    .opacity(0.8)
                VStack(spacing: 4) {
                    let left = Int((total - elapsed).rounded(.up))
                    Text(String(format: "%d:%02d", left / 60, left % 60))
                        .font(mono(46, .bold)).monospacedDigit().foregroundStyle(Color.fg)
                    Label12(text: start == nil ? "BEREIT" : (finished ? "ABGESCHLOSSEN" : "SITZEN"),
                            color: finished ? .phos : .muted)
                }
                .offset(y: 70)
            }
            .aspectRatio(1, contentMode: .fit)
            .padding(.horizontal, 8)

            Text(start == nil
                 ? "Hinsetzen, aufrecht, Augen zu. Beim Start klingt ein Gong, nach fünf Minuten wieder. Das iPhone darf gesperrt werden."
                 : "Augen zu. Der Gong holt dich zurück.")
                .font(mono(13)).foregroundStyle(Color.muted).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if start == nil {
                Button("GONG · START") { begin() }
                    .buttonStyle(HangarButtonStyle(color: .mind, filled: true))
                Button(action: onSkip) {
                    Text("passt gerade nicht").font(mono(12)).foregroundStyle(Color.muted).frame(maxWidth: .infinity, minHeight: 40)
                }
            } else if !finished {
                Button("FRÜHER BEENDEN") { end(complete: false) }
                    .buttonStyle(HangarButtonStyle(color: .muted))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(LabBackdrop())
        .onReceive(ticker) { t in
            now = t
            if let s = start, !finished, t.timeIntervalSince(s) >= total { end(complete: true) }
        }
        .onDisappear { stop() }
    }

    private func begin() {
        UIApplication.shared.isIdleTimerDisabled = true
        tone.startKeepAlive()
        tone.gong()
        start = Date(); now = Date()
    }

    private func end(complete: Bool) {
        guard !finished else { return }
        finished = true
        let secs = Int(elapsed.rounded())
        if complete {
            tone.gong()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        // Gong ausklingen lassen, dann zurück
        DispatchQueue.main.asyncAfter(deadline: .now() + (complete ? 3.5 : 0.1)) {
            stop()
            if secs >= 60 { onFinish(secs, complete) } else { onClose() }
        }
    }

    private func stop() {
        UIApplication.shared.isIdleTimerDisabled = false
        tone.stopKeepAlive()
    }
}
