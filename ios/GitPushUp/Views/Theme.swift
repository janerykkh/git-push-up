import SwiftUI

// BIO-LAB: geheimes Forschungslabor aus einem alten Science-Fiction-Film.
// Dunkles Grün-Schwarz wie getöntes Glas, cremefarbene Beschriftung wie auf alten Instrumententafeln,
// Serum-Türkis für Messgeräte, Bio-Lime für "aktiv", Bernstein für Warnlampen. Futura für Beschriftungen (60er-Jahre-Zukunft),
// Monospace für Messwerte.

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255,
                  opacity: opacity)
    }
    static let bg = Color(hex: 0x050807)
    static let panel = Color(hex: 0x0a110f)
    static let line = Color(hex: 0x182420)
    static let line2 = Color(hex: 0x2b3d35)
    static let fg = Color(hex: 0xece6cf)
    static let muted = Color(hex: 0x8a978c)
    static let dim = Color(hex: 0x4a5a51)
    static let wire = Color(hex: 0x79e6d0)
    static let phos = Color(hex: 0xb4ff5a)
    static let amber = Color(hex: 0xffae42)
    static let danger = Color(hex: 0xff5470)
    static let mind = Color(hex: 0xb49bff)
    static let glassTop = Color(hex: 0x0f1d19)
}

extension ExCategory {
    var color: Color {
        switch self {
        case .beine: return Color(hex: 0xb4ff5a)
        case .druecken: return Color(hex: 0xffae42)
        case .ziehen: return Color(hex: 0x6fc3ff)
        case .rumpf: return Color(hex: 0xe07cff)
        case .dehnen: return Color(hex: 0xff9f7a)
        case .geist: return Color(hex: 0xb49bff)
        }
    }
}

/// Messwerte, Zahlen, Fließtext
func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    .system(size: size, weight: weight, design: .monospaced)
}

/// Große Beschriftungen: Futura, wie auf Laborgeräten und Filmplakaten der 60er
func display(_ size: CGFloat, condensed: Bool = true) -> Font {
    .custom(condensed ? "Futura-CondensedExtraBold" : "Futura-Bold", size: size)
}

func labelFont(_ size: CGFloat) -> Font { .custom("Futura-Medium", size: size) }

/// Kleine gesperrte Beschriftung wie ein graviertes Typenschild
struct Label12: View {
    let text: String
    var color: Color = .muted
    var size: CGFloat = 10.5
    var body: some View {
        Text(text).font(labelFont(size)).tracking(2).foregroundStyle(color)
    }
}

extension View {
    func glow(_ c: Color, _ r: CGFloat = 8) -> some View {
        shadow(color: c.opacity(0.55), radius: r)
    }
}

/// Hintergrund: getöntes Glas mit feinen Bildschirmzeilen, wie ein alter Monitor im Labor
struct LabBackdrop: View {
    var body: some View {
        ZStack {
            Color.bg
            RadialGradient(colors: [Color.glassTop, Color.bg], center: .top, startRadius: 0, endRadius: 650)
            Canvas { ctx, size in
                var p = Path()
                var y: CGFloat = 0
                while y < size.height { p.addRect(CGRect(x: 0, y: y, width: size.width, height: 1)); y += 3 }
                ctx.fill(p, with: .color(.black.opacity(0.25)))
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Eckwinkel wie Justiermarken auf einem Messgerät
struct CornerMarks: Shape {
    var len: CGFloat = 10
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + len)); p.addLine(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX + len, y: r.minY))
        p.move(to: CGPoint(x: r.maxX - len, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY + len))
        p.move(to: CGPoint(x: r.maxX, y: r.maxY - len)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX - len, y: r.maxY))
        p.move(to: CGPoint(x: r.minX + len, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY - len))
        return p
    }
}

/// Gerätegehäuse: dunkle Glasfläche, feiner Rahmen, Justiermarken in der Akzentfarbe
struct LabFrame: ViewModifier {
    var accent: Color = .wire
    func body(content: Content) -> some View {
        content
            .background(Color.panel.opacity(0.85))
            .overlay(Rectangle().stroke(Color.line2, lineWidth: 1))
            .overlay(CornerMarks().stroke(accent.opacity(0.8), lineWidth: 1.5))
    }
}

extension View {
    func labFrame(_ accent: Color = .wire) -> some View { modifier(LabFrame(accent: accent)) }
}

/// Leuchtende Statuslampe
struct Lamp: View {
    var color: Color = .phos
    var blink = true
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.8)) { tl in
            let on = !blink || Int(tl.date.timeIntervalSinceReferenceDate / 0.8) % 2 == 0
            Circle().fill(color.opacity(on ? 1 : 0.25)).frame(width: 7, height: 7).glow(on ? color : .clear, 5)
        }
        .frame(width: 7, height: 7)
    }
}

/// Segmentanzeige wie eine LED-Leiste
struct SegMeter: View {
    let value: Double
    var color: Color = .wire
    var segments = 20
    var height: CGFloat = 8
    var body: some View {
        let lit = Int((min(1, max(0, value)) * Double(segments)).rounded())
        HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { i in
                Rectangle()
                    .fill(i < lit ? color : Color.line)
                    .frame(height: height)
                    .shadow(color: i < lit ? color.opacity(0.6) : .clear, radius: 3)
            }
        }
    }
}

/// Knopf im Laborstil
struct HangarButtonStyle: ButtonStyle {
    var color: Color = .fg
    var filled = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(display(15, condensed: false)).tracking(2)
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 6)
            .background(color.opacity(filled ? 0.1 : 0).background(Color.panel))
            .overlay(Rectangle().stroke(filled ? color : Color.line2, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Instrumenten-Panel mit Typenschild
struct Block<Content: View>: View {
    let title: String?
    var trailing: String? = nil
    var accent: Color = .wire
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Rectangle().fill(accent).frame(width: 6, height: 6).glow(accent, 4)
                    Label12(text: title, color: .fg, size: 12)
                    Spacer()
                    if let trailing { Text(trailing).font(mono(10)).foregroundStyle(Color.muted).lineLimit(2).multilineTextAlignment(.trailing) }
                }
                Rectangle().fill(Color.line2).frame(height: 1)
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .labFrame(accent)
    }
}

func fmtTime(_ ts: Millis) -> String {
    let d = Date(timeIntervalSince1970: ts / 1000)
    let f = DateFormatter()
    f.locale = Locale(identifier: "de_DE")
    f.dateFormat = "dd.MM. · HH:mm"
    return f.string(from: d)
}
