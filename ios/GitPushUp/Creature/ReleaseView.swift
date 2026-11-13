import SwiftUI

/// Bild eines Wesens als ausgewachsenes Exemplar (fürs Archiv und den Abschied)
func creaturePortrait(seed: Int, shares: (Double, Double, Double), n: Int = 56) -> CGImage? {
    let T = Traits.from(strength: min(1, 3 * shares.0), stretch: min(1, 3 * shares.1), mind: min(1, 3 * shares.2))
    let f = renderCreature(Genome(seed: seed), g: 1, traits: T, time: 0, blink: false, n: n)
    return makeImage(f.rgba, f.n, f.n)
}

/// Abschied: das Wesen verlässt den Kasten, ein Bild und ein paar Daten kommen ins Archiv, dann ein neues Ei
struct ReleaseView: View {
    @EnvironmentObject var store: Store
    let onClose: () -> Void

    @State private var img: CGImage? = nil
    @State private var leaving = false
    @State private var step = 0

    var body: some View {
        let c = store.state.creature
        let v = store.vitals()
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button(action: onClose) {
                    Text("← SPÄTER").font(mono(12)).foregroundStyle(Color.muted).frame(minHeight: 44)
                }
                Spacer()
            }
            Text("FREILASSEN").font(display(32)).tracking(1).foregroundStyle(Color.fg)
            Text("\(c?.name.uppercased() ?? "") ist ausgewachsen. Wenn du es freilässt, kommt sein Bild mit seinen Daten ins Archiv, und in der Brutstätte wartet ein neues Ei.")
                .font(mono(12)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)

            GeometryReader { g in
                ZStack(alignment: .topLeading) {
                    PixelBlock().fill(Color.panel)
                    if let img {
                        let size = CGFloat(56) * PX * 1
                        // geht in Pixelschritten nach rechts hinaus und hüpft dabei
                        let x = snap((g.size.width - size) / 2 + CGFloat(step) * PX * 3)
                        let y = snap((g.size.height - size) / 2 - (step % 4 < 2 ? PX * 2 : 0) * (leaving ? 1 : 0))
                        Image(decorative: img, scale: 1).resizable().interpolation(.none)
                            .frame(width: size, height: size)
                            .offset(x: x, y: y)
                    }
                }
                .clipped()
                .pixelBorder()
            }
            .frame(height: 220)

            HStack(spacing: 6) {
                fact("TAGE", "\(v.ageDays)")
                fact("TONUS", "\(Int((v.shares.s * 100).rounded())) %")
                fact("FLEX.", "\(Int((v.shares.t * 100).rounded())) %")
                fact("RESONANZ", "\(Int((v.shares.m * 100).rounded())) %")
            }
            Spacer()
            Button {
                guard !leaving else { return }
                leaving = true
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task { @MainActor in
                    for i in 1...40 { step = i; try? await Task.sleep(nanoseconds: 60_000_000) }
                    store.releaseCreature()
                    store.rescheduleReminders()
                    onClose()
                }
            } label: {
                Text(leaving ? "MACH'S GUT" : "FREILASSEN").font(display(22)).tracking(1).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(PixelBlock().fill(Color.grow(1)))
            }
            .buttonStyle(PressStyle())
        }
        .padding(16)
        .background(LabBackdrop())
        .onAppear {
            guard let c else { return }
            img = creaturePortrait(seed: c.seed, shares: (v.shares.s, v.shares.t, v.shares.m))
        }
    }

    private func fact(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k).font(labelFont(9)).tracking(0.8)
            Text(v).font(display(20)).foregroundStyle(Color.fg)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pixelBorder()
    }
}

/// Archiv der freigelassenen Wesen (Laborakte)
struct ArchiveGrid: View {
    let items: [ReleasedCreature]
    @State private var images: [String: CGImage] = [:]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(items.reversed()) { a in
                VStack(alignment: .leading, spacing: 3) {
                    ZStack {
                        PixelBlock().fill(Color.panel)
                        if let img = images[a.id] {
                            Image(decorative: img, scale: 1).resizable().interpolation(.none)
                                .frame(width: 40 * PX, height: 40 * PX)
                        }
                    }
                    .frame(height: 40 * PX + PX * 4)
                    .pixelBorder()
                    Text(a.name.uppercased()).font(labelFont(10)).tracking(0.5).lineLimit(1)
                    Text("\(a.days) T · \(Int((a.shareS * 100).rounded()))/\(Int((a.shareT * 100).rounded()))/\(Int((a.shareM * 100).rounded()))")
                        .font(mono(9)).foregroundStyle(Color.muted)
                    Text(Date(timeIntervalSince1970: a.released / 1000).formatted(date: .numeric, time: .omitted))
                        .font(mono(9)).foregroundStyle(Color.dim)
                }
            }
        }
        .task(id: items.count) {
            for a in items where images[a.id] == nil {
                images[a.id] = creaturePortrait(seed: a.seed, shares: (a.shareS, a.shareT, a.shareM), n: 40)
            }
        }
    }
}
