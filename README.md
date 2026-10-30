# RuleSearch — 规则搜索

iPhone App：搜索分流规则和去广告规则，点一下导入 Quantumult X 或 Surge。

## 首页

首页只有两个大入口：**分流**、**去广告**。点进去只能搜到对应类型的规则；
搜索逻辑、模糊匹配、预览、收藏、导入都不变，只是在各自入口里先按类型过滤。
入口上显示当前索引里该类型的条数。收藏区跟着入口走：进分流只显示分流的收藏，
进广告只显示去广告的收藏。

首页右上角有一个仓库管理入口（独立页，不跟搜索结果混在一起）。

## v2 在线搜索

v1 只搜内置 16 条，不是全仓库。v2 改为：App 联网拉各仓库的最新文件列表，
在本地做模糊搜索。

- 接口：GitHub API recursive tree，不带认证，
  `https://api.github.com/repos/<owner>/<repo>/git/trees/<分支>?recursive=1`
  （jsDelivr 数据接口试过，返回 URL not found，已放弃）。
  未认证限流 60 次/小时，一次刷新最多拉仓库数个 tree，够用。
- 默认仓库（分支）：blackmatrix7/ios_rule_script（master）、fmz200/wool_scripts（main）、
  sve1r/Rules-For-Quantumult-X（main）、zqzess/rule_for_quantumultX（master）、
  ACL4SSR/ACL4SSR（master）、ddgksf2013/ddgksf2013（main）。
- 首次进去直接拉取并缓存；之后启动先显示缓存，后台按需刷新；
  拉到后无缝换成全量列表并记下更新时间；拉取失败显示空列表并给一句刷新提示。
  界面上有刷新按钮和一行“数据更新于 …”，拉取中显示加载状态。

### 索引只收 QX 资源

内置和自定义仓库同一套标准，不再按路径关键词猜类型：

- 分流 = QX 的 filter 列表：QX 倾向目录（QuantumultX、Rules、filter）下的 `.list`；
- 去广告 = QX 的重写文件：rewrite 目录下的 `.conf`。
- Surge、Loon、Clash、Shadowrocket、Stash、Egern 目录下的文件一律不收；
  `.sgmodule`、`.snippet`、`.plugin`、`.yaml`、脚本、图片、文档、整包配置一律不收。

因此 ACL4SSR（只有 Clash 目录）和 ddgksf2013（只有 README）在 v2 里贡献 0 条，
仍留在默认仓库列表里（以后它们有了 QX 目录会自动收进来）。
注意：在线索引按文件种类定类型，所以 fmz200 的 filter.list、sve1r 的 AdReject.list
会显示为分流。

### 缓存策略和断网回落

- 缓存带时间戳，存在 Application Support 的 `rule-cache.json`，24 小时内算新鲜，新鲜的不重复拉。
- 断网时优先用上次缓存的全量列表，哪怕超过 24 小时也照常用，界面上标明数据时间；
  没有缓存时不显示任何预留数据，首次进去直接拉取并缓存，拉取失败显示空列表和刷新提示。
- 离线时搜索能用，但导入只是把链接交给圈 X / Surge，真正下载规则文件的是它们，
  没网时导入会失败，等联网后再点一次——这句提示写在离线状态和导入失败的文案里。

### 自定义仓库源

仓库列表存在 UserDefaults，默认就是上面 6 家。

- 新增：输入 owner/repo 和分支（分支默认 main，拉不到自动试 master）。
  新增时先拉一次该仓库的文件列表验证，拉不到或里面没有 QX 资源就报错、不添加。
- 删除：内置 6 家和自己加的都能删，删了之后搜索结果里就不含这家的条目。
- 恢复默认仓库：一键回到最初 6 家，自定义仓库和它们的缓存会被清掉。
- 新增仓库拉到的列表同样进缓存，同样受 24 小时新鲜度约束。

### 收藏

- 每张卡片上有星标按钮（star / star.fill），点一下收藏、再点取消，收藏的规则 id 持久存在本地。
- 在线条目的 id 是稳定的“仓库 + 文件路径”，索引刷新后收藏不会丢；
  仓库被删后对应的收藏条目不再出现，仓库加回来后收藏自动恢复，不用额外处理孤儿数据。
- 搜索框为空时，页面顶部先出收藏区，下面再是全部规则；
  搜索时收藏条目正常参与搜索，卡片上带星标区分。
- 星标是次级操作，不抢搜索和导入按钮的视觉层级。

## 导入流程（v2：经 ScriptHub 转换）

