# 原型架构

当前提供 `simple-spreadsheet-spike-v1` 与 main 的 `simple-word-vba-dev-v1` 受限配置。

- `model.mbt`：限制、Audit、Finding、Relationship、RewritePlan、Receipt。
- `graph_model.mbt` / `graph.mbt`：共用 PackageGraph、source-local XML 引用、入出边/内容类型索引、迭代可达性与只报告的 orphan candidates。
- `coverage_model.mbt` / `coverage.mbt`：统一 CapabilityFinding/Coverage/Decision 与 assess；核心 profile_decision 保证 Unsupported/Incomplete/Fail 不进入重建。
- `planner_model.mbt` / `planner.mbt`：PreparedPlan 的全部前置 hash/限额、finding→decision→operation、冲突/依赖与受控闭包。saved plan 执行前重算完整计划；source XML 操作拒绝。
- `receipt_model.mbt` / `receipt.mbt`：typed v2 去向/检查状态和实际 bytes 重算验证；独立客户端为 NotChecked，未实现语义 source XML handler。
- `opc.mbt`：不依赖操作系统路径的 ASCII OPC URI 子集。拒绝 percent encoding、片段、查询、非 ASCII、反斜杠、等价名称和越界。检测到不支持语法不会继续猜测。
- `xml.mbt`：大小/深度/节点/属性 preflight、命名空间事件读取、元数据形状检查。DTD 在 parser 之前拒绝。单个元素最多 256 个属性、markup（含注释/CDATA/PI）与 text token 最多 65,536 code units。
- `package.mbt`：受限 ZIP、CRC、内容类型、根与 source-local 关系。检查所有条目，包括不可达部件。
- `profile.mbt`：允许的 part/relationship/XML vocabulary、源 `r:id` 绑定、工作簿/工作表元素位置、VBA 交叉证据和共享/孤儿拒绝。
- `rewrite.mbt`：固定策略的计划、克隆 archive 后有限修改、重新读取输出、对预期 metadata 和每个输入 payload 核验。
- `cmd/main`：私有 Native worker，只对宿主准备的受限临时文件做 I/O。
- `tools/partsieve.py`：对外原型脚本入口，读取前 stat + cap+1 受限读取、私有快照、60 秒进程超时、成对发布。没有 OOXML detector 或 rewrite 逻辑。

ZIP、XML、SHA-256 均复用公共库。删除 VBA 是 workbook 的隐式关系处理；支持配置禁止任何指向该关系的源 XML 属性，因此正文/工作簿 payload 无需改写。宏格式但无 VBA 时仍转换主类型，并不报告发现宏代码。

验证重新执行限定转换得到预期部件集合，再从真实输出 bytes 建图并比较 metadata、关系和 payload hash。main 接受完整重算一致的 PreparedPlan JSON，不以外部计划为权限；任何字段修改都会拒绝。没有全包垃圾回收；未知孤儿拒绝，已支持的静态孤儿不会仅因不可达被删除。

legacy/v2 报告共用同一次原件、预期输出和实际输出的验证事实，减少重复解析；v2 rebuild 直接执行后进入该验证。报告格式不增加额外完整重建，实际输出仍重新解析，图/逐部件 hash 检查保持一致。

生成 SDK interface 在 `pkg.generated.mbti`。结构 Pass 指本配置声明的包/引用/能力检查，不包含完整 OOXML schema 校验。Open XML SDK 仅用于独立测试，不进入运行时。

无法完成的 ZIP/XML 解析、资源限额和有界写出为 `SieveError::Incomplete`，公开宿主保留该状态，退出码为 3。明确不支持的配置为 Refused/Unsupported；Invalid 表示完整性 Fail，解析未完成时能力为 Unknown。旧 Audit/Receipt 为兼容接口；typed v2 可选，不扩大支持范围。资源数值仍 provisional；完整 SDK 工作预算/取消接口尚缺，宿主使用 60 秒进程超时。
