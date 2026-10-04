# PartSieve 项目计划

> 项目名称：**PartSieve**。副标题：OOXML Capability Auditor & Verified Rebuilder。  
> `Part` 对应 OOXML 部件，`Sieve` 表达按策略筛选；目录 `partsieve`，CLI `partsieve`，Mooncakes 模块候选 `zlhahaha/partsieve`。  
> 修订日期：2026-10-04。状态：**TODO-0 技术 GO；TODO-1/2 已验收；下一项 TODO-3；尚未 LOCK；原型 0.1.0-spike 已公开发布**。
> 定位：用 MoonBit 对 OOXML 文档中的已建模活动能力进行审计、策略化移除和结果验证。  
> 目标：做成可复用、可审查、工程扎实的生态项目，争取季度奖项；奖项是竞争目标，不是技术验收标准。

## 1. 当前事实与立项判断

计划制定时的事实（执行前快照）：

- `moonguard-office/` 已由作者删除，当前没有项目实现；不得把旧模板或计划项记为已完成。
- `research/OOXML文档重建选题复核-2026-10-04.md` 已记录选题调研；其中需求、上游状态是调研快照，正式选依赖时需要复核。
- 删除前已检查本地 `moonbit-community/flate@0.8.4` 的公开接口，存在 `read`、`Archive::remove/replace`、`write_preserving_limited` 和 `ReadLimits`。这支持 ZIP 底座可复用的判断，但尚未证明 OOXML 重建闭环；新项目须重新安装、锁定并验证依赖。
- XML 库、OOXML 上层 API、真实下游需求、可重建范围和客户端兼容性仍待验证。

执行更新（2026-10-04）：已建立 `partsieve/` 并完成真实 XLSM VBA → XLSX 的 TODO-0 技术闭环；固定 flate 0.8.4、Milky2018/xml 0.5.0、moonbitlang/x 0.5.5。Native 编译/测试、独立 ZIP、Open XML SDK 3.3.0 和 WPS 12.1.0.28505 检查通过，支持范围限于 simple-spreadsheet-spike-v1。用户允许使用 WPS，该客户端作为本轮 Office 客户端验收证据。详见 `partsieve/docs/spike-report.md` 与 `HANDOFF.md`。真实独立下游、后续能力与发布仍未完成。

**建议继续这个方向，但先做原型，不直接承诺宏、外链、OLE、ActiveX 全覆盖。** 项目最有价值的成果是：准确的能力证据、能解释的修改计划、引用一致的重建、明确的保留契约，以及不满足条件时可靠拒绝。

原计划备份：`research/plan-before-revision-2026-10-04.md`。本文是后续执行的唯一任务基线，备份只供回溯。

## 2. 产品目标与独立贡献

目标工作流是：需要接收不可信 Office 文件，并继续交付**可编辑 OOXML 文档**的 MoonBit 应用。仅需要安全预览或文本提取的工作流，应评估现有方案是否已经足够。

```text
输入字节 + 版本化策略 + 资源限制
    ↓
受限读取 → 包结构与 XML 引用建模 → 能力审计与覆盖报告
    ↓
生成修改计划，检查可修复性与保留契约
    ├── 无法可靠处理 → 拒绝重建，输出原因
    ↓
重建到临时产物 → 从产物重新解析并验证
    ├── 验证失败 → 不发布文档，输出失败报告
    ↓
发布文档 + 绑定输入/输出 hash 的 Receipt
```

独立贡献集中在三个部分：

1. **能力模型**：将已知关系、部件和 XML 语义归并为带证据的能力，区分检出、缺失、未检查和不支持。
2. **策略化重写**：同时处理部件、关系、源 XML 引用和内容类型，保护共享依赖，解释每一处删除或修改。
3. **可检查的结果**：重新读取输出，验证版本化规则及保留契约，报告验证范围与未覆盖项。

ZIP/XML 通用实现、Office 普通读写、保真重打包和 hash 报告本身不计为独有创新。与上游有重合时，优先复用或提出适配层，不能通过改名主张独立性。

## 3. 范围分层：先做深，再扩展

审计支持和重建支持必须分别列出。能识别一种能力，不等于已经能正确移除它。

| 能力或格式 | 首版最小可交付版本 | 顶奖扩展目标 | 处理边界 |
| --- | --- | --- | --- |
| DOCX/DOCM、XLSX/XLSM | 受限 OPC 审计；验证过的样本配置可重建 | 扩大公开兼容矩阵 | 扩展名只作提示，实际类型由主关系与主部件类型确定 |
| VBA | 审计、移除已支持的 VBA 关联部件；宏格式转普通格式 | 更多布局与相关元数据回归 | 宏启用类型与实际 VBA 存在分别报告 |
| 普通 hyperlink | 分类；已支持的 HTTP/HTTPS 点击链接按策略保留 | 更完整的链接类型处理 | 不承诺目标网站安全；其他 URI scheme 默认拒绝或移除 |
| Word 外部模板 | 审计；实现设置 XML 与关系同步移除 | 增加兼容变体 | 不能只删除 `.rels` 条目 |
| 外部图片、媒体 | 检出后拒绝未支持的重建 | 逐类支持删除或保留静态替代物 | 不联网下载或补齐资源 |
| XLSX 外部工作簿 | 检出后拒绝重建 | 单独设计公式、名称、缓存等处理后开放 | 删除 externalLink 关系不能替代公式语义处理 |
| OLE、ActiveX | 识别已知证据；遇到时拒绝重建 | 每类通过源码 XML、预览物、共享依赖回归后开放 | 不执行、不分析其中代码，不递归清洗嵌入包 |
| 连接、查询、DDE、字段、网络相关公式 | 对已建模语法报告；未覆盖项明确说明 | 按实际需求选择有限子集 | 无外部关系不代表无此类能力 |
| 未知部件、扩展和关系 | 审计标记；重建按兼容配置判断 | 扩大允许清单与覆盖 | 未分类不等于安全，不自动删除未知内容 |

首个垂直闭环选择 **简单 XLSM 的 VBA 移除与 XLSX 转换**。随后加入 **DOCM 的 VBA 和外部模板移除**。每个配置有允许的部件类型、XML 特征与关系类型清单，不能声称所有 DOCX/XLSX 都可重建。

顶奖扩展目标保留外链、OLE、ActiveX、多格式样本、真实集成与独立验证；每新增一类能力都独立过门槛，不等待全部完成才交付已有成果。

本轮不做：PPTX、旧二进制 DOC/XLS/PPT、XLSB、加密解密、宏恶意行为分析、漏洞扫描、通用杀毒、渲染引擎、数字签名重签、全部字段或公式语义、云服务与用户系统。

