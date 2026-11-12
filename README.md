# PartSieve

PartSieve 是 MoonBit 实现的 Office 文档清理与保留验证库。它面向外来文档接收和报表交付，在支持范围内移除 VBA、Word 外部模板和嵌入 OLE，并核验实际生成的可编辑 DOCX/XLSX。回执记录移除、重写和原样保留的部件。处理过程无需启动 Office、执行宏或访问外部资源。

## 版本与安装

| 使用方式 | 功能 |
| --- | --- |
| Mooncakes `0.9.1` | 下表中的清理与保留、Word 脚注/尾注/多级编号、内容损失预览和应用授权、结构化错误、实际文件验证与目录批处理。 |
| Mooncakes `0.8.0-spike` | 旧版 SDK 和基础清理。可通过旧版文档复现其固定工具链与支持范围。 |

在独立 MoonBit 项目中设置 `preferred_target = "native"`，安装包并在消费包的 `moon.pkg` 里导入 `"zlhahaha/partsieve" @sieve`。

```powershell
moon add zlhahaha/partsieve@0.9.1
moon check --target native --deny-warn
```

[结构化 SDK](docs/sdk.md)包含一次清理、计划后执行和归档验证。
需要限制内容损失的接收服务使用[预览、授权和执行](docs/authorization.md)。
在任意消费项目完成依赖同步后，可以用已安装包内的脚本启动新的独立消费验收。

```powershell
pwsh -File .mooncakes/zlhahaha/partsieve/tools/check-registry-consumer.ps1 -OutputDirectory PATH_TO_NEW_DIRECTORY
```

## 支持范围

| 输入或内容 | 0.9.1 的处理 |
| --- | --- |
| XLSX / XLSM | 保留共享及内联文本、数字、布尔值、1900/1904 日期系统、工作表顺序、常见单元格样式、合并区域和符合配置的编辑时长属性。移除受支持的 VBA，输出 XLSX。 |
| DOCX / DOCM | 保留段落、表格、合并单元格、内嵌 PNG/JPEG、分节页眉页脚、受支持的脚注、尾注及显式多级编号。移除受支持的 VBA，输出 DOCX。 |
| Word 外部模板 | 移除受支持的 HTTP(S) 附加模板及其设置引用。 |
| Word / Excel 点击链接 | 保留符合配置的 HTTP(S) 链接及目标，在回执中列出。 |
| Word 嵌入 OLE | 支持最多 32 个独立正文对象，删除对象、专属预览、载荷及引用。共享、链接型和嵌套对象会触发拒绝。 |

公式、外部工作簿或图片、ActiveX、Excel OLE、签名以及超出配置的内容会触发拒绝。支持范围按文档内容判定。日期以原始数值和格式保留，部件字节与引用核验的适用范围见 [兼容矩阵](docs/compatibility-matrix.md)和[保留契约](docs/preservation-contract.md)。

## 可下载样例

直接打开无宏输出，查看清理后保留的内容。含宏原件用于 PartSieve 命令行复现。

| 场景 | 原件 | 无宏输出 | 可查看的内容 |
| --- | --- | --- | --- |
| Word 文档接收 | [DOCM](tests/fixtures/business/document-template.docm) | [DOCX](examples/business/preview/document-template.docx) | 合并表格、PNG/JPEG、两节的页眉页脚。清理移除了 VBA 和外部模板引用。 |
| Excel 报表交付 | [XLSM](tests/fixtures/business/report-1900.xlsm) | [XLSX](examples/business/preview/report-1900.xlsx) | 三张工作表、中英文、日期、货币格式和合并单元格。清理移除了 VBA。 |

这两组业务样例使用项目自建内容，宏来源和许可见[业务样本来源](tests/fixtures/business/README.md)。0.9.1 还支持重建 Apache POI 的脚注文档和多级编号文档，输出与原件字节一致。样本来源、其他原件和验证命令见 [Word 结构验证](docs/word-structures.md)。

## 从源码运行

使用固定的 `moonc 0.10.20+65efd5b93`、Native C 工具链及 PowerShell 7。Windows 使用 MSVC。安装命令和支持边界见[工具链复现](docs/toolchain.md)。以下命令在包含本 README 的源码目录运行。

```powershell
moon update
moon build --target native --deny-warn
New-Item -ItemType Directory -Force tests/generated/quickstart | Out-Null
moon run cmd/main --target native -- rebuild tests/fixtures/business/report-1900.xlsm -o tests/generated/quickstart/report.xlsx --receipt tests/generated/quickstart/report.json --receipt-format v2
moon run cmd/main --target native -- verify tests/generated/quickstart/report.xlsx --original tests/fixtures/business/report-1900.xlsm --receipt tests/generated/quickstart/report.json --receipt-format v2
```

`prepare INPUT` 可先保存计划，再通过 `rebuild INPUT --plan PLAN.json` 执行。执行时重新核验原件与计划。通过 [目录批处理](docs/batch.md) 可以一次处理目录顶层的支持格式，并从 `batch.json` 获取每份文档的处理结果。

```powershell
moon run cmd/main --target native -- batch INPUT_DIR -o tests/generated/NEW_OUTPUT_DIR --json
```

请为文档、回执和批处理目录使用新的输出路径。CLI 退出码 `0` 表示成功，`2` 表示完整性或保留检查失败，`3` 表示不支持或检查不完整，`4` 表示用法或文件操作错误。归档核验需要实际输出和原件。默认输入上限 32 MiB、输出上限 64 MiB，每次工作进程限时 60 秒。见[资源预算](docs/resources.md)。

## 验证与复现

当前源码的离线验收通过 82 个 MoonBit 测试，包含 293 次历史 CLI 调用。独立 ZIP/XML 检查通过 23 组。五份固定 Apache POI 脚注、尾注和编号文档的输出哈希与原件一致，全部通过 Office 2013 格式校验。Office 2007 校验中，`NumberingWOverrides.docx` 的原件和输出均有相同的样式属性错误。固定 20 份兼容性语料在 0.9.1 中为 8 份支持、12 份拒绝，开发源码补齐普通 Word 表格样式与页眉图片后为 10 份支持、10 份拒绝。见 [Word 结构验证](docs/word-structures.md)、[兼容性语料](docs/external-corpus.md)与[实际 Office 客户端复测](docs/office-clients.md)。

```powershell
./tools/check.ps1
# 将 RUN 替换为脚本打印的本次运行目录名
python tests/independent_business.py tests/generated/check-runs/RUN/business --next tests/generated/check-runs/RUN/next --word-modern tests/generated/check-runs/RUN/evidence/word-modern
```

已安装[锁定依赖](docs/dependency-lock.json)时可用 `./tools/check.ps1 -Offline`。日常运行只需 Native 工具链。独立验证另用 Python、`jsonschema==4.23.0` 和 Open XML SDK。复跑脚本将生成文件写入 `tests/generated/check-runs/`，CI 在 GitHub Actions artifacts 中提供实际输出和验证报告。可直接运行[业务示例](examples/business/README.md)或[验收演示](docs/acceptance-demo.md)。

## 设计与许可

查看[架构](docs/architecture.md)、[威胁模型](docs/threat-model.md)、[回执格式](docs/receipt-v2.schema.json)及 [DocBleach 功能对照](docs/docbleach-comparison.md)。PartSieve 的处理核心使用 MoonBit，原生 C 适配层提供文件和进程接口。

源码采用 Apache-2.0。测试夹具包含自建文档和具有固定来源与许可的 Apache POI、XlsxWriter 样本。见[第三方许可](docs/third-party.md)和[业务样本来源](tests/fixtures/business/README.md)。
