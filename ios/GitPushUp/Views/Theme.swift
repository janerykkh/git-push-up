import SwiftUI

// LABORBLATT: hellgraues Papier, schwarze Haarlinien, ein Signal-Orange, Schiefergrau für Geräte.
// Helvetica für Namen, Zahlen und Beschriftungen, Courier Prime (Schreibmaschine) für Messwerte. Alles andere als Pixel:
// Rahmen mit abgeknipsten Ecken, Balken aus Blöcken, Symbole aus Pixeln. Kein Leuchten, keine Verläufe.
// Die alten Farbnamen bleiben, damit alle Bildschirme automatisch mitziehen.

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255,
                  opacity: opacity)
    }
    static let bg = Color(hex: 0xe9e9e6)
    static let panel = Color(hex: 0xf1f1ee)
    static let line = Color(hex: 0xd0d0cc)
    static let line2 = Color(hex: 0x1c1c1c)    // Haarlinie, Rahmen
    static let fg = Color(hex: 0x181818)
    static let muted = Color(hex: 0x6a6a66)
    static let dim = Color(hex: 0xa0a09c)
    static let wire = Color(hex: 0x3e464d)     // Schiefer: Geräte, Messwerte
    static let phos = Color(hex: 0x181818)     // aktiv, geschafft: Tinte
    static let amber = Color(hex: 0xf04e23)    // Hinweis, Rekord: Signal-Orange
    static let danger = Color(hex: 0xd4351c)
    static let mind = Color(hex: 0x5b6190)     // Geist: gedämpftes Blauviolett
    static let force = Color(hex: 0xf04e23)
    static let signal = Color(hex: 0xf04e23)
    static let glassTop = Color(hex: 0xdedfdc)
}

extension ExCategory {
    var color: Color {
        switch self {
        case .beine: return Color(hex: 0x181818)
        case .druecken: return Color(hex: 0xf04e23)
        case .ziehen: return Color(hex: 0x3e464d)
        case .rumpf: return Color(hex: 0x8c8c88)
        case .dehnen: return Color(hex: 0x5f8a84)
        case .geist: return Color(hex: 0x5b6190)
        }
    }
}

/// Messwerte und Fließtext: Schreibmaschine, wie in getippten Missionsakten
func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    switch weight {
    case .semibold, .bold, .heavy, .black, .medium: return .custom("CourierPrime-Bold", size: size)
    default: return .custom("CourierPrime-Regular", size: size)
    }
}

/// Große Zahlen und Namen: Helvetica schmal und fett, die Schrift aus dem NASA-Grafikhandbuch von 1975
func display(_ size: CGFloat, condensed: Bool = true) -> Font {
    .custom(condensed ? "HelveticaNeue-CondensedBold" : "Helvetica-Bold", size: size)
}

/// Kleine Beschriftungen: Helvetica fett, gesperrt
func labelFont(_ size: CGFloat) -> Font { .custom("Helvetica-Bold", size: size) }

/// Kleine gesperrte Beschriftung wie ein graviertes Typenschild
struct Label12: View {
    let text: String
    var color: Color = .muted
    var size: CGFloat = 10.5
    var body: some View {
        Text(text).font(labelFont(size)).tracking(0.8).foregroundStyle(color)
    }
}

extension View {
    func glow(_ c: Color, _ r: CGFloat = 8) -> some View {
        // Im hellen Labor kein Leuchten mehr, nur ein Hauch Tiefe
        shadow(color: c.opacity(0.0), radius: 0)
    }
}

/// Hintergrund: helles Laborpapier mit sehr feinem Raster
struct LabBackdrop: View {
    var body: some View {
        ZStack {
            Color.bg
            Canvas { ctx, size in
                var p = Path()
                var x: CGFloat = 0
                while x < size.width { p.addRect(CGRect(x: x, y: 0, width: 0.5, height: size.height)); x += 24 }
                var y: CGFloat = 0
                while y < size.height { p.addRect(CGRect(x: 0, y: y, width: size.width, height: 0.5)); y += 24 }
                ctx.fill(p, with: .color(Color.line.opacity(0.45)))
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

/// Gerätegehäuse: helle Fläche, feiner Rahmen, kleine Justiermarken in der Akzentfarbe
struct LabFrame: ViewModifier {
    var accent: Color = .wire
    func body(content: Content) -> some View {
        content
            .background(PixelBlock().fill(Color.panel))
            .pixelBorder()
            .overlay(alignment: .topTrailing) { Rectangle().fill(accent).frame(width: PX * 2, height: PX * 2).padding(PX * 2) }
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
            Rectangle().fill(color.opacity(on ? 1 : 0.25)).frame(width: PX * 3, height: PX * 3)
        }
        .frame(width: PX * 3, height: PX * 3)
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
        HStack(spacing: PX) {
            ForEach(0..<segments, id: \.self) { i in
                Rectangle()
                    .fill(i < lit ? color : Color.line)
                    .frame(height: height)
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
            .font(mono(12, .semibold)).tracking(1)
            .foregroundStyle(filled ? Color.bg : color)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 6)
            .background(PixelBlock().fill(filled ? color : Color.panel))
            .overlay(PixelFrame().fill(filled ? color : Color.line2))
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
                    Rectangle().fill(accent).frame(width: PX * 3, height: PX * 3)
                    Label12(text: title, color: .fg, size: 12)
                    Spacer()
                    if let trailing { Text(trailing).font(mono(10)).foregroundStyle(Color.muted).lineLimit(2).multilineTextAlignment(.trailing) }
                }
                Rectangle().fill(Color.line2).frame(height: PX)
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
