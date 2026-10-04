# 第三方复用与许可证

项目代码采用 Apache-2.0；这是新的 OOXML 能力审计/策略重建适配层，并非把其他语言 Office 库整体翻译为 MoonBit。

| 来源 | 链接 / 固定版本 | 许可 | 实际复用范围 |
| --- | --- | --- | --- |
| moonbit-community/flate | [0.8.4](https://mooncakes.io/docs/moonbit-community/flate@0.8.4/) | Apache-2.0 | ZIP 受限读取、解压、archive 删除/替换、保留写出、CRC 工具；本项目适配层额外核验 payload CRC |
| Milky2018/xml | [0.5.0](https://mooncakes.io/docs/Milky2018/xml@0.5.0/) | Apache-2.0 | NamespaceReader / Writer；本项目在 parser 前做资源 preflight 与 DTD 拒绝 |
| moonbitlang/x | [0.5.5](https://mooncakes.io/docs/moonbitlang/x@0.5.5/) | Apache-2.0 | SHA-256、私有 worker/可信 SDK 示例的 fs、进程退出 |
| XlsxWriter | [固定 commit](https://github.com/jmcnamara/XlsxWriter/tree/5d4606d89a955226d2d0825a0f44309043ae7251) | BSD-2-Clause | 真实 Excel XLSM/XLSX 比较 fixture、对应来源测试文件；没有使用 Python Office 逻辑实现 MoonBit 核心 |
| DocumentFormat.OpenXml | [Open XML SDK](https://github.com/dotnet/Open-XML-SDK), 3.3.0 | MIT | 仅独立测试校验，未进入 MoonBit 运行时 |

运行时依赖的精确版本、registry checksum 和源码 hash 在 [dependency-lock.json](dependency-lock.json)。fixture 原始 BSD-2-Clause 版权与许可在 `tests/fixtures/upstream/LICENSE.txt`，来源与 SHA-256 在 [provenance.json](../tests/fixtures/provenance.json)。

Python 标准库承担有界 I/O 宿主和独立 ZIP/XML 测试；jsonschema 4.23.0 仅校验测试中的 Receipt 形状。oletools 0.60.2 / olefile 0.47 仅用于静态检查无害 fixture 的 VBA，测试安装目录不进入 Git 或 Mooncakes。WPS 是本机独立兼容客户端，不是运行时依赖，未分发其程序或用户文档。

分发 archive 保留本项目 LICENSE、公开 API、核心实现、测试源码及 fixture 许可；开发缓存、临时产物、客户端截图与历史测试日志通过 .moonignore 排除，完整证据保留在 GitHub。所有 fixture 都来自上述固定公开来源；不把用户文件加入测试语料。
