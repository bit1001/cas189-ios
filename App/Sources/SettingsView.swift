import SwiftUI
import QHCore

/// Settings — mirrors SettingsPane + HaijiaoLoginDialog + UsageHelp.
struct SettingsView: View {
    @Environment(\.palette) private var p
    @EnvironmentObject private var theme: ThemeStore
    @State private var showHelp = false
    @State private var showLogin = false
    @State private var layout = "大卡"
    @State private var autoPlay = true
    @State private var backgroundPlay = false
    @State private var swipeBrightness = true
    @State private var swipeVolume = true
    @State private var swipeProgress = true
    @State private var mobileNotice = true
    @State private var autoExport = false
    @State private var wifiOnly = true
    @State private var privacy = false

    private let layouts = ["大卡", "网格", "列表"]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                Text("设置").font(.largeTitle.bold()).foregroundStyle(p.textPrimary)
                    .padding(.horizontal, 20).padding(.top, 8)

                settingsCard("外观") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("主题").font(.subheadline.weight(.semibold)).foregroundStyle(p.textPrimary)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(ThemeMode.allCases, id: \.self) { m in
                                PillButton(label: m.label, selected: theme.mode == m) { theme.mode = m }
                            }
                        }
                        Text("布局").font(.subheadline.weight(.semibold)).foregroundStyle(p.textPrimary)
                            .padding(.top, 4)
                        HStack(spacing: 8) {
                            ForEach(layouts, id: \.self) { l in
                                PillButton(label: l, selected: layout == l) { layout = l }
                            }
                        }
                    }
                }

                settingsCard("播放") {
                    VStack(spacing: 4) {
                        ToggleRow("自动连播", isOn: $autoPlay)
                        ToggleRow("后台播放", isOn: $backgroundPlay)
                        ToggleRow("滑动调节亮度", isOn: $swipeBrightness)
                        ToggleRow("滑动调节音量", isOn: $swipeVolume)
                        ToggleRow("滑动调节进度", isOn: $swipeProgress)
                        ToggleRow("移动网络播放提醒", isOn: $mobileNotice)
                    }
                }

                settingsCard("下载") {
                    VStack(spacing: 4) {
                        ToggleRow("自动导出 MP4", isOn: $autoExport)
                        ToggleRow("仅 Wi-Fi 下载", isOn: $wifiOnly)
                        Text("离开 Wi-Fi 或有线网络时等待，连上后自动继续。手动暂停保持暂停。")
                            .font(.caption2).foregroundStyle(p.textTertiary)
                    }
                }

                settingsCard("隐私与存储") {
                    VStack(spacing: 4) {
                        ToggleRow("隐私保护", isOn: $privacy)
                        NavRow("缓存", detail: "存储占用还在估算") {}
                        NavRow("观看足迹", detail: "没有记录") {}
                        Button("清理缓存") {}.font(.caption).foregroundStyle(p.accentPrimary)
                    }
                }

                settingsCard("账号与平台") {
                    VStack(spacing: 4) {
                        NavRow("海角账号", detail: "未登录") { showLogin = true }
                        NavRow("平台", detail: "") {}
                    }
                }

                settingsCard("数据") {
                    VStack(spacing: 4) {
                        NavRow("导出片库备份", detail: "") {}
                        NavRow("导入片库备份", detail: "") {}
                        NavRow("导出诊断", detail: "") {}
                        NavRow("清除诊断记录", detail: "") {}
                        NavRow("恢复默认设置", detail: "") {}
                    }
                }

                settingsCard("关于") {
                    VStack(spacing: 4) {
                        NavRow("使用帮助", detail: "") { showHelp = true }
                        NavRow("版本", detail: "青禾学堂 · v1.9.5") {}
                    }
                }
            }
            .padding(.bottom, 100)
        }
        .sheet(isPresented: $showHelp) { HelpSheet() }
        .sheet(isPresented: $showLogin) { LoginSheet() }
    }

    @ViewBuilder
    private func settingsCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(p.textTertiary)
                .textCase(.uppercase)
            content()
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(corner: 16).padding(.horizontal, 20)
    }
}

struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    @Environment(\.palette) private var p
    init(_ title: String, isOn: Binding<Bool>) { self.title = title; self._isOn = isOn }
    var body: some View {
        Toggle(title, isOn: $isOn).font(.subheadline).foregroundStyle(p.textPrimary)
            .padding(.vertical, 6)
    }
}

struct NavRow: View {
    let title: String
    let detail: String
    let action: () -> Void
    @Environment(\.palette) private var p
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.subheadline).foregroundStyle(p.textPrimary)
                Spacer()
                if !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(p.textTertiary)
                }
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(p.textTertiary)
            }
            .padding(.vertical, 8)
        }.buttonStyle(.plain)
    }
}

private struct HelpSheet: View {
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    private let sections: [(String, String)] = [
        ("进入与导航", "首页、片库、搜索、资料库、设置五个入口，底部胶囊切换。"),
        ("学习页", "学习、课程、发现、我的四个分区，含阅读器与随堂小测。"),
        ("搜索", "输入标题、作者或标签，可按排序、分区、发布时间、播放次数、时长筛选。"),
        ("普通播放", "单击显隐控制栏，双击左/中/右快退、播放暂停、快进，横滑调进度。"),
        ("短视频", "上下滑动切换，双击收藏，左右滑动切换倍速。"),
        ("片库", "收藏与观看足迹可在资料库管理、备份与清理。"),
        ("下载与 MP4", "在需处理中找到暂停或失败的任务，选择继续后可批量继续下载。"),
        ("无障碍操作", "支持系统字体与读屏。"),
        ("备份与清理", "片库备份上限 8 MB、10000 条；清理缓存不影响离线下载。"),
        ("后台与隐私", "隐私保护开启时离开应用暂停播放并屏蔽投屏。"),
        ("故障处理", "解析失败可重试当前来源、更换 API 连接或重新解析。")
    ]
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(sections, id: \.0) { s in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(s.0).font(.headline).foregroundStyle(p.textPrimary)
                            Text(s.1).font(.caption).foregroundStyle(p.textSecondary)
                        }
                    }
                }.padding(20)
            }
            .navigationTitle("使用帮助").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } } }
        }
    }
}

private struct LoginSheet: View {
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @State private var account = ""
    @State private var password = ""
    @State private var showPwd = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextField("账号", text: $account)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    if showPwd { TextField("密码", text: $password) }
                    else { SecureField("密码", text: $password) }
                    Button { showPwd.toggle() } label: {
                        Image(systemName: showPwd ? "eye.slash" : "eye")
                    }.buttonStyle(.plain)
                }
                Button("登录") { dismiss() }
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .foregroundStyle(p.badgeText)
                    .background(p.accentPrimary, in: RoundedRectangle(cornerRadius: 10))
                Button("注册") {}.font(.caption).foregroundStyle(p.accentPrimary)
            }.padding(20)
            .navigationTitle("海角账号").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } } }
        }
    }
}
