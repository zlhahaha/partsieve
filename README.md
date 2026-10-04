# PartSieve

MoonBit OOXML Capability Auditor & Verified Rebuilder。当前是 **0.1.0-spike，未发布**，已完成 TODO-0 技术 GO 与 TODO-1 Bounded Package Loader。完整路线图见工作区 `plan.md`，交接记录见工作区 `HANDOFF.md`。

首个配置 `simple-spreadsheet-spike-v1` 支持简单 XLSX/XLSM：受限读取、VBA 证据、固定策略计划、重建、重新读取验证和所有 part 的 payload hash。真实样本经独立 ZIP、Open XML SDK 3.3.0、WPS 12.1.0.28505 检查。外链、公式、hyperlink、图片、OLE、ActiveX、未知部件/扩展及 DOCX/DOCM 当前拒绝，不宣称通用文档安全或视觉保真。

## 本地运行

使用记录在 [dependency-lock.json](docs/dependency-lock.json) 的 MoonBit 工具链与依赖：

```powershell
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

原型退出码：0 请求的检查完成；2 Receipt/已发布 hash 复核不符；3 配置不支持、检查不完整、资源拒绝或 worker 失败；4 I/O/用法错误。解析失败、截断与限额耗尽有明确的 Incomplete 诊断，不能发布重建结果。统一的 Coverage/Decision 和完整 Pass/Fail/Incomplete/Unsupported 结果模型属于后续 TODO-3，当前不把这些退出码当作最终发布契约。无 original 的 verify 会标 preservation NotChecked、整体 Incomplete，返回 3。

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

执行 [tools/check.ps1](tools/check.ps1) 可复核版本、依赖源码、格式与公开接口漂移、编译和回归。当前 15 个单元测试、48 个特征样本、17 项端到端检查通过。WPS 检查是独立客户端证据，不宣称已由 CI 自动完成。大量样本为人工变体；真实兼容样本只有上游 macro01.xlsm/simple01.xlsx，不能靠样本数量扩大支持范围。

详见 [Spike 报告](docs/spike-report.md)、[实际兼容矩阵](docs/compatibility-matrix.md)、[保留契约](docs/preservation-contract.md)、[威胁模型](docs/threat-model.md)、[架构](docs/architecture.md)、[来源](tests/fixtures/provenance.json)、[Receipt schema](docs/receipt.schema.json)。

## 许可

项目 Apache-2.0。核心第三方依赖 Apache-2.0；真实 fixture 与上游测试 BSD-2-Clause，其许可在 `tests/fixtures/upstream/LICENSE.txt`，来源与 hash 在 provenance.json。不保存用户文档或执行宏。
