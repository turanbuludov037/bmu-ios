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
    static let deep = Color.dyn(0x1B2850, 0x2A3672)
    static let indigo = Color.dyn(0x4558B8, 0x9AA8FF)
    static let btn = Color.dyn(0x4558B8, 0x4F62D0)
    static let lime = Color(hex: 0xD6F57A)
    static let onLime = Color(hex: 0x1B2850)
    static let muted = Color.dyn(0x6B7194, 0x9CA2C6)
    static let green = Color.dyn(0x2E8B57, 0x7BDCA0)
    static let orange = Color.dyn(0xE07A10, 0xFFA552)
    static let rose = Color.dyn(0xB3322F, 0xFF8E89)
}

// MARK: - Fon: şüşə effekti rəngli fonda görünür, ona görə yumşaq rəngli ləkələr

struct AppBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        ZStack {
            LinearGradient(colors: dark ? [Color(hex: 0x0B0F1E), Color(hex: 0x161D3D)] : [Color(hex: 0xE8EBFF), Color(hex: 0xF7F8FE)],
                           startPoint: .top, endPoint: .bottom)
            Circle().fill(Color(hex: 0x4558B8).opacity(dark ? 0.55 : 0.32))
                .frame(width: 380, height: 380).blur(radius: 90).offset(x: -150, y: -330)
            Circle().fill(Color(hex: 0xD6F57A).opacity(dark ? 0.22 : 0.45))
                .frame(width: 320, height: 320).blur(radius: 100).offset(x: 170, y: 80)
            Circle().fill(Color(hex: 0x9AA8FF).opacity(dark ? 0.30 : 0.35))
                .frame(width: 280, height: 280).blur(radius: 90).offset(x: -130, y: 430)
        }
        .ignoresSafeArea()
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

    /// Dairəvi / kapsul şüşə (kiçik nişanlar, ikon düymələri).
    @ViewBuilder
    func glassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(liquidGlass(tint: tint, interactive: interactive), in: .capsule)
        } else {
            self.background(Capsule().fill(.ultraThinMaterial))
                .overlay(Capsule().strokeBorder(.white.opacity(0.18)))
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
}

@available(iOS 26.0, *)
private func liquidGlass(tint: Color?, interactive: Bool) -> Glass {
    var g: Glass = .regular
    if let tint { g = g.tint(tint) }
    if interactive { g = g.interactive() }
    return g
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