## 4. 威胁模型与保证边界

### 4.1 输入与运行约束

假设攻击者完全控制 ZIP 结构、部件名、XML、关系、元数据及嵌入字节。读取、审计、重建过程不执行宏，不激活嵌入对象，不解析外部实体，不访问外部关系指向的资源。

重建默认拒绝：加密包、数字签名包、歧义部件名、重复条目、结构损坏、超限输入、不支持的命名空间或语义、无法可靠修复的引用。数字签名涉及独立完整性承诺，首版不静默移除后声称签名仍有效。

审计允许返回部分结果，但必须标注 `Incomplete`、具体原因及已检查范围。发生解析失败或检查截断时，不能报告“禁止能力为零，因此通过”。

### 4.2 验证状态

| 状态 | 含义 | 可以发布重建文档吗 |
| --- | --- | --- |
| `Pass` | 所声明的配置、规则和契约均已检查并满足 | 可以 |
| `Fail` | 已检查条件明确不满足 | 不可以 |
| `Incomplete` | 检查未完成、覆盖不足或缺少必要基线 | 不可以 |
| `Unsupported` | 输入或转换不在支持范围 | 不可以 |

`Pass` 只表示**指定工具版本、规则集、策略和兼容配置下的验证通过**。它不是形式化证明，也不表示文档在所有 Office 实现中无恶意行为。Receipt 的 hash 绑定字节，不提供作者身份认证或防篡改签名。

文案采用“所声明范围内的禁止能力已移除”，不用“绝对安全”“证明所有危险内容不存在”。正常 hyperlink 是用户点击能力，与自动外部引用分别建模；允许 HTTP/HTTPS 不等于验证其目的地可信。

## 5. 架构与核心模型

采用少量清楚的模块，先按职责组织文件，出现稳定边界后再拆 MoonBit package；不要先建几十个空模块。

```text
package/       受限 ZIP 读取、部件索引、内容类型、OPC URI
model/         包关系图、XML 引用索引、能力证据、覆盖报告
rules/         版本化 detector 与各格式 rewrite handler
policy/        Allow / Remove / Refuse 决策
rewrite/       计划、冲突检查、执行、重打包
verify/        输出检查、保留契约、Receipt
cmd/main/      Native CLI 与文件发布
examples/      只调用 SDK 的集成例子
tests/         fixture、回归、独立校验脚本
```

核心是两层关联信息：

- **包关系图**：`source part → relationship → internal part / external URI`；根关系使用明确的 package-root 节点。
- **XML 引用索引**：`source XML element/attribute → relationship ID 或语义引用`。关系 ID 只在所属 source 的关系集合内唯一。

不能假设每条关系都在 XML 中有 `r:id`，也不能假设所有 XML 引用都用 `r:id`。已支持 handler 要处理对应的隐式关系、`r:embed`、`r:link`、索引或特定元素语义。

| 模型 | 必需字段或语义 |
| --- | --- |
| `Part` | 规范部件 URI、原条目名、content type、字节 hash、已识别类型 |
| `Relationship` | source、局部 ID、精确 type URI、原 target、解析后 target、target mode |
| `XmlReference` | source、命名空间与元素位置、引用形式、对应关系或语义目标 |
| `Finding` | 能力 kind、证据列表、rule ID、确定性、是否可重建 |
| `Coverage` | 支持配置、检查过的规则、未覆盖特征、截断或解析错误 |
| `Decision` | Allow/Remove/Refuse、policy ID、理由、关联 finding |
| `RewritePlan` | 输入 hash、规则/策略版本、操作与前置条件、预期变化、拒绝原因 |

OPC 路径和 URI 处理以规范为准，不能直接套 Windows 文件路径函数。正确解析 source-relative 与 package-absolute target；拒绝越界与歧义，按规范检查编码和等价名称，不简单全体转小写或反复 URL decode。

XML 使用 namespace URI 与 local name 识别，不依赖前缀文本；拒绝 DTD/外部实体，限制大小、深度、节点与属性数量。`AlternateContent`、VML 和未知扩展要进入覆盖判断，不能只检查一个分支就宣称完整。

## 6. 策略与重写规则

### 6.1 首版策略

`audit` 是只读模式，不作为一个“允许所有内容”的安全策略。首版只实现 `passive-office-v1`，明确绑定当前已验收兼容配置；后续才增加自定义策略。

| 能力 | 策略意图 | 实际动作 |
| --- | --- | --- |
| VBA、外部模板 | 禁止 | 有完整 handler 时 Remove，否则 Refuse |
| OLE、ActiveX、外部资源、外部数据 | 禁止 | 首版 Refuse；对应 handler 通过验收后再开放 Remove |
| 已支持的 HTTP/HTTPS 点击 hyperlink | 允许 | 保留并记录 |
| 其他外部 scheme、未知关系语义 | 默认不允许 | 能可靠修复时 Remove，否则 Refuse |
| 未知影响执行/外部访问的扩展 | 覆盖不足 | Refuse |

未知静态部件只在明确允许其 opaque preservation 的配置中保留，并声明其字节未解释。这样的保留不扩大能力审计的保证范围。`NoExternal` 后续必须定义其是否只覆盖关系层；若没有字段与公式检测，不得命名或宣传为“保证没有网络访问”。

### 6.2 每个 handler 的完成定义

一个 capability 可开放重建，必须同时具备：

1. 部件、关系和 XML 语义证据，包含改名及多个证据交叉校验。
2. 所有受影响源 XML 的变换规则、删除关系规则、受控部件集合。
3. 共享依赖、预览图、fallback 和扩展分支的处理或明确拒绝。
4. 必需的内容类型、主文档类型及相关元数据调整。
5. 保留和允许损失的契约，前后样本与独立校验。
6. 正例、负例、混合能力和不支持变体的测试。

例如，外部模板处理要同步修改 Word settings 中的 `attachedTemplate` 和对应关系；XLSX 外部引用有自己的 `externalReference` 与 relationship ID，不能只删除目标 ZIP 条目。[外部模板结构](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.attachedtemplate?view=openxml-3.0.1)、[工作簿外部引用结构](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.spreadsheet.externalreference?view=openxml-3.0.1)是 handler 设计的参考依据。

### 6.3 计划与闭包算法

```text
受限解析 → 图与引用索引 → audit + coverage → policy decisions
    ↓
检查 handler 完整性；有 Refuse 则停止
    ↓
确定直接删除集合与源 XML 修改集合
    ↓
检查所有入边、共享引用、主部件和受保护内容
    ↓
在允许的规则范围内计算依赖变化，直到稳定
    ↓
生成关系、部件、源 XML、Content Types 和格式转换操作
    ↓
检查冲突与前置 hash → 执行 → 重新读取验证
```

