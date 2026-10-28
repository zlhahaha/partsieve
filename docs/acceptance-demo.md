# PartSieve 0.7.1 固定验收演示

这是一套约五分钟的命令行演示，覆盖实际处理、保留核验和拒绝行为。
演示样本由项目公开测试数据构成，不是用户文件或第三方采用证明。
本说明不替代主办方验收结论，也不需要另填验收表格。

## 一次准备

从仓库根目录使用PowerShell 7，具备README要求的MoonBit 0.10.14和Native编译环境：

```powershell
moon update
moon install
./tools/acceptance-demo.ps1
# 或指定一个尚不存在的本地目录：
./tools/acceptance-demo.ps1 -OutputDirectory 'E:/演示/PartSieve-0.7.1'
```

脚本构建Release命令行，使用随源码和Mooncakes包提供的固定多OLE组合样本，并在运行中按固定输出摘要核对。
默认演示包位于被忽略的`tests/generated/acceptance-demo/`，不会提交到GitHub或Mooncakes。
包内包含本机Native可执行文件、三个输入、运行器、来源许可，以及本次运行的计划/报告/输出。
它不是跨系统安装包；在同一平台和兼容运行环境中重复演示，直接运行包内：

```powershell
./run-demo.ps1
```

重复运行不再调用MoonBit、Python、.NET SDK或网络，每次使用新的`runs`目录。
已存在的准备目录不会覆盖，输入和可执行文件的摘要变化会被拒绝。
原始含宏样本只交给本地命令行静态处理；展示文档使用`runs`中的清理输出。

## 五分钟讲解

| 时间 | 操作与文件 | 建议说明 |
| --- | --- | --- |
| 0:00–0:30 | 说明模块版本和支持范围 | MoonBit实现的文档清理与保留核验库；范围外明确拒绝，不是通用杀毒软件 |
| 0:30–1:30 | 查看`01-report.xlsx`及对应报告 | XLSM去宏后交付XLSX，中文、日期、三个工作表和样式按原数据保留；核验读取实际输出 |
| 1:30–3:00 | 查看`02-word.docx`、计划与报告 | 三个独立OLE各有删除决定，源XML共同重写一次；普通正文、对象之间文字、表格、图片、页眉页脚和允许链接核验保留 |
| 3:00–4:00 | 查看`03-tamper-rejected.stdout.json` | 修改的是普通正文；即使ZIP仍可读取，也不能通过与原件的保留核验；预期退出码2 |
| 4:00–4:30 | 查看`04-unsupported-rejected.stdout.json` | 不支持的真实测试文档被拒绝，预期退出码3，目标文档和回执均不存在 |
| 4:30–5:00 | 查看`demo-result.json`及边界说明 | 区分程序核验、独立格式校验与Office客户端观察，展示实际证据而非只展示Pass文字 |

运行器同时使用保存计划执行、实际原件/输出/回执核验和固定清理输出SHA-256，命令与退出码都有记录。
这验证演示本身，不等同于全部测试或对任意文档的安全证明。

## 必须讲清楚的边界

- 最多32个互不共享依赖的Word正文内嵌OLE；OLE内容、编辑能力及专属预览一起丢失。
- 共享/链接型/嵌套/未知对象、Excel OLE、ActiveX和其他未支持内容仍拒绝。
- HTTP(S)点击链接可以保留，程序不访问其目标；允许保留不表示地址可信。
- 工作预算和协作取消不保证硬实时或总堆内存上限。
- 多对象WPS验证尚待补齐；旧Word保存副本的三处样式顺序错误仍保留，不能称为全面Office兼容。
- 本运行器不调用WPS、独立Schema或OpenXML验证器；对应证据必须单独绑定实际文件摘要。

## 完整回归与独立验证

仓库的`tools/check.ps1`及CI执行完整回归。另可对本次清理输出运行已有独立格式校验器：

```powershell
dotnet run --project tests/OpenXmlValidation -- '演示包/runs/本次目录/01-report.xlsx' '演示包/runs/本次目录/02-word.docx'
```

具体路径用脚本打印的结果目录替换。WPS编辑保存后的文件应另存为独立副本，分别验证，不能沿用清理输出的Pass。
演示包的`licenses`保留项目、Apache POI及XlsxWriter测试数据许可与来源；固定上游及变换见仓库的第三方说明。
