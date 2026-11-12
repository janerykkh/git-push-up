import SwiftUI
import UIKit

/// Protein eintragen: ganze oder halbe Portion antippen, oder direkt ein Lebensmittel aus der Liste.
struct ProteinView: View {
    @EnvironmentObject var store: Store
    let onClose: () -> Void
    @State private var flashText: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("PROTEIN").font(mono(15, .bold)).tracking(2).foregroundStyle(Color.ziehen).glow(.ziehen, 6)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark").foregroundStyle(Color.muted).frame(width: 44, height: 44)
                    }
                }

                summary

                HStack(spacing: 10) {
                    Button { add(1, nil) } label: {
                        VStack(spacing: 4) {
                            Text("+ GANZE").font(mono(16, .heavy)).tracking(2)
                            Text("PORTION · ~25 G").font(mono(10)).tracking(1).foregroundStyle(Color.muted)
                        }
                        .foregroundStyle(Color.ziehen)
                        .frame(maxWidth: .infinity, minHeight: 72)
                        .background(Color.ziehen.opacity(0.1))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.ziehen, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    Button { add(0.5, nil) } label: {
                        VStack(spacing: 4) {
                            Text("+ HALBE").font(mono(16, .heavy)).tracking(2)
                            Text("PORTION · ~12 G").font(mono(10)).tracking(1).foregroundStyle(Color.muted)
                        }
                        .foregroundStyle(Color.ziehen)
                        .frame(maxWidth: .infinity, minHeight: 72)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.ziehen.opacity(0.6), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                if let t = flashText {
                    Text(t).font(mono(12)).foregroundStyle(Color.phos).transition(.opacity)
                }

                Block(title: "WAS IST EINE PORTION?", trailing: "antippen zum Eintragen") {
                    VStack(spacing: 0) {
                        ForEach(ProteinModel.foods) { f in
                            Button { add(f.portions, f.id) } label: {
                                HStack(spacing: 10) {
                                    Text(portionText(f.portions)).font(mono(12, .bold)).foregroundStyle(Color.ziehen)
                                        .frame(width: 34, alignment: .leading)
                                    Text(f.id).font(mono(13)).foregroundStyle(Color.fg).multilineTextAlignment(.leading)
                                    Spacer(minLength: 6)
                                    Text(f.note).font(mono(11)).foregroundStyle(Color.muted)
                                }
                                .padding(.vertical, 9)
                                .contentShape(Rectangle())
                                .overlay(alignment: .top) { Rectangle().fill(Color.line).frame(height: 1) }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text("Richtwerte, gerundet. Bei 1 = ganze Portion, ½ = halbe, ¾ = drei Viertel.")
                        .font(mono(10.5)).foregroundStyle(Color.dim)
                }

                Block(title: "HEUTE") {
                    let s = store.startOfDay()
                    let today = store.state.protein.filter { $0.ts >= s }
                    if today.isEmpty {
                        Text("Noch nichts eingetragen.").font(mono(12)).foregroundStyle(Color.muted)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(today.reversed()) { e in
                                HStack {
                                    Text(portionText(e.portions)).font(mono(12, .bold)).foregroundStyle(Color.ziehen).frame(width: 34, alignment: .leading)
                                    Text(e.label ?? "Portion").font(mono(12)).foregroundStyle(Color.fg)
                                    Spacer()
                                    Text(fmtTime(e.ts).components(separatedBy: " · ").last ?? "").font(mono(11)).foregroundStyle(Color.muted)
                                }
                                .padding(.vertical, 8)
                                .overlay(alignment: .top) { Rectangle().fill(Color.line).frame(height: 1) }
                            }
                        }
                        Button("LETZTEN EINTRAG ENTFERNEN") { store.undoLastProtein() }
                            .buttonStyle(HangarButtonStyle(color: .muted))
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(Color.bg.ignoresSafeArea())
        .presentationBackground(Color.bg)
    }

    private var summary: some View {
        let todayG = store.proteinToday
        let avg = store.proteinAverage
        let days = store.proteinLast7
        let maxG = max(ProteinModel.targetHigh, days.max() ?? 0)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Label12(text: "HEUTE")
                    Text("\(Int(todayG.rounded())) g").font(mono(30, .heavy)).monospacedDigit().foregroundStyle(Color.fg)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Label12(text: "Ø 7 TAGE")
                    Text(avg.map { "\(Int($0.rounded())) g" } ?? "–").font(mono(30, .heavy)).monospacedDigit()
                        .foregroundStyle(avgColor(avg)).glow(avgColor(avg), 8)
                }
                Spacer()
            }
            Text(avgText(avg)).font(mono(11)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
            // 7 Balken, Zielbereich als Band
            GeometryReader { g in
                let w = g.size.width / 7
                ZStack(alignment: .bottomLeading) {
                    Rectangle().fill(Color.ziehen.opacity(0.08))
                        .frame(height: g.size.height * CGFloat((ProteinModel.targetHigh - ProteinModel.targetLow) / maxG))
                        .offset(y: -g.size.height * CGFloat(ProteinModel.targetLow / maxG))
                    ForEach(0..<7, id: \.self) { i in
                        let v = days[i]
                        Rectangle().fill(i == 6 ? Color.ziehen : Color.ziehen.opacity(0.55))
                            .frame(width: w * 0.6, height: max(1, g.size.height * CGFloat(v / maxG)))
                            .offset(x: w * CGFloat(i) + w * 0.2)
                    }
                }
            }
            .frame(height: 70)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.line2).frame(height: 1) }
        }
    }

    private func avgColor(_ a: Double?) -> Color {
        guard let a else { return .muted }
        if a >= ProteinModel.targetLow { return .phos }
        if a < ProteinModel.warnBelow { return .amber }
        return .ziehen
    }

    private func avgText(_ a: Double?) -> String {
        guard let a else { return "Ziel: im Schnitt 90–100 g am Tag. Einzelne Tage dürfen schwanken." }
        if a >= ProteinModel.targetLow { return "Im Zielbereich. Weiter so, einzelne Tage dürfen schwanken." }
        if a < ProteinModel.warnBelow { return "Der Schnitt liegt unter 80 g. Eine proteinreiche Hauptzutat pro Mahlzeit hilft am meisten." }
        return "Knapp unter dem Ziel von 90–100 g, kein Grund zur Sorge."
    }

    private func portionText(_ p: Double) -> String {
        switch p {
        case 1: return "1"
        case 0.75: return "¾"
        case 0.5: return "½"
        case 0.25: return "¼"
        default: return String(format: "%.1f", p)
        }
    }

    private func add(_ p: Double, _ label: String?) {
        store.addProtein(p, label: label)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation { flashText = "+ \(Int((p * ProteinModel.gramsPerPortion).rounded())) g eingetragen" }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation { flashText = nil } }
    }
}

extension Color {
    /// Protein-Farbe: das kühle Blau der Kategorie "Ziehen"
    static let ziehen = Color(hex: 0x7fd3ff)
}
