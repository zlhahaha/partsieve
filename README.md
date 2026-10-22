# PartSieve

MoonBit Office 文档清理与保留验证库。面向文档接收和报表交付，在已验证范围内移除 VBA 宏及 Word 外部模板，输出可继续编辑的 DOCX/XLSX，并从实际输出重新检查引用和所有内部文件的处理结果。不执行宏，不访问外部资源。

当前版本 **0.3.0-spike**，范围明确的实验版本，不承诺任意 Office 文件安全或视觉完全一致。参考 [DocBleach 的功能划分](docs/docbleach-comparison.md)，核心由 MoonBit 实现；Python 只承担命令行文件读写、超时和配套输出。

## 支持范围

| 输入与内容 | 处理和保留 |
| --- | --- |
| XLSX/XLSM：中文/英文文本、数字、布尔值、日期、多工作表、常用样式 | 共享/内联文本、1900/1904日期系统、工作表名称与顺序、字体/颜色/边框/对齐/数字格式及合并单元格保留；移除 VBA、转 XLSX |
| DOCX/DOCM：段落、表格、合并单元格、内嵌 PNG/JPEG、分节页眉页脚 | 正常内容和图片原始数据保留；校验正文、页眉和页脚各自引用；移除 VBA、转 DOCX |
| Word 设置中一个 HTTP(S) 外部模板 | 同步移除 attachedTemplate 元素和设置本地关系；核验其余设置语义，不下载模板 |
| 公式、普通超链接、外部图片/工作簿、OLE/ActiveX、签名、未知扩展 | 拒绝重建，返回原因，不生成成功文件对 |

浮动图片、SVG、VML、复杂绘图、字段和其他未知布局仍拒绝。日期按原有值及格式保留，不提供公式计算或渲染引擎。详见 [兼容矩阵](docs/compatibility-matrix.md)。

## 安装与使用

```powershell
moon add zlhahaha/partsieve@0.3.0-spike
```

调用方导入 `"zlhahaha/partsieve" @sieve`。主要接口：`assess`、`prepare`、`rebuild_verified`、`rebuild_verified_with_plan`、`verify_contract`；传入 bytes 和可选 Limits。报告包含能力、覆盖、处理计划、逐项去向与检查状态。`audit/plan/rebuild/verify/inspect_graph` 继续提供。

```powershell
git clone https://github.com/zlhahaha/partsieve.git
cd partsieve
moon update
moon install
moon build --target native --deny-warn
moon run examples/business --target native
python tools/partsieve.py rebuild tests/fixtures/business/report-1900.xlsm -o report.xlsx --receipt report.json --receipt-format v2
python tools/partsieve.py rebuild tests/fixtures/business/document-template.docm -o document.docx --receipt document.json --receipt-format v2
python tools/partsieve.py verify document.docx --original tests/fixtures/business/document-template.docm --receipt document.json --receipt-format v2
```

[业务示例](examples/business/README.md) 覆盖五个支持输入和一个拒绝输入。样本为注明来源的作者自建组合文档，真实第三方采用尚未确认。CLI `prepare INPUT` 可保存计划，再以 `rebuild INPUT --plan PLAN.json` 执行；每个字段均独立重算。

建议使用 `--receipt-format v2`。0.3 更新配置、规则和工具标识；旧报告需用对应版本验证，或基于真实文件重新生成。独立客户端/完整格式检查在 SDK 中为 NotChecked，不沿用历史 Pass。

输出与报告不覆盖已有文件，临时输出从磁盘重新验证后配套发布；两个路径不保证事务原子性。退出码：0完成，2完整性/保留/报告不符，3不支持/不完整/资源拒绝，4文件读写或用法错误。缺少原件时保留检查NotChecked、整体Incomplete、退出3。

输入上限32MiB、输出64MiB；其他限额见公开 Limits。数值仍为实验值，SDK完整工作预算/取消接口尚缺；CLI每次worker调用超时60秒。较大输入可先 `moon build --release --target native --deny-warn`，CLI加 `--release`。私有worker不能绕过有界CLI直接用于不可信路径。

## 验证与兼容性

固定工具链 `moonc 0.10.14+7d59c7ec9`，依赖见 [锁定记录](docs/dependency-lock.json)。Windows Native/MSVC：

```powershell
python -m pip install jsonschema==4.23.0
.\tools\check.ps1
python tests/independent_business.py
```

CI将本次实际生成的输出交给独立ZIP/XML与Open XML SDK检查，报告保存为Actions artifacts。WPS本地验证三份表格与两份Word输出的读取、编辑、另存和重开；Word保存副本仍有三处WPS生成的styles顺序错误，不能视为格式通过。原始输出与客户端保存副本分开记录。

[架构](docs/architecture.md)、[威胁模型](docs/threat-model.md)、[保留契约](docs/preservation-contract.md)、[报告格式](docs/receipt-v2.schema.json)。Schema只约束形状；完整核验需要真实原件和输出。申报书、交接、工作记录与截图仅在本地维护。

## 许可与来源

Apache-2.0。运行时复用 flate0.8.4、Milky2018/xml0.5.0、moonbitlang/x0.5.5。上游测试数据来自XlsxWriter（BSD-2-Clause）与Apache POI（Apache-2.0）；新增布局和图片为自建，宏字节及其原始来源许可保留。见 [第三方说明](docs/third-party.md) 和 [样本来源](tests/fixtures/business/README.md)。未移植Python/Java Office核心，未分发WPS或用户文档。
