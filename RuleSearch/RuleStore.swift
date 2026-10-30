import Foundation
import Network

/// 在线索引的状态：仓库列表、缓存条目、更新时间、离线状态。
/// 缓存策略（纠正后的版本，以此为准）：
/// - 24 小时内算新鲜，新鲜的不重复拉；
/// - 断网或拉取失败时，优先用上次缓存的全量列表，哪怕超过 24 小时也照常用，界面标明数据时间；
/// - 只有从没成功拉到过、本地完全没有缓存时，才回落到内置 16 条。
/// 仓库被删后，它的缓存条目不再出现；加回来后，缓存还在就直接恢复，不用重新拉。
@MainActor
final class RuleStore: ObservableObject {
    @Published private(set) var repos: [RepoSource] = []
    @Published private(set) var entries: [RuleEntry] = []
    @Published private(set) var updatedAt: Date?
    @Published var isLoading = false
    @Published var notice: String?
    @Published var isOffline = false
    @Published var adding = false
    @Published var addError: String?

    private var cache: CacheFile = CacheFile(repos: [:])
    private var hasEverFetched = false
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "rulesearch.network")

    private enum Keys {
        static let repos = "rulesearch.repos.v1"
        static let everFetched = "rulesearch.hasEverFetched.v1"
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Keys.repos),
           let saved = try? JSONDecoder().decode([RepoSource].self, from: data),
           !saved.isEmpty {
            repos = saved
        } else {
            repos = SearchEngine.defaultRepos
        }
        hasEverFetched = UserDefaults.standard.bool(forKey: Keys.everFetched)
        cache = CacheFile.load()
        recompute()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.isOffline = path.status != .satisfied }
        }
        monitor.start(queue: monitorQueue)
    }

    // MARK: - 派生状态

    private var hasCachedEntries: Bool {
        repos.contains { !(cache.repos[$0.key]?.entries.isEmpty ?? true) }
    }

    var updatedText: String {
        if let updatedAt {
            let formatter = DateFormatter()
            formatter.dateFormat = "MM-dd HH:mm"
            return "数据更新于 \(formatter.string(from: updatedAt))"
        }
        if entries.isEmpty { return "暂无数据" }
        return "内置数据"
    }

    func cachedEntryCount(for repo: RepoSource) -> Int? {
        cache.repos[repo.key]?.entries.count
    }

    private func recompute() {
        let keys = Set(repos.map { $0.key })
        var all: [RuleEntry] = []
        var latest: Date?
        for (key, repoCache) in cache.repos where keys.contains(key) {
            all.append(contentsOf: repoCache.entries)
            if let current = latest {
                latest = max(current, repoCache.fetchedAt)
            } else {
                latest = repoCache.fetchedAt
            }
        }
        if all.isEmpty {
            // 从没成功拉到过才回落内置 16 条；删光仓库后是空列表，不是内置。
            entries = hasEverFetched ? [] : RuleSearch.loadBundledRules()
            updatedAt = latest
        } else {
            entries = all.sorted { a, b in
                a.source == b.source
                    ? a.name.localizedStandardCompare(b.name) == .orderedAscending
                    : a.source < b.source
            }
            updatedAt = latest
        }
    }

    private func saveRepos() {
        if let data = try? JSONEncoder().encode(repos) {
            UserDefaults.standard.set(data, forKey: Keys.repos)
        }
    }

    private func markFetched() {
        hasEverFetched = true
        UserDefaults.standard.set(true, forKey: Keys.everFetched)
    }

    // MARK: - 刷新

    func refreshIfNeeded() async {
        let now = Date()
        let stale = repos.contains { repo in
            guard let cached = cache.repos[repo.key], cached.branch == repo.branch else { return true }
            return now.timeIntervalSince(cached.fetchedAt) >= 24 * 3600
        }
        if stale { await refresh() }
    }

    func refresh(force: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        notice = nil
        defer { isLoading = false }
        var failed: [String] = []
        var anySuccess = false
        var updatedRepos = repos
        for (index, repo) in repos.enumerated() {
            if !force,
               let cached = cache.repos[repo.key], cached.branch == repo.branch,
               Date().timeIntervalSince(cached.fetchedAt) < 24 * 3600 {
                continue
            }
            do {
                let result = try await SearchEngine.fetchEntries(for: repo)
                cache.repos[repo.key] = RepoCache(branch: result.resolvedBranch, fetchedAt: Date(), entries: result.entries)
                if result.resolvedBranch != repo.branch {
                    updatedRepos[index].branch = result.resolvedBranch
                }
                anySuccess = true
            } catch {
                failed.append(repo.key)
            }
        }
        if updatedRepos != repos {
            repos = updatedRepos
            saveRepos()
        }
        cache.save()
        if anySuccess { markFetched() }
        recompute()
        if !failed.isEmpty {
            if hasCachedEntries {
                notice = "更新失败，仍显示上次缓存"
            } else if !hasEverFetched {
                notice = "拉取失败，当前显示内置数据，联网后点刷新重试"
            } else {
                notice = "拉取失败，暂无可用数据"
            }
        }
    }

    // MARK: - 仓库管理

    /// 新增仓库：先拉一次文件列表验证，拉不到或里面没有 QX 资源就报错、不添加。
    func addRepo(ownerRepo: String, branch: String) async {
        adding = true
        addError = nil
        defer { adding = false }
        let trimmed = ownerRepo.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "/").map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            addError = "格式不对，填 owner/repo，例如 blackmatrix7/ios_rule_script"
            return
        }
        let owner = parts[0], repo = parts[1]
        let key = "\(owner)/\(repo)"
        guard !repos.contains(where: { $0.key == key }) else {
            addError = "该仓库已在列表中"
            return
        }
        let wantedBranch = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        let wanted = wantedBranch.isEmpty ? "main" : wantedBranch
        do {
            let result = try await SearchEngine.fetchEntries(owner: owner, repo: repo, branch: wanted)
            guard !result.entries.isEmpty else {
                addError = "该仓库没有 QX 资源，未添加"
                return
            }
            repos.append(RepoSource(owner: owner, repo: repo, branch: result.resolvedBranch, isCustom: true))
            saveRepos()
            cache.repos[key] = RepoCache(branch: result.resolvedBranch, fetchedAt: Date(), entries: result.entries)
            cache.save()
            markFetched()
            recompute()
        } catch {
            addError = "拉取失败，请检查仓库名和分支（网络问题或仓库不存在）"
        }
    }

    /// 内置和自定义的仓库都能删；删了之后搜索结果里就不含这家的条目。
    func deleteRepo(_ repo: RepoSource) {
        repos.removeAll { $0.key == repo.key }
        saveRepos()
        cache.repos.removeValue(forKey: repo.key)
        cache.save()
        recompute()
    }

    /// 一键回到最初 6 家，并把自定义仓库的缓存清掉，随后按新鲜度补拉。
    func restoreDefaultsAndRefresh() async {
        repos = SearchEngine.defaultRepos
        saveRepos()
        let defaultKeys = Set(repos.map { $0.key })
        cache.repos = cache.repos.filter { defaultKeys.contains($0.key) }
        cache.save()
        recompute()
        await refresh()
    }
}
