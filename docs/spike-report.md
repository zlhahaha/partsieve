# TODO-0 Kill Spike 报告

日期：2026-10-04。结论：**GO（技术闭环）**。随后完成 TODO-1 Bounded Package Loader；下一项为 TODO-2。随后按作者授权发布 `0.1.0-spike` 原型，项目尚未 LOCK。发布结果见 [发布记录](https://github.com/zlhahaha/partsieve/blob/main/docs/release.md)。

计划第 9.3 节的五项技术门槛已有实际证据：公开依赖的有界读写；真实 XLSM → XLSX；从实际输出重解析验证；所有未改写 payload 的保留；独立 ZIP/Open XML SDK 与客户端检查。用户允许使用 WPS，故客户端验收记录为 WPS，未声称测过 Microsoft Excel 或 LibreOffice。

此结论允许继续主线，不扩大兼容范围，不代替真实下游需求和发布验收。当前支持配置为 `simple-spreadsheet-spike-v1`、固定 `passive-office-v1`。后续 TODO 未因原型含有部分实现而整体标完成。

## 可复核的输入与结果

真实样本固定于 XlsxWriter commit `5d4606d89a955226d2d0825a0f44309043ae7251`，来自其 Excel 比较测试，BSD-2-Clause 许可证已随样本保存。完整路径、上游链接、大小和 SHA-256 见 [provenance.json](../tests/fixtures/provenance.json)。上游测试说明和 fixture 一并保存，人工变体只作为结构/拒绝证据。

| 项目 | 大小 | SHA-256 |
| --- | --- | --- |
| 原件 `macro01.xlsm` | 11,463 bytes | `09c35d1580eb6d7e678ba8249cdd1cbc0bd245fbb0eed8794981728715944736` |
| 结果 `verified.xlsx` | 6,236 bytes | `fcc9a0ca93810d894df21c71d5764db7252afd3b1232b5aef55c21f3efcc9e53` |
| 干净控制 `simple01.xlsx` | 见 provenance | `cc6caf6efe9b60d5e9b59cc9c490cd02d7998af42021830f2def3e87f79004ad` |

真实 VBA 静态提取仅有手动将 A1 设为 123 的 Macro1；其余模块是属性。检查记录见 [vba-source-review.json](evidence/vba-source-review.json)，没有执行宏。客户端只打开经核验的无宏输出。

原件有 10 个部件。五项计划操作：删除 VBA payload；删除 workbook 的 VBA 隐式关系；重生成 workbook relationship metadata；主类型改为 XLSX；重生成 Content Types。没有正文改写：本配置验证工作簿源 XML 的 `r:id` 只绑定 worksheet，拒绝未知引用，VBA 关系没有需改写的正文引用。

所有输入部件有去向：1 个 `RemovedByPolicy`、2 个 `RegeneratedMetadata`、7 个 `BytePreserved`。工作簿、工作表、样式、主题、文档属性等未修改 payload 的 SHA-256 相等。宏功能按策略丢失；ZIP 容器字节、时间戳和压缩结果不属于保留契约。没有全包垃圾回收。

计划与全量记录见 [Receipt](evidence/verified.receipt.json)。其 `structure` / `preservation` 为 Pass，`independent_validation` 保持 NotChecked；独立测试证据在外部记录中，不能伪装成 SDK 每次已经执行。

## 命令与复现

在 `partsieve/` 运行，重建输出路径必须不存在：

```powershell
moon build --target native --deny-warn
python tools/partsieve.py audit tests/fixtures/upstream/macro01.xlsm --json
python tools/partsieve.py rebuild tests/fixtures/upstream/macro01.xlsm --dry-run
python tools/partsieve.py rebuild tests/fixtures/upstream/macro01.xlsm --policy passive-office-v1 -o example.xlsx --receipt example.receipt.json
python tools/partsieve.py verify example.xlsx --original tests/fixtures/upstream/macro01.xlsm --receipt example.receipt.json
moon run examples/sdk --target native
.\tools\check.ps1
python tools/validate_evidence.py
```

最后一条需要测试依赖 `jsonschema` 和 .NET Open XML SDK 3.3.0（项目文件固定版本）；这些不进入 MoonBit 核心。WPS COM 检查脚本在 `tests/wps_compatibility.ps1`，界面截图需独立观察。当前校验结果记录于 [final-checks.log](evidence/final-checks.log) 和 [evidence-check.json](evidence/evidence-check.json)。

宿主 Python 负责读取前限额、私有临时快照、60 秒 worker 超时、输出重读和成对发布，所有 OOXML 模型/审计/变换位于 MoonBit SDK。直接 worker 的 x/fs 不提供读取前限额，只能用于受限快照，不是公开不可信文件入口。

## 依赖和资源边界

固定工具链 `moon 0.1.20260920` / `moonc v0.10.14+7d59c7ec9`。flate 0.8.4、Milky2018/xml 0.5.0、moonbitlang/x 0.5.5，均 Apache-2.0。精确 manifest 版本、registry checksum、安装源码 hash 及文件数在 [dependency-lock.json](dependency-lock.json)；它是项目复核证据，不冒充 Moon 原生 lockfile。

- flate 的公共 `ReadLimits`、remove、replace、`write_preserving_limited` 可复用。适配层显式比较 CRC：上游 read 不做此项。测试验证未知 opaque ZIP payload 删除其他项后仍字节保留；OOXML profile 并未因此允许未知部件。
- XML 使用 namespace URI/local name。上游没有节点/深度限额，适配层在 parser 前执行有界扫描；拒绝 DTD/ENTITY、非法 UTF-8、超深 XML、过量节点/属性/markup 或 text token，然后才分配命名空间节点。DTD 字样即使在注释中也保守拒绝。
- 默认且硬上限：输入 32 MiB、entry 32 MiB、解压总量 128 MiB、4096 entries、单 XML 8 MiB、深度 128、节点 200000、属性 400000、输出 64 MiB。SDK 配置允许降低，当前不允许调高。
- 附加硬限额：每元素属性 256、markup（含注释/CDATA/PI）与 text token 65536 code units、名称/relationship ID 1024、关系 32768、全包 XML 节点/属性分别 1000000、preserved source 为输入限额的两倍、worker JSON 字符 8 Mi、宿主报告字节 16 MiB。

这些是原型起点，**未完成默认参数校准**。TODO-1 已明确将截断、解析失败和资源耗尽报告为 Incomplete；限制触发返回非零、不返回成功重建 bytes。核心工作预算、取消接口、统一 Coverage/Decision 模型和可配置附加限制尚待后续主线。

规范基准为 [ECMA-376 Part 2，第 5 版（2021-12）](https://ecma-international.org/publications-and-standards/standards/ecma-376/)；OPC 实现是保守子集，拒绝 percent encoding、非 ASCII、歧义名称与越界，不声称完整 OPC 合规。运行时只检查配置声明的结构和能力规则，不是完整 OOXML schema validator。

## 验证证据

| 检查 | 实际结果与证据 |
| --- | --- |
| 工具链、依赖、公开接口、格式 | check.ps1 校验版本和源码；moon info 生成接口无漂移；moon fmt --check 通过 |
| 编译/SDK | moon check/test/build Native --deny-warn 通过；SDK 示例使用公开 API 完成闭环 |
| 单元测试 | 15/15：SHA-256、URI、namespace、XML 上限/加一、DTD/UTF-8、ZIP/output 限额、opaque payload 保留；SDK 全部配置边界、token/每元素属性精确边界、Incomplete 失败状态 |
| 特征样本 | 48 个案例通过，见 [regression.json](evidence/regression.json)；真实样本只有两个，其余为人工变体 |
| 端到端 | 17 项逐项列出：成对发布、原件/Receipt 复核、伪造/篡改拒绝、无原件 Incomplete、dry-run、禁止覆盖、干净控制全部 payload 保留、二次重建 payload 稳定、不支持输入不产文件及支持变体 |
| 独立 ZIP/XML | CPython 3.12.7 zipfile CRC、ElementTree、精确变化集合、7 个未改 payload、A1=123；[independent-zip.json](evidence/independent-zip.json) |
| 独立 schema | Open XML SDK 3.3.0 Office2007：原件、输出、干净控制、WPS 保存副本全部 Pass，0 errors；[openxml-final.json](evidence/openxml-final.json) 含实际检查 bytes 的 hash |
| WPS COM | 12.1.0.28505 打开、保存、重开，1 sheet、A1=123；[wps-compatibility.json](evidence/wps-compatibility.json) |
| WPS 界面 | 正常打开无修复提示，A1/公式栏 123；[观察记录](evidence/wps-ui-observation.json)、[截图](evidence/wps-open-verified.jpg) |
| Receipt | schema 形状和重新计算结果一致；schema 形状通过本身不能代替 hash/保留复核 |

失败样本包括重复/大小写等价名字、local/central 歧义、CRC 损坏、截断、非法 XML/DTD、重复局部 ID、缺失/越界 target、错误源引用、共享/孤儿 VBA、非 CFB 假 VBA、类型冲突、外链/公式/ActiveX/OLE/未知扩展、高压缩比和资源超限。支持与拒绝范围见 [compatibility-matrix.md](compatibility-matrix.md)。

WPS 打开文件时 Open XML SDK 默认文件共享方式曾产生 I/O 冲突；验证脚本改为受限只读快照并记录其 SHA-256，重新检查成功。此问题不是文档 schema 错误，没有替换文件来掩盖失败。

## 性能与当前未解决项

[benchmark.json](evidence/benchmark.json) 是 Windows 11 Native debug、psutil 5.9.0、每场景三次的微型 smoke benchmark。真实样本 audit/rebuild/verify 在几十至百毫秒量级，高压缩 XML 拒绝为亚秒量级；记录了采样工作集。采样可能漏掉瞬时峰值，未覆盖 1/10/30 MiB 校准，不以该结果承诺生产吞吐或限额充分性。

当前不能交付 DOCM/DOCX、公式、hyperlink、图片、OLE/ActiveX、外部模板或未知扩展的重建；复杂 VBA 变体也默认拒绝。一个数字单元格的客户端证据不等于图文保真。

需求调查记录于 [demand-evidence.md](demand-evidence.md)。尚无经确认的实际可编辑文档清洗用户或非作者维护的 MoonBit 下游调用；作者的 SDK 示例不是独立采用。后续真实集成、源 XML handler、扩能力、CI、限额 benchmark 和发布均仍有独立门槛。本轮没有发布 Mooncakes、提 PR、联系外部维护者或操作用户文档。

TODO-1 验收已通过：SDK 降低限额测试全部配置的精确边界/加一，XML markup/comment/CDATA/text 与每元素属性边界、截断/错误状态、高压缩比、虚报解压大小和失败不发布均有证据。后续按 TODO-2/3 建立共用图、引用、Coverage 模型；按实际支持逐项验收，不以本报告替代后续 TODO。