计划操作至少包括 `RemovePart`、`RemoveRelationship`、`RewriteSourceXml`、`RewriteRelationshipPart`、`RewriteContentTypes` 和 `ChangeMainContentType`。每项能追溯到规则与策略决定。

**可达性降低只产生孤儿候选，不能触发全包垃圾回收。** 只删除已确认属于移除能力、且不存在保留引用的部件；输入中原有的未知孤儿先报告，按兼容配置保留或拒绝。若一个禁止部件仍被保留内容必需，且无法安全解除引用，应拒绝整个转换。

`.xlsm → .xlsx` 与 `.docm → .docx` 是真实格式转换：校准主部件内容类型、移除已支持的 VBA 相关结构、检查其他宏/控件证据与输出扩展名。宏启用文件未必包含 VBA，不能据类型单独报告“发现宏代码”。

## 7. 保留契约、验证与 Receipt

### 7.1 保留契约从原型开始定义

每个输入部件必须有去向，不只记录“重要部件”：

| 分类 | 承诺 | 检查方式 |
| --- | --- | --- |
| `BytePreserved` | 部件解压后的字节完全一致 | before/after SHA-256 相等 |
| `SemanticallyRewritten` | 只发生 handler 明确允许的语义变化 | XML 结构差异、引用一致性与格式专属断言 |
| `RemovedByPolicy` | 部件因具体规则与策略删除 | finding → decision → plan operation 可追溯 |
| `RegeneratedMetadata` | 内容类型、关系等必需元数据调整 | 白名单变化与一致性检查 |

`Unsupported` 是拒绝或覆盖状态，不能把它当作“已经保真”的部件分类。新生成部件也要单列来源与理由。

字节保留指 **part payload**，不是 ZIP 容器字节一致。ZIP 时间戳、压缩结果和条目排列可能变化；确定性首先要求计划、报告排序及部件结果稳定。若需要整个 ZIP 可复现，再单独规范元数据与写出选项。

允许损失也要写清：移除宏后宏功能消失；移除外部模板后使用客户端默认模板可能改变表现；删除对象可能影响布局。不得据普通文本仍在推导出视觉保真。重写 XML 时要保护空白语义、命名空间、未知节点与扩展；做不到时拒绝。

### 7.2 三种验证分开报告

1. **结构与规则验证**：从输出字节重新解析，不依赖 executor 的内存图；检查条目、关系、Content Types、主类型及支持配置，重新运行 capability rules。
2. **保留验证**：从原文件和输出重新计算部件 hash 与预期变化；对重写正文、工作簿等执行专属内容断言。
3. **独立兼容验证**：使用独立 ZIP 检查、Open XML SDK 和 Office/LibreOffice 样本测试，记录工具版本与结果。

`verify output.xlsx` 只能提供输出本身的结构和策略检查；没有原文件时，保留检查标为 `NotChecked`，完整重建契约结论为 `Incomplete`。需要完整复核时使用原文件与 Receipt，且不能只相信 Receipt 声称的 hash 或 PASS。

输出能被本工具解析，不等于 Office 无修复提示；客户端能打开，不等于所有规则已满足。Open XML SDK 的格式验证也不代替能力审计。[OpenXmlValidator](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.validation.openxmlvalidator?view=openxml-3.0.1)用于独立文档/部件校验，作为开发测试依赖。

### 7.3 每次成功重建必须满足的不变量

- 输出处于声明支持的配置内，必要规则均完成，无阻塞性未覆盖项。
- 声明范围内禁止能力为零；允许的 hyperlink 等能力逐项列出。
- 保留内部关系均解析到存在部件；已支持源 XML 引用不存在悬空或错误绑定。
- 每个部件存在唯一、有效的内容类型映射；主部件类型与输出格式一致。
- 未引入未授权外部关系或未列入计划的部件变化。
- 所有输入部件的保留、改写和删除记录完整；共享依赖未被误删。
- `BytePreserved` 部件字节 hash 相等；重写部件符合其 handler 的允许差异。
- 从实际输出字节重新验证成功后才返回可发布结果。

### 7.4 Receipt 必需字段

Receipt schema 版本化，至少包含：

- 输入/输出整体 SHA-256、大小、实际格式；工具、规则集、策略和配置版本。
- 生效资源限制、覆盖范围、能力证据、策略决定、允许保留能力。
- 修改计划及所有部件去向；关系、源 XML、内容类型的变更与理由。
- 部件 before/after hash；保留断言、结构断言及其状态。
- 错误、拒绝、未检查项和已知限制；独立校验是否执行及工具版本。

Receipt 不保存宏正文，不默认回显带凭据的完整外部 URI。终端输出对不可信名称和控制字符做转义。

### 7.5 文件发布

SDK 只在全部内置验证通过后返回输出 bytes 与 Receipt。CLI 默认不覆盖输入或已有输出，临时文件写在输出所在文件系统，重新读取实际临时产物进行验证，再发布。

文档与 Receipt 是两个文件，普通 rename 不能保证它们同时原子出现。首版采用明确提交顺序和成功标记：两者均发布、hash 对齐后才返回成功；下游只接受成对且 hash 匹配的产物。中途失败要返回非零状态并报告清理结果，不声称两个独立路径具备事务原子性。

## 8. 资源限制：读取阶段就是安全边界

不能先无限解压，再计算大小决定是否拒绝。选依赖时验证限制是否在实际读取、解压和分配前后有效执行，不只检查 ZIP 声明大小。

以下数值全部标记为 **[PROVISIONAL] 原型初始配置**，尚未 benchmark 校准；它们是实现与测试起点，不是已经定案的产品参数。允许配置但保留硬上限：

| 资源 | 原型默认建议 | 强制点 |
| --- | --- | --- |
| 输入 ZIP | 32 MiB | 文件读取前和 SDK 入口 |
| 全部解压字节 | 128 MiB | 解压累计计数 |
| 单条目解压字节 | 32 MiB | 解压过程 |
| 单 XML | 8 MiB | XML 解码与解析前 |
| ZIP 条目 | 4096 | 建立条目索引前 |
| 关系总数 | 32768 | 解析关系时 |
| XML 深度 | 128 | parser 过程 |
| XML 节点与属性 | 单 XML 节点 200000、属性 400000；全包节点/属性分别最多 1000000 | parser 过程 |
| Findings | 4096 | 审计累计；超出标记 Incomplete |
| 输出字节 | 64 MiB | 有界写出 |

另行限制 target/名称长度、报告大小、保留源字节及图遍历工作量；使用迭代或 visited 集合处理循环，暴露取消与工作预算。实际运行时间硬超时由 CLI/宿主执行器保障，不能把未实现的超时写成已有功能。

