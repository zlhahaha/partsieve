# PartSieve 交接文档

更新时间：2026-10-04（Asia/Shanghai）。任务基线：`plan.md`；历史备份不作为执行基线。

## 任务目标

按计划建设 MoonBit OOXML 能力审计与验证重建项目 PartSieve。当前已完成 TODO-0 Kill Spike 技术 GO 和 TODO-1 Bounded Package Loader 和 TODO-2 OPC Graph + XML Reference Index、TODO-3 Capability/Coverage/Decision；TODO-4 受限 VBA Handler 已验收，下一个主线任务是 TODO-5 Rewrite Planner。完整路线图尚未完成，项目尚未 LOCK；原型已按作者新增授权发布到 GitHub 和 Mooncakes 0.1.0-spike。当前真实、无害 VBA XLSM → XLSX 已完成 audit → plan → rebuild → verify、部件保留、Receipt、独立校验和 WPS 客户端证据。原型完成时未联系外部维护者或发布包；作者随后明确授权创建指定 GitHub 仓库并发布 Mooncakes。

## 已完成内容

- 已读取 `plan.md`，确认 TODO 依赖和 GO / CONDITIONAL GO / RE-SCOPE / STOP 门槛。
- 初始工作区 `E:\moonbit10` 不是 Git 仓库、没有实现目录；随后建立独立 `partsieve/` 仓库，并遵循模板生成的 AGENTS.md。
- 已确认环境有 moon、Python、dotnet、git、Node。
- 建立本交接文档与独立 Git 仓库 `partsieve/`（MoonBit 模板自动创建）；已有真实有效提交并推送指定公开仓库。
- 固定 flate 0.8.4、Milky2018/xml 0.5.0、moonbitlang/x 0.5.5，均 Apache-2.0。
- MoonBit 原型已实现受限 ZIP、CRC、保守 OPC URI、命名空间 XML、内容类型、关系图、VBA 证据、计划、重建、重新读取验证和 Receipt。
- Python 宿主 CLI 提供有界文件读取、60 秒 worker 超时、dry-run、成对文件发布及 original/Receipt 复核；OOXML 逻辑在 MoonBit SDK。
- 固定 XlsxWriter 上游 commit 的真实 Excel XLSM/XLSX 样本，许可证随样本保存；宏静态提取内容为手动将 A1 写为 123，没有执行。
- 真实 XLSM 11,463 bytes → XLSX 6,236 bytes；移除 1 个 VBA 部件，改写 2 个元数据部件，7 个 payload 字节保留。
- TODO-1：解析失败、截断、超限和有界写出失败返回 typed Incomplete；XML token 限额覆盖 tag、注释、CDATA/PI 与 text，不返回成功产物。
- 15 个 MoonBit 单元测试、48 个特征样本、17 项端到端检查通过；Native check/test/build --deny-warn、格式/公开接口复核和 SDK 示例通过。
- Python zipfile/ElementTree 独立校验、Open XML SDK 3.3.0 校验通过。WPS 12.1.0.28505 COM 打开、保存副本、重开通过，A1 保持 123。
- WPS 界面确认无修复提示；截图与输出 hash 绑定保存。用户允许使用 WPS，未声称检查过 Excel/LibreOffice。
- spike-report、版本/依赖源码校验、真实样本 provenance、Receipt schema、威胁模型/架构/契约/矩阵、SDK example 与复核脚本已保存。

## 当前问题

- 已发布配置为 simple-spreadsheet-spike-v1；main 0.2.0-dev 新增 simple-word-vba-dev-v1。外链、公式、图片、控件、未知扩展仍不支持；不声称通用 OOXML 安全或视觉保真。
- WPS Word 保存副本有 3 个 styles schema 顺序错误。PartSieve 输出原始 payload 通过同一 SDK 校验；副本失败另列，不能当完整保留成功。
- 真实可编辑 OOXML 接入工作流和非作者维护的 MoonBit 下游需求证据尚缺。
- 现有 Audit/Receipt 的兼容 JSON 仍为原型字符串 Coverage；PackageGraph/XmlReference 与内部索引已完成，统一 CapabilityFinding/Coverage/Decision 与 Fail/Incomplete/Unsupported 已完成；新版 Receipt 的完整 typed 状态还需 TODO-6。
- 资源数字仍为 PROVISIONAL；微型 benchmark 已跑，未完成 1/10/30 MiB 校准、完整工作预算/取消接口。
- Python 是有界宿主入口，Native worker 使用无限 x/fs 读取，只能接收宿主已限额的私有快照。硬链接文件发布不保证两个路径事务原子性。
- GitHub 两个功能 CI job 已通过，Mooncakes 原型已发布并由独立目录消费者安装验证；独立第三方下游采用仍缺，自建消费者不计入 TODO-11。

