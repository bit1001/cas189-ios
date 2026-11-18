import SwiftUI

// MARK: - Apple Glass palette (extracted 1:1 from decompiled com.pornshop.player.ui.AppThemeColors)
// Colors are ARGB longs from the APK converted to #AARRGGBB.
struct GlassPalette {
    let isDark: Bool
    let bgBase: Color
    let bgTopTint: Color
    let surface: Color
    let cardSurface: Color
    let cardBorder: Color
    let cardBorderHighlight: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let accentPrimary: Color
    let progressColor: Color
    let dockBg: Color
    let dockActivePill: Color
    let dockBorder: Color
    let dockTextActive: Color
    let dockTextInactive: Color
    let badgeBg: Color
    let badgeText: Color
}

extension GlassPalette {
    // WarmSand — default light export from the APK
    static let warmSand = GlassPalette(
        isDark: false,
        bgBase: Color(hex: 0xFFD6CEBA),
        bgTopTint: Color(hex: 0xFFDED8C6),
        surface: Color(hex: 0xFFDFD8C6),
        cardSurface: Color(hex: 0xFFE8E2D2).opacity(0.88),
        cardBorder: Color(hex: 0xFF8C7F6B).opacity(0.18),
        cardBorderHighlight: Color.white.opacity(0.55),
        textPrimary: Color(hex: 0xFF262118),
        textSecondary: Color(hex: 0xFF6B6152),
        textTertiary: Color(hex: 0xFF706656),
        accentPrimary: Color(hex: 0xFF6832BD),
        progressColor: Color(hex: 0xFF8B5CF6),
        dockBg: Color(hex: 0xFFE4DDD0).opacity(0.94),
        dockActivePill: Color(hex: 0xFFC7BFA8),
        dockBorder: Color.white.opacity(0.5),
        dockTextActive: Color(hex: 0xFF241E15),
        dockTextInactive: Color(hex: 0xFF706656),
        badgeBg: Color(hex: 0xFFEDE7DC).opacity(0.92),
        badgeText: Color(hex: 0xFF3C3326)
    )

    static let white = GlassPalette(
        isDark: false,
        bgBase: .white,
        bgTopTint: Color(hex: 0xFFF7F8FA),
        surface: Color(hex: 0xFFF3F4F6),
        cardSurface: Color.white.opacity(0.98),
        cardBorder: Color(hex: 0xFF111827).opacity(0.08),
        cardBorderHighlight: Color.white.opacity(0.95),
        textPrimary: Color(hex: 0xFF111827),
        textSecondary: Color(hex: 0xFF4B5563),
        textTertiary: Color(hex: 0xFF6B7280),
        accentPrimary: Color(hex: 0xFF6832BD),
        progressColor: Color(hex: 0xFF7C3AED),
        dockBg: Color.white.opacity(0.96),
        dockActivePill: Color(hex: 0xFFEDE9FE),
        dockBorder: Color(hex: 0xFF111827).opacity(0.08),
        dockTextActive: Color(hex: 0xFF111827),
        dockTextInactive: Color(hex: 0xFF6B7280),
        badgeBg: Color(hex: 0xFFF3F4F6),
        badgeText: Color(hex: 0xFF111827)
    )

    static let obsidianDark = GlassPalette(
        isDark: true,
        bgBase: Color(hex: 0xFF101216),
        bgTopTint: Color(hex: 0xFF171A21),
        surface: Color(hex: 0xFF1C1F28),
        cardSurface: Color(hex: 0xFF232733),
        cardBorder: Color.white.opacity(0.10),
        cardBorderHighlight: Color.white.opacity(0.10),
        textPrimary: Color(hex: 0xFFF8FAFC),
        textSecondary: Color(hex: 0xFF94A3B8),
        textTertiary: Color(hex: 0xFFA0AEC2),
        accentPrimary: Color(hex: 0xFFB69AF7),
        progressColor: Color(hex: 0xFF8B5CF6),
        dockBg: Color(hex: 0xFF1B1E28),
        dockActivePill: Color(hex: 0xFF33384A),
        dockBorder: Color.white.opacity(0.10),
        dockTextActive: .white,
        dockTextInactive: Color(hex: 0xFF94A3B8),
        badgeBg: Color(hex: 0xFF282D3D),
        badgeText: Color(hex: 0xFFE2E8F0)
    )
}

enum ThemeMode: String, CaseIterable, Identifiable {
    case system, light, dark, warmSand
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "纯白"
        case .dark: return "曜石黑"
        case .warmSand: return "暖沙"
        }
    }
}

final class ThemeStore: ObservableObject {
    @Published var mode: ThemeMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "theme_mode") }
    }
    init() {
        mode = ThemeMode(rawValue: UserDefaults.standard.string(forKey: "theme_mode") ?? "") ?? .warmSand
    }
    func palette(systemDark: Bool) -> GlassPalette {
        switch mode {
        case .system: return systemDark ? .obsidianDark : .warmSand
        case .light: return .white
        case .dark: return .obsidianDark
        case .warmSand: return .warmSand
        }
    }
}

extension Color {
    init(hex: UInt32) {
        let a = CGFloat((hex >> 24) & 0xFF) / 255
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

// Environment key for the active palette
struct PaletteKey: EnvironmentKey {
    static let defaultValue: GlassPalette = .warmSand
}
extension EnvironmentValues {
    var palette: GlassPalette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}