测试至少覆盖精确上限、上限加一、声明大小与真实大小不符、高压缩比、重复条目、中心目录/本地头歧义、非法 UTF-8、CRC 错误及解析截断。依赖没有检查的歧义，适配层补上或明确拒绝。

## 9. Kill Spike：先交出最小证据链

### 9.1 目标

先用最小真实样本验证关键 API 与最大阻碍；Spike 的目标不是按时间打卡，而是尽快回答“有界读取、关系建模、VBA 移除、重建、重新验证、客户端兼容”这条最小闭环能否成立。若卡住，记录阻碍并按 GO / CONDITIONAL GO / RE-SCOPE / STOP 门槛判断，不因已经投入而继续救题。

优先级是一个真实 XLSM 的 VBA 移除闭环，附一个干净 XLSX 控制样本。宏 fixture 可自行在 Office 创建，使用无害 VBA；不能用随意塞入字符串的 `vbaProject.bin` 代替真实兼容性样本。人工最小 ZIP 只用于结构和拒绝测试。

### 9.2 步骤与产物

- [x] 创建 `partsieve/` MoonBit module，设置作者命名空间与 Apache-2.0 许可；先不发布。
- [x] 固定 ZIP/XML/hash 依赖与许可证，实际验证删除、替换、写出、限制和未知部件保留。
- [x] 准备一个正常 XLSX、一个含 VBA 的真实 XLSM；记录来源、hash 和预期内容。
- [x] 实现受限读取、Content Types、根关系和 part-local relationships 解析及 target resolver。
- [x] 拒绝重复条目、非法 target、缺失目标、重复局部关系 ID 和不支持配置。
- [x] 输出 VBA 证据、类型信息及覆盖状态；检查全包，不只扫描根可达部件。
- [x] 形成可查看的修改计划，明确源 XML 是否需要改变；遇到未支持引用时拒绝。
- [x] 移除已支持 VBA part/relationships/相关类型，调整 workbook 主内容类型，写出 XLSX。
- [x] 从输出重新建图审计，核验结构和所有未修改 part 的 hash。
- [x] 生成原型 Receipt；完成 `audit → rebuild → verify` 脚本入口。
- [x] 在 Office 或 LibreOffice 打开输出，记录版本、无修复提示及文本/单元格/图片的检查结果。
- [x] 独立 ZIP 与 Open XML SDK 检查前后样本；验证失败不得宣称兼容。
- [x] 保存 `docs/spike-report.md`：命令、输入/输出、plan、Receipt、限制、证据与未解决问题。

Spike 期间就加入失败样本测试，不推迟到发布前。不能在支持未确认时打开含不可信宏的样本；兼容测试使用已知无害样本并禁用自动执行/外部刷新。

### 9.3 决策门槛

| 结论 | 条件 | 下一步 |
| --- | --- | --- |
| `GO` | 公开依赖可完成受限读写；真实样本闭环通过；保留检查与至少一组客户端/独立检查有证据 | 进入 TODO-1 及后续主线，支持范围仍按配置限定 |
| `CONDITIONAL GO` | 核心闭环通过，部分环境或兼容证据未完成 | 可继续完善实现；不对外承诺兼容，也不把 Kill Spike 标记为完整通过 |
| `RE-SCOPE` | 个别 capability 无法稳定移除，其他闭环成立 | 缩小兼容配置，转为审计/拒绝，重新估算 |
| `STOP` | 有界读取做不到、核心必须重做通用 Office parser、输出破坏不可控，且合理适配仍不能解决 | 停止主线投入并记录证据 |

少量上游 bug 或 API 适配不自动触发 STOP；先确认修复成本。发现相似项目也不自动终止，先比较实际安全模型、接口和验收证据。

## 10. TODO 执行主线

所有任务按**前置依赖 + 验收证据**推进，不采用日期排期或阶段工时表。  
测试、文档、资源限制、需求调查从对应 TODO 开始同步进入主线，不允许“功能写完后再补正确性”。

### P0：核心闭环

#### TODO-0：Kill Spike —— 真实 XLSM VBA → XLSX

**目标**：证明真实 OOXML 文档可以完成 `audit → plan → rebuild → verify` 闭环。

- [x] 建立 `partsieve/` MoonBit module。
- [x] 固定 ZIP/XML/hash 依赖与许可证。
- [x] 准备一个干净 XLSX 和一个真实、无害 VBA XLSM。
- [x] 实现受限 package 读取。
- [x] 解析 `[Content_Types].xml`。
- [x] 解析根 relationships 与 part-local relationships。
- [x] 实现 OPC target resolver。
- [x] 建立最小 package graph。
- [x] 检出 VBA 证据与宏启用类型。
- [x] 生成可查看的 RewritePlan。
- [x] 移除已支持 VBA part / relationships。
- [x] 调整 workbook 主 content type。
- [x] 重建为 XLSX。
- [x] 从实际输出重新读取、重新建图、重新审计。
- [x] 验证未修改 part 的 payload hash。
- [x] 生成原型 Receipt。
- [x] 使用 Office 或 LibreOffice 打开输出，确认无修复提示并检查关键内容。
- [x] 使用独立 ZIP / Open XML SDK 校验。
- [x] 保存 `docs/spike-report.md`。

**GO 条件**：

- [x] 公开依赖可以完成有界读写。
- [x] 真实 XLSM → XLSX 闭环通过。
- [x] 输出可重新读取并通过结构/策略验证。
- [x] 未修改关键 part 的保留检查有证据。
- [x] 至少一组独立校验与客户端打开证据成立。

**STOP 条件**：

- [ ] 有界读取无法可靠实现。
- [ ] 核心必须重做通用 Office parser。
- [ ] 重建会产生不可控内容破坏且合理适配无法解决。
- [ ] 发现已有项目已经完成同等级 capability-aware audit + policy rewrite + verified rebuild 核心。

---

#### TODO-1：Bounded Package Loader

**依赖：TODO-0 GO**

- [x] 输入 ZIP 大小限制。
- [x] 总解压字节限制。
- [x] 单 entry 解压限制。
- [x] entry 数量限制。
- [x] 重复 entry 检测。
- [x] 中心目录/本地头歧义检测。
- [x] CRC / malformed ZIP 错误处理。
- [x] 有界 XML 读取。
- [x] DTD / external entity 禁止。
- [x] XML 深度、节点、属性、token 长度限制。
- [x] 输出大小限制。
- [x] 所有限制失败均 fail closed。
- [x] 失败路径不返回可发布文档。

**验收**：

- [x] 精确上限 / 上限+1 测试通过。
- [x] 高压缩比输入不会无限制分配内存。
- [x] 解析截断返回 `Incomplete`，不能误报 `Pass`。

