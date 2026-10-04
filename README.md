# PartSieve

MoonBit OOXML Capability Auditor & Verified Rebuilder。首次原型版本为 **0.1.0-spike**，该发布包已完成 TODO-0 技术 GO 与 TODO-1 Bounded Package Loader；GitHub main 开发版 **0.2.0-dev（未发布）** 后续已完成 TODO-2 OPC 图与 XML 引用索引、TODO-3 结构化能力/覆盖/决策、TODO-4 受限 Word VBA handler。完整路线图见 [plan.md](https://github.com/zlhahaha/partsieve/blob/main/plan.md)，交接记录见 [HANDOFF.md](https://github.com/zlhahaha/partsieve/blob/main/HANDOFF.md)，发布与章程要求的实际状态见 [发布记录](https://github.com/zlhahaha/partsieve/blob/main/docs/release.md)。

首个配置 `simple-spreadsheet-spike-v1` 支持简单 XLSX/XLSM：受限读取、VBA 证据、固定策略计划、重建、重新读取验证和所有 part 的 payload hash。main 的 `simple-word-vba-dev-v1` 新增受限 DOCM→DOCX，删除独占 VBA supporting 元数据，正文与其他 payload 字节保留；详见 [Word handler](docs/word-vba.md)。真实样本经独立 ZIP、Open XML SDK 3.3.0、WPS 12.1.0.28505 检查。外链、公式、hyperlink、图片、OLE、ActiveX、未知部件/扩展仍拒绝，不宣称通用文档安全或视觉保真。WPS Word 另存副本存在三个 styles 顺序校验错误，原始 PartSieve 输出通过校验；该差异在矩阵中单列。

## 本地运行

Mooncakes SDK 使用：

```powershell
moon update
moon add zlhahaha/partsieve@0.1.0-spike
```

在调用方 `moon.pkg` 中 `import { "zlhahaha/partsieve" @sieve }`，然后调用下方 SDK API。当前声明支持 Native；版本为实验性原型，API 和支持配置可能变化。脚本 CLI、完整测试与客户端证据请克隆源码仓库：

```powershell
git clone https://github.com/zlhahaha/partsieve.git
cd partsieve
```

使用记录在 [dependency-lock.json](docs/dependency-lock.json) 的 MoonBit 工具链与依赖：

```powershell
moon update
moon add moonbit-community/flate@0.8.4
moon add Milky2018/xml@0.5.0
moon add moonbitlang/x@0.5.5
python tools/lock_evidence.py
moon build --target native --deny-warn
python tools/partsieve.py audit tests/fixtures/upstream/macro01.xlsm --json
python tools/partsieve.py rebuild tests/fixtures/upstream/macro01.xlsm --dry-run
python tools/partsieve.py rebuild tests/fixtures/upstream/macro01.xlsm --policy passive-office-v1 -o output.xlsx --receipt output.receipt.json
python tools/partsieve.py verify output.xlsx --original tests/fixtures/upstream/macro01.xlsm --receipt output.receipt.json
```

输出与 Receipt 默认不覆盖。成功只在重新读取实际临时输出验证、两个文件发布并 hash 对齐后返回。下游接受完整、匹配的文件对；两个路径不具备事务原子性。Windows/Linux 文件系统需支持同文件系统的 hard link。

Python 是原型有界 I/O 宿主，所有 OOXML 核心逻辑在 MoonBit SDK。不要直接将 `cmd/main` 私有 worker 用于不可信文件输入；它假设宿主已限制输入文件。

原型退出码：0 请求的检查完成；2 明确结构完整性、保留契约、Receipt/已发布 hash 复核不符；3 配置不支持、检查不完整、资源拒绝或 worker 失败；4 I/O/用法错误。解析失败、截断与限额耗尽有明确的 Incomplete 诊断，不能发布重建结果。main 的 `assess` 已提供统一 Coverage/Decision 和 Pass/Fail/Incomplete/Unsupported；原型 Audit/Receipt 保留兼容形状，完整新版 Receipt 属于 TODO-6，当前不把这些退出码当作最终发布契约。无 original 的 verify 会标 preservation NotChecked、整体 Incomplete，返回 3。

## SDK 与验证

公开接口：`audit(bytes, limits?)`、`plan(bytes, limits?)`、`rebuild(bytes, limits?)`、`verify(output, original, limits?)`；当前固定 `passive-office-v1`。SDK 只在内置重解析与保留检查通过后返回 bytes + Receipt。宿主自行实现有界读取、取消/超时和发布。

```powershell
moon run examples/sdk --target native
moon check --target native --deny-warn
moon test --target native --deny-warn
moon build --target native --deny-warn
python tests/regression.py
python tests/independent_zip.py tests/fixtures/upstream/macro01.xlsm docs/evidence/verified.xlsx
dotnet run --project tests/OpenXmlValidation -- tests/fixtures/upstream/macro01.xlsm docs/evidence/verified.xlsx
```

执行 [tools/check.ps1](tools/check.ps1) 可复核版本、依赖源码、格式与公开接口漂移、编译和回归。main 当前 25 个单元测试、48 个特征样本、17 项端到端检查、11 项图宿主检查、17 项覆盖/决策检查和 29 项 Word 检查通过；首次发布包对应 15 个单元测试。WPS 检查是独立客户端证据，不宣称已由 CI 自动完成。大量样本为人工变体；真实支持证据来自上游 macro01.xlsm/simple01.xlsx/SimpleMacro.docm，另有真实 SampleDoc.docx 作为超出配置的拒绝负例，不能靠样本数量扩大支持范围。

详见 [Spike 报告](https://github.com/zlhahaha/partsieve/blob/main/docs/spike-report.md)、[实际兼容矩阵](docs/compatibility-matrix.md)、[保留契约](docs/preservation-contract.md)、[威胁模型](docs/threat-model.md)、[架构](docs/architecture.md)、[来源](tests/fixtures/provenance.json)、[Receipt schema](docs/receipt.schema.json)。依赖来源/许可见 [第三方说明](docs/third-party.md)。本项目并非通用 Office 读写库或宏行为检测器，核心贡献为已声明配置内的能力证据、策略变换和实际产物保留复核。

## main 的未发布图检查 API

`inspect_graph(bytes, limits?)` / `python tools/partsieve.py graph INPUT --json` 暴露局部 XML 绑定、关系/内容类型索引、可达性、孤儿候选和覆盖缺口。空缺口不等于 profile 支持或可重建。该新 API 尚不包含在 Mooncakes `0.1.0-spike` 内，详见 [图事实模型](docs/package-graph.md)。

## main 的未发布能力/覆盖 API

`assess(bytes, limits?)` / `python tools/partsieve.py assess INPUT --json` 返回 CapabilityFinding、Coverage、Decision；未检查/不透明/解析未完成都保持 Unknown，不允许重建。Pass 仅表示当前配置下检查和变换许可，不表示输入没有 VBA。该新 API 尚不在 Mooncakes `0.1.0-spike` 内，详见 [覆盖与决策](docs/coverage-decision.md)。

## 许可

项目 Apache-2.0。核心第三方依赖 Apache-2.0；XlsxWriter fixture 与上游测试 BSD-2-Clause，许可在 `tests/fixtures/upstream/LICENSE.txt`；Apache POI Word fixture 为 Apache-2.0，完整 LICENSE/NOTICE 在 `tests/fixtures/poi/`。两处 provenance 记录固定来源与 hash。不保存用户文档或执行宏。
