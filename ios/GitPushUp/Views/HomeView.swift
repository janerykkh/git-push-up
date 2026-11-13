import SwiftUI

/// Startbildschirm: oben der Glaskasten mit dem Wesen, darunter Name, Alter, Zustand und die drei Pflegewerte,
/// unten links GO (groß, mit dem Daumen gut zu treffen), rechts der Körper-Scan.
struct HomeView: View {
    @EnvironmentObject var store: Store
    let onGo: () -> Void
    let onManual: () -> Void
    let onRecord: () -> Void
    let onSettings: () -> Void
    let onPulse: () -> Void
    let onReport: (Muscle?) -> Void

    @State private var selected: Muscle? = nil
    @State private var previewG: Double? = nil
    @State private var previewTask: Task<Void, Never>? = nil
    @State private var renaming = false
    @State private var newName = ""

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            let v = store.vitals()
            let creature = store.state.creature
            GeometryReader { geo in
                let topInset = geo.safeAreaInsets.top
                let side = (geo.size.width - 32 - 10) * 0.47
                VStack(spacing: 0) {
                    tank(creature, v)
                        .frame(height: topInset + geo.size.height * 0.36)
                    VStack(alignment: .leading, spacing: 10) {
                        nameRow(creature, v)
                        traitBars(v)
                        healthRow(v)
                        Spacer(minLength: 4)
                        bottomRow(side: side)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                }
                .ignoresSafeArea(edges: .top)
            }
        }
        .background(Color.bg.ignoresSafeArea())
        .onAppear { store.ensureCreature() }
        .onChange(of: selected) { m in
            if let m { onReport(m); selected = nil }
        }
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
                .onLongPressGesture(minimumDuration: 0.6) { startPreview(to: 1) }
                .overlay(alignment: .bottomLeading) {
                    if let p = previewG {
                        Text("ZEITRAFFER · TAG \(Int((p * 60).rounded()))")
                            .font(mono(10, .semibold)).tracking(1.5).foregroundStyle(Color.fg)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.panel.opacity(0.85))
                            .padding(.leading, 14).padding(.bottom, 40)
                            .transition(.opacity)
                    }
                }
        } else {
            Color.glassTop
        }
    }

    /// Lange drücken: so wächst es bei der jetzigen Pflege, von der Zelle bis ausgewachsen
    private func startPreview(to end: Double) {
        previewTask?.cancel()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        previewTask = Task { @MainActor in
            let dur = 9.0, start = Date()
            while !Task.isCancelled {
                let p = min(1, Date().timeIntervalSince(start) / dur)
                previewG = p * end
                if p >= 1 { break }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if !Task.isCancelled { withAnimation { previewG = nil } }
        }
    }

    // MARK: Name, Alter, Werte

    private func nameRow(_ c: CreatureState?, _ v: CreatureVitals) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button {
                newName = c?.name ?? ""
                renaming = true
            } label: {
                Text((c?.name ?? "—").uppercased())
                    .font(display(30)).tracking(3).foregroundStyle(Color.fg)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Umbenennen")
            if let c { Text("#\(c.seed)").font(mono(10)).foregroundStyle(Color.dim) }
            Spacer(minLength: 4)
            Text("TAG \(v.ageDays) · \(v.stage)").font(mono(11, .medium)).tracking(1).foregroundStyle(Color.muted)
        }
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.line2).frame(height: 1) }
    }

    private func traitBars(_ v: CreatureVitals) -> some View {
        VStack(spacing: 9) {
            TraitBar(name: "TONUS", sub: "KRAFT", value: v.strength, color: .force)
            TraitBar(name: "ELASTIZITÄT", sub: "DEHNEN", value: v.stretch, color: .wire)
            TraitBar(name: "RESONANZ", sub: "GEIST", value: v.mind, color: .mind)
        }
    }

    private func healthRow(_ v: CreatureVitals) -> some View {
        HStack(spacing: 8) {
            Image(systemName: v.health >= 0.15 ? "heart.fill" : "moon.zzz.fill")
                .font(.system(size: 12)).foregroundStyle(v.health >= 0.15 ? Color.danger : Color.muted)
            Text(v.healthLabel).font(labelFont(11)).tracking(2).foregroundStyle(Color.fg)
            ECGLine(health: v.health)
                .frame(height: 18)
            if store.hasBaseline && store.recordDue {
                Button(action: onRecord) {
                    Text("REKORDTAG ›").font(labelFont(10)).tracking(1.5).foregroundStyle(Color.amber)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .overlay(Rectangle().stroke(Color.amber, style: StrokeStyle(lineWidth: 1, dash: [4, 2])))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: GO und Körper-Scan

    private func bottomRow(side: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 8) {
                goButton.frame(width: side, height: side)
                HStack(spacing: 6) {
                    tool("plus", "Nachtragen", enabled: store.hasBaseline, onManual)
                    tool("waveform.path.ecg", "Puls", enabled: true, onPulse)
                    tool("gearshape", "Einstellungen", enabled: true, onSettings)
                }
                .frame(width: side, height: 44)
            }
            scanTile
                .frame(maxWidth: .infinity)
                .frame(height: side + 8 + 44)
        }
    }

    private var goButton: some View {
        let first = !store.hasBaseline
        return Button(action: { first ? onRecord() : onGo() }) {
            ZStack {
                Rectangle().fill(Color.go)
                VStack(spacing: 4) {
                    Text(first ? "START" : "GO").font(display(first ? 40 : 66)).tracking(first ? 3 : 8)
                        .foregroundStyle(.white)
                    Text(first ? "KRAFT EINMAL MESSEN" : "KRAFT · DEHNEN · GEIST")
                        .font(labelFont(9)).tracking(1.5).foregroundStyle(.white.opacity(0.8))
                }
            }
            .overlay(CornerMarks(len: 10).stroke(.white.opacity(0.7), lineWidth: 2).padding(6))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(first ? "Start: Kraft messen" : "Los, nächste Übung")
    }

    private func tool(_ icon: String, _ label: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 16, weight: .medium))
                .foregroundStyle(enabled ? Color.fg : Color.dim)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.panel)
                .overlay(Rectangle().stroke(Color.line2, lineWidth: 1))
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private var scanTile: some View {
        let f = store.fatigue()
        let tired = f.values.filter { $0 >= 0.5 }.count
        return ZStack {
            Color.panel
            BodyScanView(fatigue: f, selected: $selected)
                .padding(.top, 18).padding(.bottom, 22)
        }
        .overlay(alignment: .topLeading) {
            Label12(text: "KÖRPER", color: .fg, size: 10).padding(.horizontal, 10).padding(.top, 8)
        }
        .overlay(alignment: .topTrailing) {
            Text("\(tired)/\(Muscle.allCases.count)").font(mono(10, .semibold)).foregroundStyle(tired > 0 ? Color.force : Color.dim)
                .padding(.horizontal, 10).padding(.top, 8)
        }
        .overlay(alignment: .bottomLeading) {
            Button { onReport(nil) } label: {
                Text("LABORAKTE ›").font(labelFont(10)).tracking(1.5).foregroundStyle(Color.wire)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .overlay(Rectangle().stroke(Color.line2, lineWidth: 1))
        .clipped()
    }
}

// MARK: - Bausteine

extension Color {
    /// Der GO-Knopf: kräftiges Signal-Orange
    static let go = Color(hex: 0xe2552b)
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Ein Pflegewert als schlichter Balken mit Fachbegriff und Klartext
struct TraitBar: View {
    let name: String
    let sub: String
    let value: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(name).font(labelFont(11)).tracking(2).foregroundStyle(Color.fg)
                Text(sub).font(mono(9)).tracking(1).foregroundStyle(Color.dim)
                Spacer()
                Text("\(Int((min(1, value) * 100).rounded()))").font(mono(12, .semibold)).monospacedDigit().foregroundStyle(color)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.line)
                    Rectangle().fill(color).frame(width: g.size.width * CGFloat(min(1, max(0, value))))
                    // feine Skala alle 10 %
                    HStack(spacing: 0) {
                        ForEach(0..<10, id: \.self) { i in
                            Spacer()
                            if i < 9 { Rectangle().fill(Color.bg.opacity(0.7)).frame(width: 1) }
                        }
                    }
                }
            }
            .frame(height: 7)
        }
    }
}

