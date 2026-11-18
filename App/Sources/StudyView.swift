import SwiftUI

/// Study (青禾学堂) — mirrors StudyCoverScreen: 4-tab standalone module
/// StudyPine palette extracted from APK ARGB longs.
private struct StudyColors {
    static let pine = Color(hex: 0xFF2D6A5B)
    static let mist = Color(hex: 0xFFF3F6F7)
    static let ink = Color(hex: 0xFF172B36)
    static let muted = Color(hex: 0xFF6B7881)
    static let line = Color(hex: 0xFFE3E9EB)
    static let correct = Color(hex: 0xFF2D6A5B)
    static let wrong = Color(hex: 0xFFAC713B)
}

enum StudyTab: Int, CaseIterable {
    case learn = 0, courses, discover, profile
    var label: String {
        switch self {
        case .learn: return "学习"
        case .courses: return "课程"
        case .discover: return "发现"
        case .profile: return "我的"
        }
    }
    var icon: String {
        switch self {
        case .learn: return "book.fill"
        case .courses: return "books.vertical.fill"
        case .discover: return "compass"
        case .profile: return "person"
        }
    }
}

struct StudyView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tab: StudyTab = .learn
    @State private var showJoin = false
    @State private var showReader = false
    @State private var showGoal = false
    @State private var showNickname = false
    @State private var nickname = "学习者"
    @State private var goal = 15

    var body: some View {
        NavigationStack {
            ZStack {
                StudyColors.mist.ignoresSafeArea()
                VStack(spacing: 0) {
                    studyTopBar
                    tabBar
                    TabView(selection: $tab) {
                        LearnPage(showReader: $showReader).tag(StudyTab.learn)
                        CoursesPage(showJoin: $showJoin).tag(StudyTab.courses)
                        DiscoverPage().tag(StudyTab.discover)
                        ProfilePage(nickname: $nickname, goal: $goal, showGoal: $showGoal, showNickname: $showNickname)
                            .tag(StudyTab.profile)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
            .navigationTitle("青禾学堂")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showJoin = true } label: { Image(systemName: "magnifyingglass") }
                }
            }
            .sheet(isPresented: $showJoin) { JoinDialog() }
            .sheet(isPresented: $showReader) { ReaderView() }
            .sheet(isPresented: $showGoal) { GoalDialog(goal: $goal) }
            .sheet(isPresented: $showNickname) { NicknameDialog(nickname: $nickname) }
        }
    }

    private var studyTopBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "book.fill").font(.title3).foregroundStyle(StudyColors.pine)
            Text("青禾学堂").font(.system(size: 20, weight: .bold)).foregroundStyle(StudyColors.ink)
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(StudyTab.allCases, id: \.self) { t in
                Button {
                    withAnimation { tab = t }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: t.icon).font(.system(size: 18))
                        Text(t.label).font(.system(size: 11))
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(tab == t ? StudyColors.pine : StudyColors.muted)
                    .background(Capsule().fill(tab == t ? Color(hex: 0xFFE9F2EE) : Color.clear))
                }.buttonStyle(.plain)
            }
        }
        .padding(6).background(Color.white).padding(.horizontal, 16)
    }
}