---

#### TODO-2：OPC Graph + XML Reference Index

**依赖：TODO-1**

- [x] `Part`
- [x] `Relationship`
- [x] `XmlReference`
- [x] `PackageGraph`
- [x] package-root node
- [x] Content Type index
- [x] Internal / External target distinction
- [x] source-relative target resolution
- [x] package-absolute target resolution
- [x] path/URI normalization
- [x] 重复局部 relationship ID 检测
- [x] missing target 检测
- [x] inbound / outbound edge index
- [x] reachability
- [x] orphan candidate
- [x] `r:id`
- [x] `r:embed`
- [x] `r:link`
- [x] 已支持 handler 的隐式关系/索引语义
- [x] namespace URI + local name 匹配
- [x] `AlternateContent` / VML / 未知扩展进入 Coverage 判断

**验收**：

- [x] Internal edge 要么解析到存在 part，要么产生明确错误/覆盖缺口。
- [x] External target 不误当 package part。
- [x] relationship ID 只在其 source 作用域内解释。
- [x] 同一输入重复解析得到稳定结果。
- [x] audit / rewrite / verify 共用这一事实模型。

---

#### TODO-3：Capability + Coverage Model

**依赖：TODO-2**

实现统一模型：

- [ ] `Finding`
- [ ] `Coverage`
- [ ] `Decision`
- [ ] rule ID
- [ ] certainty
- [ ] rebuild support status
- [ ] checked rules
- [ ] unchecked features
- [ ] parse truncation / error
- [ ] `Pass / Fail / Incomplete / Unsupported`

首版 capability 分类至少包含：

- [ ] VBA
- [ ] HTTP/HTTPS 点击 hyperlink
- [ ] Word external template
- [ ] External Resource
- [ ] External Data
- [ ] OLE
- [ ] ActiveX
- [ ] Unknown external relationship
- [ ] Unknown potentially active extension

**Coverage 必须成为一级输出。**

CLI/JSON 至少能表达：

```text
Coverage:
  VBA                  CHECKED
  Remote Template      CHECKED
  Hyperlink            CHECKED
  OLE                  UNSUPPORTED
  ActiveX              UNSUPPORTED
  Unknown extensions   OPAQUE / REFUSED / INCOMPLETE

Result:
  PASS within declared coverage
```

**验收**：

- [ ] `Pass` 只在声明支持范围内成立。
- [ ] `Incomplete` 永远不能发布重建文档。
- [ ] 未检查能力不能被当作“不存在”。
- [ ] 普通 hyperlink 与自动外部引用分开建模。

---

#### TODO-4：VBA Handler

**依赖：TODO-3**

- [ ] 检出 `vbaProject.bin`。
- [ ] 检出 VBA relationship。
- [ ] 检出 macro-enabled main content type。
- [ ] 区分“宏启用格式”和“实际存在 VBA”。
- [ ] 处理 XLSM → XLSX。
- [ ] 处理 DOCM → DOCX。
- [ ] 处理 shared reference。
- [ ] 处理孤儿/异常 VBA 结构。
- [ ] unsupported 变体 Refuse。
- [ ] 正例 / 干净负例 / 混合样本 / 不支持变体测试。

**验收**：

- [ ] 输出中声明范围内 VBA capability 为 0。
- [ ] 主 content type 与输出格式一致。
- [ ] 不误删无关 part。
- [ ] 输出客户端无修复提示。

---

#### TODO-5：Rewrite Planner + Dependency Closure

**依赖：TODO-3、TODO-4**

- [ ] `RemovePart`
- [ ] `RemoveRelationship`
- [ ] `RewriteSourceXml`
- [ ] `RewriteRelationshipPart`
- [ ] `RewriteContentTypes`
- [ ] `ChangeMainContentType`
- [ ] plan precondition hash
- [ ] plan conflict detection
- [ ] shared dependency protection
- [ ] orphan candidate handling
- [ ] deterministic plan ordering
- [ ] dry-run
- [ ] Refuse 时不产生输出

核心规则：

> **可达性降低只产生 orphan candidate，不能触发全包垃圾回收。**

只允许删除：

- [ ] 已确认属于被移除 capability 的 part；
- [ ] 不再有任何保留引用；
- [ ] handler 明确声明可删除。

**验收**：

- [ ] 不存在 dangling internal relationship。
- [ ] shared target 不被误删。
- [ ] 未知孤儿不会仅因不可达被自动删除。
- [ ] 每个 plan operation 可追溯到 rule + finding + decision。

---

#### TODO-6：Verify + Preservation Receipt

**依赖：TODO-5**

Preservation 分类：

- [ ] `BytePreserved`
- [ ] `SemanticallyRewritten`
- [ ] `RemovedByPolicy`
- [ ] `RegeneratedMetadata`

Verify 必须：

- [ ] 从输出 bytes 重新解析。
- [ ] 重新建立 graph。
- [ ] 重新执行 capability rules。
- [ ] 检查禁止 capability。
- [ ] 检查内部关系。
- [ ] 检查 Content Types。
- [ ] 检查主文档类型。
- [ ] 检查计划外变化。
- [ ] 检查所有输入 part 去向。
- [ ] 比较 `BytePreserved` payload SHA-256。
- [ ] 对 `SemanticallyRewritten` 执行 handler 专属断言。
- [ ] original 缺失时把 preservation 检查标为 `NotChecked / Incomplete`。

Receipt 至少包含：

- [ ] input/output hash
- [ ] tool/rules/policy/config version
- [ ] effective resource limits
- [ ] coverage
- [ ] findings
- [ ] decisions
- [ ] rewrite plan
- [ ] 所有 part 去向
- [ ] before/after part hash
- [ ] verification states
- [ ] refusal / unsupported / not-checked items
- [ ] independent validation evidence（若执行）

**验收**：

- [ ] executor 内存状态不能直接作为 verify 结果。
- [ ] 篡改输出后 verify 必须失败。
- [ ] 篡改 Receipt 不能制造完整验证通过。
- [ ] Refuse / Fail / Incomplete 不返回可发布 bytes。

---

### P1：顶奖能力覆盖

> 最终顶奖版本不能只停在“宏清理器”。

顶奖最低能力覆盖固定为三类不同结构：

```text
1. Executable Content
   VBA

2. External Capability
   至少一类：
   - Word Remote Template
   - XLSX External Workbook
   - External Resource

3. Embedded Active Content
   至少一类：
   - OLE
   - ActiveX
```

只有证明同一套：

```text
Package Graph
→ Capability Model
→ Policy
→ Rewrite Handler
→ Verify / Receipt
```

