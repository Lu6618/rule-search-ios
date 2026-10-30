import SwiftUI

/// 根视图：首页（分流 / 去广告两个大入口）+ 仓库管理 sheet。
/// 设计语言沿用 v1：ScrollView + LazyVStack、52pt 大搜索框、20pt 边距、18pt 卡片圆角、
/// 语义色（亮暗都好看）、spring 展开动画、毛玻璃胶囊 toast。
struct ContentView: View {
    @StateObject private var store = RuleStore()
    @StateObject private var favorites = FavoritesStore()
    @State private var showingRepos = false

    var body: some View {
        NavigationStack {
            HomeView(store: store, favorites: favorites, showingRepos: $showingRepos)
        }
        .sheet(isPresented: $showingRepos) {
            RepoManagementView(store: store)
        }
        .task {
            await store.refreshIfNeeded()
        }
    }
}

// MARK: - 首页

struct HomeView: View {
    @ObservedObject var store: RuleStore
    @ObservedObject var favorites: FavoritesStore
    @Binding var showingRepos: Bool

    private var routingCount: Int { store.entries.filter { $0.type == .routing }.count }
    private var adblockCount: Int { store.entries.filter { $0.type == .adblock }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("规则搜索")
                        .font(.largeTitle.bold())
                    Text("分流规则 · 去广告规则，搜 QX 资源，导入时经 ScriptHub 转成对应客户端格式")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                NavigationLink {
                    SearchView(store: store, favorites: favorites, type: .routing)
                } label: {
                    HomeEntryCard(type: .routing, count: routingCount)
                }
                .buttonStyle(.plain)
                NavigationLink {
                    SearchView(store: store, favorites: favorites, type: .adblock)
                } label: {
                    HomeEntryCard(type: .adblock, count: adblockCount)
                }
                .buttonStyle(.plain)
                VStack(spacing: 4) {
                    Text("共 \(store.entries.count) 条规则 · 来源：GitHub 公开仓库")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(store.updatedText)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingRepos = true
                } label: {
                    Image(systemName: "folder.badge.gearshape")
                }
                .accessibilityLabel("仓库管理")
            }
        }
    }
}

private struct HomeEntryCard: View {
    let type: RuleEntry.Kind
    let count: Int

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.14))
                    .frame(width: 52, height: 52)
                Image(systemName: type == .adblock ? "shield.fill" : "globe")
                    .font(.title3)
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(type == .adblock ? "去广告" : "分流")
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                Text(type == .adblock ? "QX 重写文件，屏蔽广告与开屏推广" : "QX filter 列表，按域名分流到代理")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(count) 条")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    private var tint: Color { type == .adblock ? .orange : .blue }
}

// MARK: - 搜索页（已按入口类型过滤）

struct SearchView: View {
    @ObservedObject var store: RuleStore
    @ObservedObject var favorites: FavoritesStore
    let type: RuleEntry.Kind

    @State private var query = ""
    @State private var expandedKey: String?
    @State private var toast: String?
    @FocusState private var searchFocused: Bool

    private var typed: [RuleEntry] { store.entries.filter { $0.type == type } }
    private var favoriteEntries: [RuleEntry] { typed.filter { favorites.isFavorite($0.id) } }
    private var results: [RuleEntry] { RuleSearch.filter(typed, query: query) }
    private var title: String { type == .adblock ? "去广告" : "分流" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                dataRow
                if store.isOffline {
                    Text("当前离线：搜索可用；导入只是把链接交给圈 X / Surge，由它们下载规则文件，没网时导入会失败，联网后再点一次。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let notice = store.notice {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                searchBar
                if query.isEmpty, !favoriteEntries.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("收藏")
                            .font(.headline)
                        LazyVStack(spacing: 12) {
                            ForEach(favoriteEntries) { rule in
                                card(rule, section: "fav")
                            }
                        }
                        Text("全部规则")
                            .font(.headline)
                            .padding(.top, 4)
                    }
                }
                if query.isEmpty {
                    if typed.isEmpty {
                        emptyState(text: store.entries.isEmpty ? "暂无规则，去首页右上角仓库管理添加来源" : "该类型下暂无规则")
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(typed) { rule in
                                card(rule, section: "all")
                            }
                        }
                    }
                } else if results.isEmpty {
                    emptyState(text: "没有找到相关规则")
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(results) { rule in
                            card(rule, section: "search")
                        }
                    }
                }
                Text("共 \(typed.count) 条规则 · 来源：GitHub 公开仓库")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: expandedKey)
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

    private var dataRow: some View {
        HStack(spacing: 8) {
            if store.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
            Text(store.updatedText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("刷新") {
                Task { await store.refresh(force: true) }
            }
            .font(.subheadline.weight(.medium))
            .disabled(store.isLoading)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("搜索\(title)规则，例如：\(type == .adblock ? "去广告、重写" : "抖音、YouTube")", text: $query)
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

    private func emptyState(text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.headline)
            Text("换个关键词试试")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private func card(_ rule: RuleEntry, section: String) -> some View {
        let key = "\(section):\(rule.id)"
        return RuleCard(
            rule: rule,
            expanded: expandedKey == key,
            onToggle: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    expandedKey = expandedKey == key ? nil : key
                }
            },
            onToast: { toast = $0 },
            isFavorite: favorites.isFavorite(rule.id),
            onToggleFavorite: { favorites.toggle(rule.id) },
            isOffline: store.isOffline
        )
    }
}

