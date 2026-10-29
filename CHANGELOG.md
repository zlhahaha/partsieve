# Changelog

## Unreleased

- Add the Native `batch INPUT_DIR -o NEW_OUTPUT_DIR` command: bounded top-level discovery, deterministic filename order, independent document/receipt verification, per-file success/refusal/failure/skip records and a persisted JSON summary. Continue after individual failures and refuse existing output directories.
- Add real CLI batch regressions to Windows/Linux CI, including mixed valid/invalid inputs, output protection, names with spaces/Chinese characters, colliding stems, the 1024-entry boundary and platform-dependent link/special-file fixtures. No new Office content profile or Mooncakes publication in this batch.

## 0.7.1-spike（2026-10-28）

- Ship the fixed acceptance-demo runner, Chinese walkthrough and a small provenance-pinned three-OLE input in the published package, without requiring the excluded development fixture generator.
- Run the demonstration in Windows/Linux CI; record saved-plan rebuilds, actual-file verification, ordinary-text tampering rejection and unsupported-input refusal without successful outputs.
- Office support profiles, public SDK signatures and output document bytes remain unchanged. Receipts use the new tool version and must be regenerated from actual files.
- WPS multi-object client validation remains deferred by the user; this release adds no new client compatibility claim.

## 0.7.0-spike（2026-10-25）

- Remove up to 32 independent inline Word OLE objects with private CFB payloads, PNG/JPEG/EMF previews and source-local relationships; retain ordinary text between objects and all unrelated content.
- Parse the validated object catalog once per package. Reject shared targets/references/identities, nested objects, linked/unknown objects, wrong relationship kinds and a 33rd object. ActiveX and Excel OLE remain unsupported.
- Bind each object's deletions to its own finding decision, with a single source/metadata writer and checked dependencies; multi-object plans use bounded-links-ole-plan-v2. Keep the single-object path and public SDK signatures.
- Add four multi-object combinations, ten refusal cases, forged-plan/output tampering and independent source/output ZIP/XML/Schema/OpenXML checks, plus five core identity/catalog/range unit tests.

## 0.6.0-spike（2026-10-25）

- Add optional shared WorkControl to every document SDK entry point, with sticky cancellation, cumulative work accounting, overflow-safe pair reservations and no successful return after stopping.
- Connect ZIP cancellation and XML scan/event checkpoints; bound graph/profile/plan/execution/actual-output verification across repeated internal passes. Keep serialized Limits unchanged; runtime work units are not a heap or wall-clock guarantee.
- Add a runnable resource example, nine unit regressions and a Windows/Linux resource matrix: Word text near 1/4/7 MiB, 5,000/20,000-row sheets, work/input/output boundaries, ZIP/XML cancellation and two oversized XML refusals.
- Preserve existing Office profiles and document outputs. Reports use the new tool version; regenerate them from actual files or use the corresponding old version.

## 0.5.0-spike（2026-10-24）

- Preserve source-bound HTTP(S) click hyperlinks in Word body/header/footer and Excel worksheet ranges; report allowed clicks separately and never fetch their targets.
- Remove one validated inline Word embedded OLE object, its exclusively owned CFB payload and PNG/JPEG/EMF preview. Reject shared/linked/unknown objects and ActiveX; unrelated Word semantics and all other payloads are verified.
- Extend prepared-plan closure/dependencies, source rewrite verification and typed/legacy report schemas; retain the existing v1 business path and historical command corpus.
- Add six combined scenarios, 36 refusal cases, public CLI saved-plan/actual-file checks, URL tampering and forged-Receipt checks, plus independent ZIP/XML/Schema/OpenXML validation.

## 0.4.0-spike（2026-10-23）

- MoonBit Native CLI replaces the Python runtime host; a small original C adapter provides filesystem/process syscalls for Windows and Linux.
- Preserve bounded reads, private snapshots, worker timeouts, capped stdout, exclusive publication and identity-checked rollback. Reject non-finite JSON numbers and distinguish boolean from numeric Receipt fields.
- Migrate seven Python regression drivers to 293 native command replays with pinned input states and exact report/document expectations; add host resource and argument boundary tests.
- Keep only three independent Python ZIP/XML/JSON Schema validators. Move dependency and fixture checks/evidence export to PowerShell; exclude the development corpus from Mooncakes packages.
- OOXML support profiles and document output bytes are unchanged; reports carry the new tool version and need regeneration for verification with this release.

## 0.3.0-spike（2026-10-22）

- 业务表格配置：共享/内联中文文本、1900/1904日期、多工作表、常见样式与合并；补样式/共享字符串索引检查。
- Word表格、合并单元格、内嵌PNG/JPEG、两节独立页眉页脚及图片引用保留。
- 一个settings本地HTTP(S)外部模板的XML/关系同步移除；计划依赖、预期hash、实际输出语义核验与SemanticallyRewritten报告贯通。
- 新增固定来源的自建业务样本、SDK业务示例、拒绝/篡改回归与独立ZIP/OpenXML CI。
- 配置、规则、报告工具标识更新；旧报告需要对应版本或从真实文件重新生成。
- 五份输出完成WPS编辑、另存和重开；Word保存副本仍有三处客户端生成的样式顺序错误，保留该限制。

未声称OLE/ActiveX移除、完整DocBleach功能对等、真实第三方采用或通用Office安全。

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
