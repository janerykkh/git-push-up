import SwiftUI

/// Drehendes Wireframe-Körpermodell. Jede Muskelgruppe ist ein Ellipsoid aus Ringen;
/// je erschöpfter, desto heller leuchtet sie grün. Antippen wählt einen Muskel.
struct BodyScanView: View {
    let fatigue: [Muscle: Double]
    @Binding var selected: Muscle?

    @State private var dragOffset: Double = 0
    @State private var dragBase: Double? = nil
    @State private var startDate = Date()

    private let spin = 0.32 // Radiant pro Sekunde

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { tl in
                let angle = currentAngle(tl.date)
                Canvas { ctx, size in
                    BodyModel.draw(ctx: &ctx, size: size, angle: angle, fatigue: fatigue, selected: selected)
                }
                .overlay(alignment: .bottomTrailing) {
                    let deg = (Int((angle * 180 / .pi).rounded()) % 360 + 360) % 360
                    Text("ROT \(String(format: "%03d", deg))°").font(mono(10)).tracking(1.4)
                        .foregroundStyle(Color.muted).padding(10)
                }
            }
            .contentShape(Rectangle())
            // Nur waagerechtes Wischen dreht das Modell; senkrecht scrollt die Seite ganz normal weiter
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { v in
                        if dragBase == nil {
                            guard Swift.abs(v.translation.width) > Swift.abs(v.translation.height) else { return }
                            dragBase = dragOffset - Double(v.translation.width) * 0.012
                        }
                        dragOffset = (dragBase ?? 0) + Double(v.translation.width) * 0.012
                    }
                    .onEnded { _ in dragBase = nil }
            )
            .onTapGesture(coordinateSpace: .local) { loc in
                let m = BodyModel.pick(at: loc, size: geo.size, angle: currentAngle(Date()))
                selected = (m == selected) ? nil : m
            }
        }
        .aspectRatio(1 / 1.05, contentMode: .fit)
    }

    private func currentAngle(_ d: Date) -> Double {
        -0.5 + d.timeIntervalSince(startDate) * spin + dragOffset
    }
}

enum BodyModel {
    struct Part { let m: Muscle?; let c: SIMD3<Double>; let r: SIMD3<Double> }

    /// x rechts, y unten (350 = Boden), z vorne
    static let parts: [Part] = {
        let raw: [(Muscle?, Double, Double, Double, Double, Double, Double, Bool)] = [
            (nil, 0, 32, 0, 15, 18, 16, false), (nil, 0, 55, 0, 7, 8, 7, false),
            (nil, 56, 160, 0, 6, 21, 6, true), (nil, 59, 190, 0, 5, 7, 4, true),
            (nil, 0, 182, 0, 25, 11, 15, false),
            (nil, 13, 305, 3, 8, 29, 8, true), (nil, 14, 342, 7, 7, 4, 13, true),
            (.chest, 16, 94, 15, 15, 12, 7, true),
            (.frontDelt, 36, 79, 6, 10, 11, 9, true),
            (.rearDelt, 36, 79, -7, 10, 11, 8, true),
            (.biceps, 48, 118, 5, 7, 18, 6, true),
            (.triceps, 48, 118, -5, 7, 18, 6, true),
            (.abs, 0, 140, 16, 12, 31, 6, false),
            (.obliques, 22, 143, 10, 7, 22, 8, true),
            (.upperBack, 0, 88, -14, 25, 22, 8, false),
            (.lats, 20, 126, -12, 11, 24, 8, true),
            (.lowerBack, 0, 152, -15, 12, 17, 6, false),
            (.glutes, 12, 190, -12, 13, 15, 10, true),
            (.quads, 13, 233, 6, 12, 37, 10, true),
            (.hamstrings, 13, 244, -6, 11, 31, 9, true),
            (.calves, 13, 302, -6, 9, 25, 8, true),
        ]
        var out: [Part] = []
        for p in raw {
            out.append(Part(m: p.0, c: SIMD3(p.1, p.2, p.3), r: SIMD3(p.4, p.5, p.6)))
            if p.7 { out.append(Part(m: p.0, c: SIMD3(-p.1, p.2, p.3), r: SIMD3(p.4, p.5, p.6))) }
        }
        return out
    }()

    /// Ringe eines Einheits-Ellipsoids: 3 Breitengrade, 3 Längengrade
    static let rings: [[SIMD3<Double>]] = {
        let seg = 14
        var rs: [[SIMD3<Double>]] = []
        for lat in [-0.55, 0, 0.55] {
            let y = sin(lat * .pi / 2), rr = cos(lat * .pi / 2)
            rs.append((0...seg).map { (i: Int) -> SIMD3<Double> in
                let a = Double(i) / Double(seg) * 2 * .pi
                return SIMD3(cos(a) * rr, y, sin(a) * rr)
            })
        }
        for k in 0..<3 {
            let lon = Double(k) / 3 * .pi
            rs.append((0...seg).map { (i: Int) -> SIMD3<Double> in
                let a = Double(i) / Double(seg) * 2 * .pi
                return SIMD3(cos(a) * cos(lon), sin(a), cos(a) * sin(lon))
            })
        }
        return rs
    }()

