import SwiftUI

/// Übung nachtragen, die du außerhalb der App gemacht hast, damit die Erschöpfung stimmt
struct ManualEntryView: View {
    @EnvironmentObject var store: Store
    let onDone: () -> Void

    @State private var exId: String = Exercise.all.first { !$0.retired }?.id ?? "pushup"
    @State private var amount = ""
    @State private var sets = 1
    @State private var hoursAgo: Double = 0
    @FocusState private var focused: Bool

    private struct Ago: Identifiable { let id: Double; let label: String }
    private let agoOptions: [Ago] = [Ago(id: 0, label: "JETZT"), Ago(id: 1, label: "VOR 1 H"), Ago(id: 3, label: "VOR 3 H"),
                                     Ago(id: 6, label: "VOR 6 H"), Ago(id: 20, label: "GESTERN")]

    private var ex: Exercise? { Exercise.byId[exId] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("NACHTRAGEN").font(mono(15, .bold)).tracking(2).foregroundStyle(Color.wire)
                    Spacer()
                    Button(action: onDone) {
                        PixelIcon(rows: PixelIcon.close, color: .muted).frame(width: 44, height: 44)
                    }
                }

                Text("Für Sätze, die du ohne die App gemacht hast. Sie zählen für Erschöpfung und Wochen-Belastung, aber nicht für deine Ziele.")
                    .font(mono(12)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)

                Label12(text: "ÜBUNG")
                VStack(spacing: 0) {
                    ForEach(store.pool) { e in
                        Button { exId = e.id } label: {
                            HStack(spacing: 12) {
                                Rectangle().fill(e.cat.color).frame(width: PX * 3, height: PX * 3)
                                Text(e.name).font(mono(14)).foregroundStyle(exId == e.id ? Color.amber : Color.fg)
                                Spacer()
                                if exId == e.id { PixelIcon(rows: ["......#", ".....#.", "#...#..", ".#.#...", "..#...."], color: .amber) }
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                            .overlay(alignment: .top) { Rectangle().fill(Color.line).frame(height: 1) }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let ex {
                    Label12(text: (ex.unit == .sec ? "SEKUNDEN PRO SATZ" : "WIEDERHOLUNGEN PRO SATZ") + (ex.side ? " (PRO SEITE)" : ""))
                    HStack(spacing: 10) {
                        TextField("0", text: $amount)
                            .keyboardType(.numberPad).focused($focused)
                            .font(mono(22)).foregroundStyle(Color.fg)
                            .padding(.horizontal, 14).frame(height: 52)
                            .background(Color.panel)
                            .overlay(PixelFrame().fill(Color.line2))
                        Stepper(value: $sets, in: 1...10) {
                            Text("\(sets) \(sets == 1 ? "SATZ" : "SÄTZE")").font(mono(13, .bold)).foregroundStyle(Color.fg)
                        }
                        .frame(width: 170)
                    }
                }

                Label12(text: "WANN")
                HStack(spacing: 4) {
                    ForEach(agoOptions) { opt in
                        let on = hoursAgo == opt.id
                        Button { hoursAgo = opt.id } label: {
                            Text(opt.label).font(mono(10.5, on ? .bold : .regular)).tracking(0.8)
                                .foregroundStyle(on ? Color.amber : Color.muted)
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .overlay(alignment: .bottom) { Rectangle().fill(on ? Color.amber : Color.line2).frame(height: 1) }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button("EINTRAGEN") {
                    guard let ex, let n = Int(amount), n > 0 else { return }
                    for i in 0..<sets {
                        // Sätze ein paar Minuten auseinander, damit die Reihenfolge stimmt
                        store.logManual(ex, actual: n, hoursAgo: hoursAgo + Double(sets - 1 - i) * 0.05)
                    }
                    onDone()
                }
                .buttonStyle(HangarButtonStyle(color: .phos, filled: true))
                .disabled(Int(amount) == nil)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(LabBackdrop())
        .presentationBackground(Color.bg)
    }
}
