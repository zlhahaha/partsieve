# Changelog

## Unreleased

- TODO-2：共用 PackageGraph/XmlReference、source-local 与入出边/内容类型索引、隐式 VBA 关系、迭代可达性与只报告的孤儿候选。
- 新增 `inspect_graph` SDK 与有界 `graph` CLI，未知扩展显式报告覆盖缺口；新增 7 个单元测试和 11 项图宿主检查。


## 0.1.0-spike（2026-10-04）

- 首个真实 XLSM VBA → XLSX 技术闭环。
- 有界 ZIP/XML、CRC、关系/引用一致性、严格配置拒绝。
- MoonBit audit/plan/rebuild/verify SDK、Python 有界宿主 CLI。
- 原型 Receipt、所有部件去向和 payload hash；原件/输出/Receipt 篡改回归。
- 独立 ZIP、Open XML SDK 和 WPS 客户端证据。
- TODO-1：解析截断/资源超限明确为 Incomplete；SDK 配置边界、完整 token/属性限额与虚报解压大小回归通过。

不含 DOCM、外链、OLE/ActiveX handler，不承诺通用 Office 兼容；已发布到 Mooncakes；GitHub CI 与从注册表安装的 SDK 验证通过。
