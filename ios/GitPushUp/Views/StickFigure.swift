import SwiftUI

/// Animierte Strichfigur: pendelt zwischen den zwei Posen der Übung.
/// Halteübungen bleiben lange in der Endposition, Wiederholungen schwingen gleichmäßig.
struct StickFigure: View {
    let ex: Exercise
    private static let limbs: [(Int, Int)] = [(1, 2), (2, 3), (3, 4), (2, 5), (5, 6), (1, 7), (7, 8), (1, 9), (9, 10)]
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15)) { tl in
            Canvas { ctx, size in
                draw(&ctx, size: size, t: tl.date.timeIntervalSince(start))
            }
        }
        .aspectRatio(240 / 165, contentMode: .fit)
        .background(Color.panel)
        .overlay(PixelFrame().fill(Color.line))
        .clipShape(Rectangle())
        .onAppear { start = Date() }
    }

    private func phase(_ t: Double) -> Double {
        let per = ex.unit == .sec ? 4.2 : 2.4
        let ph = t.truncatingRemainder(dividingBy: per) / per
        if ex.unit == .sec {
            let q = ph < 0.2 ? ph / 0.2 : (ph < 0.8 ? 1 : 1 - (ph - 0.8) / 0.2)
            return (1 - cos(q * .pi)) / 2
        }
        return (1 - cos(ph * 2 * .pi)) / 2
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let s = size.width / 240
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        let color = ex.cat.color

        // Boden mit Perspektiv-Linien, alles auf dem Pixelraster
        var floor = PixelPath()
        var x: CGFloat = 10
        while x <= 230 { floor.move(to: pt(x, 152)); floor.addLine(to: pt(120 + (x - 120) * 1.6, 165)); x += 20 }
        ctx.pixelStroke(floor, .line)
        var base = PixelPath(); base.move(to: pt(6, 152)); base.addLine(to: pt(234, 152))
        ctx.pixelStroke(base, .line2)

        // Hilfsmittel (Tisch, Türrahmen)
        var props = PixelPath()
        for l in ex.prop where l.count == 4 { props.move(to: pt(l[0], l[1])); props.addLine(to: pt(l[2], l[3])) }
        ctx.pixelStroke(props, Color.wire.opacity(0.45), size: PX * 2)

        let k = CGFloat(phase(t))
        let P: [CGPoint] = zip(ex.a, ex.b).map { a, b in
            CGPoint(x: (a.x + (b.x - a.x) * k) * s, y: (a.y + (b.y - a.y) * k) * s)
        }
        guard P.count == 11 else { return }
        var body = PixelPath()
        for (a, b) in Self.limbs { body.move(to: P[a]); body.addLine(to: P[b]) }

        // Kopf: entlang der Linie Hals → Kopf versetzt, damit er auf dem Hals sitzt; als Pixelring
        let n = P[1], h = P[0]
        let dx = h.x - n.x, dy = h.y - n.y, d = max(0.001, hypot(dx, dy))
        let hc = CGPoint(x: n.x + dx / d * 11 * s, y: n.y + dy / d * 11 * s)
        var head = PixelPath()
        let r = 9 * s
        for i in 0...24 {
            let a = Double(i) / 24 * 2 * .pi
            let p = CGPoint(x: hc.x + CGFloat(cos(a)) * r, y: hc.y + CGFloat(sin(a)) * r)
            if i == 0 { head.move(to: p) } else { head.addLine(to: p) }
        }
        ctx.pixelStroke(body, color, size: PX * 2)
        ctx.pixelStroke(head, color, size: PX * 2)
    }
}
