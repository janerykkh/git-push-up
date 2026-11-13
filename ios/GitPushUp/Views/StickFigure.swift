import SwiftUI

/// Animierte Strichfigur: pendelt zwischen den zwei Posen der Übung.
/// Halteübungen bleiben lange in der Endposition, Wiederholungen schwingen gleichmäßig.
struct StickFigure: View {
    let ex: Exercise
    private static let limbs: [(Int, Int)] = [(1, 2), (2, 3), (3, 4), (2, 5), (5, 6), (1, 7), (7, 8), (1, 9), (9, 10)]
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                draw(&ctx, size: size, t: tl.date.timeIntervalSince(start))
            }
        }
        .aspectRatio(240 / 165, contentMode: .fit)
        .background(
            RadialGradient(colors: [Color.glassTop, .bg], center: .init(x: 0.5, y: 0.6), startRadius: 0, endRadius: 260)
        )
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 4))
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

        // Boden mit Perspektiv-Linien
        var floor = Path()
        var x: CGFloat = 10
        while x <= 230 { floor.move(to: pt(x, 152)); floor.addLine(to: pt(120 + (x - 120) * 1.6, 165)); x += 20 }
        ctx.stroke(floor, with: .color(.line), lineWidth: 1)
        var base = Path(); base.move(to: pt(6, 152)); base.addLine(to: pt(234, 152))
        ctx.stroke(base, with: .color(.line2), lineWidth: 1)

        // Hilfsmittel (Tisch, Türrahmen)
        for l in ex.prop where l.count == 4 {
            var p = Path(); p.move(to: pt(l[0], l[1])); p.addLine(to: pt(l[2], l[3]))
            ctx.stroke(p, with: .color(Color.wire.opacity(0.35)), style: StrokeStyle(lineWidth: 3 * s, lineCap: .round))
        }

        let k = CGFloat(phase(t))
        let P: [CGPoint] = zip(ex.a, ex.b).map { a, b in
            CGPoint(x: (a.x + (b.x - a.x) * k) * s, y: (a.y + (b.y - a.y) * k) * s)
        }
        guard P.count == 11 else { return }
        var body = Path()
        for (a, b) in Self.limbs { body.move(to: P[a]); body.addLine(to: P[b]) }

        // Kopf: entlang der Linie Hals → Kopf versetzt, damit er wie ein Kopf auf dem Hals sitzt
        let n = P[1], h = P[0]
        let dx = h.x - n.x, dy = h.y - n.y, d = max(0.001, hypot(dx, dy))
        let hc = CGPoint(x: n.x + dx / d * 11 * s, y: n.y + dy / d * 11 * s)
        let head = Path(ellipseIn: CGRect(x: hc.x - 9 * s, y: hc.y - 9 * s, width: 18 * s, height: 18 * s))

        // Leuchten: breiter, durchsichtiger Strich unter dem eigentlichen
        let glow = StrokeStyle(lineWidth: 9 * s, lineCap: .round, lineJoin: .round)
        ctx.stroke(body, with: .color(color.opacity(0.18)), style: glow)
        ctx.stroke(head, with: .color(color.opacity(0.18)), lineWidth: 8 * s)
        ctx.stroke(body, with: .color(color), style: StrokeStyle(lineWidth: 4 * s, lineCap: .round, lineJoin: .round))
        ctx.fill(head, with: .color(.bg))
        ctx.stroke(head, with: .color(color), lineWidth: 3 * s)
    }
}
