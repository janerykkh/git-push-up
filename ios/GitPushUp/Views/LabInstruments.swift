import SwiftUI

/// Drehender DNA-Strang in einer Probenröhre
struct DNAHelixView: View {
    var color: Color = .wire
    var accent: Color = .phos
    var speed: Double = 0.9

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate * speed
                let w = Double(size.width), h = Double(size.height)
                let amp = w * 0.32, cx = w / 2
                let n = 24
                // Stränge
                var s1 = Path(), s2 = Path()
                let steps = 120
                for i in 0...steps {
                    let y = h * Double(i) / Double(steps)
                    let ph = Double(i) / Double(steps) * Double(n) * 0.42 + t
                    let p1 = CGPoint(x: cx + amp * sin(ph), y: y)
                    let p2 = CGPoint(x: cx - amp * sin(ph), y: y)
                    if i == 0 { s1.move(to: p1); s2.move(to: p2) } else { s1.addLine(to: p1); s2.addLine(to: p2) }
                }
                ctx.stroke(s1, with: .color(color.opacity(0.18)), lineWidth: 5)
                ctx.stroke(s2, with: .color(accent.opacity(0.14)), lineWidth: 5)
                ctx.stroke(s1, with: .color(color.opacity(0.75)), lineWidth: 1.2)
                ctx.stroke(s2, with: .color(accent.opacity(0.6)), lineWidth: 1.2)
                // Basenpaare
                for i in 0..<n {
                    let y = h * (Double(i) + 0.5) / Double(n)
                    let ph = (Double(i) + 0.5) * 0.42 + t
                    let x1 = cx + amp * sin(ph), x2 = cx - amp * sin(ph)
                    let d = cos(ph)
                    var rung = Path()
                    rung.move(to: CGPoint(x: x1, y: y)); rung.addLine(to: CGPoint(x: x2, y: y))
                    ctx.stroke(rung, with: .color(color.opacity(0.15 + 0.2 * Swift.abs(d))), lineWidth: 1)
                    let r1 = 2.2 + 1.3 * d, r2 = 2.2 - 1.3 * d
                    ctx.fill(Path(ellipseIn: CGRect(x: x1 - r1, y: y - r1, width: 2 * r1, height: 2 * r1)),
                             with: .color(color.opacity(0.5 + 0.5 * d)))
                    ctx.fill(Path(ellipseIn: CGRect(x: x2 - r2, y: y - r2, width: 2 * r2, height: 2 * r2)),
                             with: .color(accent.opacity(0.5 - 0.45 * d)))
                }
            }
        }
    }
}

/// Gehirn-Scan: Umriss mit Windungen, leuchtet stärker mit mehr Meditation; darunter eine EEG-Kurve,
/// die ruhiger wird, je höher der Wert
struct NeuroScanView: View {
    let score: Double

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                let w = Double(size.width), h = Double(size.height)
                let c = Color.mind
                let pulse = 0.5 + 0.5 * sin(t * (1.0 + 1.6 * (1 - score)))
                let br = CGRect(x: w * 0.14, y: h * 0.05, width: w * 0.72, height: h * 0.58)
                var brain = Path(ellipseIn: br)
                let cere = CGRect(x: br.maxX - w * 0.19, y: br.maxY - h * 0.15, width: w * 0.17, height: h * 0.13)
                brain.addEllipse(in: cere)
                var stem = Path()
                stem.move(to: CGPoint(x: br.midX + br.width * 0.12, y: br.maxY - 2))
                stem.addLine(to: CGPoint(x: br.midX + br.width * 0.16, y: br.maxY + h * 0.08))

                // Windungen
                var g = Path()
                for k in 0..<6 {
                    let y0 = Double(br.minY) + Double(br.height) * (0.16 + 0.13 * Double(k))
                    var x = Double(br.minX) + Double(br.width) * 0.06
                    let end = Double(br.maxX) - Double(br.width) * 0.06
                    let step = Double(br.width) * 0.085
                    var up = (k % 2 == 0)
                    g.move(to: CGPoint(x: x, y: y0))
                    while x < end {
                        let nx = x + step
                        let cy = y0 + (up ? -1.0 : 1.0) * Double(br.height) * 0.06
                        g.addQuadCurve(to: CGPoint(x: nx, y: y0), control: CGPoint(x: (x + nx) / 2, y: cy))
                        x = nx; up.toggle()
                    }
                }
                ctx.drawLayer { l in
                    l.clip(to: Path(ellipseIn: br.insetBy(dx: 3, dy: 3)))
                    l.stroke(g, with: .color(c.opacity(0.18 + 0.55 * score * (0.6 + 0.4 * pulse))), lineWidth: 1)
                }
                ctx.stroke(brain, with: .color(c.opacity(0.08 + 0.2 * score * pulse)), lineWidth: 7)
                ctx.stroke(brain, with: .color(c.opacity(0.85)), lineWidth: 1.3)
                ctx.stroke(stem, with: .color(c.opacity(0.6)), lineWidth: 1.3)

                // EEG
                var e = Path()
                let baseY = h * 0.86
                let calm = score
                let n = 140
                for i in 0...n {
                    let x = w * Double(i) / Double(n)
                    let p = Double(i) / Double(n) * 14 + t * 2.6
                    let v = sin(p * 2.2) * 0.6 + sin(p * 6.9 + 1) * 0.45 * (1 - calm) + sin(p * 15.3) * 0.3 * (1 - calm)
                    let y = baseY - v * h * (0.04 + 0.06 * (1 - calm))
                    if i == 0 { e.move(to: CGPoint(x: x, y: y)) } else { e.addLine(to: CGPoint(x: x, y: y)) }
                }
                ctx.stroke(e, with: .color(c.opacity(0.25)), lineWidth: 4)
                ctx.stroke(e, with: .color(c), lineWidth: 1.1)
            }
        }
    }
}
