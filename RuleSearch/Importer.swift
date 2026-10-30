import UIKit

/// 只拼 URL Scheme 并 openURL，不做网络请求、不改任何配置。
enum Importer {

    /// 按 RFC 3986 编码 query 参数值（只保留不保留字符）。
    private static func encode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    /// 圈 X：一键加资源。
    /// 分流进 filter_remote；去广告重写（.conf）进 rewrite_remote；
    /// 其余 .list（包括去广告过滤列表）进 filter_remote。
    @discardableResult
    static func openQuantumultX(_ rule: RuleEntry) -> Bool {
        guard let link = rule.qxURL else { return false }
        let key: String
        if rule.type == .adblock, link.hasSuffix(".conf") {
            key = "rewrite_remote"
        } else {
            key = "filter_remote"
        }
        let entry = "\(link), tag=\(rule.name)"
        guard let data = try? JSONSerialization.data(withJSONObject: [key: [entry]]),
              let json = String(data: data, encoding: .utf8),
              let url = URL(string: "quantumult-x:///add-resource?remote-resource=\(encode(json))") else {
            return false
        }
        UIApplication.shared.open(url)
        return true
    }

    /// Surge：去广告/直连类如果有 .sgmodule 链接 → 真一键装模块；
    /// 分流到代理的没有真一键导入 → 复制 RULE-SET 行并打开 Surge，
    /// 界面上写明需手动粘贴到配置。
    /// 返回（是否执行，复制到剪贴板的内容）。
    static func openSurge(_ rule: RuleEntry) -> (done: Bool, copiedLine: String?) {
        if rule.type == .adblock, let module = rule.surgeModuleURL,
           let url = URL(string: "surge:///install-module?url=\(encode(module))") {
            UIApplication.shared.open(url)
            return (true, nil)
        }
        guard let link = rule.surgeURL else { return (false, nil) }
        let line = "RULE-SET,\(link),你的策略组"
        UIPasteboard.general.string = line
        if let url = URL(string: "surge:///") {
            UIApplication.shared.open(url)
        }
        return (true, line)
    }
}
