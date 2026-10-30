import SwiftUI

struct ContentView: View {
    @State private var query = ""
    @State private var expandedID: String?
    @State private var toast: String?
    @FocusState private var searchFocused: Bool

    private let rules = RuleSearch.loadBundledRules()

    private var filtered: [RuleEntry] {
        RuleSearch.filter(rules, query: query)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    searchBar
                    if filtered.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(filtered) { rule in
                                RuleCard(
                                    rule: rule,
                                    expanded: expandedID == rule.id,
                                    onToggle: {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                            expandedID = expandedID == rule.id ? nil : rule.id
                                        }
                                    },
                                    onToast: { toast = $0 }
                                )
                            }
                        }
                    }
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .sensoryFeedback(.selection, trigger: expandedID)
            .overlay(alignment: .bottom) {
                if let toast {
                    ToastView(text: toast)
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: toast)
            .task(id: toast) {
                guard toast != nil else { return }
                try? await Task.sleep(for: .seconds(2.2))
                toast = nil
            }
        }
    }

    // MARK: - 顶部

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("规则搜索")
                .font(.largeTitle.bold())
            Text("分流规则 · 去广告规则，一键导入圈 X / Surge")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// 视觉中心的大搜索框：聚焦时出现主题色描边，输入内容后出现清除按钮。
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("搜索规则，例如：抖音、YouTube、去广告", text: $query)
                .focused($searchFocused)
                .submitLabel(.search)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.accentColor.opacity(searchFocused ? 0.5 : 0), lineWidth: 2)
        }
        .animation(.easeInOut(duration: 0.2), value: searchFocused)
        .animation(.easeInOut(duration: 0.2), value: query.isEmpty)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text("没有找到相关规则")
                .font(.headline)
            Text("换个关键词试试，例如：抖音、YouTube、GPT")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private var footer: some View {
        Text("共 \(rules.count) 条规则 · 来源：GitHub 公开仓库")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - 结果卡片

private struct RuleCard: View {
    let rule: RuleEntry
    let expanded: Bool
    let onToggle: () -> Void
    let onToast: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(alignment: .center, spacing: 14) {
                    icon
                    VStack(alignment: .leading, spacing: 5) {
                        Text(rule.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(rule.source)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        badges
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    Divider()
                        .padding(.top, 14)
                    importButtons
                        .padding(.top, 14)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    private var icon: some View {
        let (symbol, tint): (String, Color) = rule.type == .adblock
            ? ("shield.fill", .orange)
            : ("globe", .blue)
        return ZStack {
            Circle()
                .fill(tint.opacity(0.14))
                .frame(width: 44, height: 44)
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(tint)
        }
    }

    private var badges: some View {
        HStack(spacing: 6) {
            Badge(text: rule.type.rawValue, tint: rule.type == .adblock ? .orange : .blue)
            ForEach(rule.clients, id: \.self) { client in
                Badge(text: client, tint: .green)
            }
        }
    }

    private var importButtons: some View {
        VStack(spacing: 10) {
            if rule.qxURL != nil {
                Button {
                    if Importer.openQuantumultX(rule) {
                        onToast("已打开圈 X，确认后即可导入")
                    }
                } label: {
                    Label("导入到圈 X", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.plain)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 13))
                .foregroundStyle(.white)
                .font(.body.weight(.semibold))
            }
            if rule.surgeModuleURL != nil {
                Button {
                    if Importer.openSurge(rule).done {
                        onToast("已打开 Surge，确认后即可安装模块")
                    }
                } label: {
                    Label("导入到 Surge（模块）", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.plain)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 13))
                .foregroundStyle(Color.accentColor)
                .font(.body.weight(.semibold))
            } else if rule.surgeURL != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        if Importer.openSurge(rule).done {
                            onToast("RULE-SET 已复制，去 Surge 里粘贴即可")
                        }
                    } label: {
                        Label("复制 RULE-SET 并打开 Surge", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.plain)
                    .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 13))
                    .foregroundStyle(Color.accentColor)
                    .font(.body.weight(.semibold))
                    Label("Surge 没有单条规则一键导入，需手动粘贴到配置", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("该规则暂无 Surge 导入方式")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - 小组件

private struct Badge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
    }
}

private struct ToastView: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }
}