    static let tiltC = cos(0.18), tiltS = sin(0.18)

    /// 3D → Bildschirm (x, y) plus Tiefe z
    static func project(_ p: SIMD3<Double>, angle: Double, scale: Double, cx: Double, cy: Double) -> SIMD3<Double> {
        let ca = cos(angle), sa = sin(angle)
        let x = p.x * ca + p.z * sa
        let z = -p.x * sa + p.z * ca
        let y = p.y - 185
        let y2 = y * tiltC - z * tiltS, z2 = y * tiltS + z * tiltC
        let f = 700 / (700 - z2 * 1.2)
        return SIMD3(cx + x * scale * f, cy + y2 * scale * f, z2)
    }

    static func frame(_ size: CGSize) -> (scale: Double, cx: Double, cy: Double) {
        (min(Double(size.width) / 260, Double(size.height) / 400), Double(size.width) / 2, Double(size.height) * 0.5)
    }

    static func draw(ctx: inout GraphicsContext, size: CGSize, angle: Double, fatigue: [Muscle: Double], selected: Muscle?) {
        let (scale, cx, cy) = frame(size)

        // Bodengitter
        var grid = Path()
        for i in -4...4 {
            let d = Double(i) * 25
            for (a, b) in [(SIMD3(d, 350, -100), SIMD3(d, 350, 100)), (SIMD3(-100, 350, d), SIMD3(100, 350, d))] {
                let p = project(a, angle: angle, scale: scale, cx: cx, cy: cy)
                let q = project(b, angle: angle, scale: scale, cx: cx, cy: cy)
                grid.move(to: CGPoint(x: p.x, y: p.y)); grid.addLine(to: CGPoint(x: q.x, y: q.y))
            }
        }
        ctx.stroke(grid, with: .color(Color.wire.opacity(0.1)), lineWidth: 1)

        // Hinten zuerst
        let sorted = parts.map { ($0, project($0.c, angle: angle, scale: scale, cx: cx, cy: cy).z) }.sorted { $0.1 < $1.1 }
        for (p, zc) in sorted {
            let (color, alpha, glow) = style(p, fatigue: fatigue, selected: selected)
            var back = Path(), front = Path()
            for ring in rings {
                var penB = false, penF = false
                for u in ring {
                    let w = SIMD3(p.c.x + u.x * p.r.x, p.c.y + u.y * p.r.y, p.c.z + u.z * p.r.z)
                    let q = project(w, angle: angle, scale: scale, cx: cx, cy: cy)
                    let pt = CGPoint(x: q.x, y: q.y)
                    if q.z > zc - 0.5 {
                        if penF { front.addLine(to: pt) } else { front.move(to: pt); penF = true }
                        penB = false
                    } else {
                        if penB { back.addLine(to: pt) } else { back.move(to: pt); penB = true }
                        penF = false
                    }
                }
            }
            ctx.stroke(back, with: .color(color.opacity(alpha * 0.35)), lineWidth: 1)
            if glow > 0 { ctx.stroke(front, with: .color(color.opacity(0.1 + 0.12 * glow)), lineWidth: 4 + 3 * glow) }
            ctx.stroke(front, with: .color(color.opacity(alpha)), lineWidth: glow > 0 ? 1.3 : 1)
        }
    }

    private static func style(_ p: Part, fatigue: [Muscle: Double], selected: Muscle?) -> (Color, Double, Double) {
        guard let m = p.m else { return (.wire, 0.2, 0) }
        if m == selected { return (.amber, 0.95, 1) }
        let r = min(1, fatigue[m] ?? 0)
        if r <= 0.02 { return (.wire, 0.34, 0) }
        let k = min(1, 0.3 + r)
        let c = Color(.sRGB,
                      red: (168 + (126 - 168) * k) / 255,
                      green: (221 + (240 - 221) * k) / 255,
                      blue: (230 + (166 - 230) * k) / 255,
                      opacity: 1)
        return (c, 0.45 + 0.5 * r, r)
    }

    /// Welcher Muskel liegt unter dem Finger? Bei Überlappung gewinnt der vordere.
    static func pick(at pt: CGPoint, size: CGSize, angle: Double) -> Muscle? {
        let (scale, cx, cy) = frame(size)
        var best: (m: Muscle, z: Double, d: Double)? = nil
        for p in parts {
            guard let m = p.m else { continue }
            let c = project(p.c, angle: angle, scale: scale, cx: cx, cy: cy)
            let rx = max(p.r.x, p.r.z) * scale + 6, ry = p.r.y * scale + 6
            let dx = (Double(pt.x) - c.x) / rx, dy = (Double(pt.y) - c.y) / ry
            let d = dx * dx + dy * dy
            guard d <= 1 else { continue }
            if let b = best {
                if c.z > b.z + 4 || (Swift.abs(c.z - b.z) <= 4 && d < b.d) { best = (m, c.z, d) }
            } else { best = (m, c.z, d) }
        }
        return best?.m
    }
}
