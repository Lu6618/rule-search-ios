import Foundation

/// 一个规则仓库源。存在 UserDefaults，默认就是下面 6 家，用户可增删。
struct RepoSource: Codable, Equatable, Identifiable {
    var owner: String
    var repo: String
    var branch: String
    var isCustom: Bool

    /// 稳定键：owner/repo，也是缓存和条目 id 的前缀。
    var key: String { "\(owner)/\(repo)" }
    var id: String { key }
}

/// 单个仓库的缓存：拉到的条目 + 拉取时间。写进 Application Support 的文件，不走 UserDefaults（条目多）。
struct RepoCache: Codable {
    var branch: String
    var fetchedAt: Date
    var entries: [RuleEntry]
}

struct CacheFile: Codable {
    var repos: [String: RepoCache]

    static func fileURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("rule-cache.json")
    }

    static func load() -> CacheFile {
        guard let url = fileURL(),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(CacheFile.self, from: data) else {
            return CacheFile(repos: [:])
        }
        return file
    }

    func save() {
        guard let url = Self.fileURL() else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: url)
        }
    }
}

/// 在线搜索的引擎：拉 GitHub 仓库的 recursive tree，本地筛出规则文件生成条目。
/// 不带任何认证（GitHub 未认证限流 60 次/小时，App 一次刷新最多拉仓库数个 tree，够用）。
/// jsDelivr 数据接口曾试过，返回 URL not found，已放弃，不再用它。
///
/// 索引只收 QX 资源（内置和自定义仓库同一套标准）：
/// - 分流 = QX 的 filter 列表，即 QX 倾向目录下的 .list；
/// - 去广告 = QX 的重写文件，即 rewrite 目录下的 .conf。
/// Surge、Loon、Clash、Shadowrocket、Stash、Egern 目录下的文件一律不收；
/// .sgmodule、.snippet、.plugin、.yaml、脚本、图片、文档、整包配置一律不收。
/// 类型只按文件种类定，不再靠路径关键词猜。
enum SearchEngine {

    static let defaultRepos: [RepoSource] = [
        RepoSource(owner: "blackmatrix7", repo: "ios_rule_script", branch: "master", isCustom: false),
        RepoSource(owner: "fmz200", repo: "wool_scripts", branch: "main", isCustom: false),
        RepoSource(owner: "sve1r", repo: "Rules-For-Quantumult-X", branch: "main", isCustom: false),
        RepoSource(owner: "zqzess", repo: "rule_for_quantumultX", branch: "master", isCustom: false),
        RepoSource(owner: "ACL4SSR", repo: "ACL4SSR", branch: "master", isCustom: false),
        RepoSource(owner: "ddgksf2013", repo: "ddgksf2013", branch: "main", isCustom: false),
    ]

    // MARK: - 拉取

    private struct GitHubTree: Decodable {
        struct Node: Decodable {
            let path: String
            let type: String
        }
        let tree: [Node]
    }

    /// 拉一个仓库的条目。分支拉不到就自动试 master（新增仓库时分支默认 main，走的就是这条 fallback）。
    /// 返回条目和实际用到的分支；分支解析失败（404 等）会抛错，调用方据此报错。
    static func fetchEntries(for repo: RepoSource) async throws -> (entries: [RuleEntry], resolvedBranch: String) {
        try await fetchEntries(owner: repo.owner, repo: repo.repo, branch: repo.branch)
    }

    static func fetchEntries(owner: String, repo: String, branch: String) async throws -> (entries: [RuleEntry], resolvedBranch: String) {
        var branches = [branch]
        if branch != "master" { branches.append("master") }
        var lastError: Error?
        for b in branches {
            do {
                let paths = try await fetchTreePaths(owner: owner, repo: repo, branch: b)
                let source = RepoSource(owner: owner, repo: repo, branch: b, isCustom: false)
                return (buildEntries(source: source, paths: paths), b)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? URLError(.badURL)
    }

    static func fetchTreePaths(owner: String, repo: String, branch: String) async throws -> [String] {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/git/trees/\(branch)?recursive=1") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.setValue("RuleSearch", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let tree = try JSONDecoder().decode(GitHubTree.self, from: data)
        return tree.tree.filter { $0.type == "blob" }.map { $0.path }
    }

    // MARK: - 筛选（只收 QX 资源）

    /// 其他客户端的目录：一出现就一票否决，不管文件叫什么。
    private static let excludedClientDirs: Set<String> = ["surge", "loon", "clash", "shadowrocket", "stash", "egern"]

    /// QX 倾向的目录：.list 必须处在其中之一。
    /// quantumultx 覆盖 bm7 的 rule/QuantumultX、fmz200 的 QuantumultX/filter、zqzess 的 QuantumultX/rules；
    /// rules 覆盖 sve1r 的 Rules（这个仓库本身就是 QX 规则集）；filter 覆盖扁平布局的 QX 仓库。
    private static let qxDirs: Set<String> = ["quantumultx", "rules", "filter"]

    /// 一条路径是不是 QX 资源。返回类型，nil 表示不收。
    static func qxKind(for path: String) -> RuleEntry.Kind? {
        let lower = path.lowercased()
        let parts = lower.split(separator: "/").map(String.init)
        if parts.contains(where: { excludedClientDirs.contains($0) }) { return nil }
        if lower.hasSuffix(".list") {
            return parts.contains(where: { qxDirs.contains($0) }) ? .routing : nil
        }
        if lower.hasSuffix(".conf") {
            return parts.contains("rewrite") ? .adblock : nil
        }
        return nil
    }

    static func buildEntries(source: RepoSource, paths: [String]) -> [RuleEntry] {
        paths.compactMap { path in
            guard let type = qxKind(for: path) else { return nil }
            let name = displayName(for: path)
            var keywords = Array(Set([name, parentDir(of: path), fileBase(of: path)]).filter { !$0.isEmpty })
            keywords.append(type == .adblock ? "去广告" : "分流")
            if type == .adblock { keywords.append("adblock") }
            return RuleEntry(
                id: "\(source.key):\(path)",
                name: name,
                keywords: keywords,
                source: source.key,
                type: type,
                url: rawURL(source: source, path: path)
            )
        }.sorted { a, b in
            a.source == b.source
                ? a.name.localizedStandardCompare(b.name) == .orderedAscending
                : a.source < b.source
        }
    }

    // MARK: - 命名

    private static func fileBase(of path: String) -> String {
        let last = path.split(separator: "/").last.map(String.init) ?? path
        if let dot = last.lastIndex(of: ".") { return String(last[..<dot]) }
        return last
    }

    private static func parentDir(of path: String) -> String {
        let parts = path.split(separator: "/").map(String.init)
        return parts.count >= 2 ? parts[parts.count - 2] : ""
    }

    /// 名字取文件名去后缀；文件名太泛（filter、list、index 之类）时取父目录名。
    private static func displayName(for path: String) -> String {
        let base = fileBase(of: path)
        let parent = parentDir(of: path)
        let generic: Set<String> = ["filter", "list", "rules", "index", "main", "all"]
        if generic.contains(base.lowercased()), !parent.isEmpty, !generic.contains(parent.lowercased()) {
            return parent
        }
        return base
    }

    static func rawURL(source: RepoSource, path: String) -> String {
        "https://raw.githubusercontent.com/\(source.owner)/\(source.repo)/\(source.branch)/\(path)"
    }
}