搜索规则 → 点卡片展开 → 选择客户端（圈 X / Surge）→ 自动走 ScriptHub 转换 →
界面出现两个按钮：**预览**、**导入**。一条规则不再分客户端版本：
搜出来的全是 QX 资源，选客户端时 ScriptHub 负责转成对应格式，Surge 用户同样能用这些 QX 规则。

### 转换链接格式（对照官方解析器源码核实，非猜测）

- 规则集（.list）→ Surge：
  `http://script.hub/file/_start_/<原始链接>/_end_/<文件名>?type=rule-set&target=surge-rule-set`
  （rule-parser.js：target 为 surge-rule-set 时输出 Surge RULE-SET 格式，HOST→DOMAIN 等映射都在里面）
- QX 重写（.conf）→ Surge 模块：
  `http://script.hub/file/_start_/<原始链接>/_end_/<名>.sgmodule?type=qx-rewrite&target=surge-module`
  （Rewrite-Parser.js：target 为 surge-module 时输出 Surge 模块）
- 圈 X：不需要转换，转换后链接就是原始链接（rule-parser 没有 QX 目标，QX 资源原生就是 QX 格式）。
- 预览按钮显示的是转换后的内容（总行数 + 前面约 15 行非空行，等宽小字体）；
  导入按钮用的是转换后的 ScriptHub 链接。预览不做持久缓存，Surge 的转换结果在选客户端时拉到后暂存卡片内，
  圈 X 的原始内容在点预览时现拉。

### 导入方式

- 圈 X：`quantumult-x:///add-resource`，转换后链接（即原始链接）放进 filter_remote（分流）
  或 rewrite_remote（去广告重写 .conf，按文件格式分）。
- Surge 去广告类：`surge:///install-module`，用转换后的模块链接真一键安装。
- Surge 分流到代理：模块规则指不到用户策略组，这个限制不变，
  仍走一键复制 `RULE-SET,<转换后链接>,你的策略组` + 跳转 Surge 手动粘贴。

### 前置条件：必须安装 ScriptHub 模块

`script.hub` 不是公开域名，转换链接只有在设备上的圈 X / Surge 里安装了 ScriptHub 模块
（MITM 解析 script.hub）时才能打开。沙箱里直接拉 script.hub 链接会报“不是可解析的公开 URL”，
这正是无 MITM 环境的预期表现，不是参数错误——参数已对照 rule-parser.js / Rewrite-Parser.js 源码核实无误。
真机上转换是否可用，取决于 Lu 的客户端里有没有装 ScriptHub 模块，这一点只能上机验证，
App 里也在 Surge 转换区写明了这句。

### 失败兜底

ScriptHub 拉不到或转换失败时，App 给一句提示，并给回直接导入原始链接的选项，不让用户卡死：

- Surge 分流：复制原始链接的 RULE-SET 行（QX 格式，Surge 可能无法识别部分规则）；
- Surge 去广告：复制原始链接（QX 重写文件需经转换才能用作 Surge 模块）；
- 圈 X 不需要兜底：原始链接本身就是 QX 格式，直接导入永远可用。

## 规则索引

没有内置索引：首次进去直接拉取各仓库的文件列表并缓存，之后只显示拉到的数据。
第一版的 16 条内置数据已移除，不再显示。核实不了的路径见 `UNVERIFIED.md`。

## 搜索

搜索框输入时实时过滤，支持模糊搜索：大小写不敏感的子串匹配 + 常见别名表
（抖音/DouYin、油管/YouTube、推特/Twitter、电报/Telegram、奈飞/Netflix、
GPT/OpenAI/ChatGPT、苹果/Apple、快手/KuaiShou、小红书/RedBook、谷歌/Google）。
匹配逻辑 v1 之后没动过。

## 图标

`RuleSearch/Assets.xcassets/AppIcon.appiconset/`：全尺寸图标（1024 营销图标 + 各尺寸主屏图标），
源文件是 `icon/AppIcon-1024.png`（靛蓝到青色的斜向渐变底 + 白色放大镜，
镜片里三行“圆点 + 横线”的规则行，设计没改），`icon/make_icon.py` 是生成脚本，留着以后改色改稿。
pbxproj 里 asset catalog 已加进 target 资源，AppIcon 名称已设置。

## 本地构建

用 Xcode 打开 `RuleSearch.xcodeproj`，选一台 iOS 17+ 的模拟器或真机运行即可。
不需要签名证书也能在模拟器上跑；真机安装走 Actions 打出来的 unsigned IPA。

## CI

`.github/workflows/ios.yml`：macos-15 上 `xcodebuild archive`，不签名，
把 `RuleSearch.app` 打包成 unsigned IPA 并上传为 Actions artifact。
新 Swift 文件和 asset catalog 都已写进 pbxproj，workflow 本身不用改。