// MARK: - 结果卡片：星标 + 选客户端 + ScriptHub 转换 + 预览 + 导入 + 兜底

private struct RuleCard: View {
    let rule: RuleEntry
    let expanded: Bool
    let onToggle: () -> Void
    let onToast: (String) -> Void
    let isFavorite: Bool
    let onToggleFavorite: () -> Void
    let isOffline: Bool

    @State private var client: ImportClient?
    @State private var surgeConverting = false
    @State private var surgeConvertedText: String?
    @State private var surgeFailed = false
    @State private var showPreview = false
    @State private var qxPreviewText: String?
    @State private var qxPreviewLoading = false
    @State private var qxPreviewFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                HStack(spacing: 14) {
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
                        Badge(text: rule.type.rawValue, tint: rule.type == .adblock ? .orange : .blue)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onToggle)
                Button(action: onToggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.body)
                        .foregroundStyle(isFavorite ? .yellow : .tertiary)
                }
                .buttonStyle(.plain)
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
                    .onTapGesture(perform: onToggle)
            }
            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    Divider()
                        .padding(.top, 14)
                    importFlow
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

    // MARK: 导入流程：选客户端 → 转换 → 预览 / 导入，失败给兜底

    private var importFlow: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch client {
            case nil:
                Text("选择客户端")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    clientButton("圈 X") { client = .qx }
                    clientButton("Surge") { chooseSurge() }
                }
            case .qx:
                qxImportSection
            case .surge:
                if surgeConverting {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在通过 ScriptHub 转换…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else if let text = surgeConvertedText {
                    previewToggle
                    if showPreview {
                        previewBox(text: text)
                    }
                    surgeImportButtons
                    Text("转换链接需设备上安装 ScriptHub 模块才能打开（script.hub 经模块 MITM 解析）。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    resetClientButton
                } else if surgeFailed {
                    Text("ScriptHub 转换失败：可能未安装 ScriptHub 模块，或当前网络无法解析 script.hub。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    surgeFallbackButtons
                    HStack(spacing: 16) {
                        Button("重新转换") { chooseSurge() }
                        resetClientButton
                    }
                    .font(.footnote)
                }
            }
            if isOffline, client != nil {
                Text("导入只是把链接交给圈 X / Surge，由它们下载规则文件；没网时导入会失败，联网后再点一次。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func clientButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
        .foregroundStyle(Color.accentColor)
        .font(.body.weight(.semibold))
    }

    private var resetClientButton: some View {
        Button("换个客户端") {
            client = nil
            surgeConvertedText = nil
            surgeFailed = false
            showPreview = false
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private func chooseSurge() {
        client = .surge
        surgeConverting = true
        surgeFailed = false
        surgeConvertedText = nil
        showPreview = false
        let link = Importer.conversionLink(for: rule, client: .surge)
        Task {
            do {
                guard let url = URL(string: link) else { throw URLError(.badURL) }
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                let text = String(decoding: data, as: UTF8.self)
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw URLError(.cannotDecodeContentData)
                }
                surgeConvertedText = text
            } catch {
                surgeFailed = true
            }
            surgeConverting = false
        }
    }

    // MARK: 圈 X：无需转换，原始链接直接可用

    private var qxImportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            previewToggle
            if showPreview {
                if qxPreviewLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在拉取…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let text = qxPreviewText {
                    previewBox(text: text)
                } else if qxPreviewFailed {
                    Text("网络问题，预览失败，联网后再试")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                if Importer.openQuantumultX(link: rule.url, tag: rule.name) {
                    onToast(isOffline ? "已打开圈 X；当前离线，联网后请再点一次导入" : "已打开圈 X，确认后即可导入")
                }
            } label: {
                Label("导入到圈 X", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.plain)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 13))
            .foregroundStyle(.white)
            .font(.body.weight(.semibold))
            resetClientButton
        }
    }

    private var previewToggle: some View {
        Button {
            showPreview.toggle()
            if showPreview, client == .qx, qxPreviewText == nil, !qxPreviewLoading, !qxPreviewFailed {
                fetchQXPreview()
            }
        } label: {
            Label(showPreview ? "收起预览" : "预览", systemImage: "eye")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private func fetchQXPreview() {
        qxPreviewLoading = true
        Task {
            do {
                guard let url = URL(string: rule.url) else { throw URLError(.badURL) }
                let (data, _) = try await URLSession.shared.data(from: url)
                qxPreviewText = String(decoding: data, as: UTF8.self)
            } catch {
                qxPreviewFailed = true
            }
            qxPreviewLoading = false
        }
    }

    private func previewBox(text: String) -> some View {
        let (total, lines) = previewLines(for: text)
        return VStack(alignment: .leading, spacing: 6) {
            Text("共 \(total) 行，前 \(lines.count) 行非空行")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(lines.joined(separator: "\n"))
                .font(.system(.caption, design: .monospaced))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func previewLines(for text: String) -> (total: Int, lines: [String]) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return (0, []) }
        var all = text.components(separatedBy: .newlines)
        if text.hasSuffix("\n") { all.removeLast() }
        let nonEmpty = all.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return (all.count, Array(nonEmpty.prefix(15)))
    }

    // MARK: Surge：转换后链接导入

    private var surgeImportButtons: some View {
        VStack(alignment: .leading, spacing: 10) {
            if rule.type == .adblock {
                Button {
                    let link = Importer.conversionLink(for: rule, client: .surge)
                    if Importer.openSurgeModule(link: link) {
                        onToast(isOffline ? "已打开 Surge；当前离线，联网后请再点一次" : "已打开 Surge，确认后即可安装模块")
                    }
                } label: {
                    Label("导入到 Surge（模块）", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.plain)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 13))
                .foregroundStyle(Color.accentColor)
                .font(.body.weight(.semibold))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        let link = Importer.conversionLink(for: rule, client: .surge)
                        Importer.copySurgeRuleSet(link: link)
                        onToast(isOffline ? "RULE-SET 已复制；当前离线，联网后去 Surge 粘贴" : "RULE-SET（转换后）已复制，去 Surge 里粘贴即可")
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
            }
        }
    }

    // MARK: 兜底：直接导入原始链接，不让用户卡死

    private var surgeFallbackButtons: some View {
        VStack(alignment: .leading, spacing: 10) {
            if rule.type == .routing {
                Button {
                    Importer.copySurgeRuleSet(link: rule.url)
                    onToast("已复制原始链接的 RULE-SET（QX 格式，Surge 可能无法识别部分规则）")
                } label: {
                    Label("直接导入原始链接（复制 RULE-SET）", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.plain)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 13))
                .foregroundStyle(Color.accentColor)
                .font(.body.weight(.semibold))
            } else {
                Button {
                    Importer.copyText(rule.url)
                    onToast("原始链接已复制（QX 重写文件需经转换才能用作 Surge 模块）")
                } label: {
                    Label("复制原始链接", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.plain)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 13))
                .foregroundStyle(Color.accentColor)
                .font(.body.weight(.semibold))
            }
        }
    }
}

