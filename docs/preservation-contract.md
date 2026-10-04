# 原型保留契约

对象为解压后的 part payload，不是 ZIP 容器的 bytes。

| 输入部件 | 去向 | 检查 |
| --- | --- | --- |
| 已支持 VBA 项目 | RemovedByPolicy | 精确类型+关系；单入边；无 companion；输出不存在 |
| workbook 关系部件（有 VBA 时） | RegeneratedMetadata | 除 VBA relation 外关系字段一致；从输出重新解析 |
| Content Types（输入主类型 XLSM 时） | RegeneratedMetadata | 删除 VBA 映射，将主 workbook 类型改为 XLSX，其余映射保留 |
| 其余输入部件 | BytePreserved | 每个 payload SHA-256 相等，禁止新增/漏失 |

此配置没有 SemanticallyRewritten 正文部件；不把不存在的正文 handler 列为完成。工作簿和工作表包括 codeName 的 XML bytes 保留，VBA 关系为隐式关联，无需删源 XML 节点。

允许损失只有 VBA 项目及其宏功能、macro-enabled 主类型。普通单元格/工作簿/样式/主题/文档属性 payload 必须保留。不支持的图片、对象、外链、公式或扩展直接拒绝，不以文本存在推导视觉保真。

完整 verify 需要原文件。从原件重新生成预期有限修改，重新读取实际输出、核验每个 input part 去向。Receipt 与重新计算结果须完全一致，不能只信任其 Pass 或 hash。无 original 时脚本报告 preservation NotChecked、整体 Incomplete，退出 3。

发布先将文档临时文件写在输出文件系统，从实际文件重新 verify；再发布文档、最后发布带 `publication: pair-complete` 的 Receipt。使用 exclusive hard link 防止覆盖。任一步失败返回非零并报告回滚/清理。不承诺两路径事务原子性，也不承诺停电后 fsync 级目录持久化；消费者只接受存在且 hash 匹配的完整文件对。

## main 开发版 Word VBA 契约

`simple-word-vba-dev-v1` 使用同一图/引用索引和验证管线。DOCM 的单一实际 VBA 项目、其专属 relationship part、至多一个由 `wordVbaData` 关系独占的 supporting XML 为 RemovedByPolicy；主 document 的 VBA 关系和 Content Types 是 RegeneratedMetadata。正文、样式、设置、字体、主题、属性等其他 payload 必须 BytePreserved。共享项目/元数据、原有孤儿 VBA、保留 XML 引用、未知 companion 均拒绝；不做通用孤儿 GC。

真实 fixture 的 14 个 parts 中删除 3 个、重写 2 个元数据、保留 9 个。源正文没有 VBA relationship ID，因此没有正文语义改写。宏启用类型没有实际 VBA 时仅转换主类型，不制造 finding。输出必须为实际 DOCX 主类型且使用 .docx 扩展名。Word schema/规则标为开发版，尚未进入已发布 0.1.0-spike；完整 typed Receipt 仍属 TODO-6。

WPS 保存副本属于客户端重写，不属于 PartSieve 的 BytePreserved 契约。该 Word 副本正文一致、可以重开，但独立 SDK 发现 styles 中三个元素顺序错误，见 [Word handler 报告](word-vba.md)；不得把客户端另存副本当成 PartSieve 完整 verify 成功产物。
