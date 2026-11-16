import SwiftUI
import UIKit

// MARK: - Rənglər (Android tətbiqi ilə eyni palitra)

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    init(hex: UInt32) { self.init(uiColor: UIColor(hex: hex)) }

    /// İşıqlı / tünd rejimə görə dəyişən rəng.
    static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

enum C {
    static let navy = Color.dyn(0x1B2850, 0xE6E9FA)
    static let indigo = Color.dyn(0x4558B8, 0x9AA8FF)
    static let btn = Color.dyn(0x4558B8, 0x5468D8)
    static let lime = Color(hex: 0xD6F57A)
    static let onLime = Color(hex: 0x1B2850)
    static let green = Color.dyn(0x2E8B57, 0x7BDCA0)
    static let orange = Color.dyn(0xE07A10, 0xFFA552)
    static let rose = Color.dyn(0xB3322F, 0xFF8E89)
    static let purple = Color.dyn(0x7A4FD0, 0xC2A6FF)
    static let teal = Color.dyn(0x1A8C8C, 0x6FE0DA)
    static let pink = Color.dyn(0xC2457A, 0xFF9CC4)
}

// MARK: - Canlı fon: şüşə effekti rəngli fonda görünür, ləkələr yavaş-yavaş üzür

struct AppBackground: View {
    @Environment(\.colorScheme) private var scheme
    @State private var drift = false

    var body: some View {
        let dark = scheme == .dark
        ZStack {
            LinearGradient(colors: dark ? [Color(hex: 0x0B0F1E), Color(hex: 0x161D3D)] : [Color(hex: 0xE8EBFF), Color(hex: 0xF7F8FE)],
                           startPoint: .top, endPoint: .bottom)
            Circle().fill(Color(hex: 0x4558B8).opacity(dark ? 0.55 : 0.32))
                .frame(width: 380, height: 380).blur(radius: 90)
                .offset(x: drift ? -110 : -170, y: drift ? -300 : -350)
            Circle().fill(Color(hex: 0xD6F57A).opacity(dark ? 0.22 : 0.45))
                .frame(width: 320, height: 320).blur(radius: 100)
                .offset(x: drift ? 130 : 190, y: drift ? 130 : 60)
            Circle().fill(Color(hex: 0x9AA8FF).opacity(dark ? 0.30 : 0.35))
                .frame(width: 280, height: 280).blur(radius: 90)
                .offset(x: drift ? -90 : -150, y: drift ? 400 : 460)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}

// MARK: - Liquid Glass (iOS 26). Köhnə iOS-da buzlu şüşə (material) ilə əvəz olunur.

extension View {
    /// Şüşə kart: iOS 26-da əsl Liquid Glass, köhnə versiyalarda ultraThinMaterial.
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 24, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(liquidGlass(tint: tint, interactive: interactive), in: .rect(cornerRadius: cornerRadius))
        } else {
            self
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(.ultraThinMaterial)
                        if let tint { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(tint.opacity(0.25)) }
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(.white.opacity(0.18)))
        }
    }

    /// Kapsul şüşə (kiçik nişanlar).
    @ViewBuilder
    func glassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(liquidGlass(tint: tint, interactive: interactive), in: .capsule)
        } else {
            self.background(Capsule().fill(.ultraThinMaterial))
                .overlay(Capsule().strokeBorder(.white.opacity(0.18)))
        }
    }

    /// Dairəvi şüşə (ikonlar).
    @ViewBuilder
    func glassCircle(tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(liquidGlass(tint: tint, interactive: false), in: .circle)
        } else {
            self.background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().strokeBorder(.white.opacity(0.18)))
        }
    }

    /// Şüşə düymə. prominent = əsas əməliyyat (rəngli şüşə).
    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if prominent { self.buttonStyle(.glassProminent) } else { self.buttonStyle(.glass) }
        } else {
            if prominent { self.buttonStyle(.borderedProminent) } else { self.buttonStyle(.bordered) }
        }
    }

    /// Kart ekrana gələndə yumşaq "üzüb çıxma" animasiyası (index = sıra, ardıcıl gəlir).
    func appear(_ index: Int = 0) -> some View { modifier(AppearFx(index: index)) }

    /// Sürüşdürəndə kənara çıxan kartlar bir az kiçilib solur (iOS 17 scrollTransition).
    func scrollFx() -> some View {
        self.scrollTransition(.animated(.spring(response: 0.4, dampingFraction: 0.85))) { content, phase in
            content
                .scaleEffect(phase.isIdentity ? 1 : 0.94)
                .opacity(phase.isIdentity ? 1 : 0.55)
                .blur(radius: phase.isIdentity ? 0 : 1.5)
        }
    }
}

@available(iOS 26.0, *)
private func liquidGlass(tint: Color?, interactive: Bool) -> Glass {
    var g: Glass = .regular
    if let tint { g = g.tint(tint) }
    if interactive { g = g.interactive() }
    return g
}

private struct AppearFx: ViewModifier {
    let index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 18)
            .scaleEffect(shown ? 1 : 0.97, anchor: .top)
            .onAppear {
                guard !shown else { return }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(Double(min(index, 12)) * 0.045)) { shown = true }
            }
    }
}

/// Toxunanda yaylanan (basılıb buraxılan) düymə üslubu + yüngül titrəmə.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(.spring(response: 0.28, dampingFraction: 0.6), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in if pressed { Haptic.soft() } }
    }
}

/// Aşağıdakı şüşə tab paneli aşağı sürüşdürəndə kiçilsin (iOS 26).
struct TabBarMinimize: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}

// MARK: - Yüklənmə: parıldayan şüşə kartlar (boz skelet yox)

private struct Shimmer: ViewModifier {
    @State private var x: CGFloat = -1

    func body(content: Content) -> some View {
        content.overlay {
            GeometryReader { g in
                LinearGradient(colors: [.clear, .white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: g.size.width * 0.6)
                    .offset(x: x * g.size.width * 1.4)
                    .blendMode(.plusLighter)
            }
            .mask(content)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { x = 1.2 }
        }
    }
}

extension View {
    func shimmer() -> some View { modifier(Shimmer()) }
}

/// Məzmun yüklənərkən göstərilən parıldayan kartlar.
struct LoadingStack: View {
    var count = 3
    var height: CGFloat = 86

    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<count, id: \.self) { i in
                HStack(spacing: 14) {
                    Circle().fill(Color.primary.opacity(0.08)).frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 8) {
                        Capsule().fill(Color.primary.opacity(0.10)).frame(width: 170, height: 12)
                        Capsule().fill(Color.primary.opacity(0.06)).frame(width: 110, height: 10)
                    }
                    Spacer()
                }
                .padding(16)
                .frame(height: height)
                .glassCard(cornerRadius: 22)
                .shimmer()
                .appear(i)
            }
        }
    }
}
