import SwiftUI
import Combine
import UIKit

/// Fünf Minuten sitzen. Keine Anleitung, nur Gong, ein langsam schließender Ring und am Ende wieder Gong.
/// Läuft auch bei gesperrtem Bildschirm weiter.
struct MeditationView: View {
    let onFinish: (_ seconds: Int, _ complete: Bool) -> Void
    let onSkip: () -> Void
    let onClose: () -> Void
    /// Wird beim Drücken auf Start gefragt (z. B. Puls vorher messen); ruft danach `go` auf, dann startet der Gong
    var beforeStart: ((_ go: @escaping () -> Void) -> Void)? = nil

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
                    PixelIcon(rows: PixelIcon.close, color: .muted).frame(width: 44, height: 44)
                }
            }

            Text("MEDITATION").font(display(42)).tracking(3).foregroundStyle(Color.fg)
                .frame(maxWidth: .infinity, alignment: .leading)

            ZStack {
                // Restzeit als Pixelring
                Canvas { ctx, size in
                    let c = CGPoint(x: size.width / 2, y: size.height / 2), r = min(size.width, size.height) / 2 - PX * 3
                    var all = PixelPath(), left = PixelPath()
                    let steps = 160, rest = 1 - progress
                    for i in 0...steps {
                        let f = Double(i) / Double(steps), a = -Double.pi / 2 + f * 2 * .pi
                        let p = CGPoint(x: c.x + CGFloat(cos(a)) * r, y: c.y + CGFloat(sin(a)) * r)
                        if i == 0 { all.move(to: p); left.move(to: p) } else {
                            all.addLine(to: p)
                            if f <= rest { left.addLine(to: p) }
                        }
                    }
                    ctx.pixelStroke(all, .line, size: PX)
                    ctx.pixelStroke(left, .mind, size: PX * 2)
                }
                ResonanceWave(calm: start == nil ? 0.3 : 0.4 + 0.6 * progress, color: .mind)
                    .frame(height: 40)
                    .padding(.horizontal, 56)
                    .offset(y: -10)
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
                Button("GONG · START") {
                    if let b = beforeStart { b { begin() } } else { begin() }
                }
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
