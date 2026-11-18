import SwiftUI

enum AppTab: Int, CaseIterable, Identifiable {
    case home = 0, browse, search, library, settings
    var id: Int { rawValue }
    // Labels are placeholder until the home/nav spec lands from decompiled source.
    var label: String {
        switch self {
        case .home: return "首页"
        case .browse: return "浏览"
        case .search: return "搜索"
        case .library: return "资料库"
        case .settings: return "设置"
        }
    }
    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .browse: return "square.grid.2x2.fill"
        case .search: return "magnifyingglass"
        case .library: return "books.vertical.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

/// Floating capsule dock — mirrors FloatingCapsuleDock in AppleGlassTheme.kt
struct DockView: View {
    @Binding var selection: AppTab
    @Environment(\.palette) private var p
    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selection = tab }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 20, weight: selection == tab ? .semibold : .regular))
                        Text(tab.label)
                            .font(.system(size: 10, weight: selection == tab ? .semibold : .regular))
                    }
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .foregroundStyle(selection == tab ? p.dockTextActive : p.dockTextInactive)
                    .background(
                        Capsule().fill(selection == tab ? p.dockActivePill : Color.clear)
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(
            Capsule()
                .fill(p.dockBg)
                .overlay(Capsule().stroke(p.dockBorder, lineWidth: 0.5))
                .shadow(color: .black.opacity(p.isDark ? 0.4 : 0.12), radius: 18, y: 6)
        )
        .padding(.horizontal, 16)
    }
}

/// Apple-glass background: vertical gradient + soft radial blobs (mirrors AppleGlassBackground)
struct GlassBackground: View {
    @Environment(\.palette) private var p
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [p.bgTopTint, p.bgBase, p.isDark ? Color(hex: 0xFF0B0D11) : p.bgBase],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            if p.isDark {
                Circle().fill(Color(hex: 0xFF241442).opacity(0.35))
                    .frame(width: 420, height: 420)
                    .blur(radius: 90)
                    .offset(x: -120, y: -240)
                Circle().fill(p.accentPrimary.opacity(0.18))
                    .frame(width: 360, height: 360)
                    .blur(radius: 100)
                    .offset(x: 150, y: 320)
            }
        }
    }
}

/// Glass card modifier (mirrors appleGlassCard)
struct GlassCard: ViewModifier {
    @Environment(\.palette) private var p
    var corner: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: corner)
                    .fill(p.cardSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: corner)
                            .stroke(p.cardBorder, lineWidth: 0.8)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: corner))
    }
}
extension View {
    func glassCard(corner: CGFloat = 16) -> some View { modifier(GlassCard(corner: corner)) }
}
