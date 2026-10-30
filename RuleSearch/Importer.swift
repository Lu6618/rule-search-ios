import UIKit

/// 导入目标客户端。
enum ImportClient {
    case qx, surge
}

/// 导入：先选客户端，再经 ScriptHub 转换（圈 X 资源本身就是 QX 格式，无需转换）。
///
/// ScriptHub 转换链接格式（对照 Script-Hub 官方解析器源码核实，非猜测）：
/// - 规则集（.list）→ Surge：http://script.hub/file/_start_/<原始链接>/_end_/<文件名>?type=rule-set&target=surge-rule-set
///   （rule-parser.js：target == 'surge-rule-set' 输出 Surge RULE-SET 格式，HOST→DOMAIN 等映射都在里面）
/// - QX 重写（.conf/.snippet）→ Surge 模块：http://script.hub/file/_start_/<原始链接>/_end_/<名>.sgmodule?type=qx-rewrite&target=surge-module
///   （Rewrite-Parser.js：target == 'surge-module' 输出 Surge 模块）
/// - 圈 X：不需要转换，转换后链接就是原始链接（rule-parser 没有 QX 目标，QX 资源原生就是 QX 格式）。
///
/// 前置条件（必须让用户知道）：script.hub 不是公开域名，转换链接只有在设备上的圈 X / Surge
/// 里安装了 ScriptHub 模块（MITM 解析 script.hub）时才能打开；没装模块时转换链接拉不到，
/// App 会给回直接导入原始链接的选项，不会让用户卡死。
enum Importer {

    /// 按 RFC 3986 编码 query 参数值（只保留不保留字符）。
    private static func encode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func fileName(of url: String) -> String {
        url.split(separator: "/").last.map(String.init) ?? "rule.list"
    }

    private static func fileBase(of url: String) -> String {
        let name = fileName(of: url)
        if let dot = name.lastIndex(of: ".") { return String(name[..<dot]) }
        return name
    }

    /// 选了客户端之后的转换后链接。圈 X 直接返回原始链接。
    /// 原始链接按文档原样拼在 _start_ 和 _end_ 之间，不做百分号编码（解析器按这两个标记切分）。
    static func conversionLink(for rule: RuleEntry, client: ImportClient) -> String {
        switch client {
        case .qx:
            return rule.url
        case .surge:
            if rule.type == .adblock {
                return "http://script.hub/file/_start_/\(rule.url)/_end_/\(fileBase(of: rule.url)).sgmodule?type=qx-rewrite&target=surge-module"
            } else {
                return "http://script.hub/file/_start_/\(rule.url)/_end_/\(fileName(of: rule.url))?type=rule-set&target=surge-rule-set"
            }
        }
    }

    // MARK: - 圈 X：一键加资源

    /// .list 进 filter_remote，.conf/.snippet 进 rewrite_remote（按文件格式分，不按类型标签分）。
    @discardableResult
    static func openQuantumultX(link: String, tag: String) -> Bool {
        let key = (link.hasSuffix(".conf") || link.hasSuffix(".snippet")) ? "rewrite_remote" : "filter_remote"
        let entry = "\(link), tag=\(tag)"
        guard let data = try? JSONSerialization.data(withJSONObject: [key: [entry]]),
              let json = String(data: data, encoding: .utf8),
              let url = URL(string: "quantumult-x:///add-resource?remote-resource=\(encode(json))") else {
            return false
        }
        UIApplication.shared.open(url)
        return true
    }

    // MARK: - Surge

    /// Surge 去广告类：转换后的模块链接真一键安装。
    @discardableResult
    static func openSurgeModule(link: String) -> Bool {
        guard let url = URL(string: "surge:///install-module?url=\(encode(link))") else {
            return false
        }
        UIApplication.shared.open(url)
        return true
    }

    /// Surge 分流到代理：模块规则指不到用户策略组，这个限制不变，
    /// 所以仍走复制 RULE-SET 行 + 打开 Surge 手动粘贴。返回复制的行。
    @discardableResult
    static func copySurgeRuleSet(link: String) -> String {
        let line = "RULE-SET,\(link),你的策略组"
        UIPasteboard.general.string = line
        if let url = URL(string: "surge:///") {
            UIApplication.shared.open(url)
        }
        return line
    }

    /// 兜底用的复制：把一段文本放进剪贴板。
    static func copyText(_ text: String) {
        UIPasteboard.general.string = text
    }
}