可以处理这三类结构差异明显的 capability，才形成 **OOXML Capability Auditor & Verified Rebuilder** 的完整顶奖叙事。

---

#### TODO-7：External Capability Handler

**依赖：TODO-6**

优先实现 Word Remote Template；其他 external capability 按真实需求排序。

- [ ] Word `attachedTemplate` 源 XML 证据。
- [ ] relationship 证据。
- [ ] 同步修改 settings XML + relationship。
- [ ] 保留普通 HTTP/HTTPS 点击 hyperlink。
- [ ] unknown external scheme 默认 Refuse 或显式 Remove。
- [ ] 正例 / 干净负例 / 混合 / 不支持变体测试。

如果改做 XLSX External Workbook：

- [ ] `externalReference`
- [ ] relationship
- [ ] externalLinks parts
- [ ] 公式/名称/cache 影响分析
- [ ] 无法安全处理时 Refuse，而不是只删关系。

**验收**：

- [ ] 至少一类 External Capability 达到完整 handler 完成定义。
- [ ] 普通 hyperlink 不被误删。
- [ ] 删除关系后 source XML 不存在悬空引用。

---

#### TODO-8：OLE 或 ActiveX Handler

**依赖：TODO-6**

二选一先做深，另一类放后续。

- [ ] 完整证据模型。
- [ ] relationship。
- [ ] source XML。
- [ ] preview / fallback / companion parts。
- [ ] shared dependency。
- [ ] Content Types。
- [ ] removal contract。
- [ ] unsupported variant Refuse。
- [ ] 正例 / 负例 / 混合 / unsupported fixture。

**验收**：

- [ ] 至少一类 Embedded Active Content 完成完整移除闭环。
- [ ] 不通过“删除 bin 文件”假装完成。
- [ ] 客户端兼容与独立校验通过。

---

#### TODO-9：Adversarial Corpus + Resource Limits

**依赖：TODO-1～TODO-8，持续建设，最终阻塞发布**

- [ ] 有效包
- [ ] malformed ZIP
- [ ] malformed XML
- [ ] namespace prefix variation
- [ ] URI 相对/绝对
- [ ] traversal target
- [ ] 编码歧义
- [ ] duplicate names
- [ ] duplicate local rel ID
- [ ] missing target
- [ ] cycle
- [ ] original orphan
- [ ] shared dependency
- [ ] hidden capability in unreachable part
- [ ] macro-enabled type without VBA
- [ ] extension / true type mismatch
- [ ] rule evidence conflict
- [ ] exact resource limit
- [ ] limit + 1
- [ ] high compression ratio
- [ ] parser truncation
- [ ] mixed supported/unsupported capability

目标：

- [ ] 30–50 个**有意义** fixture。
- [ ] 每个 fixture 有来源、许可、预期、允许变化、拒绝原因。
- [ ] 每个发现过的 bug 都进入 regression corpus。

---

#### TODO-10：Independent Validation

**依赖：已有稳定 handler**

- [ ] independent ZIP validation
- [ ] Open XML SDK validation
- [ ] Office open
- [ ] Office save + reopen
- [ ] LibreOffice open（若作为兼容目标）
- [ ] 关键内容检查
- [ ] 记录工具/客户端版本
- [ ] 不把“能打开”当作 capability audit 通过
- [ ] 不把 OpenXmlValidator 当作安全规则验证

---

### P1：顶奖生态硬门槛

#### TODO-11：Real MoonBit Integration

**依赖：SDK 已具备可用 audit/rebuild/verify 接口**

这是顶奖硬门槛，不允许用“理论用户”替代。

必须完成：

- [ ] 找到至少一个真实 MoonBit 项目正在接收、保存或交付 Office 文件。
- [ ] 确认该工作流为什么需要继续输出**可编辑 OOXML**，而不是只做 HTML preview / 文本提取。
- [ ] 明确其希望禁止哪些 capability。
- [ ] 明确可接受哪些内容损失。
- [ ] 提供真实 integration example 或经授权的接入 PR。
- [ ] 收集维护者/使用者实际测试反馈。
- [ ] 根据真实接入修正 SDK/CLI。
- [ ] 保存可公开引用的接入证据。

**最低顶奖门槛**：

- [ ] 至少 1 个非本项目作者维护的真实 MoonBit 下游完成实际调用/测试。

**强竞争力目标**：

- [ ] 2 个独立消费者；或
- [ ] 1 个高质量真实集成 + 明确维护者反馈 + 可复现实例。

如果始终找不到需要“清洗后继续交付 OOXML”的真实工作流：

> **暂停能力扩张并重新评估项目的顶奖定位。**

---

#### TODO-12：Compatibility Matrix

**依赖：TODO-4、TODO-7、TODO-8、TODO-10**

公开矩阵至少列：

- [ ] format
- [ ] capability
- [ ] audit support
- [ ] rebuild support
- [ ] verify support
- [ ] known unsupported variants
- [ ] independent validation
- [ ] tested client versions
- [ ] preservation class / allowed loss

不能用一个总的“支持 DOCX/XLSX”掩盖实际范围。

---

#### TODO-13：Top-Award Demo + Release

**依赖：TODO-11、TODO-12**

演示至少包含：

1. **Executable Content**：VBA。
2. **External Capability**：Remote Template 或其他已验收外部能力。
3. **Embedded Active Content**：OLE 或 ActiveX。
4. **Refusal Case**：unsupported / incomplete / over-limit 输入。

必须展示：

- [ ] audit
- [ ] Coverage
- [ ] RewritePlan
- [ ] rebuild
- [ ] verify
- [ ] Preservation Receipt
- [ ] 客户端前后效果
- [ ] 独立验证
- [ ] real integration
- [ ] known boundaries

发布材料：

- [ ] README
- [ ] architecture.md
- [ ] threat-model.md
- [ ] preservation-contract.md
- [ ] Receipt schema
- [ ] compatibility matrix
- [ ] changelog
- [ ] license
- [ ] fixture provenance
- [ ] benchmark
- [ ] resource-limit documentation
- [ ] SDK example
- [ ] Mooncakes package
- [ ] 3 分钟比赛 Demo
- [ ] 完整技术演示

---

### BONUS：不阻塞主线

#### TODO-14：第二个 External / Embedded Capability

只有 TODO-13 主线质量完成后再扩展。

#### TODO-15：Wasm Audit

- [ ] core package graph / audit 可在 Wasm 运行。
- [ ] 浏览器本地加载 OOXML。
- [ ] 本地展示 Coverage / Findings / Graph。
- [ ] 不上传文件。
- [ ] 不阻塞 Native rebuild 主链路。

---

### TODO 依赖总览

