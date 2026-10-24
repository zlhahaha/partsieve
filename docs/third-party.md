# 第三方复用与许可证

项目代码采用 Apache-2.0；这是新的 OOXML 能力审计/策略重建适配层，并非把其他语言 Office 库整体翻译为 MoonBit。

| 来源 | 链接 / 固定版本 | 许可 | 实际复用范围 |
| --- | --- | --- | --- |
| moonbit-community/flate | [0.8.4](https://mooncakes.io/docs/moonbit-community/flate@0.8.4/) | Apache-2.0 | ZIP 受限读取、解压、archive 删除/替换、保留写出、CRC 工具；本项目适配层额外核验 payload CRC |
| Milky2018/xml | [0.5.0](https://mooncakes.io/docs/Milky2018/xml@0.5.0/) | Apache-2.0 | NamespaceReader / Writer；本项目在 parser 前做资源 preflight 与 DTD 拒绝 |
| moonbitlang/x | [0.5.5](https://mooncakes.io/docs/moonbitlang/x@0.5.5/) | Apache-2.0 | SHA-256、私有 worker/可信 SDK 示例的 fs、进程退出 |
| XlsxWriter | [固定 commit](https://github.com/jmcnamara/XlsxWriter/tree/5d4606d89a955226d2d0825a0f44309043ae7251) | BSD-2-Clause | 真实 Excel XLSM/XLSX 比较 fixture；没有使用 Python Office 逻辑实现 MoonBit 核心 |
| Apache POI | [固定 commit](https://github.com/apache/poi/tree/12c3688d130035f3dc2ca2a0f50d929456435a93) | Apache-2.0 | 真实 SimpleMacro.docm、公开宏源与超出配置的 SampleDoc.docx；只复用测试数据，没有复用 Java 核心实现 |
| DocumentFormat.OpenXml | [Open XML SDK](https://github.com/dotnet/Open-XML-SDK), 3.3.0 | MIT | 仅独立测试校验，未进入 MoonBit 运行时 |
| DocBleach | [固定 revision](https://github.com/docbleach/DocBleach/tree/a42309704108719dfb308783cd36ab363d185450) | MIT | 只参考 OOXML 功能划分和规则思路，无代码/fixture 复制或运行时调用；见 [功能对照](docbleach-comparison.md) |

运行时依赖的精确版本、registry checksum 和源码 hash 在 [dependency-lock.json](dependency-lock.json)。fixture 原始 BSD-2-Clause 版权与许可在 `tests/fixtures/upstream/LICENSE.txt`，来源与 SHA-256 在 [provenance.json](../tests/fixtures/provenance.json)。

Apache POI fixture 的完整原始 LICENSE/NOTICE 位于 `tests/fixtures/poi/`，固定字节与来源在 [POI provenance](../tests/fixtures/poi/provenance.json)。NOTICE 中上游其他依赖说明随原文保留，不代表本项目使用那些依赖。宏仅静态提取；原始 DOCM 未在 Office 打开，未执行宏。衍生 Word 变体保留上游测试数据许可。

正常运行使用MoonBit和项目自有C系统接口适配层；Python标准库只用于三个独立ZIP/XML校验器，jsonschema 4.23.0只在独立测试中校验Receipt形状。oletools 0.60.2 / olefile 0.47 仅用于本地静态检查无害 fixture 的 VBA，脚本/安装目录和提取记录不进入公开源码包。WPS 是本机独立兼容客户端，不是运行时依赖，未分发其程序或用户文档。

新增 business fixtures 为作者自建组合文档，布局、文本和测试图片采用 Apache-2.0；由 XlsxWriter 3.2.9、CPython XML/Pillow 离线生成。宏字节不变，沿用既有 XlsxWriter/POI 的对应来源许可。来源、固定 hash 及声明见 [business provenance](../tests/fixtures/business/provenance.json)，不能将这些自建样本记为真实第三方采用。

分发 archive 保留本项目 LICENSE、公开 API、核心实现、测试源码及 fixture 许可；开发缓存、临时产物、客户端截图与历史测试日志通过 .moonignore 排除，完整证据保留在本地，CI 报告作为 Actions artifacts 保存。不把用户文件加入测试语料。

0.5的受控OLE测试另从同一固定Apache POI commit的EmbeddedDocument.docx静态提取CFB工作表、EMF预览和对象XML；完整来源及变换已加入POI provenance。提取物只用于组合测试，不激活OLE，不移植POI实现代码。