## 正在做什么

TODO-0/1 原型公开发布已收尾：CI 成功、Mooncakes 返回 200、独立目录从注册表下载并运行 SDK，通过真实 fixture 与准确输出 hash 检查。发布记录、踩坑和公开镜像已同步。随后 TODO-2 已完成，新增结构检查 API、source-local XML 绑定、入出边/内容类型索引、隐式引用和迭代遍历；22 单元、11 图宿主检查与原 48/17 回归全过，独立证据复核 Pass。随后 TODO-3 的结构化 assess API/CLI 与共用 typed gate 已通过 25 单元、17 覆盖/决策检查，原回归/真实输出一致；TODO-4 随后已验收：真实 DOCM→DOCX、29 Word 回归、独立 ZIP/SDK 和 WPS 输出打开通过；下一项 TODO-5。后续任务保持未完成状态。

## 下一步计划

1. TODO-5～6：补计划前置 hash/冲突检查与可追溯决策、共享依赖闭包、完整 typed Receipt 和专属保留断言。已完成的 Word handler 继续作为真实回归基线。
2. SDK 可用后启动 TODO-11 真实需求/下游验证。自建 example 只算示例；外部消息、PR 与公开发布按计划需要明确授权，先准备具体可审查的集成方案。
3. 按依赖推进外部模板和 OLE/ActiveX handler、完整样本/CI/benchmark/兼容矩阵和演示；没有真实采用证据时不能扩充顶奖宣称。后续版本发布前复核命名、规则、分发和本轮授权范围。

## 踩过的坑

- 目录不是 Git checkout，不能把 git status 失败当作实现问题，也不能引用不存在的旧项目成果。
- `plan.md` 很长，一次读取会截断；分段读取验收条款，避免漏掉 Spike 前置门槛。
- 真实 VBA fixture 不能用随意字符串伪造；人工 ZIP 只能作为结构/拒绝测试。
- 客户端打开、独立结构校验与本工具规则验证是不同证据，不能互相替代。
- flate ZIP read 不校验 CRC，必须在适配层显式计算并比较。
- XML parser 支持命名空间但无深度/节点限额；进入 parser 前先做有界 preflight，拒绝 DTD，使用切片避免扫描时反复复制字符串。
- MoonBit 新模板使用 `moon.mod` / `moon.pkg`；旧 JSON 配置文件名在本工具链不存在。
- Windows README 符号链接创建失败，需保存真正的 README；不能依赖管理员权限。
- WPS UI 输入会因用户操作而失效；先重新观察，COM 可用于客观数值核对，但不能伪造无修复提示截图。
- 原型 worker 只用于宿主已限制的私有临时文件，直接 worker 的 x/fs 读取没有读取前限额，不能把它当对外安全 CLI。
- WPS 打开文件后，Open XML SDK 默认共享方式发生 I/O 冲突。测试改为受限只读快照并保存 hash，再验证成功；不能将文件占用误判为 schema 错误。
- Windows Python 默认文本编码可能是 GBK，读取 JSON/Moon manifest 要显式 UTF-8。
- token 的限额要包含整个 token，并检查注释/CDATA/text；只限制 tag 会遗漏 parser 大块分配。
- 只测底层 ZIP API 不足以验收 SDK 限额接线，新增 SDK 边界包同时覆盖全部配置上限/加一。
- 测试统计需要逐项清单：端到端 17 项，特征样本 48 个；多数是人工变体，不能把数量等同于真实客户端覆盖。

## 验证记录

证据存于 `partsieve/docs/evidence/`：最终 `final-checks.log`、`regression.json`、`evidence-check.json`、`openxml-final.json`；独立 ZIP、WPS COM/UI/截图、VBA 静态检查、Receipt 和 benchmark。早期 openxml-sdk/openxml-controls 是历史运行记录，最终含 hash 的证据以 openxml-final 为准。

原件 SHA-256：`09c35d1580eb6d7e678ba8249cdd1cbc0bd245fbb0eed8794981728715944736`。
输出 SHA-256：`fcc9a0ca93810d894df21c71d5764db7252afd3b1232b5aef55c21f3efcc9e53`。

继续工作前，在 `E:\moonbit10\partsieve` 运行 `.\tools\check.ps1`；独立证据运行 `python tools/validate_evidence.py`。需要保持当前工具链/依赖；升级先复核源码和公开接口，不直接更新 evidence 掩盖漂移。

完整说明见 `partsieve/docs/spike-report.md`。原型发布阶段仅对有证据的 TODO-0/1 勾选；此后 TODO-2 按新增证据验收勾选；后续计划与外部需求门槛仍未完成。

