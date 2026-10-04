# Changelog

## 0.2.0-spike（2026-10-04）

- 受限 DOCM→DOCX VBA 移除，保护共享依赖和正文 payload；真实 Word fixture 与独立校验通过。
- source-local 关系/XML 图、结构化能力与覆盖报告；未知/未检查不推导为 Absent。
- PreparedPlan 绑定 hash/限额/决策/依赖，saved plan 独立重算后执行。
- typed v2 Receipt，从实际输出重建图并验证全部 part 去向/hash；独立客户端为 NotChecked。
- 复用验证事实减少重复解析；CLI 可选 Release 构建，Receipt JSON 类型/重复键/资源防线。
- 输入与输出使用各自 byte limit，合法增长不误拒绝，超限仍返回 Incomplete。

实验版本已发布 Mooncakes，发布源码双 job CI 和独立注册表消费者通过。source XML handler、外部能力/OLE/ActiveX 与真实下游尚未完成；WPS Word 保存副本有三个 styles 顺序错误，资源数值仍 provisional。

## 0.1.0-spike（2026-10-04）

- 首个真实 XLSM VBA → XLSX 技术闭环。
- 有界 ZIP/XML、CRC、关系/引用一致性、严格配置拒绝。
- MoonBit audit/plan/rebuild/verify SDK、Python 有界宿主 CLI。
- 原型 Receipt、所有部件去向和 payload hash；原件/输出/Receipt 篡改回归。
- 独立 ZIP、Open XML SDK 和 WPS 客户端证据。
- TODO-1：解析截断/资源超限明确为 Incomplete；SDK 配置边界、完整 token/属性限额与虚报解压大小回归通过。

不含 DOCM、外链、OLE/ActiveX handler，不承诺通用 Office 兼容；已发布到 Mooncakes；GitHub CI 与从注册表安装的 SDK 验证通过。
