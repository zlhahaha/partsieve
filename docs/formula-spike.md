# 公式与计算链决策

0.9.1 维持公式和 calcChain 拒绝。固定语料中的 `SimpleNormal.xlsx` 包含同表引用
与 `SUM(A3:D3)`，`Booleans.xlsx` 包含布尔函数，`DateFormatTests.xlsx` 包含带
缓存的共享 `TEXT` 公式和计算链。即使去掉首个 calcChain 关系，公式仍需独立处理。
其余研究样本 `FormulaSheetRange.xlsx`、`TestShiftRowSharedFormula.xlsx`、
`link-external-workbook-b.xlsx` 来自同一 Apache POI 固定提交，Apache-2.0。
前两份提供跨表范围和共享公式，后者包含外部工作簿关系和公式。生成的本地引用、
WEBSERVICE、DDE 风格和 INDIRECT 负例来自固定 `styles.xlsx` 的 XML 注入，
由仓库 Apache-2.0 测试脚本生成。各输入哈希、公式、缓存、计算链条目、
关系和 CLI 结果见 [机器报告](https://github.com/zlhahaha/partsieve/blob/main/tests/external/formula-spike-0.9.0.json)。

实验只读取实际存储的公式与缓存，不启动客户端执行外部数据或未知表达式。
分类将有限本地表达式记为 Formula、外部工作簿或已知访问样式记为 ExternalData、
共享公式及其他表达式记为 Unknown。实验分类器只解释选定样本；生产决策仍统一拒绝。
对本地公式原字节保留，需要有界检查工作簿/工作表身份、引用、公式属性和 calcChain
条目，独立排除外部数据，并验证目标客户端打开与另存行为。仅检查 `<f>`
或缓存存在都不能建立这一结论。现有证据不足以启用声明的子集。

## 原件客户端复测

对只包含本地公式的固定 `SimpleNormal.xlsx` 用 Excel 16.0.20527 与 WPS 表格
12.1.0.29161 打开、另存、重开。两者保留 A7 的 `SUM(A3:D3)` 与缓存 10、
C7 的 `C3` 与缓存 3。Excel 保留 calcChain 部件和工作簿关系，
WPS 另存件删除两者。对含连接、外部工作簿、DDE 风格及网络函数的负例只运行 CLI，
全部拒绝，输出和回执均未生成。