```text
TODO-0 Kill Spike
    ↓
TODO-1 Bounded Loader
    ↓
TODO-2 OPC Graph + XML Reference Index
    ↓
TODO-3 Capability + Coverage
    ↓
TODO-4 VBA Handler
    ↓
TODO-5 Rewrite Planner + Dependency Closure
    ↓
TODO-6 Verify + Preservation Receipt
    ├────────→ TODO-7 External Capability
    ├────────→ TODO-8 OLE / ActiveX
    └────────→ SDK 可用后启动 TODO-11 Real Integration

TODO-9  Adversarial Corpus ────────┐
TODO-10 Independent Validation ────┤
TODO-11 Real Integration ──────────┤
TODO-12 Compatibility Matrix ──────┤
                                   ↓
                         TODO-13 Top-Award Release

BONUS:
TODO-14 第二扩展能力
TODO-15 Wasm Audit
```

Issue 模板统一写：问题、范围、输入/输出、依赖、拒绝边界、验收命令、fixture 和预期结果。一个 Issue 解决一个可审查问题，不用“实现整个 sanitizer”作为任务标题。

## 11. 测试与发布门槛

### 11.1 P0：任何可发布版本都不能跳过

- [ ] 有效包与结构损坏包；XML namespace 前缀变化与非法 XML。
- [ ] URI 相对/绝对解析、越界、编码歧义、重复名称、重复局部 ID。
- [ ] 资源精确上限/超限；读取、解析、报告、输出均有界。
- [ ] 每个开放重建的 capability 至少有正例、干净负例、混合样本、不支持变体。
- [ ] 删除关系后源 XML 引用仍存在的负例，必须被检查发现。
- [ ] 共享依赖、环、原有孤儿、隐藏在不可达部件中的已知 capability。
- [ ] 宏启用类型但无 VBA、文件后缀与真实类型不一致、规则证据冲突。
- [ ] 所有部件去向与 hash 核验；重写 XML 仅发生允许变化。
- [ ] 修改原文件、输出或 Receipt 任一项，都不能误报完整验证通过。
- [ ] 再次重建已处理输出，在语义与部件层幂等；不能要求未规范的 ZIP 整体字节相同。
- [ ] Refuse/Fail/Incomplete 不返回可发布 bytes；CLI 失败不报告成功。
- [ ] 每个已公开兼容配置有真实样本、独立检查和客户端打开记录。

### 11.2 Corpus 与独立检查

按特征矩阵建设 corpus，记录每个样本的格式、能力、结构变体、来源/许可证、预期审计结果、允许变化和拒绝原因。目标可以是 30–50 个有意义样本，但发布门槛由覆盖决定，不能靠复制文件凑数。

人工最小包适合错误路径；真实 Office 样本适合兼容性。必须同时有干净控制样本，避免只测“危险内容删除成功”而不测误删。

独立校验工具只用于测试，不进入 MoonBit 运行时核心。固定目标 Office 版本/规范配置；对本来无效的输入默认拒绝，不用“输出新增错误不多”作为成功标准。客户端测试记录打开、保存后再打开及关键内容检查，不能只留下“看起来正常”的截图。

### 11.3 CI 与数据

基础 CI 必须运行 `moon check`、`moon test`、`moon build`，以及格式/公开接口生成后的差异检查；具体 target 参数按锁定工具链确认。Native 为主交付；纯核心 Wasm 测试按依赖可移植性安排，浏览器界面放到后续。

独立 ZIP/Open XML SDK 校验作为单独 job。Office 人工兼容测试用有版本的记录补充，不能标为已由 CI 自动执行。

benchmark 记录工具链、机器、输入压缩/解压大小、part/关系数、audit/rebuild/verify 各自耗时、峰值内存、失败输入成本。先测 1/10/30 MiB 等默认范围内数据；更大样本要使用明确的扩展 limit 配置，不能与默认限制矛盾。

## 12. CLI 与 SDK 交付约定

以下是设计命令，不代表已经发布或可安装；暂不承诺 `moonx` 的安装入口。

```text
partsieve audit input.xlsm --json
partsieve rebuild input.xlsm --policy passive-office-v1 -o output.xlsx --receipt output.receipt.json
partsieve rebuild input.xlsm --policy passive-office-v1 --dry-run
partsieve verify output.xlsx --policy passive-office-v1
partsieve verify output.xlsx --original input.xlsm --receipt output.receipt.json
```

CLI 使用 SDK，不复制审计/重写逻辑。SDK 接受 bytes、typed policy、limits，暴露 audit、plan、rebuild、verify；重建默认执行完整内置验证。文件 I/O 与发布属于 CLI/宿主，核心可独立使用。

建议退出码：`0` 表示所请求检查完整通过，`2` 表示规则/策略拒绝或验证失败，`3` 表示格式不支持、覆盖或检查不完整，`4` 表示 I/O/内部错误。`audit` 检出允许能力不等于失败；是否满足策略与是否检查完整分别呈现。具体退出码在 CLI/SDK 交付 TODO 中固定并测试。

成功响应、失败诊断及 JSON schema 均版本化。`verify` 无 original 的完整契约检查返回不完整状态；dry-run 不写文档，展示拒绝项与全部预期变化。

## 13. 真实需求、演示与发布

### 13.1 需求调查早于功能扩张

从 Kill Spike 起记录至少一个具体工作流：谁接收什么格式、为什么要继续输出可编辑文档、希望禁止什么、能接受哪些损失、如何处理拒绝。引用公开需求或经授权反馈，不能把附件支持等同于清洗需求。

SDK 可用后必须推进真实 MoonBit 下游验证。作者自建示例只能称示例，不能称独立下游采用。若目标仍是冲季度顶奖，则至少需要一个非本项目作者维护的真实 MoonBit 项目完成实际调用、测试或经授权的集成；否则应暂停继续扩能力，并重新评估顶奖定位。

提出 PR、发送消息或公开投稿均需作者明确授权；本计划中的调研任务不自动授权代理联系外部人员。

### 13.2 三段演示

1. **成功案例**：真实 XLSM 的表格/图片 + 无害 VBA；展示 audit、plan、rebuild、Receipt 和客户端前后结果。
2. **源 XML 案例**：DOCM 中 VBA + 外部模板 + 普通 HTTPS hyperlink；展示模板引用同步移除、链接按策略保留及正文检查。
3. **拒绝案例**：含尚未支持的外链公式/ActiveX、未知扩展或超限输入；展示拒绝原因和没有成功产物。

扩展能力只展示已经完成对应 handler 验收的样本。图展示先用 CLI tree；GUI、网站和浏览器 Wasm 不阻塞主线。

3 分钟演示按“问题 → 前后结果 → 证据 → 边界与价值”组织。每个 PASS 来自实际检查，拒绝能力也是可靠性成果。

