# RuleSearch — 规则搜索

iPhone App：搜索分流规则和去广告规则，点一下一键导入 Quantumult X 或 Surge。

## 功能

- 搜索框输入时实时过滤，支持模糊搜索：大小写不敏感的子串匹配 + 常见别名表
  （抖音/DouYin、油管/YouTube、推特/Twitter、电报/Telegram、奈飞/Netflix、
  GPT/OpenAI/ChatGPT、苹果/Apple、快手/KuaiShou、小红书/RedBook、谷歌/Google）。
- 结果行显示规则名、来源仓库、类型（分流/去广告）、支持的客户端；点一条展开导入按钮。
- 圈 X：`quantumult-x:///add-resource?remote-resource=<JSON>` 真一键导入。
  分流进 `filter_remote`，去广告重写（.conf）进 `rewrite_remote`，其余 .list 进 `filter_remote`。
- Surge：去广告/直连类如果有 `.sgmodule` 链接，走 `surge:///install-module` 真一键安装；
  分流到代理的没有真一键导入，App 会把 `RULE-SET,<链接>,你的策略组` 复制到剪贴板并打开 Surge，
  界面上写明需手动粘贴到配置（Surge 官方只有 install-config / install-module，没有单条规则导入接口）。

## 规则索引

`RuleSearch/rules.json` 是 App 内置索引，第一版 16 条，全部经 GitHub API 核实过真实存在：

| 来源 | 条数 |
| --- | --- |
| blackmatrix7/ios_rule_script | 11 |
| fmz200/wool_scripts | 3 |
| sve1r/Rules-For-Quantumult-X | 2 |

类型：分流 13 条，去广告 3 条。核实不了的路径见 `UNVERIFIED.md`，一律没放进 `rules.json`。

## 本地构建

用 Xcode 打开 `RuleSearch.xcodeproj`，选一台 iOS 17+ 的模拟器或真机运行即可。
不需要签名证书也能在模拟器上跑；真机安装走 Actions 打出来的 unsigned IPA。

## CI

`.github/workflows/ios.yml`：macos-15 上 `xcodebuild archive`，不签名，
把 `RuleSearch.app` 打包成 unsigned IPA 并上传为 Actions artifact。
