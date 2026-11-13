import SwiftUI
import QuartzCore

/// Rendert das Wesen im Hintergrund, etwa 10 Bilder pro Sekunde (Pixel-Art braucht nicht mehr).
@MainActor
final class CreatureRenderer: ObservableObject {
    struct Params: Equatable {
        var seed: Int
        var g: Double
        var traits: Traits
        var vigor: Double
        var sleepy: Bool
    }

    @Published private(set) var image: CGImage?
    @Published private(set) var n = 8
    /// Oberste und unterste belegte Zeile als Anteil der Bildhöhe (geglättet, damit nichts zuckt)
    @Published private(set) var topFrac = 0.4
    @Published private(set) var bottomFrac = 0.6
    @Published private(set) var float = 0.0

    var params: Params?
    /// Gewünschte Auflösung (Pixel pro Seite). Gewechselt wird erst ab 2 Pixeln Unterschied, damit es nicht flackert.
    var targetN = 8
    private var genome: Genome?
    private var nextBlink = 0.0, blinkUntil = 0.0
    private var lastSeed = -1

    func loop() async {
        let t0 = CACurrentMediaTime()
        while !Task.isCancelled {
            if let p = params {
                if genome?.seed != p.seed { genome = Genome(seed: p.seed) }
                let now = CACurrentMediaTime(), t = now - t0
                // Blinzeln: alle 2,5–6 s kurz; schläfrig hält es die Augen meist zu
                if now > nextBlink {
                    blinkUntil = now + (p.sleepy ? Double.random(in: 2.5...5) : 0.14)
                    nextBlink = blinkUntil + (p.sleepy ? Double.random(in: 0.6...1.4) : Double.random(in: 2.5...6))
                }
                let blink = now < blinkUntil && p.g > 0.15
                let G = genome!
                let useN = (abs(targetN - n) >= 2 || p.seed != lastSeed || p.g < 0.02) ? targetN : n
                let frame = await Task.detached(priority: .userInitiated) {
                    renderCreature(G, g: p.g, traits: p.traits, time: t, blink: blink, vigor: p.vigor, n: useN)
                }.value
                let rows = frame.rgba.count / 4 / max(1, frame.n)
                var topRow = frame.n - 1
                for j in 0..<rows {
                    var any = false
                    for i in 0..<frame.n where frame.rgba[(j * frame.n + i) * 4 + 3] > 0 { any = true; break }
                    if any { topRow = j; break }
                }
                let tf = Double(topRow) / Double(frame.n), bf = Double(frame.bottomRow + 1) / Double(frame.n)
                let snap = p.seed != lastSeed || frame.n != n
                lastSeed = p.seed
                image = makeImage(frame.rgba, frame.n, frame.n)
                n = frame.n
                topFrac = snap ? tf : lerpD(topFrac, tf, 0.2)
                bottomFrac = snap ? bf : lerpD(bottomFrac, bf, 0.2)
                float = frame.float
            }
            try? await Task.sleep(nanoseconds: 90_000_000)
        }
    }
}

/// Der Glaskasten: Pixel-Labor im Hintergrund, Wesen auf dem Sockel (oder schwebend), Glas davor.
struct LabTankView: View {
    let seed: Int
    let vitals: CreatureVitals
    /// Zeitraffer-Vorschau: zeigt das Wachstum von 0 bis heute (oder bis ausgewachsen)
    var previewG: Double? = nil

    @StateObject private var renderer = CreatureRenderer()
    @State private var scene: (bg: CGImage?, glass: CGImage?, w: Int, h: Int)? = nil

    /// Ein Pixel im Labor ist genauso groß wie jedes andere Pixel der App
    private let pixel: CGFloat = PX

