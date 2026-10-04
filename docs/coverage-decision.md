# Capability、Coverage 与 Decision

TODO-3 的新增 API 位于 GitHub main，尚未包含在 Mooncakes `0.1.0-spike`。保留原型 Audit/Receipt 的兼容 JSON；新的 `assess(bytes, limits?) -> Assessment` / 有界宿主 `assess` 是完整能力与覆盖结果接口。`audit/plan/rebuild/verify` 使用同一 `profile_decision` 强制执行重建门槛，不能绕过 Unsupported/Incomplete 决策。

```powershell
moon build --target native --deny-warn
python tools/partsieve.py assess tests/fixtures/upstream/macro01.xlsm --json
python tests/coverage_regression.py
```

## 独立表达证据、覆盖与权限

`CapabilityFinding` 包含 rule ID、能力、证据来源/目标、certainty、rebuild support status 和可追溯元数据证据。Declared 表示存在对应声明，不证明宏行为、网络实际访问或恶意性；Unknown 表示类型或扩展语义不透明。相同能力/目标的声明证据合并，不以找到一个已知能力掩盖另外的不透明部件。

覆盖记录独立包含每条规则的 `state`、`presence`、重建支持范围和原因：

| state | presence | 含义 |
| --- | --- | --- |
| Checked | Present | 找到声明证据；不自动允许改写 |
| Checked | Absent | 严格支持配置的检查全部通过，才能在此范围内断言不存在 |
| NotChecked | Unknown | 不支持/未能确立范围，不能从空 finding 推导不存在 |
| Opaque | Unknown | 未知关系、namespace、扩展或部件声明 |
| Incomplete | Unknown | 解析/限额未完成，不产生可发布结果 |

`Coverage` 还包括 declared_profile、checked_rules、unchecked_features、parse_complete 和 parse_error。规则名同 finding.rule_id；检测到正向声明时可以记录该声明，其他未检查规则继续 Unknown。重建能力没有因为发现证据而自动升级。

当前九类规则：VBA、HTTPHyperlink、RemoteTemplate、ExternalResource、ExternalData、OLE、ActiveX、UnknownExternalRelationship、UnknownPotentiallyActiveExtension。普通 HTTP/HTTPS hyperlink 类型与 image/audio/video 的外部资源类型分别分类；URI 字符串仅作证据，绝不访问。Word template/数据/OLE/ActiveX 的声明可识别，不代表这些 handler 或格式已经得到兼容验收。

## Decision 的闭合状态

- Pass：严格 `simple-spreadsheet-spike-v1` 范围成立，允许现有 VBA 变换。输入可以仍有 VBA；Pass 不是“输入已被动化”。
- Fail：已证明的结构/CRC/目标完整性错误，不允许发布。
- Incomplete：解析截断、资源限额、未完成检查，不允许发布。空 findings 的 presence 全是 Unknown。
- Unsupported：不支持的语法、配置或能力，不允许发布。已发现证据继续可报告，未检查能力不会变成 Absent。

`Decision` 明确输出 result、rebuild_allowed、profile、reason。`assess` 不返回 bytes。SDK 重建仍只能在有界实际写出、重解析和完整验证成功后返回 bytes；宿主拒绝时不创建输出/Receipt。

CLI `assess` 返回结构化报告，并以 0/2/3 对应 Pass/Fail/Incomplete或Unsupported；worker 与宿主校验状态和退出码一致，失败报告不会被压成无证据的成功。新增 `SieveError::Invalid` 用于明确的完整性失败；保守 URI/能力拒绝仍用 Refused，无法解析/资源耗尽仍为 Incomplete。其他 I/O/用法错误保持退出 4。

## 验收

3 个新增单元测试覆盖九类能力分类、点击链接与资源获取的区别、Incomplete/Unknown、Fail/Unsupported 与可序列化状态。17 项宿主检查覆盖真实正/负样本、七类 unsupported 关系、未知 XML/二进制/内部关系、截断/非法编码、CRC/缺失目标与拒绝时无产物。人工关系变体只证明分类和拒绝，不增加 Word/OLE/ActiveX 客户端覆盖。

当前 25 单元、48 原有特征样本、17 端到端检查、11 图检查、17 覆盖/决策检查全部通过。已发布原型成功产物和旧 Receipt 的独立重算保持一致；外部格式/客户端证据仍与本工具的 Coverage 分开。

统一 typed Coverage/Decision 已进入核心门槛。旧 Audit/Receipt 只是原型兼容接口；TODO-6 才完成新版本 Receipt 的完整 coverage、decision 和 handler 验证状态，不提前勾选。