### 13.3 发布材料

- README：定位、支持矩阵、安装/本地运行、示例、退出码、拒绝行为、资源配置、保证与非保证。
- `architecture.md`、`threat-model.md`、`preservation-contract.md`、Receipt schema 与 compatibility matrix。
- 依赖/fixture 来源与许可证、changelog、版本与工具链、有效 CI 结果。
- 可运行 SDK example、前后 fixture、独立校验与客户端记录、benchmark。
- 再确认包命名与发布规则后发布 Mooncakes；发布成功与质量验收分别记录。

比赛提交的截止日期、材料和资格以对应黑客松官方最新规则为准；不要混用 OSC 开源大赛要求。代码量、fixture 数量、两个消费者或 Wasm GUI 不在本文中当作官方获奖硬指标。

## 14. 风险与范围调整

| 风险 | 观察信号 | 应对 |
| --- | --- | --- |
| ZIP/XML API 不满足有界处理或保留 | 原型需要绕过限制、全量重写未知内容 | 小范围适配或换依赖；不能解决则 STOP |
| 源 XML/公式/扩展语义复杂 | 只能删关系，无法解释剩余引用 | 能力改为 Audit/Refuse；独立设计后开放 |
| 未知内容与“被动”保证冲突 | 保留了无法分类的执行/网络特征 | 拒绝，缩小配置；报告覆盖不能填 PASS |
| 内容保真不稳定 | Office 修复提示、图表/格式/数据变化 | fixture 定位、收紧契约，不追加新功能掩盖问题 |
| 上游覆盖同类价值 | 出现相同策略审计与重建接口 | 复评差异，优先贡献或适配；不把通用重写当创新 |
| 可编辑输出需求不足 | 用户只需要预览/提取 | 调整目标工作流；继续扩能力前重新立项判断 |
| 交付时间不足 | Kill Spike 或核心 TODO 持续卡住，兼容证明迟迟缺失 | 优先完成 P0 核心闭环；扩展能力按真实需求排序，不能牺牲安全门槛 |
| 名称或命名空间冲突 | 注册/发布时发现占用 | 在对外发布前复核；不保证公开检索穷尽撞名 |

每个新增任务回答：提升哪条保证、支持哪个真实用例、需要多少投入、用什么证据验收。若四项都不明确，留在 backlog，不进当前里程碑。

## 15. 当前执行清单

执行状态以实际证据为准，不把设计命令、矩阵或原型已有部分实现等同于后续 TODO 完成。

- [x] 复核并建立 `partsieve/`，模块名 `zlhahaha/partsieve`，已发布实验性 `0.1.0-spike`。
- [x] 确认 ZIP/XML/hash 公共 API、许可证和限制执行点。
- [x] 获取干净 XLSX 与真实、无害 VBA XLSM 样本，固定来源与 hash。
- [x] 执行 TODO-0 Kill Spike，保存 spike-report 与前后证据。
- [x] 作出 GO 判断：技术闭环通过；真实需求和独立下游门槛仍缺。
- [x] TODO-1：收敛 Bounded Package Loader 的解析截断/限额失败状态和边界验收。
- [x] TODO-2：共用 PackageGraph/XML 引用与关系索引、迭代可达性、孤儿候选和覆盖缺口验收通过。
- [ ] TODO-3 至后续任务：依赖逐项满足后推进，不提前勾选。

TODO-0/1/2 已验收，下一开发 P0 为 TODO-3。22 个单元测试、48 个特征样本、17 项端到端检查和 11 项图宿主检查通过；统计不扩大支持范围。统一 Coverage/Decision、DOCM 与后续 handler、真实下游、benchmark 校准与最终成品发布仍未完成；原型的 Native/独立格式 CI 和 Mooncakes 预发布已完成。

## 16. 参考依据与待复核项

- [ECMA-376](https://ecma-international.org/publications-and-standards/standards/ecma-376/)：Part 2 为 OPC；源 XML 引用与兼容扩展还涉及 Part 1/3/4。实现前固定使用版本与适用条款。
- [Open XML SDK：ExternalReference](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.spreadsheet.externalreference?view=openxml-3.0.1)、[AttachedTemplate](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.attachedtemplate?view=openxml-3.0.1)：源 XML 与局部关系 ID 的对应结构。
- [OpenXmlValidator](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.validation.openxmlvalidator?view=openxml-3.0.1)：独立格式验证参考，不能替代本项目策略验证。
- 本地调研：`research/OOXML文档重建选题复核-2026-10-04.md`；其上游 issue 状态、下游意向与“未找到同类项目”均不能当长期事实。此次未能重新读取 office.mbt #265，保持待复核。
- ZIP/XML/hash 依赖已重新安装、精确固定并验证源码；执行证据见 `partsieve/docs/dependency-lock.json`，Spike 与回归记录见 `partsieve/docs/evidence/`。
- 命名于 2026-10-04 做过公开关键词检索；未发现显著的同名 OOXML 工具，但这不保证商标、仓库、CLI 或 Mooncakes 名称可用，发布前按目标平台复核。



## 17. 原型公开发布授权更新（2026-10-04）

作者已明确要求初始化 GitHub `https://github.com/zlhahaha/partsieve` 并在原型完成后发布 Mooncakes。TODO-0/1 已完成，因此本轮执行 `zlhahaha/partsieve@0.1.0-spike` 的原型预发布；这更新此前“暂不发布”的执行约定，不代表 TODO-13 顶奖成品验收或整个路线图完成。

章程要求公开源码、合理开发记录、README、检查/构建/测试、可运行示例、关键测试、Mooncakes 与 OSI 许可，本轮逐项保存证据。申报时至少 10 个有效 commits 尚未满足；按后续实际变化积累。不得以空提交、重复提交或过度拆分凑数，报名与作者的人工作文等要求仍由作者确认。最新发布状态见 `partsieve/docs/release.md`。

原型发布结果：GitHub main 已推送；源码提交 `a7be1e1` 的两个功能 CI job 全部成功；Mooncakes 正式发布返回 HTTP 200 / exit 0，独立目录从注册表下载 `0.1.0-spike`，通过 Native SDK audit/rebuild/verify 和准确输出 hash 检查。完整记录与可复现消费者见 `partsieve/docs/evidence/release-validation.json` / `registry-consumer/`。已有 5 次真实有效提交，10 次章程申报门槛仍未达成。

TODO-2 后续开发：新增 Graph API 位于 main，原型已发布标签不包含此 API。用户已确认暂无第三方下游；office.mbt #265 经公开 GitHub API 重新读取仍 open，说明全量重写保留问题，不等于清洗需求或采用承诺。TODO-11 保持未完成。