    private var params: CreatureRenderer.Params {
        CreatureRenderer.Params(seed: seed, g: previewG ?? vitals.g, traits: vitals.traits,
                                vigor: previewG == nil ? vitals.vigor : 1, sleepy: previewG == nil && vitals.health < 0.15)
    }

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width, H = geo.size.height
            let w = Int(ceil(W / pixel)), h = Int(ceil(H / pixel))
            let G = LabScene.geo(w, h)
            let floorPt = CGFloat(G.feetY) * pixel
            let ceilPt = CGFloat(G.ct) * pixel
            ZStack(alignment: .topLeading) {
                if let s = scene, let bg = s.bg {
                    Image(decorative: bg, scale: 1).resizable().interpolation(.none)
                        .frame(width: CGFloat(s.w) * pixel, height: CGFloat(s.h) * pixel)
                }
                TimelineView(.animation(minimumInterval: 1 / 15)) { tl in
                    creature(t: tl.date.timeIntervalSinceReferenceDate, W: W, H: H, floorPt: floorPt, ceilPt: ceilPt)
                }
                .onAppear { renderer.targetN = wantN(W: W, floorPt: floorPt, ceilPt: ceilPt) }
                .onChange(of: wantN(W: W, floorPt: floorPt, ceilPt: ceilPt)) { n in renderer.targetN = n }
                if let s = scene, let gl = s.glass {
                    Image(decorative: gl, scale: 1).resizable().interpolation(.none)
                        .frame(width: CGFloat(s.w) * pixel, height: CGFloat(s.h) * pixel)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: W, height: H, alignment: .topLeading)
            .clipped()
            .onAppear { makeScene(w, h) }
            .onChange(of: w) { _ in makeScene(w, h) }
            .onChange(of: h) { _ in makeScene(w, h) }
        }
        .onAppear { renderer.params = params }
        .onChange(of: params) { p in renderer.params = p }
        .task { await renderer.loop() }
    }

    /// Das Labor wird einmal pro Größe im Hintergrund gerechnet (Sichtstrahlen für jedes Pixel)
    private func makeScene(_ w: Int, _ h: Int) {
        guard w > 8, h > 8, scene?.w != w || scene?.h != h else { return }
        Task {
            let imgs = await Task.detached(priority: .userInitiated) { (LabScene.backdrop(w, h).image, LabScene.glass(w, h).image) }.value
            scene = (imgs.0, imgs.1, w, h)
        }
    }

    /// Wie viele Pixel das Wesen breit sein soll: wächst mit dem Alter, passt aber immer in den Kasten
    private func wantN(W: CGFloat, floorPt: CGFloat, ceilPt: CGFloat) -> Int {
        let g = previewG ?? vitals.g
        let avail = floorPt - ceilPt - pixel * 2
        let want = avail * 1.25 * CGFloat((0.3 + 0.62 * g) * frameSpan(g) / 2.5)
        let content = CGFloat(max(0.05, renderer.bottomFrac - renderer.topFrac))
        let size = min(want, avail / content, W * 0.9)
        return max(6, Int(size / pixel))
    }

    @ViewBuilder
    private func creature(t: Double, W: CGFloat, H: CGFloat, floorPt: CGFloat, ceilPt: CGFloat) -> some View {
        if let img = renderer.image {
            let sleepy = previewG == nil && vitals.health < 0.15
            let avail = floorPt - ceilPt - pixel * 2
            let size = CGFloat(renderer.n) * pixel
            let contentH = size * CGFloat(max(0.05, renderer.bottomFrac - renderer.topFrac))
            let fl = CGFloat(renderer.float)
            let hover = min(fl * avail * 0.15, max(0, avail - contentH))
            let speed = sleepy ? 0.5 : 1.0
            let bob = CGFloat(sin(t * 1.1 * speed)) * (fl > 0.05 ? avail * 0.025 * fl : 0)
            // Auf das Pixelraster gelegt, damit die Pixel des Wesens genau auf denen des Labors sitzen
            let left = snap((W - size) / 2)
            let top = snap(floorPt - hover + bob - size * CGFloat(renderer.bottomFrac))
            ZStack(alignment: .topLeading) {
                // Schatten auf dem Kastenboden, kleiner wenn es schwebt
                Rectangle().fill(Color.black.opacity(0.08 * Double(1 - 0.6 * fl)))
                    .frame(width: snap(size * 0.45 * (1 - 0.4 * fl)), height: pixel * 2)
                    .position(x: W / 2, y: snap(floorPt) + pixel)
                Image(decorative: img, scale: 1).resizable().interpolation(.none)
                    .frame(width: size, height: size)
                    .offset(x: left, y: top)
            }
            .frame(width: W, height: H, alignment: .topLeading)
        }
    }
}
