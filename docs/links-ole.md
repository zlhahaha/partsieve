# HTTP(S)点击链接与受控Word OLE（0.5.0-spike）

Word正文、页眉、页脚和Excel工作表中的来源局部HTTP/HTTPS点击链接可以保留。文字、格式、目标和非重写部件的数据保持原样，不进行DNS查询、下载或跟随重定向。报告的`allowed_capabilities`明确列出保留的点击能力，`output_findings`不能据此声称所有外部目标均消失。

首批URL范围为ASCII DNS/IPv4主机和可选1–65535端口；拒绝凭据式地址、IPv6、其他协议、内部书签与不明确的引用。Excel单元格/范围必须在A1–XFD1048576内。Word普通链接不包含字段式链接或嵌套链接。

Word OLE首批支持一个正文运行中的`w:object`：一个`o:OLEObject Type="Embed"`与匹配的VML shape/preview，可带已建模的局部shapetype定义。CFB载荷需由`oleObject`关系及受支持的内容类型共同声明，预览为PNG/JPEG/EMF。程序不打开、执行或递归清理嵌入内容。

**对象及其专属预览图会一起消失，嵌入对象的内容与编辑能力会丢失。** 只有这两个内部文件及专属关系可被删除；未知子树/属性、共享载荷或预览、额外依赖、链接型OLE、多对象、Excel OLE、ActiveX继续拒绝。主文档其余元素、属性、文字与关系独立复核，其他图片和表格不因此授权修改。允许删除的VML子树不扩大一般VML支持。

```powershell
moon build --target native --deny-warn
moon run tests/next --target native --deny-warn
# tests/generated/next-v6 下生成六组组合样本、处理结果、计划与报告。
moon run cmd/main --target native -- verify tests/generated/next-v6/word-ole-emf.docx --original tests/generated/next-v6/word-ole-emf.input.docm --receipt tests/generated/next-v6/word-ole-emf.receipt.json --receipt-format v2
python tests/independent_business.py --next tests/generated/next-v6
```

新场景按`business-word-v2`或`business-spreadsheet-v2`进入链接/OLE规则，原业务v1回归保持原有行为。PreparedPlan逐项重算，XML修改必须有对应决策、前后摘要与依赖；输出重新读取后核对。独立Schema与客户端在SDK报告中继续为NotChecked。

组合输入沿用作者自建业务布局。OLE载荷、EMF预览及对象XML来自固定Apache POI测试文档`EmbeddedDocument.docx`，仅做静态提取；来源、变换和hash见`tests/fixtures/poi/provenance.json`，保留Apache-2.0 LICENSE/NOTICE。组合样本不是外部采用证明。

模型参照：[Word Hyperlink](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.hyperlink)、[Spreadsheet Hyperlink](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.spreadsheet.hyperlink)、[Office OLEObject](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.vml.office.oleobject)。这些说明不是完整Office兼容性或文档安全证明。
