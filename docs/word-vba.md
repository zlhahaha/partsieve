# Word VBA handler：main 开发配置

TODO-4 使用真实 Apache POI SimpleMacro.docm，在 `simple-word-vba-dev-v1` 内完成 DOCM → DOCX。这不是通用 Word 支持，也不包含在不可变的 Mooncakes 0.1.0-spike 中。

## 真实来源与结果

输入：[固定 POI 源文件](https://github.com/apache/poi/blob/12c3688d130035f3dc2ca2a0f50d929456435a93/test-data/document/SimpleMacro.docm)，15,517 bytes，SHA-256 `fd591958fcf5322f72c0a740e9606309c949254bda4c3d9bd966481ddf220563`。完整上游 LICENSE/NOTICE、公开宏源与来源在 `tests/fixtures/poi/`。静态提取实际 VBA 仅有手动 TestMacro：设置首段文字；原始 DOCM 未在 Office 打开，未运行宏。

输出：[word-verified.docx](evidence/word-verified.docx)，9,029 bytes，SHA-256 `4bb624cf9a6e465b1658c69f6d0bc607ccccf25e2ee1e3048b3e11376d8aa65e`。14 个输入部件中删除 VBA 项目、独占 vbaData.xml、专属关系文件，共 3 个；重写主文档关系与 Content Types 共 2 个；正文、样式、设置、字体、主题和属性等 9 个 payload 字节保留。正文为 `This is a macro word processing document`；页尺寸 12240×15840 保留。

## 支持与拒绝

依据精确 content type、主关系及 Word VBA supporting 关系识别，支持项目/元数据改名和 package-absolute target。主关系必须是项目唯一入边；数据只能由该项目独占。任何共享、孤儿 VBA、保留 XML 引用、未知 companion、外部关系或未允许的 Word 功能会拒绝。原有孤儿不会按可达性自动删除。

配置只允许简单正文、受限被动样式/字体/设置、主题与属性；不允许字段、链接、图片、对象、模板引用、MCE、VML shape、未知属性/命名空间。真实 SampleDoc.docx 含 customXml，因此作为真实不支持负例；无 VBA 不等于支持该文档。干净支持负例是本真实 DOCM 的宏移除输出，明确为衍生样本。

Word app 属性只允许字面 Template `Normal.dotm`。该属性描述创建时使用的模板名称，依据 [Open XML SDK Template](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.extendedproperties.template?view=openxml-3.0.1)；它不能替代 settings 中 attachedTemplate 的外部关系判断。任意路径、URI 或其他模板值拒绝。客户端本地模板环境不在本工具保证内。

## 实际验证与限制

- 29 项 Word 宿主回归覆盖真实正例、衍生干净负例、无 VBA 的宏启用主类型、改名/绝对 target、共享/孤儿、混合能力、未知属性、字段、VML、扩展名错配、实际正文篡改。多数变体为人工拒绝测试，不是额外客户端兼容样本。
- 独立 CPython ZIP/ElementTree 验证删除集合、主类型、全部 payload hash、正文和页尺寸；Open XML SDK 3.3.0 Office2007 对真实原件和 PartSieve 输出均 0 errors。
- WPS 12.1.0.28505 可见打开 PartSieve 输出，没有修复对话框。独立 COM 实例另存、关闭、重开，正文、1 段、1 节保持；UI 再次只读打开保存副本，正文可见、没有修复提示。文件占用提示来自 COM 保持打开，不是修复提示。截图仅保留测试页面与 WPS 工具栏，排除其他个人文档标题。
- **WPS 保存副本有独立格式失败**：`styles.xml` 的 3 个 style 将 uiPriority 放在 qFormat 后，Open XML SDK 报顺序错误。PartSieve 输出原样保留的 styles 通过相同校验。副本可被 WPS 重开不代表其 schema 通过；本项目不修补或掩盖客户端保存问题，也不将它计为 BytePreserved 成功产物。

实际记录见 [Word 回归](evidence/word-regression.json)、[独立 ZIP](evidence/word-independent-zip.json)、[独立 SDK（含保存副本失败）](evidence/word-openxml.json)、[WPS 绑定记录](evidence/word-wps-client.json)。Receipt 仍为临时 Word 开发 schema；TODO-5/6 的完整规划/Receipt 尚未完成。

```powershell
python tools/partsieve.py rebuild tests/fixtures/poi/SimpleMacro.docm --dry-run
python tools/partsieve.py rebuild tests/fixtures/poi/SimpleMacro.docm -o result.docx --receipt result.receipt.json
python tools/partsieve.py verify result.docx --original tests/fixtures/poi/SimpleMacro.docm --receipt result.receipt.json
python tests/word_regression.py
python tests/independent_word.py tests/fixtures/poi/SimpleMacro.docm docs/evidence/word-verified.docx
dotnet run --no-restore --project tests/OpenXmlValidation -- tests/fixtures/poi/SimpleMacro.docm docs/evidence/word-verified.docx
```
