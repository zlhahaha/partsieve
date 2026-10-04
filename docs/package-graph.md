# OPC 图与 XML 引用事实模型

TODO-2 的开发实现位于 GitHub main；已发布的 `0.1.0-spike` / `v0.1.0-spike` 尚不包含新增 `inspect_graph` API。发布版本来源仍以标签和发布记录为准。

```powershell
moon build --target native --deny-warn
python tools/partsieve.py graph tests/fixtures/upstream/macro01.xlsm --json
python tests/graph_regression.py
```

SDK `inspect_graph(bytes, limits?)` 返回 `partsieve.graph.v1`。它只检查有界 ZIP/XML、OPC 目标与局部 XML 引用，不授权重建。`coverage_gaps` 为空也不表示通过支持配置、内容能力或保留契约检查；使用 `audit/plan/rebuild/verify` 判断当前支持配置。结构损坏、悬空引用、超限会明确失败，不能通过图接口绕过。

## 事实与索引

- Part 使用现有 `PartRecord`：规范部件名、实际解析的内容类型、payload SHA-256。
- 虚拟 package-root 为 `/`，与实际 ZIP 部件区分。`nodes` 中包含 root、每个 part 的 inbound/outbound relationship 数组索引和其 XML 引用索引。
- `relationships` 保留 source、局部 ID、Type、原始 Target、规范化的 resolved 与 external。external 的 resolved 为 `""`，没有内部 inbound edge，也不加入可达队列。
- `xml_references` 按部件名、XML 元素前序及属性顺序稳定排列。只按 namespace URI + local name 识别关系属性 `id/embed/link`，不依赖 `r` 前缀。记录源部件、元素索引、深度、元素 namespace/local name、属性 local name、局部 ID 和绑定的 relationship index。
- 局部 ID 只查询所属 source 的关系表；不查 root 或其他 part。重复局部 ID、缺失内部目标和悬空 XML 引用明确拒绝。
- `content_types` 按类型排序，包含从 Default/Override 解析出的全部实际 part，组内名字排序。
- `implicit_references` 保存 package 元数据关系，以及已支持 workbook 类型的 VBA/styles/theme/sharedStrings 隐式关系事实。保留样式和共享字符串原有索引，不作索引重排；这不是完整 SpreadsheetML 索引有效性校验。

`audit/rewrite/verify` 均通过同一 loader 建立这份事实模型：VBA 入边、profile 中的目标和 source-local XML 绑定使用索引，verify 比较实际重解析的完整图与计划所得预期图。现有 Audit/Receipt JSON 的字段形状保持兼容；图作为单独 SDK/CLI 结果暴露。

## 遍历、覆盖与保留

从 `/` 进行迭代遍历，每个 source 只访问一次，支持循环；external 不参与内部遍历。`[Content_Types].xml` 属于 package 元数据，`.rels` 属于其 source；对应 source 可达时，metadata 也标可达。未可达的 payload 为 `orphan_candidates`。原有孤儿只报告，受支持且不禁止的 payload 仍原样保留，绝不因遍历结果自动 GC。

AlternateContent、VML、未知元素/属性 namespace、ext/extLst 和未知关系语义产生 `coverage_gaps`。支持配置还会进一步拒绝未知形状、未支持能力、关系/内容类型冲突等，不能将图的结构信息当作安全结论。当前 OPC ASCII URI 子集、UTF-8、ZIP/XML 限额继续适用；新增整个包最多 32,768 个 XML 关系引用，超限为 Incomplete。统一 Capability/Coverage/Decision 输出属于 TODO-3。

## 验收证据

7 个新增单元测试覆盖 source scope、namespace alias、id/embed/link、错误 namespace、缺失目标、重复 ID、external、Content Type index、metadata 所有权、隐式 VBA、4096 part 链加循环、覆盖缺口、32,768 个引用的精确边界和加一。

11 项公有宿主集成检查使用固定真实 XLSM 和人工变体：audit/graph facts 一致、重复稳定、实际 worksheet 绑定、完整索引、VBA 可达、绝对/相对目标、external 不产生内部边、已支持孤儿 payload 经 rebuild/verify 字节保留、AlternateContent/VML/ext 明确缺口。证据为 `docs/evidence/graph-regression.json`。这些人工变体不增加客户端兼容样本覆盖。
