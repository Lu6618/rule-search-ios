import Foundation

/// 一条规则的索引数据，对应 rules.json 里的一条。
/// Codable：在线拉到的条目同样要写进本地缓存，所以需要可编码。
/// id 必须是稳定的“仓库 + 文件路径”，收藏靠它在索引刷新后不丢。
/// url 是唯一的原始链接：索引只收 QX 资源，选客户端时再经 ScriptHub 转换，
/// 不再像 v1 那样一条规则分圈 X 版 / Surge 版，搜索结果也不再按客户端分开展示。
struct RuleEntry: Identifiable, Codable {
    enum Kind: String, Codable {
        case routing = "分流"
        case adblock = "去广告"
    }

    let id: String
    let name: String
    let keywords: [String]
    let source: String
    let type: Kind
    /// 原始 QX 资源链接（raw.githubusercontent.com）。
    let url: String

    enum CodingKeys: String, CodingKey {
        case id, name, keywords, source, type, url
    }
}

/// 模糊搜索：大小写不敏感的子串匹配 + 常见别名表。
enum RuleSearch {

    /// 一组同义词：命中组里任一词，就等于命中组里所有词。
    static let aliasGroups: [[String]] = [
        ["抖音", "douyin", "dy"],
        ["油管", "youtube", "yt"],
        ["推特", "twitter"],
        ["电报", "telegram", "tg"],
        ["奈飞", "netflix", "nf"],
        ["gpt", "openai", "chatgpt"],
        ["苹果", "apple"],
        ["快手", "kuaishou"],
        ["小红书", "redbook", "xiaohongshu"],
        ["谷歌", "google"],
        ["去广告", "广告", "adblock"],
    ]

    static func matches(_ rule: RuleEntry, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }
        let haystacks = ([rule.name] + rule.keywords).map { $0.lowercased() }
        if haystacks.contains(where: { $0.contains(q) }) { return true }
        // 别名展开：单字查询不展开，避免一个字母命中一大片。
        guard q.count >= 2 else { return false }
        for group in aliasGroups {
            let synonyms = group.map { $0.lowercased() }
            guard synonyms.contains(where: { $0.contains(q) || q.contains($0) }) else { continue }
            if haystacks.contains(where: { h in synonyms.contains(where: { h.contains($0) }) }) {
                return true
            }
        }
        return false
    }

    static func filter(_ rules: [RuleEntry], query: String) -> [RuleEntry] {
        rules.filter { matches($0, query: query) }
    }

    /// 从 App 包里读 rules.json；读不到就返回空列表，不崩。
    static func loadBundledRules() -> [RuleEntry] {
        guard let url = Bundle.main.url(forResource: "rules", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rules = try? JSONDecoder().decode([RuleEntry].self, from: data) else {
            return []
        }
        return rules
    }
}
