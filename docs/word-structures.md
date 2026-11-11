# Word 脚注、尾注、编号与常见样式（主分支，未发布）

本轮补齐普通 Word 结构的有界保留支持。核心实现是 MoonBit 的
[`word_structures.mbt`](../word_structures.mbt)，不是对其他语言 Office 库的封装。
已发布 0.8.0-spike 不含这些扩展；请使用本次源码构建，不能把新的支持范围写成已发布功能。

## 范围与引用契约

| 内容 | 支持和检查 | 仍拒绝 |
| --- | --- | --- |
| 脚注/尾注 | 各一个正文拥有的内部部件；普通文字、段落、受支持表格；正文引用绑定对应正常定义；设置中的分隔符引用绑定对应特殊定义 | 重复/悬空/跨部件引用、孤立正常定义、类型错配；注释内图片/链接、字段等未支持内容 |
| 分隔符 | `separator`、`continuationSeparator`；支持现代 `-1/0` 和旧文档 `0/1` ID 布局；每类最多一个定义 | 重复特殊类型、重复设置引用、分隔符标记与定义类型不一致 |
| 显式列表编号 | 正文/样式中 `numPr` 的实例 ID → 抽象定义 ID → 0–8 层级；多级普通格式、原有缩进与编号文本；起始值及已定义层级覆盖 | 缺失/重复实例或抽象 ID、悬空层级、重复/错绑覆盖；无显式实例的继承配置、样式链接、图片项目符号、未知格式 |
| 常见样式 | 标题大纲级别、字距、复杂文字粗体/斜体、段落制表位/边框、段落标记字符属性、页眉页脚位置制表符等已建模内容保留 | 错命名空间/位置、越界大纲级别、不合法位置制表符配置、未知扩展 |
| 辅助属性 | Word 文档属性的 HeadingPairs/TitlesOfParts 类型化向量，核对类型、子元素与 size；有限的只影响文档保存/显示的设置标记 | 向量计数/类型冲突、资源属性、未知兼容模式或字段；未知设置仍拒绝 |

数字 ID 规范化后再判重，`2` 与 `02` 不会被当成不同定义。
正文引用不能指向分隔符；脚注与尾注引用不跨类型查找。
这些是内部引用模型，未新增外部获取行为，也不计算编号或渲染脚注布局。
普通内容保留原始内部文件字节；VBA 删除与宏容器类型转换沿用已有重建/核验流程。

参考规范说明：[脚注 ID 与引用](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.footnoteendnoteseparatorreferencetype.id)、
[抽象编号定义](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.abstractnum)、
[层级与覆盖](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.level)、
[位置制表符](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.positionaltab)。

## 实际验证

新增自建固定输入 `tests/fixtures/business/document-notes-lists.docm`，来源与 hash
写入原有 provenance。包含中英文正文、普通脚注/尾注、各自两类分隔符、两级编号、
起始值覆盖及标题样式；VBA 原字节复用已固定许可的 Apache POI SimpleMacro.docm，未执行。
它是组合测试文档，不是真实客户或独立采用者的文件。

```powershell
moon run cmd/main --target native -- rebuild tests/fixtures/business/document-notes-lists.docm -o NEW.docx --receipt NEW.json --receipt-format v2
moon run cmd/main --target native -- verify NEW.docx --original tests/fixtures/business/document-notes-lists.docm --receipt NEW.json --receipt-format v2
```

输出 SHA-256：`e0e64150b3810d75119d3474a3df14161fc6776e7660788faf7a6047277b8efa`。
CPython 独立 ZIP/XML 检查证明保留原始普通内部文件并逐项核对脚注、尾注与编号；
Open XML SDK 3.3.0 / Office2007 对最终原件、输出均通过。
首次生成样本的样式元素顺序错误被独立检查检出后已修正，未沿用失败文件的哈希或通过结论。

完整固定工具链检查通过，79 个 MoonBit 测试通过；原有链接/OLE、健壮性、授权、批处理、
资源和演示流程继续通过。12 个新增变体触发拒绝且未生成输出或成功回执。
独立检查包括 6 组业务样本、10 组链接/OLE 和 5 组脚注及编号样本，共 21 组。
这只是本地运行结果，未声称已运行远端 CI 或新增客户端打开/编辑/另存结论。

## 第三方语料的实际增量

2026-11-11，初始 20 份 Apache POI 原件支持数从 6 份增至 7 份，新增 `HeaderFooterUnicode.docx`。13 份拒绝，处理失败为 0。

额外五份 Apache POI 原件全部通过重建。独立 ZIP/XML 校验逐份核对完整文件哈希、内部文件字节、脚注和尾注正文引用、编号层级及两个编号格式分支。

| 原件 | 本轮保留内容 |
| --- | --- |
| `footnotes.docx` | 普通脚注正文、分隔符和空 APA 参考文献数据 |
| `endnotes.docx` | 普通尾注正文、分隔符、空 APA 参考文献数据和网页布局属性 |
| `Numbering.docx` | 多级编号、自定义编号格式及十进制后备分支 |
| `NumberingWOverrides.docx` | 36 个抽象编号、37 个实例、9 个覆盖以及 Office 2013 主题和样式筛选设置 |
| `NumberingWithOutOfOrderId.docx` | 按标识查找编号定义以及 Office 2013 文档标识 |

Office 2013 校验通过全部五组原件和输出。Office 2007 校验通过四组，`NumberingWOverrides.docx` 的原件和输出都报同样的 15 个样式筛选属性错误。五份输出的 SHA-256 均与原件相同。

兼容标记通过作用域中的命名空间绑定识别。编号格式的 Choice 与 Fallback 都经过校验，空 APA 数据只支持固定内置样式标识和内部属性关系。完整编号覆盖可以提供新的层级定义，起始值覆盖须有相应层级。未知扩展、资源关系和字段仍触发拒绝。

五份原件固定在 `tests/fixtures/poi/word-modern/`，来源和哈希记入 POI provenance。`tools/check.ps1 -Offline` 生成文件和回执，CI 对这些结果运行独立 ZIP/XML 与 Office 2013 检查。规范参见 [标记兼容性](https://learn.microsoft.com/en-us/office/open-xml/general/introduction-to-markup-compatibility)、[编号扩展](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-docx/0f4109a2-ad35-41e2-9d8d-5478397abac4)和 [APA 样式属性](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.bibliography.sources.selectedstyle)。
