# 实际兼容矩阵（2026-10-04）

| 配置/能力 | Audit | Rebuild | Verify | 独立校验 | 客户端 |
| --- | --- | --- | --- | --- | --- |
| simple-spreadsheet-spike-v1 / 真实 macro01.xlsm VBA | 支持 | XLSM → XLSX，删除 VBA | 原件+输出+Receipt | Python ZIP/XML、Open XML SDK 3.3.0 Office2007 Pass | WPS 12.1.0.28505 打开、保存、重开，A1=123；UI 无修复提示 |
| 同配置 / simple01.xlsx 干净控制 | 支持 | 部件 payload 原样保留 | 同上 | Open XML SDK 3.3.0 Pass | 未单独 UI 检查 |
| 同配置 / macro-enabled 无 VBA | 主类型与 VBA 证据分开报告 | 转换类型 | 支持 | 人工变体回归 | 未单独客户端检查 |
| 同配置 / VBA 改名、namespace prefix、绝对 target | 支持 | 支持 | 支持 | 人工变体回归 | 未逐项客户端检查 |
| DOCM/DOCX、外链、公式、hyperlink、图片、OLE、ActiveX、未知扩展 | 拒绝并报告原因，非完整审计 | 不支持 | 不支持 | 拒绝回归 | 不承诺 |

首个真实样本只有一个数字单元格，不含图片。WPS 客户端证据经用户指定纳入验收；没有声称 Microsoft Excel/LibreOffice 已测试。WPS 保存副本通过 SDK 格式校验和 A1 检查，但客户端重写不属于 PartSieve 的 BytePreserved 契约。
