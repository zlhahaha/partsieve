# PartSieve

MoonBit OOXML 能力审计与验证重建 SDK。按受限配置识别 VBA、生成删除计划、重建为普通可编辑 OOXML，再从实际输出重算结构和所有部件的保留契约。不执行宏，不获取外部资源。

Mooncakes 已发布 **0.1.0-spike**；GitHub main 为 **0.2.0-dev（未发布）**。原型支持简单 XLSM→XLSX，main 新增受限 DOCM→DOCX、图/引用索引和结构化覆盖报告。通用 Office 文档、外链、公式、图片、OLE/ActiveX、未知扩展仍拒绝；不保证任意文档安全或视觉保真。

## 安装与使用

```powershell
moon update
moon add zlhahaha/partsieve@0.1.0-spike
```

调用方 `moon.pkg` 导入 `"zlhahaha/partsieve" @sieve`。公开 SDK：`audit(bytes, limits?)`、`plan(bytes, limits?)`、`rebuild(bytes, limits?)`、`verify(output, original, limits?)`；main 另有 `inspect_graph`、`assess`、`prepare`、`rebuild_with_plan(input, prepared_json, limits?)`。`rebuild` 仅在重解析和保留验证通过后返回 bytes + Receipt。调用方负责有界文件读取、取消/超时和发布。

本地 CLI 与测试：

```powershell
git clone https://github.com/zlhahaha/partsieve.git
cd partsieve
moon update
moon install
moon build --target native --deny-warn
python tools/partsieve.py assess tests/fixtures/upstream/macro01.xlsm
python tools/partsieve.py rebuild tests/fixtures/upstream/macro01.xlsm --dry-run
python tools/partsieve.py rebuild tests/fixtures/upstream/macro01.xlsm -o result.xlsx --receipt result.receipt.json
python tools/partsieve.py verify result.xlsx --original tests/fixtures/upstream/macro01.xlsm --receipt result.receipt.json
```

Word 示例替换输入为 `tests/fixtures/poi/SimpleMacro.docm`，输出使用 `.docx`。格式以主关系与 content type 判断，输出扩展名必须一致。宏启用主类型不等于存在 VBA。

`python tools/partsieve.py prepare INPUT` 返回绑定输入、全部 part hash、生效限额、finding→policy decision→operation、依赖及元数据预期 hash 的计划；保存 UTF-8 JSON 后用 `rebuild INPUT --plan PLAN.json -o RESULT --receipt RECEIPT` 执行。执行前独立重算整份计划，过期或修改的字段均 Fail。当前 source XML handler 尚未验收，`RewriteSourceXml` 不接受执行；计划声明该缺口，不扩大 VBA 配置范围。

Python `tools/partsieve.py` 是有界 I/O 宿主；全部 OOXML 逻辑在 MoonBit。不要直接将私有 Native worker 用于不可信文件：worker 只接收宿主已限制的快照。固定策略为 `passive-office-v1`。输出与 Receipt 不覆盖已有文件；实际文件重读验证后才成对发布，两个路径不保证事务原子性。

退出码：0 请求完成，2 明确完整性/保留/Receipt 不符，3 Unsupported/Incomplete/资源拒绝，4 I/O 或用法错误。没有 original 的 verify 保留检查为 NotChecked，完整结论 Incomplete，退出 3。未检查、未知和解析失败不能推导为无禁止能力。

## 支持与保留

| 配置 | 审计与重建 | 保留与证据 |
| --- | --- | --- |
| simple-spreadsheet-spike-v1 | 简单 XLSX/XLSM；已支持 VBA 移除、主类型转换 | 真实 macro01.xlsm 删除 1 VBA part、重写 2 元数据、保留 7 payload；独立 ZIP/SDK 校验和 WPS 打开通过 |
| simple-word-vba-dev-v1（main） | 简单 DOCX/DOCM；项目和独占 supporting 元数据移除 | 真实 SimpleMacro.docm 删除 3 parts、重写 2 元数据、保留 9 payload；独立 ZIP/SDK 校验和 WPS 打开通过 |
| 共享/孤儿 VBA、保留 XML 引用、未知 companion、外部能力和扩展 | Refuse | 不返回重建文档；未知孤儿不按可达性自动删除 |

字节保留指解压后的 part payload。移除宏会失去宏功能。客户端保存的文件属于客户端重写；WPS Word 另存副本可重开、正文一致，但独立 SDK 发现 3 个 styles 元素顺序错误，不能记为 PartSieve 的保留成功。没有 Microsoft Office/LibreOffice 的验收证据。

## 开发验证

工具链固定 `moonc 0.10.14+7d59c7ec9`，依赖见 [dependency-lock.json](docs/dependency-lock.json)。Windows Native/MSVC 完整检查：

```powershell
.\tools\check.ps1
moon run examples/sdk --target native
```

检查会生成本地 `docs/evidence/` 输出与报告。GitHub Actions 将实际生成的 SDK 输出传给独立 ZIP/Open XML SDK 3.3.0 校验 job，并将报告作为 CI artifacts 保存；不依赖预先提交的成功输出。核心回归覆盖读取限额、CRC、URI、namespace、引用/关系图、能力/拒绝、共享保护和保留篡改。WPS 检查是本地客户端证据，CI 不自动运行 WPS。

[架构](docs/architecture.md)、[威胁模型](docs/threat-model.md)、[保留契约](docs/preservation-contract.md)、[兼容矩阵](docs/compatibility-matrix.md)、[原型 Receipt schema](docs/receipt.schema.json)、[开发 Word schema](docs/word-receipt.schema.json)。完整路线图、HANDOFF、工作日志、截图和详细验证档案仅在本地维护。真实第三方 MoonBit 下游尚未确认，不把作者示例计作独立采用。

## 许可与来源

项目 Apache-2.0。运行时依赖：flate 0.8.4、Milky2018/xml 0.5.0、moonbitlang/x 0.5.5（均 Apache-2.0）。XlsxWriter fixture 为 BSD-2-Clause；Apache POI fixture 为 Apache-2.0。保留上游完整 LICENSE/NOTICE、固定来源与 SHA-256。详见 [第三方说明](docs/third-party.md)、[XlsxWriter provenance](tests/fixtures/provenance.json)、[POI provenance](tests/fixtures/poi/provenance.json)。不收录用户文档，未执行 fixture 宏。
