# 未核实清单（没有放进 rules.json）

第一版只收经 GitHub API 或 raw 链接核实过真实存在的路径。下面这些没核实到，
一律没进 `rules.json`，等核实后再加。

## bm7 抖音（状态未知，不是“不存在”）

- `blackmatrix7/ios_rule_script` 的 `rule/QuantumultX/DouYin/DouYin.list`：
  API 检查时返回 403（疑似 GitHub 未登录限流），按要求没有重试。
  只能记为“未核实”，不能断言该文件不存在，也不要凭印象把它加进索引。

## zqzess（只核实到目录结构）

- `zqzess/rule_for_quantumultX`：确认根目录有 QuantumultX、Surge、Clash、Loon 等目录，
  QuantumultX 下有 rules、rewrite、snippet 子目录和 `zqzess.conf` 整包配置，
  但没有核实到具体某条规则文件的文件名，因此一条都没收。
  `zqzess.conf` 是整包配置，不是单条规则，不适合做一键导入条目。

## ACL4SSR（没有圈 X / Surge 可用路径）

- `ACL4SSR/ACL4SSR`：根目录只有 Acl、Clash、Tool、scripts，没有 QuantumultX 或 Surge 目录，
  没有可直接用于圈 X / Surge 的 `.list`，因此没收。

## ddgksf2013（没有规则文件）

- `ddgksf2013/ddgksf2013`：根目录只有一个 README.md，没有可直接链接的规则文件，
  因此没收。

## Surge 侧（第一版数据里没有 .sgmodule）

- 本次核实的三家来源里，没有核实到可用于去广告/直连类的 `.sgmodule` 链接。
  因此第一版所有 Surge 导入都走“复制 RULE-SET 行 + 打开 Surge 手动粘贴”这一路，
  `surge:///install-module` 的分支代码已写好，但第一版数据里没有触发它的条目，
  这条分支的真机表现还没法验证（见汇报）。

## bm7 Surge 只核实了 6 条

- bm7 Surge 目录只核实了 Apple、Twitter、Telegram、YouTube、Netflix、OpenAI 六条。
  因此 KuaiShou、TikTok、Claude、Gemini、Google 这五条在第一版里只有圈 X 导入，
  没有 Surge 按钮——不是 Surge 不支持，是没核实到对应 Surge 路径。
