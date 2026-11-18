import SwiftUI
import QHCore

/// Shared small components matching AppleGlassChip / section headers.
struct PillButton: View {
    let label: String
    let selected: Bool
    let action: () -> Void
    @Environment(\.palette) private var p
    var body: some View {
        Button(action: action) {
            Text(label).font(.subheadline.weight(.medium))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .foregroundStyle(selected ? p.badgeText : p.textSecondary)
                .background(Capsule().fill(selected ? p.accentPrimary.opacity(0.85) : p.cardSurface))
                .overlay(Capsule().stroke(p.cardBorder, lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }
}

struct SectionHeader: View {
    let title: String
    var icon: String? = nil
    var trailing: String? = nil
    var action: (() -> Void)? = nil
    @Environment(\.palette) private var p
    var body: some View {
        HStack {
            if let icon { Label(title, systemImage: icon).font(.headline) }
            else { Text(title).font(.headline) }
            Spacer()
            if let trailing {
                Button(trailing, action: action ?? {}).font(.caption).foregroundStyle(p.accentPrimary)
            }
        }
        .foregroundStyle(p.textPrimary)
    }
}

struct EmptyState: View {
    let icon: String
    let text: String
    @Environment(\.palette) private var p
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 40)).foregroundStyle(p.textTertiary)
            Text(text).font(.subheadline).foregroundStyle(p.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

func demoVideos(prefix: String, count: Int = 10) -> [SiteVideo] {
    let titles = ["深入解析极限与连续", "从零开始的网页请求", "第一天：认识函数", "路线表达与方向词",
                  "借阅场景常用表达", "常见状态码详解", "直观理解变化与趋近", "课后复习步骤"]
    return (0..<count).map { i in
        SiteVideo(site: "demo", id: "\(prefix)-\(i)", title: titles[i % titles.count],
                  cover: nil, views: (i + 1) * 987,
                  durationText: String(format: "%02d:%02d", 5 + i, (i * 11) % 60))
    }
}
