import SwiftUI
import Charts

/// Laborakte: alles Genaue hinter dem Startbildschirm. Wochenpensum, Körper-Scan, Gewebeanalyse, Ziele, Verlauf.
struct LabReportView: View {
    @EnvironmentObject var store: Store
    let onClose: () -> Void
    let jump: ReportJump

    @State private var selected: Muscle?
    @State private var running: ActivePick? = nil
    @State private var done: DoneInfo? = nil

    init(onClose: @escaping () -> Void, jump: ReportJump = .top) {
        self.onClose = onClose
        self.jump = jump
        if case let .muscle(m) = jump { _selected = State(initialValue: m) } else { _selected = State(initialValue: nil) }
    }

    /// Übung direkt aus der Akte heraus starten; sie läuft über der Akte, danach ist man wieder hier
    private func run(_ ex: Exercise) { running = ActivePick(ex: ex, boss: false) }

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
                        biomarkerPanel(bio)
                        Color.clear.frame(height: 0).id("scanTop")
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
                    // nur so weit, dass das Körperfenster knapp unter der Oberkante steht
                    if m != nil { withAnimation { proxy.scrollTo("scanTop", anchor: UnitPoint(x: 0.5, y: 0.012)) } }
                }
                .onAppear {
                    switch jump {
                    case .history:
                        store.state.period = .day
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { withAnimation { proxy.scrollTo("verlauf", anchor: .top) } }
                    case .muscle:
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { withAnimation { proxy.scrollTo("scanTop", anchor: UnitPoint(x: 0.5, y: 0.012)) } }
                    case .top: break
                    }
                }
            }
        }
        .background(LabBackdrop())
        .doneFlash($done)
        .fullScreenCover(item: $running) { pick in
            ActivityRunner(
                pick: pick,
                onDone: { d in running = nil; done = d },
                onSkip: { running = nil },
                onClose: { running = nil }
            )
            .environmentObject(store)
        }
    }

    // MARK: Kopf

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text("LABORAKTE").font(display(26)).tracking(4).foregroundStyle(Color.fg)
                Label12(text: "MESSWERTE · KÖRPER · VERLAUF", color: .dim, size: 9)
            }
            Spacer()
            Button(action: onClose) {
                PixelIcon(rows: PixelIcon.close, color: .muted).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Schließen")
        }
    }

    // MARK: Biomarker

    /// Alles auf einer Skala: Anteil am Wochenziel, mit echter Einheit daneben. Erholung ist ein Zustand, kein Wochenwert,
    /// darum steht sie getrennt darunter.
    private func biomarkerPanel(_ b: Store.Biomarkers) -> some View {
        Block(title: "WOCHENPENSUM", trailing: "LETZTE 7 TAGE", accent: .signal) {
            marker("KRAFTSÄTZE", b.strengthSets, Store.Biomarkers.strengthTarget, "SÄTZE")
            marker("DEHNEN", b.stretchCount, Store.Biomarkers.stretchTarget, "EINHEITEN")
            marker("MEDITATION", b.neuroMinutes, Store.Biomarkers.mindTarget, "MIN")
            marker("AKTIVE TAGE", b.activeDays, Store.Biomarkers.daysTarget, "TAGE")
        }
    }

    /// Ein Block pro Satz, Minute oder Tag des Ziels
    private func marker(_ name: String, _ v: Int, _ target: Int, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Label12(text: name, color: .fg, size: 10)
                Spacer()
                Text("\(v) / \(target) \(unit)").font(mono(13, .bold)).foregroundStyle(v >= target ? Color.signal : Color.fg)
            }
            SegMeter(value: Double(v) / Double(max(1, target)), color: .signal, segments: target, height: 8)
        }
    }

    // MARK: Körper-Scan

    private func scan(_ f: [Muscle: Double]) -> some View {
        let tired = f.values.filter { $0 >= 0.5 }.count
        let calm = store.eegCalm
        return BodyScanView(fatigue: f, selected: $selected)
            .background(Color.panel)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    Label12(text: "SPECIMEN · KÖRPER", color: .fg, size: 11)
                    Label12(text: "EEG", color: .muted, size: 8)
                    EEGWave(calm: calm, color: .mind).frame(width: 96, height: 22)
                }
                .padding(12)
            }
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
                    PixelIcon(rows: PixelIcon.close, color: .muted).frame(width: 36, height: 36)
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
                    Button("KRAFT: \(ex.name.uppercased())") { run(ex) }
                        .buttonStyle(HangarButtonStyle(color: .phos, filled: true))
                }
                if let s = stretch {
                    Button("DEHNEN") { run(s) }
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
        return Block(title: "GEWEBEANALYSE", trailing: "BELASTUNG JETZT", accent: .signal) {
            ForEach(groups) { g in
                HStack(spacing: 6) {
                    Label12(text: g.id, color: .wire)
                    Spacer()
                    Text(pct(groupAverage(g, f))).font(mono(11, .bold)).foregroundStyle(Color.fg)
                }
                .padding(.top, 6)
                ForEach(g.muscles) { m in muscleRow(m, f[m] ?? 0) }
            }
        }
    }

    private func muscleRow(_ m: Muscle, _ v: Double) -> some View {
        let h = store.hoursToRecover(m, v)
        return Button { selected = (selected == m) ? nil : m } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(m.label.uppercased()).font(labelFont(12)).tracking(1)
                        .foregroundStyle(selected == m ? Color.amber : Color.fg)
                    Spacer()
                    Text(pct(v)).font(mono(12, .bold)).monospacedDigit().foregroundStyle(v >= 0.8 ? Color.signal : Color.fg)
                }
                SegMeter(value: v, color: v >= 0.8 ? .signal : .wire, segments: 30, height: 4)
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
        .id("verlauf")
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
        Button { run(ex) } label: { progressRowContent(ex).contentShape(Rectangle()) }
            .buttonStyle(.plain)
    }

    private func progressRowContent(_ ex: Exercise) -> some View {
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