## 原型公开发布（2026-10-04 新增授权）

- 作者明确授权 GitHub `https://github.com/zlhahaha/partsieve` 和原型 Mooncakes 发布；该授权更新此前暂不发布的执行范围。指定公开仓库已经存在且为空、账号具备写权限，直接初始化已有仓库。
- 首次有效提交 `21f10e4` 包含已验证的完整原型，未伪造开发日期或提交记录。章程申报要求至少 10 个有效提交，当前未达门槛，随后续真实开发积累。
- 版本定为 `0.1.0-spike`，Native 预发布；元数据、第三方说明、分发过滤与 CI 已配置。发布包没有凭据、缓存、临时文件和客户端证据，完整证据保留在 GitHub。
- 服务器 dry-run 通过，HTTP 202 明确表示成功且未改索引；当前 moon CLI 对此仍返回退出码 1。`--frozen` 会阻止临时解包目录安装依赖，普通 dry-run 已验证干净包编译。正式推送已完成；CI run 37176472295 的两个 job 全部成功，正式 `moon publish` 返回 HTTP 200、退出 0；独立目录 `moon add zlhahaha/partsieve@0.1.0-spike` 从注册表下载，Native audit/rebuild/verify 与 hash 检查通过。
- 仓库中的 HANDOFF.md / plan.md 是本工作区文件的公开镜像，通过 `tools/sync_workspace_docs.py` 同步；持续以当前文档为交接基线。原型发布不等于 TODO-13 顶奖成品完成，也没有代作者提交报名表或联系主办方。

