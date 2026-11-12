# Office 客户端编辑复测

2026-11-13，Windows 11 23H2 x64（10.0.22631）。
Microsoft Word/Excel 16.0.20527.20150，WPS Office 12.1.0.29161。
用桌面客户端 COM 对象实际打开、修改、另存和重开，强制禁用宏并关闭链接更新。
检查涵盖客户端读取的内容和结构；本轮未做逐页视觉对照。

```powershell
# 先按 README 构建 Native CLI。可选的链接原件由 tests/next 生成。
./tools/check-office-clients.ps1 `
  -Cli ./_build/native/debug/build/cmd/main/main.exe `
  -OutputDirectory PATH_TO_NEW_DIRECTORY `
  -WordLinkInput PATH_TO_WORD_LINKS_INPUT_DOCM
```

`original/` 是原件副本，`partsieve/` 是实际 CLI 输出与已核验回执，
`client/` 是客户端编辑另存件。运行生成 `client-matrix.json`，记录各阶段哈希、客户端版本、属性差异和持久化结果。

| 样本 | 对原件和清理件分别执行 | 结果 |
| --- | --- | --- |
| document-template | Word/WPS Writer 插入正文标记 | 重开保留编辑；正文、表格、图片、两节的页眉/页脚和样式观测值一致 |
| document-notes-lists | Word/WPS Writer 插入正文标记 | 重开保留编辑；脚注、尾注及编号观测值一致 |
| report-1900 / report-1904 | Excel/WPS 表格修改 A7 | 重开保留编辑；工作表名、合并区域、填充、字重、金额格式和日期显示/序列值一致 |
| word-links | Word/WPS Writer 插入正文标记，未点击链接 | 两者保留目标。Word 另存保留关系型链接，WPS Writer 对原件和清理件均转成 HYPERLINK 字段 |

Open XML SDK 3.3.0 / Office2013 对四组业务原件和 PartSieve 清理件通过。
WPS Writer 另存 `document-template` 与 `document-notes-lists` 的两条输入路径均产生
`styles.xml` 子元素顺序错误，首个意外元素为 `uiPriority`。Microsoft Word 另存件通过该检查。
独立解析 `word/document.xml` 证实 WPS 的关系链接转换发生在客户端另存，PartSieve 输出仍有原关系型链接。
按现有字段拒绝策略，WPS 另存后的链接文件可超出 PartSieve 处理范围。

[机器可读结果](https://github.com/zlhahaha/partsieve/blob/main/tests/external/office-clients-0.9.0.json)
