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
        TimelineView(.periodic(from: .now, by: 60)) { _ in
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
                    Text("SPECIMEN //").foregroundStyle(Color.muted)
                    Rectangle().fill(v.health >= 0.15 ? Color.signal : Color.dim).frame(width: 5, height: 5)
                    Text(v.healthLabel)
                }
                .font(mono(8.5, .medium))
                Button {
                    newName = c?.name ?? ""
                    renaming = true
                } label: {
                    Text((c?.name ?? "—").uppercased())
                        .font(display(36)).foregroundStyle(Color.fg)
                        .lineLimit(1).minimumScaleFactor(0.5)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Umbenennen")
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text("ID \(c.map { String($0.seed) } ?? "—")")
                Text("TAG \(String(format: "%03d", v.ageDays))")
                HStack(spacing: 4) {
                    Text("STUFE \(String(format: "%02d", v.stageIndex))/05").foregroundStyle(Color.muted)
                    Text(v.stage).font(mono(9, .semibold))
                }
            }
            .font(mono(9))
            .padding(.bottom, 4)
        }
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.line2).frame(height: 1) }
    }

    private func statCells(_ v: CreatureVitals) -> some View {
        let today = store.carePoints(days: 1).last.flatMap { $0 } ?? 0
        let dots = Int(today.rounded(.down))
        return HStack(spacing: 6) {
            cell("SERIE", String(format: "%02d", min(99, store.streak))) {
                Text("TAGE AM STÜCK").font(mono(8)).foregroundStyle(Color.muted)
            }
            cell("HEUTE", "\(dots)/5") {
                HStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { i in
                        Rectangle().fill(i < dots ? Color.signal : Color.clear)
                            .frame(width: 7, height: 7)
                            .overlay(Rectangle().stroke(i < dots ? Color.signal : Color.line2, lineWidth: 1))
                    }
                }
            }
            cell("WACHSTUM", "\(Int((v.g * 100).rounded(.down)))%") {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.fg).frame(width: g.size.width * CGFloat(v.g))
                        // Stufengrenzen
                        ForEach([0.12, 0.3, 0.55, 0.8], id: \.self) { s in
                            Rectangle().fill(v.g > s ? Color.bg : Color.line2).frame(width: 1).offset(x: g.size.width * CGFloat(s))
                        }
                    }
                }
                .frame(height: 7)
                .overlay(Rectangle().stroke(Color.line2, lineWidth: 1))
            }
        }
    }

    private func cell<F: View>(_ title: String, _ value: String, @ViewBuilder footer: () -> F) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(mono(8.5, .medium))
            Text(value).font(display(28)).foregroundStyle(Color.fg).lineLimit(1).minimumScaleFactor(0.6)
            footer()
        }
        .padding(.horizontal, 7).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(Rectangle().stroke(Color.line2, lineWidth: 1))
    }

    /// Die letzten 14 Tage: leer = nichts, grau = etwas, schwarz = gut gepflegt; heute orange umrandet
    private var careStrip: some View {
        let pts = store.carePoints(days: 14)
        return HStack(spacing: 6) {
            Text("PFLEGE 14T").font(mono(8.5, .medium)).frame(width: 66, alignment: .leading)
            HStack(spacing: 3) {
                ForEach(Array(pts.enumerated()), id: \.offset) { i, p in
                    let isToday = i == pts.count - 1
                    let fill: Color = p == nil ? .clear : ((p ?? 0) >= 3 ? Color.fg : ((p ?? 0) > 0 ? Color.dim : .clear))
                    Rectangle()
                        .fill(fill)
                        .frame(maxWidth: .infinity).frame(height: 10)
                        .overlay(Rectangle().stroke(isToday ? Color.signal : (p == nil ? Color.line : Color.line2),
                                                    style: StrokeStyle(lineWidth: 1, dash: p == nil ? [2, 2] : [])))
                }
            }
        }
    }

    private func traitGauges(_ v: CreatureVitals) -> some View {
        VStack(spacing: 5) {
            LabGauge(name: "TONUS", sub: "KRAFT", value: v.strength)
            LabGauge(name: "ELASTIZITÄT", sub: "DEHNEN", value: v.stretch)
            LabGauge(name: "RESONANZ", sub: "GEIST", value: v.mind)
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
                Text("EEG").font(mono(8.5, .semibold))
                Text("// \(state)").font(mono(8.5, .medium))
                Spacer()
                Text(since).font(mono(8.5)).foregroundStyle(Color.muted)
            }
            EEGWave(calm: calm).frame(height: 18)
        }
        .padding(.horizontal, 7).padding(.vertical, 5)
        .overlay(Rectangle().stroke(Color.line2, lineWidth: 1))
    }

    // MARK: Leiste unten

    private var bottomBar: some View {
        let f = store.fatigue()
        let tired = f.values.filter { $0 >= 0.5 }.count
        let first = !store.hasBaseline
        return HStack(spacing: 6) {
            Button(action: { first ? onRecord() : onGo() }) {
                ZStack {
                    Rectangle().fill(Color.signal)
                    Text(first ? "START" : "GO").font(display(first ? 17 : 30)).foregroundStyle(Color.white)
                }
                .frame(width: first ? 84 : 62)
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel(first ? "Start: Kraft messen" : "Los, nächste Übung")

            Button { onReport(nil) } label: {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("LABORAKTE").font(mono(10, .semibold))
                        Spacer()
                        Image(systemName: "arrow.right").font(.system(size: 10, weight: .semibold))
                    }
                    Spacer(minLength: 2)
                    if store.hasBaseline && store.recordDue {
                        Text("REKORDTAG FÄLLIG").font(mono(8.5, .semibold)).foregroundStyle(Color.signal)
                    } else {
                        Text("KÖRPER \(String(format: "%02d", tired))/\(Muscle.allCases.count) BELASTET").font(mono(8.5))
                            .foregroundStyle(Color.bg.opacity(0.65))
                    }
                }
                .foregroundStyle(Color.bg)
                .padding(.horizontal, 9).padding(.vertical, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(Color.wire)
            }
            .buttonStyle(PressStyle())

            tool("plus", "Nachtragen", enabled: store.hasBaseline, onManual)
            tool("waveform.path.ecg", "Puls", enabled: true, onPulse)
            tool("gearshape", "Einstellungen", enabled: true, onSettings)
        }
        .frame(height: 62)
    }

    private func tool(_ icon: String, _ label: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 15, weight: .regular))
                .foregroundStyle(enabled ? Color.fg : Color.dim)
                .frame(width: 40)
                .frame(maxHeight: .infinity)
                .overlay(Rectangle().stroke(Color.line2, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

// MARK: - Bausteine

extension Color {
    static let go = Color.signal
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

/// Messbalken: Beschriftung, Wert, gerahmter Balken in Signal-Orange
struct LabGauge: View {
    let name: String
    let sub: String
    let value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(name).font(mono(8.5, .semibold))
                Text("/ \(sub)").font(mono(8.5)).foregroundStyle(Color.dim)
                Spacer()
                Text("\(String(format: "%03d", Int((min(1, value) * 100).rounded()))) %").font(mono(8.5, .medium)).monospacedDigit()
            }
            GeometryReader { g in
                Rectangle().fill(Color.signal)
                    .frame(width: max(0, (g.size.width - 2) * CGFloat(min(1, max(0, value)))))
                    .padding(1)
            }
            .frame(height: 8)
            .overlay(Rectangle().stroke(Color.line2, lineWidth: 1))
        }
    }
}

/// Hirnströme: kurz nach einer Meditation ruhige, gleichmäßige Alpha-Wellen; je länger her,
/// desto schneller, flacher und verrauschter, mit gelegentlichen Ausschlägen.
struct EEGWave: View {
    let calm: Double
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                let mid = Double(size.height) / 2, H = Double(size.height) / 2
                let c = max(0, min(1, calm))
                var p = Path()
                var x = 0.0
                while x <= Double(size.width) {
                    let u = x + t * 28
                    let alpha = sin(u * 0.22) * (0.35 + 0.45 * c)
                    let beta = (sin(u * 0.91 + 1.3) * 0.5 + sin(u * 1.73 + 0.4) * 0.35 + sin(u * 2.9) * 0.25) * (1 - c) * 0.55
                    // seltene Spitzen, wenn lange nicht meditiert
                    let k = sin(u * 0.037) * sin(u * 0.053 + 2)
                    let spike = (k > 0.93 ? (k - 0.93) * 12 : 0) * (1 - c) * sin(u * 3.1)
                    let y = mid - (alpha + beta + spike) * H * 0.9
                    if x == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                    x += 1.5
                }
                ctx.stroke(p, with: .color(Color.fg), lineWidth: 1)
            }
        }
    }
}
