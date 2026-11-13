import SwiftUI

/// Rekordtag: fünf Markertests. Jeder einzeln machbar, Ergebnisse bleiben bis zum Abschließen gespeichert.
struct RecordView: View {
    @EnvironmentObject var store: Store
    let onClose: () -> Void
    let onFinished: () -> Void

    @State private var selected: String? = nil
    @State private var input = ""
    @State private var timerStart: Date? = nil
    @FocusState private var inputFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Button(action: { onClose() }) {
                            Text("← ZURÜCK").font(mono(12)).tracking(1).foregroundStyle(Color.muted).frame(minHeight: 44)
                        }
                        Spacer()
                        Text("REKORDTAG").font(mono(15, .bold)).tracking(2).foregroundStyle(Color.amber)
                        Spacer()
                        Color.clear.frame(width: 70, height: 1)
                    }

                    Text((store.hasBaseline ? "Alle vier Wochen: neue Rekorde, neue Baseline. "
                          : "Einmalige Kalibrierung: fünf kurze Tests, daraus berechnet der Trainer deine Ziele. ")
                         + "Jeweils so viel wie sauber geht, dann aufhören. Zwischen den Tests 2–3 Minuten Pause. Du musst nicht alle auf einmal machen.")
                        .font(mono(12)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 0) {
                        ForEach(Marker.all) { m in markerRow(m) }
                    }

                    if let id = selected, let m = Marker.all.first(where: { $0.id == id }), let ex = Exercise.byId[id] {
                        testPanel(m, ex).id("test")
                    }

                    let n = store.state.trainer.pending.count
                    if n > 0 {
                        Button(n < Marker.all.count ? "MIT \(n)/\(Marker.all.count) TESTS ABSCHLIESSEN" : "REKORDTAG ABSCHLIESSEN") {
                            store.finishRecordDay()
                            onFinished()
                        }
                        .buttonStyle(HangarButtonStyle(color: .phos, filled: true))
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: selected) { _ in
                withAnimation { proxy.scrollTo("test", anchor: .top) }
            }
        }
        .background(LabBackdrop())
        .onAppear {
            if selected == nil && store.state.trainer.pending.isEmpty { open(Marker.all[0].id) }
        }
    }

    private func markerRow(_ m: Marker) -> some View {
        let u = m.unit == .sec ? " s" : ""
        let prev = store.state.trainer.baseline?[m.id]
        let now = store.state.trainer.pending[m.id]
        let color = Exercise.byId[m.id]?.cat.color ?? .wire
        return Button { open(m.id) } label: {
            HStack(spacing: 12) {
                Circle().fill(color).frame(width: 6, height: 6).glow(color, 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.label).font(mono(14)).foregroundStyle(Color.fg)
                    Text(prev.map { "Bisher: \($0)\(u)" } ?? "noch kein Rekord").font(mono(11)).foregroundStyle(Color.muted)
                }
                Spacer()
                if let v = now {
                    HStack(spacing: 6) {
                        Text("✓ \(v)\(u)").foregroundStyle(Color.phos)
                        if let p = prev, v > p { Text("NEU!").foregroundStyle(Color.amber).bold() }
                    }
                    .font(mono(13))
                } else {
                    Text("offen").font(mono(13)).foregroundStyle(Color.muted)
                }
            }
            .padding(.vertical, 10).padding(.horizontal, 6)
            .background(selected == m.id ? Color.amber.opacity(0.06) : Color.clear)
            .overlay(alignment: .top) { Rectangle().fill(Color.line).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func testPanel(_ m: Marker, _ ex: Exercise) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Rectangle().fill(Color.line2).frame(height: 1)
            Text(m.label.uppercased()).font(mono(26, .bold)).foregroundStyle(Color.fg)
            StickFigure(ex: ex).id(ex.id)
            Text(m.how).font(mono(14)).foregroundStyle(Color.fg).fixedSize(horizontal: false, vertical: true)
            if m.unit == .sec {
                HStack(spacing: 14) {
                    Button(timerStart == nil ? "TIMER STARTEN" : "STOPP") {
                        if let t = timerStart { input = "\(Int(Date().timeIntervalSince(t)))"; timerStart = nil }
                        else { timerStart = Date() }
                    }
                    .buttonStyle(HangarButtonStyle()).frame(width: 170)
                    TimelineView(.periodic(from: .now, by: 0.25)) { tl in
                        let s = timerStart.map { Int(tl.date.timeIntervalSince($0)) } ?? (Int(input) ?? 0)
                        Text("\(s) s").font(mono(24, .bold)).monospacedDigit().foregroundStyle(ex.cat.color)
                    }
                }
            }
            Text(m.unit == .sec ? "Wie viele Sekunden hast du gehalten?" : "Wie viele hast du geschafft?")
                .font(mono(13)).foregroundStyle(Color.muted)
            HStack(spacing: 10) {
                TextField("0", text: $input)
                    .keyboardType(.numberPad).focused($inputFocused)
                    .font(mono(22)).foregroundStyle(Color.fg)
                    .padding(.horizontal, 14).frame(height: 52)
                    .background(Color.panel)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.line2, lineWidth: 1))
                Button("SPEICHERN") {
                    guard let v = Int(input), v > 0 else { return }
                    timerStart = nil
                    inputFocused = false
                    store.saveTest(m, value: v)
                    if let next = Marker.all.first(where: { store.state.trainer.pending[$0.id] == nil }) { open(next.id) }
                    else { selected = nil }
                }
                .buttonStyle(HangarButtonStyle(color: .phos, filled: true)).frame(width: 140)
            }
        }
    }

    private func open(_ id: String) {
        timerStart = nil
        selected = id
        input = store.state.trainer.pending[id].map { "\($0)" } ?? ""
    }
}
