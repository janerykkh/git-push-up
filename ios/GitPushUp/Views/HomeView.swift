import SwiftUI

/// Startbildschirm im Stil eines Laborblatts: oben der Glaskasten, darunter das Datenblatt des Wesens
/// (Name, Serie, Pflegepunkte, Wachstum, 14-Tage-Protokoll, Prägung, EEG), unten eine schmale Leiste mit GO und Laborakte.
struct HomeView: View {
    @EnvironmentObject var store: Store
    let onGo: () -> Void
    let onManual: () -> Void
    let onRecord: () -> Void
    let onSettings: () -> Void
    let onPulse: () -> Void
    let onReport: (Muscle?) -> Void

    @State private var previewG: Double? = nil
    @State private var previewTask: Task<Void, Never>? = nil
    @State private var renaming = false
    @State private var newName = ""

    var body: some View {
        TimelineView(.periodic(from: .now, by: 10)) { _ in
            let v = store.vitals()
            let creature = store.state.creature
            GeometryReader { geo in
                VStack(spacing: 0) {
                    tank(creature, v)
                        .frame(height: geo.safeAreaInsets.top + geo.size.height * 0.38)
                    VStack(alignment: .leading, spacing: 8) {
                        header(creature, v)
                        statCells(v)
                        careStrip
                        traitGauges(v)
                        eegBox
                        Spacer(minLength: 0)
                        bottomBar
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
                }
                .ignoresSafeArea(edges: .top)
            }
        }
        .background(Color.bg.ignoresSafeArea())
        .onAppear { store.ensureCreature() }
        .alert("Name", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Abbrechen", role: .cancel) {}
            Button("Speichern") { store.renameCreature(newName) }
        } message: {
            Text("Wie soll dein Wesen heißen?")
        }
    }

    // MARK: Glaskasten

    @ViewBuilder
    private func tank(_ c: CreatureState?, _ v: CreatureVitals) -> some View {
        if let c {
            LabTankView(seed: c.seed, vitals: v, previewG: previewG)
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 0.6) { startPreview() }
                .overlay(alignment: .bottomLeading) {
                    if let p = previewG {
                        Text("ZEITRAFFER // TAG \(String(format: "%03d", Int((p * 60).rounded())))")
                            .font(mono(9, .semibold)).foregroundStyle(Color.bg)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color.fg)
                            .padding(.leading, 12).padding(.bottom, 36)
                            .transition(.opacity)
                    }
                }
        } else {
            Color.glassTop
        }
    }

    /// Lange drücken: so wächst es bei der jetzigen Pflege, von der Zelle bis ausgewachsen
    private func startPreview() {
        previewTask?.cancel()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        previewTask = Task { @MainActor in
            let dur = 9.0, start = Date()
            while !Task.isCancelled {
                let p = min(1, Date().timeIntervalSince(start) / dur)
                previewG = p
                if p >= 1 { break }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if !Task.isCancelled { withAnimation { previewG = nil } }
        }
    }

    // MARK: Datenblatt

    private func header(_ c: CreatureState?, _ v: CreatureVitals) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text("\(v.stage) //").foregroundStyle(Color.muted)
                    Rectangle().fill(v.health >= 0.15 ? Color.signal : Color.dim).frame(width: PX * 3, height: PX * 3)
                    Text(v.healthLabel)
                }
                .font(labelFont(9)).tracking(0.8)
                Button {
                    newName = c?.name ?? ""
                    renaming = true
                } label: {
                    Text((c?.name ?? "—").uppercased())
                        .font(display(38)).tracking(0.5).foregroundStyle(Color.fg)
                        .lineLimit(1).minimumScaleFactor(0.5)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Umbenennen")
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text("ID \(c.map { String($0.seed) } ?? "—")")
                Text("TAG \(String(format: "%03d", v.ageDays))")
                Text("STUFE \(String(format: "%02d", v.stageIndex))/05")
            }
            .font(mono(10))
            .padding(.bottom, 4)
        }
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.line2).frame(height: PX) }
    }

    private func statCells(_ v: CreatureVitals) -> some View {
        HStack(spacing: 6) {
            cell("SERIE", String(format: "%02d", min(99, store.streak))) {
                Text(v.streakBonus > 0 ? "BONUS +\(Int((v.streakBonus * 100).rounded())) %" : "TAGE AM STÜCK")
                    .font(mono(9, v.streakBonus > 0 ? .bold : .regular)).foregroundStyle(v.streakBonus > 0 ? Color.signal : Color.muted)
            }
            .frame(maxWidth: 92)
            cell("HEUTE", String(format: "%02d", min(99, v.todayCount))) {
                Text(v.todayCount == 1 ? "ÜBUNG" : "ÜBUNGEN").font(mono(9)).foregroundStyle(Color.muted)
            }
            .frame(maxWidth: 92)
            growthCell(v)
        }
    }

    /// Wachstum: grün, wenn es gerade wächst (je kräftiger, desto grüner), grau bei Stillstand, rot beim Schrumpfen.
    /// Darunter, wie lange es bis 100 % dauert, wenn es so weitergeht wie in den letzten Tagen.
    private func growthCell(_ v: CreatureVitals) -> some View {
        let tr = v.trend
        let c: Color = tr > 0.03 ? Color.grow(min(1, tr)) : (tr < -0.03 ? Color.danger : Color.muted)
        let eta: String = {
            if v.g >= 0.9999 { return "AUSGEWACHSEN" }
            guard let d = v.etaDays, d < 999 else { return "BIS 100 %: ----" }
            return d < 1 ? "BIS 100 %: < 1 TAG" : "BIS 100 %: ≈ \(Int(d.rounded())) TAGE"
        }()
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text("WACHSTUM").font(labelFont(9)).tracking(0.8)
                Spacer()
                Text(tr > 0.03 ? "▲" : (tr < -0.03 ? "▼" : "■")).font(mono(9, .bold)).foregroundStyle(c)
            }
            Text(de(v.g * 100, 2) + " %").font(display(26)).monospacedDigit().foregroundStyle(c).lineLimit(1).minimumScaleFactor(0.5)
            Text(eta).font(mono(9, .bold)).foregroundStyle(c)
        }
        .padding(.horizontal, 7).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pixelBorder()
    }

    /// Zahl mit Komma und fester Nachkommazahl
    private func de(_ x: Double, _ digits: Int) -> String {
        String(format: "%.\(digits)f", x).replacingOccurrences(of: ".", with: ",")
    }

    private func cell<F: View>(_ title: String, _ value: String, @ViewBuilder footer: () -> F) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(labelFont(9)).tracking(0.8)
            Text(value).font(display(26)).monospacedDigit().foregroundStyle(Color.fg).lineLimit(1).minimumScaleFactor(0.5)
            footer()
        }
        .padding(.horizontal, 7).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pixelBorder()
    }

    /// Die letzten 14 Tage: leer = nichts, grau = etwas, schwarz = gut gepflegt; heute orange umrandet
    private var careStrip: some View {
        let pts = store.carePoints(days: 14)
        return HStack(spacing: 6) {
            Text("PFLEGE 14T").font(labelFont(9)).tracking(0.8).frame(width: 66, alignment: .leading)
            HStack(spacing: PX * 2) {
                ForEach(Array(pts.enumerated()), id: \.offset) { i, p in
                    let isToday = i == pts.count - 1
                    let fill: Color = p == nil ? .clear : ((p ?? 0) >= 3 ? Color.fg : ((p ?? 0) > 0 ? Color.dim : .clear))
                    PixelBlock().fill(fill)
                        .frame(maxWidth: .infinity).frame(height: PX * 5)
                        .overlay(PixelFrame().fill(isToday ? Color.signal : (p == nil ? Color.line : Color.line2)))
                }
            }
        }
    }

    /// Anteile der drei Pflegearten. Wer immer GO folgt, landet bei etwa 33/33/33; was du überspringst oder selbst
    /// dazunimmst, verschiebt die Anteile, und das Wesen entwickelt sich in diese Richtung.
    private func traitGauges(_ v: CreatureVitals) -> some View {
        VStack(spacing: 4) {
            gauge("TONUS", v.shares.s)
            gauge("FLEXIBILITÄT", v.shares.t)
            gauge("RESONANZ", v.shares.m)
        }
    }

    private func gauge(_ name: String, _ share: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(name).font(labelFont(9)).tracking(0.8)
                Spacer()
                Text("\(String(format: "%02d", Int((share * 100).rounded()))) %").font(mono(10, .bold)).monospacedDigit()
            }
            PixelBar(value: share, color: .signal, height: 4)
        }
    }

    private var eegBox: some View {
        let calm = store.eegCalm
        let h = store.hoursSinceKind(.mind)
        let state: String = calm >= 0.7 ? "α · RUHIG" : (calm >= 0.4 ? "α/β · WACH" : (calm >= 0.15 ? "β · UNRUHIG" : "γ · RAUSCHEN"))
        let since: String = h >= 999 ? "NOCH KEINE MEDITATION"
            : (h < 48 ? "MEDITATION VOR \(String(format: "%02d", Int(h))) H" : "MEDITATION VOR \(Int(h / 24)) T")
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text("EEG").font(labelFont(9)).tracking(0.8)
                Text("// \(state)").font(mono(9, .bold))
                Spacer()
                Text(since).font(mono(9)).foregroundStyle(Color.muted)
            }
            EEGWave(calm: calm).frame(height: 18)
        }
        .padding(.horizontal, 7).padding(.vertical, 5)
        .pixelBorder()
    }

    // MARK: Leiste unten

    private var bottomBar: some View {
        let f = store.fatigue()
        let tired = f.values.filter { $0 >= 0.5 }.count
        let first = !store.hasBaseline
        return HStack(spacing: 6) {
            Button(action: { first ? onRecord() : onGo() }) {
                ZStack {
                    PixelBlock().fill(Color.signal)
                    Text(first ? "START" : "GO").font(display(first ? 20 : 30)).tracking(1).foregroundStyle(Color.white)
                }
                .frame(width: first ? 84 : 62)
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel(first ? "Start: Kraft messen" : "Los, nächste Übung")

            Button { onReport(nil) } label: {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("LABORAKTE").font(labelFont(11)).tracking(1)
                        Spacer()
                        PixelIcon(rows: PixelIcon.arrow, color: .bg)
                    }
                    Spacer(minLength: 2)
                    if store.hasBaseline && store.recordDue {
                        Text("REKORDTAG FÄLLIG").font(mono(9, .bold)).foregroundStyle(Color.signal)
                    } else {
                        Text("KÖRPER \(String(format: "%02d", tired))/\(Muscle.allCases.count) BELASTET").font(mono(9))
                            .foregroundStyle(Color.bg.opacity(0.65))
                    }
                }
                .foregroundStyle(Color.bg)
                .padding(.horizontal, 9).padding(.vertical, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(PixelBlock().fill(Color.wire))
            }
            .buttonStyle(PressStyle())

            PixelToolButton(icon: PixelIcon.plus, label: "Nachtragen", enabled: store.hasBaseline, action: onManual).frame(width: 40)
            PixelToolButton(icon: PixelIcon.pulse, label: "Puls", action: onPulse).frame(width: 40)
            PixelToolButton(icon: PixelIcon.gear, label: "Einstellungen", action: onSettings).frame(width: 40)
        }
        .frame(height: 62)
    }

}

// MARK: - Bausteine

extension Color {
    static let go = Color.signal
    /// Grün für Wachstum: von Grau (kaum) bis kräftigem Grün (stark)
    static func grow(_ k: Double) -> Color {
        let a = (0x6a, 0x6a, 0x66), b = (0x1f, 0x9a, 0x3e)
        let t = 0.35 + 0.65 * max(0, min(1, k))
        return Color(.sRGB, red: (Double(a.0) + Double(b.0 - a.0) * t) / 255,
                     green: (Double(a.1) + Double(b.1 - a.1) * t) / 255,
                     blue: (Double(a.2) + Double(b.2 - a.2) * t) / 255, opacity: 1)
    }
}

extension CreatureVitals {
    var stageIndex: Int {
        switch g {
        case ..<0.12: return 1
        case ..<0.3: return 2
        case ..<0.55: return 3
        case ..<0.8: return 4
        default: return 5
        }
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
