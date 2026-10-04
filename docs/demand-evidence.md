# 需求证据状态（2026-10-04）

结论：技术 Spike 已有真实输入证据；**真实清洗后继续交付可编辑 OOXML 的 MoonBit 下游需求仍未确认**。不把作者示例当独立采用。

公开候选：

- [office.mbt](https://github.com/moonbitlang/office.mbt) 的当前 README 列有 Office CLI、可复用 integration/SDK、DOCX 编辑及 XLSX 读写；它证明存在 Office 工具工作流，不能推导其维护者需要 PartSieve 或愿意采用。该仓库现已拆为多个模块，旧调研中的路径需重新复核。
- [MoonClaw](https://github.com/vectie/moonclaw) 公开描述 Agent/job/runtime 与 artifact 工作流，可作为文件摄入候选。当前主页不足以确认其需要清洗后可编辑 Office 输出。
- [office.mbt #265](https://github.com/moonbitlang/office.mbt/issues/265) 的网页工具仍无法读取，随后已通过公开 GitHub API 成功复核：state=open，updated_at=2026-07-27T07:02:54Z；主题为全量 XLSX 重写的保留契约、依赖闭包与 Receipt。这证明上游有保留范围议题，不能推导其需要安全清洗或会采用 PartSieve。

准备好的接入边界：宿主有界读取 input bytes → `audit`/`plan` → `rebuild` → 返回 bytes 与 Receipt。对 Unsupported/Incomplete 拒绝交付。需要维护者实际说明接收格式、必须保留可编辑性的原因、禁止能力、允许损失、拒绝处理及真实测试反馈。

尚无维护者反馈、授权接入 PR、独立消费者测试或采用证据。没有发送消息、提交 PR 或联系外部人员。依据计划，扩展 P1 能力前需要补齐具体需求；顶奖定位仍未 LOCK。

用户在本轮明确答复暂无第三方下游项目。自建注册表消费者仅证明发布 SDK 可用，不计入 TODO-11；没有维护者需求确认或测试反馈。对继续扩能力的依据仍需重新评估，不能用发布次数或提交数量替代需求证据。