// MARK: - Learn page
private struct LearnPage: View {
    @Binding var showReader: Bool
    private let days = ["一", "二", "三", "四", "五", "六", "日"]
    private let learned: Set<Int> = [0, 1, 2, 4]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("今天也进步一点点").font(.title3.bold()).foregroundStyle(StudyColors.ink)
                spotlight
                HStack(spacing: 10) {
                    Metric(title: "今日分钟", value: "24")
                    Metric(title: "已学课时", value: "6")
                    Metric(title: "学习笔记", value: "3")
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("本周打卡").font(.headline).foregroundStyle(StudyColors.ink)
                    HStack(spacing: 8) {
                        ForEach(0..<7, id: \.self) { i in
                            VStack(spacing: 4) {
                                Circle()
                                    .fill(learned.contains(i) ? StudyColors.pine : StudyColors.line)
                                    .frame(width: 30, height: 30)
                                    .overlay(Image(systemName: learned.contains(i) ? "checkmark" : "")
                                        .font(.caption).foregroundStyle(.white))
                                Text(days[i]).font(.caption2).foregroundStyle(StudyColors.muted)
                            }
                        }
                    }
                }
                .padding(16).background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            }
            .padding(20)
        }
    }

    private var spotlight: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("推荐课程 · 从简单函数认识极限").font(.headline).foregroundStyle(StudyColors.ink)
            Text("阅读约 8 分钟 · 3 课时").font(.caption).foregroundStyle(StudyColors.muted)
            Button { showReader = true } label: {
                Text("继续学习").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(StudyColors.pine, in: Capsule())
            }
        }
        .padding(16).background(Color.white, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct Metric: View {
    let title: String
    let value: String
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.bold()).foregroundStyle(StudyColors.pine)
            Text(title).font(.caption2).foregroundStyle(StudyColors.muted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Courses page
private struct CoursesPage: View {
    @Binding var showJoin: Bool
    @State private var filter = 0
    private let filters = ["全部", "未开始", "学习中", "已完成"]
    private let courses = [
        ("英语听读", "校园与日常场景", 2, 1),
        ("数学基础", "从函数到极限", 3, 0),
        ("计算机基础", "看懂一次网页请求", 2, 2)
    ]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(StudyColors.muted)
                    Text("搜索课程或课时").foregroundStyle(StudyColors.muted)
                    Spacer()
                }.padding(12).background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                HStack(spacing: 8) {
                    ForEach(0..<filters.count, id: \.self) { i in
                        PillButton(label: filters[i], selected: filter == i) { filter = i }
                    }
                    Spacer()
                }
                ForEach(courses, id: \.0) { c in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(c.0).font(.headline).foregroundStyle(StudyColors.ink)
                            Spacer()
                            Image(systemName: c.3 == 2 ? "checkmark.circle.fill" : "chevron.right")
                                .foregroundStyle(c.3 == 2 ? StudyColors.pine : StudyColors.muted)
                        }
                        Text(c.1).font(.caption).foregroundStyle(StudyColors.muted)
                        Text("\(c.2) 课时 · 已学 \(c.3)").font(.caption2).foregroundStyle(StudyColors.muted)
                    }
                    .padding(14).background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                }
                Button("加入课程（输入课程码）") { showJoin = true }
                    .font(.caption).foregroundStyle(StudyColors.pine)
            }
            .padding(20)
        }
    }
}

// MARK: - Discover page
private struct DiscoverPage: View {
    private let tips = [
        ("阅读前列出问题", "写下本课要解决的一个问题，阅读后用自己的语言回答。"),
        ("用复述检查理解", "不看材料，说明概念含义和一个例子。"),
        ("课后复习步骤", "查看笔记，重做随堂题，再对照讲解检查答案。")
    ]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("学习方法与课程导读").font(.title3.bold()).foregroundStyle(StudyColors.ink)
                ForEach(tips, id: \.0) { t in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(t.0).font(.headline).foregroundStyle(StudyColors.ink)
                        Text(t.1).font(.caption).foregroundStyle(StudyColors.muted)
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                }
            }.padding(20)
        }
    }
}

// MARK: - Profile page
private struct ProfilePage: View {
    @Binding var nickname: String
    @Binding var goal: Int
    @Binding var showGoal: Bool
    @Binding var showNickname: Bool
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill").font(.system(size: 56)).foregroundStyle(StudyColors.pine)
                    VStack(alignment: .leading) {
                        Text(nickname).font(.headline).foregroundStyle(StudyColors.ink)
                        Button("修改昵称") { showNickname = true }.font(.caption).foregroundStyle(StudyColors.pine)
                    }
                }
                HStack(spacing: 10) {
                    Metric(title: "累计分钟", value: "186")
                    Metric(title: "完成课时", value: "12")
                    Metric(title: "学习天数", value: "9")
                }
                Button { showGoal = true } label: {
                    HStack {
                        Text("每日学习目标").foregroundStyle(StudyColors.ink)
                        Spacer()
                        Text("\(goal) 分钟").foregroundStyle(StudyColors.muted)
                        Image(systemName: "chevron.right").foregroundStyle(StudyColors.muted)
                    }.font(.subheadline)
                }.padding(14).background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                Text("学习进度与笔记保存在这台设备上。").font(.caption2).foregroundStyle(StudyColors.muted)
                Text("青禾学堂 · v1.9.5").font(.caption2).foregroundStyle(StudyColors.muted)
            }.padding(20)
        }
    }
}

