# 目录批处理

此功能目前在GitHub主分支，待下一版同步Mooncakes；注册表0.7.1不含此命令。需要README所列的Native工具链，正常使用不需要Python或WPS。

```powershell
moon build --target native --deny-warn
moon run cmd/main --target native -- batch tests/fixtures/business -o batch-output --json
```

`batch-output`必须不存在，其父目录必须已存在。示例处理目录中的Office文件，其他文件列为Skipped。某些样本可能按当前支持范围被拒绝，因此应读取退出码和汇总，不能只看目录是否创建。再次运行请换新的输出目录。

命令按UTF-16文件名字典序串行处理顶层普通`.docx`、`.docm`、`.xlsx`和`.xlsm`文件，扩展名不区分大小写。不递归；子目录、符号链接/Windows重解析点、特殊文件、`~$`锁文件及其他扩展名记录为Skipped，不读取其内容。输入根目录本身为链接/重解析点时拒绝。POSIX文件名含反斜杠时跳过，避免路径解释歧义。

| 输入名 | 输出文档 | v2回执 |
| --- | --- | --- |
| `report.xlsm` | `report.xlsm.cleaned.xlsx` | `report.xlsm.receipt.json` |
| `letter.docm` | `letter.docm.cleaned.docx` | `letter.docm.receipt.json` |
| `letter.docx` | `letter.docx.cleaned.docx` | `letter.docx.receipt.json` |

保留输入扩展名可以区分同名的DOCM和DOCX。文件内容仍以实际解析为准：如果扩展名属于Word而内容实际为Excel等不匹配，按失败处理，不发布该文件的成功输出对。过长路径或输出名等系统错误只影响对应文件。

每份选中文件使用单文件重建流程：有界读取输入、临时快照、独立worker重建、重新读取实际输出核验、发布并读回文档及回执。已有单文件支持范围和限制不变，批处理不增加ActiveX、公式或Excel OLE支持。输入文件不修改；已有输出目录/文件均拒绝，不自动续跑或覆盖。新建的目录请由调用方保持独占，运行期间保持输入目录稳定；目录扫描和后续逐份读取不构成整个文件系统的事务快照，也不是抵御其他进程替换父目录的隔离边界。

`batch.json`与标准输出具有相同JSON内容，schema为`partsieve.batch.v1`。根记录含输入/输出目录、成功/拒绝/失败/跳过数、总体状态和退出码。`entries`只用相对文件名：Success含输出/回执名和实际源/输出SHA-256；Refused或Failed含退出码、原决定及最多1024个UTF-16单元的原因；Skipped含跳过原因。单份完整保留证明在各自v2回执中，汇总不能替代原件和输出的核验。

| 总体退出码 | 含义及优先顺序 |
| --- | --- |
| 4 | 至少一份发生读写/用法/发布错误，或整批初始化/汇总发布失败，优先级最高 |
| 2 | 至少一份完整性/保留检查失败，且没有4 |
| 3 | 至少一份Unsupported/Incomplete，且没有4或2；或没有选中的输入（NoInputs） |
| 0 | 全部选中文件成功；Skipped不影响成功 |

文件状态分别为Success、Refused（含Unsupported和Incomplete）、Failed、Skipped。单个坏文件不会阻断后续文件；成功文件对不会因其他文件失败而撤销。输出目录创建后即使全部拒绝，也保留带原因的汇总。成功文件发布和整批结果不保证事务原子性；若最后汇总写入失败，已完成文件保留，标准输出返回`partsieve.batch.summary-failure.v1`、退出4及内嵌逐份结果，不能宣称整批成功。

目录清单最多1024项，包含跳过项，不只是Office文件；超过时退出3，在创建输出目录前中止。每个名字最多1024个UTF-8字节，非法UTF-8或扫描错误则初始化失败。每份输入32MiB、输出64MiB，串行执行；`--timeout-ms N`为**每次worker调用**1..60000毫秒，默认60000，不是整批或整份处理的总时限。`--release`沿用单文件的release二进制选择。可指定`--receipt-format v2`、`--policy passive-office-v1`；不支持legacy、`--receipt`、`--original`、`--plan`和`--dry-run`。

可复现回归：

```powershell
moon build --target native --deny-warn
moon run tests/batch --target native --deny-warn
```

程序从公开固定样本创建临时混合目录，通过真实CLI验证失败后继续、四种扩展名、中文/空格、同名不同扩展、各级退出码、目录/已有文件保护和1024项边界。成功输出分别重新执行SDK原件核验及CLI回执核验，汇总与实际磁盘JSON比较。Windows无法创建符号链接时明确记录UnavailableOnHost；Linux须实际覆盖符号链接、根链接与FIFO。CI保存`tests/generated/batch-v1.json`，只有全部断言通过才写Pass；测试目录不随Mooncakes发布。
