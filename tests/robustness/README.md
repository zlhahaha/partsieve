# 固定种子健壮性回归

从仓库根目录运行，需要README所列的MoonBit和Native编译环境：

```powershell
moon build --target native --deny-warn
moon run tests/robustness --target native --deny-warn
```

种子固定为`20261029`。120个案例由公开的固定Word三对象、报表样本及其受控变异生成；不执行宏、OLE、网络请求或Office程序，不新增Python依赖。

| 分类 | 案例数 | 判定依据 |
| --- | --- | --- |
| 正常输入对照 | 5 | 业务Word/Excel、普通文本变化、注释、Store ZIP均可处理；实际输出与原件重新核验，BytePreserved内部文件字节一致 |
| ZIP截断 | 34 | 固定边界和种子抽样截断；assessment不允许重建，prepare/rebuild_verified均拒绝 |
| ZIP CRC损坏 | 32 | 改变Store文档载荷的抽样字节，保持记录的CRC不变，必须拒绝 |
| ZIP头部 | 9 | 分别破坏local/central签名、flags、方法、CRC、尺寸、名称及偏移 |
| XML | 12 | 空/截断/非法UTF8/NUL、双根、DTD/外部DTD、未声明实体/前缀、重复属性、错误命名空间和零字符引用 |
| 内部路径、重复文件和缺少目标 | 11 | 路径穿越/绝对路径/别名、重复主文档及缺少图片目标必须拒绝 |
| 计划绑定 | 4 | 伪造源摘要、文件前置条件、操作或限制不能执行 |
| 输出内容篡改 | 3 | 修改正文、页眉或页脚后，不能通过原件保留验证 |
| 协作取消 | 3 | ZIP/XML/配置阶段中断；后续复用同一控制对象仍Incomplete且不再消耗预算 |
| 工作预算 | 3 | 输入预算不足、实际工作量恰好足够/少一单位的边界 |
| 发布保护 | 4 | 输出/回执已存在及输入/输出/回执路径冲突退出4；已有文件字节不变，无额外成功文件 |

33个破坏输入还经真实Native CLI执行，要求退出2或3且输出/回执均不存在。Word、Excel对照各经CLI重建与核验（共4次正常检查），防止只拒绝所有输入的实现蒙混通过。

运行使用新的临时语料目录，不覆盖既有输出。结果写入`tests/generated/robustness-v1.json`，记录分类、案例名、输入摘要及观察结果；只有全部断言通过才写`result: Pass`。执行中先写`Running`及观察记录，便于失败后定位。Windows/Linux CI分别保存JSON证据。

这是有界、确定性的变异回归，不是持续随机模糊测试。种子稳定不代表覆盖所有输入；部分截断/CRC情形沿用SDK的Incomplete分类，不将其改成成功或已确认无风险。样本源、许可及变换见`tests/fixtures/business/provenance.json`。生成语料及JSON证据不进入源码发布包，测试程序仅在GitHub仓库中提供。
