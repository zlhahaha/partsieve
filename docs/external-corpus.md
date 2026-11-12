# 第三方样本兼容性基线

2026-11-11 同批原件的结果为 **7 成功、13 拒绝、0 处理失败**。本轮新增支持 `HeaderFooterUnicode.docx`。
额外五份脚注和编号原件也已全部通过重建。见 [Word 结构扩展](word-structures.md)。

本轮从 Apache POI 固定版本选取 20 份未改造的 DOCX/XLSX/XLSM 测试文档。
文件按名称指示的表格、文本、日期、样式、图片、页眉页脚等功能预选，未按清理成功率筛选。
这是第三方项目回归语料，不能称为客户脱敏业务文件、随机文档总体样本或独立下游采用。
来源、大小、SHA-256 和版本见[固定清单](../tests/external/poi-manifest.json)；Apache-2.0
LICENSE/NOTICE 沿用 `tests/fixtures/poi/` 的完整上游记录，下载时随缓存保留。

| 2026-11-10 首次测量 | 修改前 | 首次修复后 |
| --- | --- | --- |
| 20 份预选输入 | 0 成功、20 拒绝、0 处理失败 | 1 成功、19 拒绝、0 处理失败 |
| 通过所选独立格式检查的 16 份输入 | 0 支持 | 1 支持、15 拒绝 |
| 未通过所选独立格式检查的 4 份输入 | 均拒绝 | 均拒绝 |

格式检查采用 Open XML SDK 3.3.0、Office2007 配置；未通过的是
`Bug66263-table.docx`、`InlineStrings.xlsx`、`TestTableCellAlign.docx`、
`TestTableColumns.docx`。不能据此认定文件在所有客户端无效或恶意。
以上比例只描述本次固定样本，不代表一般办公文档的支持率。

## 首次修复

`SimpleMultiCell.xlsx` 原因是工作表中的 `phoneticPr` 与空 `headerFooter` 被拒绝。
现在支持已建模的注音显示元数据以及仅含合法布尔设置的空页眉页脚容器。
注音字体索引必须绑定实际字体表，类型、对齐和属性命名空间受限；
页眉页脚文字、图片、未知子元素、外部关系等仍不在此项支持内。
规范参照 [PhoneticProperties](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.spreadsheet.phoneticproperties)
与 [HeaderFooter](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.spreadsheet.headerfooter)。

此文件原件和输出均通过上述独立格式检查，CPython ZIP 对比确认 11 个内部文件全部原字节一致，
整个输出 SHA-256 与原件同为
`119b6e70c5bbca6ca3e46f981e0719c154d87203adb4b5b61210d726deab9f7a`。
这是普通无宏 XLSX 的保留兼容性证明，不是新的宏移除证据。
两组新增 MoonBit 回归覆盖配置值、错放、错命名空间、缺失/无效字体、未知内容拒绝与实际重建保留。
这一轮兼容扩展包含于 Mooncakes 0.9.1。

## 可复现检查

在干净检出中按 README 构建本次 Native CLI，然后运行（首次下载需要 `curl.exe`）：

```powershell
./tools/check-external-corpus.ps1 `
  -Cli ./_build/native/debug/build/cmd/main/main.exe `
  -CacheDirectory PATH_TO_NEW_OR_PINNED_CACHE `
  -OutputDirectory PATH_TO_NEW_RESULTS
# 相同缓存复跑时加 -Offline；输出目录仍须全新。
```

脚本核对 20 份文件的大小与哈希，调用实际 CLI 批处理；逐份成功输出再读盘核验，
逐份拒绝/失败检查未发布输出或回执。`result.json` 的 `measurement=Complete`
只表示完成测量，支持/拒绝/失败计数分别列出，不能当成全部通过。
对失败与漂移报错；不修改历史文件，不自动打开原件。
独立 Open XML SDK/CPython 检查是本轮额外执行的步骤，不隐含在该脚本的结果中。
该网络语料测量是显式运行的开发工具，不加入每次默认离线构建。

## 首次测量的拒绝原因

以下只统计首个阻断原因，处理首项后仍可能暴露更多限制，不保证一次放开即支持整份文件。

1. **Word 脚注/尾注与常见样式**：6 份首先受脚注关系阻断；另有标题大纲级别、字号字距等样式需求。
   应建模引用所属正文/脚注及其关系、普通内容和异常反例，再扩大配置。
2. **Word 编号/列表**：1 份首先受编号关系阻断；与文档接收场景相关，需校验定义和引用并验证保留。
3. **Excel 计算链与公式策略**：3 份首先受 `calcChain` 关系阻断。
   不能只放开关系白名单；须先决定普通公式、外部公式、DDE、缓存结果与计算链的一致性边界。
4. **现代样式扩展与其他来源内容**：分开研究未知样式扩展、图片类型、URI 和附加属性。
   不把整个未知命名空间透传来提高成功率。

持续保留全部预选样本的拒绝结果；扩充客户文档时建立另一组经授权、脱敏、有来源的样本，
不能以开源测试文件代替客户文档。当前最紧要的是把普通文档的支持范围做实，再扩展 ActiveX 等活动内容处理。
## 0.9.1 固定基线

20 份原件清单及哈希保持不变。新版工具链迁移后重跑仍为 7 成功、13 拒绝。
加入 Excel 扩展属性 `TotalTime` 后，`styles.xlsx` 新增通过，8 成功、12 拒绝，0 处理失败。
八份输出逐个内部 payload 哈希和整包哈希均与原件一致，实际输出和回执均已读盘核验。

`TotalTime` 是编辑时长元数据。限定为扩展属性命名空间的根节点下最多一个直属叶节点，
由既有包根扩展属性关系绑定，值为 0 至 1,000,000,000 的十进制整数，属性、子元素和任何关系引用均拒绝。
该项的保留价值是保全合法样式报表的原始元数据。放行面仅限数值，不增加客户端外部访问能力。
新增回归覆盖超界、错放、错命名空间、重复和关系注入。

[机器可读矩阵](https://github.com/zlhahaha/partsieve/blob/main/tests/external/poi-matrix-0.9.0.json) 包含原件在 Office2007 / Office2013 的独立 schema 结果、
普通内容清点、首因、图检查报告的全部 gap、独立关系及公式清点、是否有输出和 payload 哈希一致性。
12 份拒绝的首因为公式 3、格式或歧义 3、未知扩展 3、待研究的配置缺口 3。资源拒绝为 0。
对于早期退出的文件，静态清点和图 gap 只能补充已识别的问题；后续配置校验仍可能有遮蔽项。

| 后续候选 | 需求与保留价值 | 风险与复杂度 | 决定 |
| --- | --- | --- | --- |
| Word 页眉原始图片表现 | `headerPic.docx` 的品牌图和显示效果 | 需建模 run 标记、裁切、填充和线条及图片引用 | 保持拒绝 |
| Word 现代样式关系 | `ComplexNumberedLists.docx` 的样式效果和列表 | 必须校验样式变体的独立内容及所有后续扩展 | 保持拒绝 |
| Excel 公式及计算链 | `SimpleNormal.xlsx` 的汇总和本地引用 | 客户端执行语义、共享公式和缓存一致性 | 维持公式拒绝，见公式 Spike |

五份 [脚注、尾注及编号保留组](https://github.com/zlhahaha/partsieve/blob/main/tests/external/poi-notes-numbering-manifest.json) 独立于固定基线，
可复跑现有 `tools/check.ps1` 与独立验证。新的公式研究样本及生成负例来源见 [公式 Spike](formula-spike.md)。