// MARK: - Reader (core feature)
private struct ReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var answer: String? = nil
    @State private var note = ""
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("从一个简单函数认识极限").font(.title2.bold()).foregroundStyle(StudyColors.ink)
                    Text("我们用 f(a) 表示函数在 a 点的取值。极限描述的是当 x 趋近 a 时，f(x) 趋近的值，而不是取到的值。无论从左侧还是右侧靠近，结果都应当一致。")
                        .font(.body).foregroundStyle(StudyColors.ink)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("随堂小测").font(.headline).foregroundStyle(StudyColors.ink)
                        Text("x 趋近 1 时，2x 的极限是？").font(.subheadline).foregroundStyle(StudyColors.ink)
                        ForEach(["A. 1", "B. 2", "C. 不存在"], id: \.self) { opt in
                            Button {
                                answer = opt
                            } label: {
                                HStack {
                                    Text(opt)
                                    Spacer()
                                    if answer == opt {
                                        Image(systemName: opt.hasPrefix("B") ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    }
                                }
                                .padding(10)
                                .foregroundStyle(answer == opt ? (opt.hasPrefix("B") ? StudyColors.correct : StudyColors.wrong) : StudyColors.ink)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain)
                        }
                        if let a = answer {
                            Text(a.hasPrefix("B") ? "回答正确。" : "再想一想。")
                                .font(.caption).foregroundStyle(a.hasPrefix("B") ? StudyColors.correct : StudyColors.wrong)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("学习笔记").font(.headline).foregroundStyle(StudyColors.ink)
                        TextEditor(text: $note).frame(minHeight: 100)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                    }
                    Button("标记本课已学完") {}.frame(maxWidth: .infinity).padding(.vertical, 12)
                        .foregroundStyle(.white).background(StudyColors.pine, in: Capsule())
                }.padding(20)
            }
            .background(StudyColors.mist)
            .navigationTitle("阅读器").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } } }
        }
    }
}

// MARK: - Dialogs
private struct JoinDialog: View {
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("输入课程码加入课程").font(.headline).foregroundStyle(p.textPrimary)
                TextField("课程码", text: $code).textFieldStyle(.roundedBorder)
                Button("加入") { dismiss() }.frame(maxWidth: .infinity).padding(.vertical, 12)
                    .foregroundStyle(p.badgeText).background(p.accentPrimary, in: RoundedRectangle(cornerRadius: 10))
            }.padding(24)
            .navigationTitle("加入课程").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } } }
        }
    }
}

private struct GoalDialog: View {
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @Binding var goal: Int
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("每日学习目标").font(.headline).foregroundStyle(p.textPrimary)
                HStack(spacing: 10) {
                    ForEach([10, 15, 30], id: \.self) { g in
                        PillButton(label: "\(g) 分钟", selected: goal == g) { goal = g }
                    }
                }
                Button("保存") { dismiss() }.frame(maxWidth: .infinity).padding(.vertical, 12)
                    .foregroundStyle(p.badgeText).background(p.accentPrimary, in: RoundedRectangle(cornerRadius: 10))
            }.padding(24)
            .navigationTitle("每日目标").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } } }
        }
    }
}

private struct NicknameDialog: View {
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @Binding var nickname: String
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("修改昵称").font(.headline).foregroundStyle(p.textPrimary)
                TextField("昵称", text: $nickname).textFieldStyle(.roundedBorder)
                Button("保存") { dismiss() }.frame(maxWidth: .infinity).padding(.vertical, 12)
                    .foregroundStyle(p.badgeText).background(p.accentPrimary, in: RoundedRectangle(cornerRadius: 10))
            }.padding(24)
            .navigationTitle("昵称").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } } }
        }
    }
}
