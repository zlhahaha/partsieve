# 首次原型发布记录

日期：2026-10-04（Asia/Shanghai）。用户明确授权初始化 `https://github.com/zlhahaha/partsieve`，并在原型完成后发布 Mooncakes。该仓库已经存在、公开且为空；本轮直接初始化已有仓库。

版本：`zlhahaha/partsieve@0.1.0-spike`，实验性 Native SDK；仅 `simple-spreadsheet-spike-v1`。发布包不等于计划 TODO-13 顶奖成品验收。

## 当前发布进度

- 已完成本地原型有效提交、15 单元测试、48 特征案例、17 端到端检查；ZIP/Open XML SDK/WPS 证据完整。
- GitHub main 推送：准备中。
- CI：已配置 Windows Native/宿主回归和独立 ZIP/Open XML SDK 两个 job，实际结果待运行。
- Mooncakes：元数据与 archive 本地检查通过，干净解包编译通过；服务端 dry-run 返回 HTTP 202、明确说明成功且未改索引。正式发布尚未执行。
- 已存在 Mooncakes 本机凭据；发布通过 moon CLI 使用，不复制到仓库。

## 目录章程核对

基准是工作区《MoonBit黑客松大赛章程.pdf》，标题为“2026 9月 MoonBit 黑客松大赛章程”，保存日期 2026-09-23，共 8 页，SHA-256 `220ee3c404714cb8eb100f560471de7354e3dd2dbea071d5dd3439ecc10eaa74`。PDF 没有可提取文本层，已渲染并逐页查看；原先空白的文本提取文件不能当作已核对证据。此文件未随项目再分发。

章程第 5.1 节验收与第七章要求：

| 要求 | 项目证据 / 状态 |
| --- | --- |
| MoonBit 为主要实现语言、完整清晰源码 | 核心审计/规划/重建/复核为 MoonBit；Python 为有界文件宿主与测试 |
| GitHub 公开、合理开发记录 | 指定公开仓库，首次有效提交是完整已测试原型；后续实际变化独立记录 |
| README：目标、安装、使用、可复现 | README、SDK 示例、脚本命令、明确支持/拒绝范围 |
| 检查/构建/测试、至少一个可运行示例 | moon check/test/build Native、examples/sdk、check.ps1；CI 需记录实际运行结果 |
| 关键功能路径测试 | 15 单元、48 特征案例、17 端到端检查及独立校验 |
| Mooncakes 发布 | 本轮执行，成功前保持未完成状态 |
| OSI 许可证、注明参考来源及复用范围 | Apache-2.0，第三方来源/许可、fixture 原始 BSD-2-Clause 文件齐全 |
| fixture/生成代码来源合法 | 固定公开上游与 hash；没有用户数据、未经授权私有源码或执行宏 |

第 5.1 节申报材料还要求 GitHub 至少 10 个有效 commits，并禁止过度拆分、空提交和重复提交。当前为真实开发初始历史，**尚未满足 10 次有效提交**；将随实际功能、修复、测试和发布变化累积，不把仓库/包上线视为已具备参赛验收资格。

本轮没有提交报名表、代表作者作比赛参与声明或联系赛事方；申报的人工作文、资格、截至时间与主办方结果还需作者自行确认。目录章程有 9 月申报日期和 10 月赛程表，不能把它当作已经确认的当前报名状态。

## 分发检查

发布前检查 archive 文件清单、许可、版本、支持 target 和 README；运行服务器 dry-run；发布后从干净调用方 `moon add zlhahaha/partsieve@0.1.0-spike` 真实解析/编译调用，避免只凭 CLI 返回判定消费者可用。GitHub CI 与手工 WPS 检查分别报告。

发布工具踩坑：`moon publish --dry-run --frozen` 阻止临时解包目录安装依赖，去掉 frozen 后干净包编译通过。此次服务端返回 202 Accepted / Dry run completed successfully / No changes were made，但当前 moon CLI 仍返回退出码 1 和 publish failed。记录真实 HTTP/detail，不把此输出当作已经正式发布；正式发布后必须独立检查索引和消费者安装。
