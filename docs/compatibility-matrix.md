# 实际兼容矩阵（2026-10-04）

| 配置/能力 | Audit | Rebuild | Verify | 独立校验 | 客户端 |
| --- | --- | --- | --- | --- | --- |
| simple-spreadsheet-spike-v1 / 真实 macro01.xlsm VBA | 支持 | XLSM → XLSX，删除 VBA | 原件+输出+Receipt | Python ZIP/XML、Open XML SDK 3.3.0 Office2007 Pass | WPS 12.1.0.28505 打开、保存、重开，A1=123；UI 无修复提示 |
| 同配置 / simple01.xlsx 干净控制 | 支持 | 部件 payload 原样保留 | 同上 | Open XML SDK 3.3.0 Pass | 未单独 UI 检查 |
| 同配置 / macro-enabled 无 VBA | 主类型与 VBA 证据分开报告 | 转换类型 | 支持 | 人工变体回归 | 未单独客户端检查 |
| 同配置 / VBA 改名、namespace prefix、绝对 target | 支持 | 支持 | 支持 | 人工变体回归 | 未逐项客户端检查 |
| main 开发版 simple-word-vba-dev-v1 / 真实 SimpleMacro.docm | 支持受限声明检查 | DOCM → DOCX；项目及独占 supporting 元数据共删 3 parts | 原件+输出+临时 Word Receipt；9 payload 保留 | Python ZIP/XML、Open XML SDK 3.3.0 Office2007 Pass | WPS 12.1.0.28505 输出可见打开，无修复提示；保存/重开正文一致 |
| WPS Word 保存副本（客户端产物） | 不承诺支持 | 不属于 PartSieve 重建输出 | 不属于原输入的保留契约 | **Open XML SDK Fail：styles.xml 三处 uiPriority 顺序错误** | 可重开，正文一致；UI 因 COM 占用使用只读打开，无修复提示 |
| main Word 配置 / 衍生干净 DOCX、无 VBA 的 DOCM、改名和绝对 target | 支持 | 支持有限转换；干净 payload 保留 | 支持 | 人工/衍生回归 | 未逐项客户端检查 |
| 真实 SampleDoc.docx（含 customXml）、其他 Word 功能；外链、公式、hyperlink、图片、OLE、ActiveX、未知扩展 | 结构化 assess 检出声明/缺口；重建拒绝 | 不支持 | 不支持完整契约 | 拒绝回归 | 不承诺 |

首个真实样本只有一个数字单元格，不含图片。WPS 客户端证据经用户指定纳入验收；没有声称 Microsoft Excel/LibreOffice 已测试。WPS 保存副本通过 SDK 格式校验和 A1 检查，但客户端重写不属于 PartSieve 的 BytePreserved 契约。

上一段 WPS 保存副本指 XLSX；Word 保存副本的独立失败在上表明确列出。Word 主体也是简单单段，无图片或复杂布局证据。Word 支持只在 GitHub main 0.2.0-dev，尚未发布 Mooncakes；完整矩阵验收 TODO-12 未完成。