- 发布源码对应 `a7be1e1d5ddec1af5cc822014fc61ddddb45adc9`；GitHub 标签 `v0.1.0-spike` 指向该提交。后续发布记录提交只补充文档与证据。发布 zip SHA-256：`66ecd3b5f2e91b2690da9d3d9ec95494ba44e2a7192823dc32b3a8e94f4faa19`，79,929 bytes / 51 files。包内容不因仓库后续更新而改变。
- 首次发布归档时累计 5 次真实有效提交（含发布结果归档），仍未满足章程 10 次门槛。没有人为凑提交，也没有提交报名材料。
- 新增踩坑：干净 Runner 必须先 `moon update` 再安装依赖，之后才能核验源码 hash；本地已有缓存不能证明 CI 可复现。调用方直接使用 x/fs 时必须显式声明 x，传递依赖不能替代直接依赖。
- 完整发布证据：`partsieve/docs/evidence/release-validation.json`；注册表消费者源码：`partsieve/docs/evidence/registry-consumer/`；成功 CI：[37176472295](https://github.com/zlhahaha/partsieve/actions/runs/37176472295)。

## TODO-2 验收更新

- `graph_model.mbt` / `graph.mbt`：PartRecord 为 Part 事实；新增 PackageGraph、XmlReference、ImplicitReference、GraphNode、ContentTypeIndex 与 `inspect_graph` 公有 SDK / 有界 `graph` CLI。
- audit/rewrite/verify 共用 loader 的图事实；source-local 绑定与入边 lookup 使用索引，verify 比较重解析后的完整图。外部 Target 不参与内部入边/遍历；循环使用迭代队列；孤儿候选不自动 GC。
- 7 个新增单元测试、11 项图宿主检查通过，包括最大部件链加循环、引用 32768/32769 边界、已支持 orphan payload 重建后字节保留及未知扩展缺口。总单元数 22；原 48 特征样本、17 端到端检查与独立证据/旧 Receipt 重算依然 Pass；输出 SHA-256 不变。
- 新 API 为 main 开发内容，不在已发布 `0.1.0-spike` 包内；原型标签仍准确指向发布源码。开发代码未重复发布同一个不可变版本。
- 用户回答暂无真实下游。重新通过 GitHub API 读取 office.mbt #265，仍 open，内容为全量 XLSX 重写保留契约；它不是安全清洗需求或采用确认。没有联系维护者，TODO-11 未完成。
- 踩坑：图的空 coverage_gaps 只能表示已建模结构未发现缺口，不能等同于支持 profile 或可重建；结构检查与重建授权必须分开。原有孤儿是否可删除不能由 reachability 单独决定。
- 完成此项时下一任务：TODO-3 统一 capability/coverage/decision（后续验收见下节）；完整 P0/P1 路线未完成，真实下游与 10 次有效提交仍未满足。

## TODO-3 验收更新

- `coverage_model.mbt` / `coverage.mbt`：CapabilityFinding、九类 Capability、RuleCoverage、Coverage、Decision、Assessment；新 `assess` SDK/CLI 报告完整证据/覆盖/权限。旧 Audit/Receipt JSON 继续兼容；typed profile_decision 已成为所有核心重建入口的共用门槛。
- 按声明证据区分 HTTP 点击 hyperlink、外部资源/数据、Word template、OLE/ActiveX、未知关系/扩展。Declared 不是宏行为或恶意性断言；不支持的 handler 不因识别声明而允许重建。
- NotChecked/Opaque/Incomplete 的 presence 为 Unknown；解析失败不以空 findings 推导 Absent。CRC、缺失内部目标、明确图/保留契约错误为 Invalid/Fail；不支持语法为 Refused/Unsupported；截断/超限为 Incomplete。
- 新增 3 个单元测试与 17 项宿主能力/决策检查；总单元 25，原 48/17、图 11 与独立证据复核 Pass，输出 SHA-256 不变。拒绝状态没有输出或 Receipt。
- 新 API 在 main，未重复发布已有不可变版本。公开提交按真实功能完成点记录，仍不足章程 10 次；真实第三方下游仍缺，用户已答复暂无。
- 下一主线 TODO-4：获取来源/许可固定的真实 DOCM，并静态审查宏；将 VBA handler 扩到 DOCM→DOCX，补共享/孤儿结构拒绝、独立格式及 WPS 宏移除后客户端证据。原始含宏文档不在客户端打开。
- 踩坑：结构解析成功与规则覆盖完成必须分别表示；元数据 capability 声明不意味着存在自动网络获取，也不意味着清洗 handler 可用；完整性 Fail 与能力 Unsupported 不应混为一个错误。

## TODO-4 验收更新

- TODO-3 CI 37178928370（f3a56bc）全部通过；TODO-2 CI 37177859901（5aa5a1b）全部通过。
- 已固定 Apache POI commit `12c3688d130035f3dc2ca2a0f50d929456435a93` 的真实 SimpleMacro.docm，15,517 bytes，SHA-256 `fd591958fcf5322f72c0a740e9606309c949254bda4c3d9bd966481ddf220563`；来源、完整 LICENSE/NOTICE 与宏源存 `tests/fixtures/poi/`。
- oletools 静态提取实际 ThisDocument/Module1，只有 TestMacro 手动设置首段文字，没有自动事件；原件未在 Office 打开、宏没有执行。证据 `docs/evidence/docm-macro-static-review.json`。
- Word fixture 有 14 个 parts，VBA 必须连同其受控 companion `.rels` 和 `vbaData.xml` 一起移除，不能套用 XLSM 的无 companion 假设。settings 含数学默认设置/Office 默认 shape layout，需精确静态允许或拒绝，不能将所有 VML 都放行。
- 已完成受限 DOCM→DOCX：14 parts 删除 3、元数据重写 2、其余 9 payload 字节保留；主类型/扩展名一致，共享/孤儿/未知 companion/保留 XML 引用拒绝。输出 9,029 bytes，SHA-256 `4bb624cf9a6e465b1658c69f6d0bc607ccccf25e2ee1e3048b3e11376d8aa65e`。
- 29 Word 宿主检查与原 25 单元/48 特征/17 端到端/11 图/17 coverage 全过；旧 XLSM 输出 hash 与 Receipt 独立重算保持不变。独立 ZIP/ElementTree 和 Open XML SDK 3.3.0 Office2007 对原 DOCM、PartSieve DOCX 均 0 errors。
- WPS 可见打开输出无修复提示；COM 另存、关闭、重开正文/1 段/1 节一致。UI 只读重开保存副本无修复提示；COM 占用导致文件占用提示，非修复提示。
- WPS 保存副本 Open XML SDK 报 3 个 styles 的 uiPriority 元素顺序错误；原输出 styles 是原件字节保留且 SDK Pass。保存失败证据与兼容矩阵，不掩盖、不把另存副本当成 PartSieve 验证产物。
- main 版本 0.2.0-dev 未发布，Word Receipt 为开发 schema；0.1.0-spike 公开包/标签保持不变。报告 `docs/word-vba.md`，证据 `word-regression.json` / `word-independent-zip.json` / `word-openxml.json` / `word-wps-client.json`。
- 踩坑：Word 支持元数据关系不能套 XLSM 假设；Template 元数据只允许字面 Normal.dotm，不等同外部 attachedTemplate 关系；WPS COM 是独立实例，不能假设能枚举 UI 已开文档。真实 SampleDoc.docx 有 customXml，保留为不支持样本；干净支持负例明确是 DOCM 清洗输出衍生样本。

用户再次明确答复“无”真实第三方下游，TODO-11 未完成，没有联系维护者或发送 PR。TODO-5/6 的 P0 核心可继续；新增 P1 能力前按计划复核真实可编辑输出需求，不用自建示例代替采用。