/// Herzlinie: schlägt ruhig bei gutem Zustand, flach und langsam, wenn es vernachlässigt wird
struct ECGLine: View {
    let health: Double
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                let period = 1.6 - 0.7 * health          // Sekunden pro Schlag
                let amp = (0.25 + 0.75 * health) * Double(size.height) * 0.45
                let mid = Double(size.height) / 2
                let w = Double(size.width)
                let beatW = 46.0
                var p = Path()
                var x = 0.0
                while x <= w {
                    // Kurve wandert nach links
                    let ph = ((x / beatW) + t / period).truncatingRemainder(dividingBy: 1)
                    var y = mid
                    if ph > 0.40 && ph < 0.46 { y = mid - amp * sin((ph - 0.40) / 0.06 * .pi) * 0.25 }
                    if ph >= 0.50 && ph < 0.54 { y = mid + amp * 0.25 }
                    if ph >= 0.54 && ph < 0.60 { y = mid - amp }
                    if ph >= 0.60 && ph < 0.64 { y = mid + amp * 0.45 }
                    if ph > 0.72 && ph < 0.84 { y = mid - amp * sin((ph - 0.72) / 0.12 * .pi) * 0.3 }
                    if x == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                    x += 1
                }
                ctx.stroke(p, with: .color(health >= 0.15 ? Color.danger.opacity(0.85) : Color.dim), lineWidth: 1.4)
            }
        }
    }
}
