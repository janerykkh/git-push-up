import SwiftUI
import Charts

/// Labor-Dashboard: GO, Biomarker mit DNA-Röhre, Neuro-Scan, Körper-Scan, Gewebeanalyse, Protokoll.
struct HomeView: View {
    @EnvironmentObject var store: Store
    let onGo: () -> Void
    let onExercise: (Exercise) -> Void
    let onManual: () -> Void
    let onRecord: () -> Void
    let onSettings: () -> Void
    let onPulse: () -> Void

    @State private var selected: Muscle? = nil

    private struct MuscleGroup: Identifiable { let id: String; let muscles: [Muscle] }
    private let groups: [MuscleGroup] = [
        MuscleGroup(id: "OBERKÖRPER", muscles: [.chest, .frontDelt, .rearDelt, .upperBack, .lats, .biceps, .triceps]),
        MuscleGroup(id: "RUMPF", muscles: [.abs, .obliques, .lowerBack]),
        MuscleGroup(id: "BEINE", muscles: [.glutes, .quads, .hamstrings, .adductors, .calves]),
    ]
    private struct CatCount: Identifiable { let id: ExCategory; let n: Int }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            let f = store.fatigue()
            let bio = store.biomarkers()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        counters
                        if store.hasBaseline && store.recordDue { recordBanner }
                        goButton
                        if store.hasBaseline {
                            Button(action: onManual) {
                                Text("+ PROBE NACHTRAGEN").font(labelFont(11)).tracking(2).foregroundStyle(Color.muted)
                                    .frame(maxWidth: .infinity, minHeight: 30)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, -8)
                        }
                        biomarkerPanel(bio)
                        neuroPanel(bio)
                        scan(f)
                        if let m = selected { muscleInfo(m, f).id("info") }
                        tissue(f)
                        periodTabs
                        stats
                        Text("LABOR-PROTOKOLL · ALLE DATEN BLEIBEN AUF DIESEM GERÄT")
                            .font(labelFont(9)).tracking(2).foregroundStyle(Color.dim)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 32)
                }
                .onChange(of: selected) { m in
                    if m != nil { withAnimation { proxy.scrollTo("info", anchor: .center) } }
                }
            }
        }
        .background(LabBackdrop())
    }

    // MARK: Kopf

    private var header: some View {
        HStack(spacing: 10) {
            Lamp(color: store.hasBaseline ? .phos : .amber)
            VStack(alignment: .leading, spacing: 0) {
                Text("BIO-LAB").font(display(26)).tracking(4).foregroundStyle(Color.fg)
                Label12(text: "SUBJEKT 01 · SEKTOR 7", color: .dim, size: 9)
            }
            Spacer()
            Button(action: onPulse) {
                Image(systemName: "waveform.path.ecg").font(.system(size: 17)).foregroundStyle(Color.danger.opacity(0.9))
                    .frame(width: 40, height: 44)
            }
            .accessibilityLabel("Puls")
            Button(action: onSettings) {
                Image(systemName: "gearshape").font(.system(size: 17)).foregroundStyle(Color.muted).frame(width: 40, height: 44)
            }
            .accessibilityLabel("Einstellungen")
        }
    }

    private var todayEntries: [LogEntry] {
        let s = store.startOfDay()
        return store.state.log.filter { $0.ts >= s }
    }

    /// Drei Zählwerke wie mechanische Zähler an einem Gerät
    private var counters: some View {
        let today = todayEntries
        let s = store.streak
        return HStack(spacing: 8) {
            counter("SERIE", s, s > 0 ? .amber : .muted)
            counter("HEUTE", today.count, today.isEmpty ? .muted : .phos)
            counter("PROBEN", store.state.log.count, .wire)
        }
    }

    private func counter(_ label: String, _ v: Int, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label12(text: label, size: 9)
            HStack(spacing: 2) {
                ForEach(Array(String(format: "%03d", min(999, v))).indices, id: \.self) { i in
                    let digits = Array(String(format: "%03d", min(999, v)))
                    Text(String(digits[i]))
                        .font(mono(22, .bold)).foregroundStyle(c).glow(c == .muted ? .clear : c, 6)
                        .frame(width: 20, height: 30)
                        .background(Color.bg)
                        .overlay(Rectangle().stroke(Color.line2, lineWidth: 1))
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .labFrame(c == .muted ? .line2 : c)
    }

    private var recordBanner: some View {
        Button(action: onRecord) {
            HStack(spacing: 10) {
                Lamp(color: .amber)
                Text("REKORDTAG FÄLLIG").font(display(16, condensed: false)).tracking(2)
                Spacer()
                Text("5 TESTS").font(mono(11)).foregroundStyle(Color.muted)
            }
            .foregroundStyle(Color.amber)
            .padding(14)
            .background(Color.amber.opacity(0.06))
            .overlay(Rectangle().stroke(Color.amber, style: StrokeStyle(lineWidth: 1, dash: [5, 3])))
        }
        .buttonStyle(.plain)
    }

    // MARK: GO

    private var goButton: some View {
        let first = !store.hasBaseline
        let c: Color = first ? .amber : .phos
        return Button(action: { first ? onRecord() : onGo() }) {
            HStack(spacing: 0) {
                // Warnstreifen
                Canvas { ctx, size in
                    var p = Path()
                    var x: CGFloat = -size.height
                    while x < size.width {
                        p.move(to: CGPoint(x: x, y: size.height)); p.addLine(to: CGPoint(x: x + size.height, y: 0))
                        x += 10
                    }
                    ctx.stroke(p, with: .color(c.opacity(0.55)), lineWidth: 4)
                }
                .frame(width: 34)
                .clipped()
                VStack(alignment: .leading, spacing: 2) {
                    Text(first ? "KALIBRIEREN" : "GO").font(display(first ? 40 : 64)).tracking(first ? 2 : 8)
                        .foregroundStyle(c).glow(c, 14)
                    Label12(text: first ? "BASELINE MESSEN · EINMALIG" : "KRAFT · DEHNEN · GEIST", color: .muted, size: 10)
                }
                .padding(.leading, 16)
                Spacer()
                Image(systemName: "chevron.right.2").font(.system(size: 22, weight: .bold)).foregroundStyle(c.opacity(0.7))
                    .padding(.trailing, 18)
            }
            .frame(maxWidth: .infinity, minHeight: 108)
            .background(c.opacity(0.07))
            .overlay(Rectangle().stroke(c, lineWidth: 1.2))
            .overlay(CornerMarks(len: 14).stroke(c, lineWidth: 3).padding(-3))
        }
        .buttonStyle(.plain)
    }

    // MARK: Biomarker + DNA

    private func biomarkerPanel(_ b: Store.Biomarkers) -> some View {
        HStack(alignment: .top, spacing: 14) {
            // Probenröhre
            ZStack {
                Capsule().fill(Color.wire.opacity(0.05))
                DNAHelixView().padding(.vertical, 14).padding(.horizontal, 6)
                Capsule().stroke(Color.wire.opacity(0.5), lineWidth: 1)
            }
            .frame(width: 70)
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Label12(text: "BIOMARKER", color: .fg, size: 12)
                    Spacer()
                    Text("7 TAGE").font(mono(9)).foregroundStyle(Color.dim)
                }
                marker("VITALITÄT", b.vitality, .phos, "Kraftarbeit der Woche")
                marker("REGENERATION", b.regeneration, .wire, "wie erholt die Muskeln sind")
                marker("FLEXIBILITÄT", b.flex, ExCategory.dehnen.color, "\(b.stretchCount) Dehneinheiten")
                marker("NEURO", b.neuro, .mind, "\(b.neuroMinutes) Min. Meditation")
                marker("KONTINUITÄT", b.continuity, .amber, "Serie")
            }
        }
        .padding(14)
        .frame(height: 290)
        .labFrame(.wire)
    }

    private func marker(_ name: String, _ v: Double, _ c: Color, _ hint: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Label12(text: name, color: .fg, size: 10)
                Spacer()
                Text(String(format: "%03d", Int((min(1, v) * 100).rounded()))).font(mono(13, .bold)).foregroundStyle(c)
            }
            SegMeter(value: v, color: c, segments: 16, height: 6)
            Text(hint).font(mono(9)).foregroundStyle(Color.dim)
        }
    }

    private func neuroPanel(_ b: Store.Biomarkers) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Label12(text: "NEURO-SCAN", color: .fg, size: 12)
                Text("\(b.neuroMinutes)").font(mono(34, .bold)).foregroundStyle(Color.mind).glow(.mind, 8)
                Label12(text: "MIN · 7 TAGE", size: 9)
                Text(b.neuro >= 0.7 ? "Ruhiges Signal." : (b.neuro > 0 ? "Signal stabilisiert sich." : "Noch kein Signal."))
                    .font(mono(10)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 112, alignment: .leading)
            NeuroScanView(score: b.neuro)
                .frame(maxWidth: .infinity)
        }
        .padding(14)
        .frame(height: 150)
        .labFrame(.mind)
    }

    // MARK: Körper-Scan

    private func scan(_ f: [Muscle: Double]) -> some View {
        let tired = f.values.filter { $0 >= 0.5 }.count
        return BodyScanView(fatigue: f, selected: $selected)
            .background(RadialGradient(colors: [Color.glassTop, .bg], center: .init(x: 0.5, y: 0.4), startRadius: 0, endRadius: 300))
            .overlay(alignment: .topLeading) { Label12(text: "SPECIMEN · KÖRPER", color: .fg, size: 11).padding(12) }
            .overlay(alignment: .topTrailing) { Label12(text: "\(tired)/\(Muscle.allCases.count) BELASTET", color: .phos, size: 10).padding(12) }
            .overlay(alignment: .bottomLeading) { Label12(text: "TIPPEN · DREHEN", color: .dim, size: 9).padding(12) }
            .labFrame(.phos)
    }

    private func muscleInfo(_ m: Muscle, _ f: [Muscle: Double]) -> some View {
        let v = f[m] ?? 0
        let h = store.hoursToRecover(m, v)
        let hitters = store.strengthPool.filter { $0.weight(m) > 0 }.sorted { $0.weight(m) > $1.weight(m) }
        let stretch = store.pool.first { $0.relieves.contains(m) }
        let best = store.best(for: m)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Lamp(color: .amber, blink: false)
                Text(m.label.uppercased()).font(display(22)).tracking(2).foregroundStyle(Color.amber).glow(.amber, 6)
                Spacer()
                Button { selected = nil } label: {
                    Image(systemName: "xmark").foregroundStyle(Color.muted).frame(width: 36, height: 36)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(pct(v)).font(mono(34, .bold)).monospacedDigit().foregroundStyle(Color.fg)
                Label12(text: h > 0 ? "BELASTET · ERHOLT IN CA. \(h) H" : "ERHOLT · BEREIT", size: 10)
            }
            SegMeter(value: v, color: .phos, segments: 24, height: 6)
            Text(muscleInfoText(m, hitters))
                .font(mono(12)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                if let ex = best, store.hasBaseline {
                    Button("KRAFT: \(ex.name.uppercased())") { onExercise(ex) }
                        .buttonStyle(HangarButtonStyle(color: .phos, filled: true))
                }
                if let s = stretch {
                    Button("DEHNEN") { onExercise(s) }
                        .buttonStyle(HangarButtonStyle(color: ExCategory.dehnen.color, filled: true))
                        .frame(width: 110)
                }
            }
        }
        .padding(14)
        .labFrame(.amber)
    }

    private func muscleInfoText(_ m: Muscle, _ hitters: [Exercise]) -> String {
        var parts: [String] = []
        for ex in hitters {
            let w = ex.weight(m)
            let role = w >= 1 ? "Haupt" : (w >= 0.5 ? "Neben" : "hilft mit")
            parts.append("\(ex.name) (\(role))")
        }
        let first = parts.isEmpty ? "Keine Kraftübung im Pool trifft diesen Muskel." : "Trainiert durch: " + parts.joined(separator: ", ") + "."
        return first + " Volle Erholung dauert etwa \(Int(m.recoveryHours)) h."
    }

    private func groupAverage(_ g: MuscleGroup, _ f: [Muscle: Double]) -> Double {
        var sum = 0.0
        for m in g.muscles { sum += min(1, f[m] ?? 0) }
        return sum / Double(g.muscles.count)
    }

    private func tissue(_ f: [Muscle: Double]) -> some View {
        let week = store.weeklyLoad()
        return Block(title: "GEWEBEANALYSE", trailing: "JETZT · WOCHE", accent: .phos) {
            Text("Jetzt = wie belastet der Muskel gerade ist. Woche = wie viel er in 7 Tagen gearbeitet hat (100 % ≈ 6 harte Sätze).")
                .font(mono(10)).foregroundStyle(Color.dim).fixedSize(horizontal: false, vertical: true)
            ForEach(groups) { g in
                HStack(spacing: 6) {
                    Label12(text: g.id, color: .wire)
                    Spacer()
                    Text(pct(groupAverage(g, f))).font(mono(11, .bold)).foregroundStyle(Color.phos)
                    Text("·").font(mono(11)).foregroundStyle(Color.dim)
                    Text(pct(groupAverage(g, week))).font(mono(11, .bold)).foregroundStyle(Color.amber)
                }
                .padding(.top, 6)
                ForEach(g.muscles) { m in muscleRow(m, f[m] ?? 0, week[m] ?? 0) }
            }
        }
    }

    private func muscleRow(_ m: Muscle, _ v: Double, _ wk: Double) -> some View {
        let h = store.hoursToRecover(m, v)
        return Button { selected = (selected == m) ? nil : m } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(m.label.uppercased()).font(labelFont(12)).tracking(1)
                        .foregroundStyle(selected == m ? Color.amber : Color.fg)
                    Spacer()
                    Text(pct(v)).font(mono(12, .bold)).monospacedDigit().foregroundStyle(v >= 0.8 ? Color.phos : Color.wire)
                    Text("·").font(mono(11)).foregroundStyle(Color.dim)
                    Text(pct(wk)).font(mono(12, .bold)).monospacedDigit().foregroundStyle(Color.amber)
                        .frame(width: 44, alignment: .trailing)
                }
                SegMeter(value: v, color: v >= 0.8 ? .phos : .wire, segments: 30, height: 4)
                SegMeter(value: wk, color: .amber, segments: 30, height: 2)
                if h > 0 { Text("erholt in ca. \(h) h").font(mono(9.5)).foregroundStyle(Color.dim) }
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func pct(_ v: Double) -> String { "\(Int((min(1, v) * 100).rounded()))%" }

    // MARK: Protokoll nach Zeitraum

    private var periodTabs: some View {
        HStack(spacing: 4) {
            ForEach(Period.allCases) { p in
                let on = store.state.period == p
                Button { store.state.period = p; store.save() } label: {
                    Text(p.label).font(labelFont(12)).tracking(2)
                        .foregroundStyle(on ? Color.bg : Color.muted)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(on ? Color.wire : Color.panel)
                        .overlay(Rectangle().stroke(on ? Color.wire : Color.line2, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var periodEntries: [LogEntry] {
        let s = store.periodStart(store.state.period)
        return store.state.log.filter { $0.ts >= s }
    }

    @ViewBuilder private var stats: some View {
        let entries = periodEntries
        let strength = entries.filter { !$0.isTest && $0.exercise?.kind == .strength }
        let doneN = strength.filter { $0.done }.count
        let reps = Int(entries.filter { $0.exercise?.kind == .strength }.reduce(0) { $0 + store.units($1) }.rounded())
        let medMin = entries.filter { $0.exercise?.kind == .mind }.reduce(0) { $0 + $1.actual } / 60
        let stretchN = entries.filter { $0.exercise?.kind == .stretch }.count
        let days = Set(entries.map { store.startOfDay($0.ts) }).count

        Block(title: "MESSWERTE", accent: .wire) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 16) {
                kpi("\(entries.count)", "PROBEN")
                kpi(strength.isEmpty ? "–" : "\(Int((Double(doneN) / Double(strength.count) * 100).rounded()))%", "GESCHAFFT")
                kpi("\(reps)", "WDH.*")
                kpi("\(stretchN)", "DEHNEN")
                kpi("\(medMin)", "MIN. GEIST")
                kpi("\(days)", "TAGE AKTIV")
            }
            Text("* Halteübungen: 1 Wdh. pro 3 s · Übungen pro Seite zählen doppelt").font(mono(9)).foregroundStyle(Color.dim)
        }

        Block(title: chartTitle, accent: .phos) { activityChart(entries) }

        Block(title: "KATEGORIEN", accent: .amber) {
            let counts = ExCategory.allCases.map { c in CatCount(id: c, n: entries.filter { $0.cat == c.rawValue }.count) }
            let cmax = max(1, counts.map { $0.n }.max() ?? 1)
            ForEach(counts) { cc in
                HStack(spacing: 10) {
                    Text(cc.id.label.uppercased()).font(labelFont(10)).tracking(1.5).foregroundStyle(Color.fg).frame(width: 74, alignment: .leading)
                    SegMeter(value: Double(cc.n) / Double(cmax), color: cc.id.color, segments: 22, height: 6)
                    Text("\(cc.n)").font(mono(11)).monospacedDigit().foregroundStyle(Color.muted).frame(width: 28, alignment: .trailing)
                }
            }
        }

        Block(title: "ZIELE & REKORDE", trailing: store.hasBaseline
              ? "Anpassung in \(store.nextReviewDays) T\nRekordtag in \(store.daysToRecord) T"
              : "Noch keine Baseline", accent: .amber) {
            VStack(spacing: 0) {
                ForEach(store.pool.filter { $0.kind != .mind }) { ex in progressRow(ex) }
            }
        }

        Block(title: "VERLAUF", accent: .wire) {
            let recent = Array(entries.suffix(40).reversed())
            if recent.isEmpty {
                Text("Noch keine Proben \(store.state.period == .day ? "heute" : "in diesem Zeitraum").")
                    .font(mono(12)).foregroundStyle(Color.muted)
            } else {
                VStack(spacing: 0) {
                    ForEach(recent) { l in logRow(l) }
                }
            }
        }
    }

    private func kpi(_ v: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(v).font(mono(22, .bold)).monospacedDigit().foregroundStyle(Color.fg)
            Label12(text: label, size: 9)
        }
    }

    private var chartTitle: String {
        switch store.state.period {
        case .day: return "AKTIVITÄT NACH UHRZEIT"
        case .week, .month: return "PROBEN PRO TAG"
        case .year: return "PROBEN PRO MONAT"
        }
    }

    private struct Bucket: Identifiable { let id: Int; let label: String; let count: Int }

    private func buckets(_ entries: [LogEntry]) -> [Bucket] {
        let cal = Calendar(identifier: .iso8601)
        let start = Date(timeIntervalSince1970: store.periodStart(store.state.period) / 1000)
        func comp(_ l: LogEntry) -> Int {
            let d = Date(timeIntervalSince1970: l.ts / 1000)
            switch store.state.period {
            case .day: return cal.component(.hour, from: d)
            case .week: return cal.dateComponents([.day], from: cal.startOfDay(for: start), to: cal.startOfDay(for: d)).day ?? 0
            case .month: return cal.component(.day, from: d) - 1
            case .year: return cal.component(.month, from: d) - 1
            }
        }
        let n: Int
        let label: (Int) -> String
        switch store.state.period {
        case .day: n = 24; label = { "\($0)" }
        case .week: n = 7; label = { ["MO", "DI", "MI", "DO", "FR", "SA", "SO"][$0] }
        case .month: n = cal.range(of: .day, in: .month, for: start)?.count ?? 31; label = { "\($0 + 1)" }
        case .year: n = 12; label = { ["JAN", "FEB", "MÄR", "APR", "MAI", "JUN", "JUL", "AUG", "SEP", "OKT", "NOV", "DEZ"][$0] }
        }
        var counts = Array(repeating: 0, count: n)
        for l in entries { let i = comp(l); if i >= 0 && i < n { counts[i] += 1 } }
        return (0..<n).map { Bucket(id: $0, label: label($0), count: counts[$0]) }
    }

    private func activityChart(_ entries: [LogEntry]) -> some View {
        let data = buckets(entries)
        let every: Int = {
            switch store.state.period { case .day: return 6; case .week: return 1; case .month: return 7; case .year: return 2 }
        }()
        return Chart(data) { b in
            BarMark(x: .value("Zeit", b.id), y: .value("Anzahl", b.count))
                .foregroundStyle(Color.phos.opacity(0.85))
        }
        .chartXAxis {
            AxisMarks(values: data.map { $0.id }.filter { $0 % every == 0 }) { v in
                AxisValueLabel {
                    if let i = v.as(Int.self), i < data.count { Text(data[i].label).font(mono(9)).foregroundStyle(Color.muted) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { _ in
                AxisGridLine().foregroundStyle(Color.line)
                AxisValueLabel().font(mono(9)).foregroundStyle(Color.muted)
            }
        }
        .frame(height: 130)
    }

    private func progressRow(_ ex: Exercise) -> some View {
        let all = store.state.log.filter { $0.ex == ex.id && !$0.isTest }
        let u = ex.unit == .sec ? " s" : ""
        let rate = all.isEmpty ? "noch nicht gemacht" : "\(Int((Double(all.filter { $0.done }.count) / Double(all.count) * 100).rounded()))% geschafft"
        let change = store.state.trainer.targets[ex.id]?.change ?? 0
        let record = store.state.trainer.baseline?[ex.id]
        return HStack(spacing: 12) {
            Rectangle().fill(ex.cat.color).frame(width: 6, height: 6).glow(ex.cat.color, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(ex.name).font(mono(13)).foregroundStyle(Color.fg)
                HStack(spacing: 4) {
                    Text("\(all.count)× · \(rate)")
                    if let r = record { Text("· Rekord \(r)\(u)").foregroundStyle(Color.amber) }
                }
                .font(mono(10)).foregroundStyle(Color.muted)
            }
            Spacer()
            HStack(spacing: 4) {
                Text("\(store.perTime(ex))\(u)\(ex.side ? "/S" : "")").foregroundStyle(Color.fg)
                if change > 0 { Text("▲\(change)").foregroundStyle(Color.phos) }
                if change < 0 { Text("▼\(-change)").foregroundStyle(Color.amber) }
            }
            .font(mono(12)).monospacedDigit()
        }
        .padding(.vertical, 9)
        .overlay(alignment: .top) { Rectangle().fill(Color.line).frame(height: 1) }
    }

    private func logRow(_ l: LogEntry) -> some View {
        let ex = l.exercise
        let u = ex?.unit == .sec ? " s" : ""
        let color = ex?.cat.color ?? .muted
        return HStack(spacing: 12) {
            Rectangle().fill(color).frame(width: 6, height: 6).glow(color, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(ex?.name ?? l.ex).font(mono(13)).foregroundStyle(Color.fg)
                Text(fmtTime(l.ts)).font(mono(10)).foregroundStyle(Color.muted)
            }
            Spacer()
            Group {
                if l.isTest { Text("REKORD \(l.actual)\(u)").foregroundStyle(Color.amber).bold() }
                else if l.isBoss { Text("BOSS \(l.actual)\(u)").foregroundStyle(Color.amber).bold() }
                else if ex?.kind == .mind { Text("\(l.actual / 60) MIN").foregroundStyle(Color.mind) }
                else if l.manual == true { Text("+ \(l.actual)\(u)").foregroundStyle(Color.wire) }
                else if l.done { Text("✓ \(l.target)\(u)").foregroundStyle(Color.phos) }
                else { Text("\(l.actual) / \(l.target)\(u)").foregroundStyle(Color.muted) }
            }
            .font(mono(12)).monospacedDigit()
        }
        .padding(.vertical, 9)
        .overlay(alignment: .top) { Rectangle().fill(Color.line).frame(height: 1) }
    }
}