// MARK: - 仓库管理（首页右上角独立入口，不跟搜索结果混在一起）

struct RepoManagementView: View {
    @ObservedObject var store: RuleStore
    @Environment(\.dismiss) private var dismiss

    @State private var ownerRepo = ""
    @State private var branch = "main"
    @State private var deleteTarget: RepoSource?
    @State private var showDeleteAlert = false
    @State private var showRestoreAlert = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    addCard
                    VStack(alignment: .leading, spacing: 12) {
                        Text("仓库（\(store.repos.count) 家）")
                            .font(.headline)
                        ForEach(store.repos) { repo in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(repo.key)
                                        .font(.headline)
                                        .lineLimit(1)
                                    HStack(spacing: 6) {
                                        Badge(text: repo.isCustom ? "自定义" : "内置", tint: repo.isCustom ? .purple : .green)
                                        Text(repo.branch)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        if let count = store.cachedEntryCount(for: repo) {
                                            Text("\(count) 条")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        } else {
                                            Text("未拉取")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                Spacer()
                                Button {
                                    deleteTarget = repo
                                    showDeleteAlert = true
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(16)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                        }
                    }
                    Button("恢复默认仓库") {
                        showRestoreAlert = true
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .buttonStyle(.plain)
                    .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 13))
                    .foregroundStyle(Color.accentColor)
                    .font(.body.weight(.semibold))
                    Text("仓库列表只存在本机。删除仓库后，它的条目会从搜索结果里消失；之后加回来，收藏会自动恢复。新增仓库会先拉一次文件列表验证，拉不到或里面没有 QX 资源时不会添加。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("仓库管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .alert("删除仓库？", isPresented: $showDeleteAlert) {
                Button("删除", role: .destructive) {
                    if let repo = deleteTarget {
                        store.deleteRepo(repo)
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("删除后该仓库的条目会从搜索结果里消失。")
            }
            .alert("恢复默认仓库？", isPresented: $showRestoreAlert) {
                Button("恢复", role: .destructive) {
                    Task { await store.restoreDefaultsAndRefresh() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("回到最初 6 家，自定义仓库和它们的缓存会被清掉。")
            }
        }
    }

    private var addCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("新增仓库")
                .font(.headline)
            TextField("owner/repo，例如 blackmatrix7/ios_rule_script", text: $ownerRepo)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(10)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            TextField("分支（默认 main，拉不到自动试 master）", text: $branch)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(10)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            if let error = store.addError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Button {
                Task {
                    await store.addRepo(ownerRepo: ownerRepo, branch: branch)
                    if store.addError == nil {
                        ownerRepo = ""
                        branch = "main"
                    }
                }
            } label: {
                HStack {
                    if store.adding {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(store.adding ? "正在验证…" : "验证并添加")
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.white)
            .font(.body.weight(.semibold))
            .disabled(store.adding || ownerRepo.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
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
