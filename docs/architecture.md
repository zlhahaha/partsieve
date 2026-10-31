# 原型架构

当前提供既有业务v1，以及按输入能力启用的 `business-spreadsheet-v2` / `business-word-v2` 链接与Word OLE配置（0.8.0-spike）。

- `model.mbt`：限制、Audit、Finding、Relationship、RewritePlan、Receipt。
- `graph_model.mbt` / `graph.mbt`：共用 PackageGraph、source-local XML 引用、入出边/内容类型索引、迭代可达性与只报告的 orphan candidates。
- `coverage_model.mbt` / `coverage.mbt`：统一 CapabilityFinding/Coverage/Decision 与 assess；核心 profile_decision 保证 Unsupported/Incomplete/Fail 不进入重建。
- `planner_model.mbt` / `planner.mbt`：PreparedPlan 的全部前置 hash/限额、finding→decision→operation、冲突/依赖与受控闭包。saved plan 执行前重算完整计划；source XML仅支持已验证的Word模板移除。
- `receipt_model.mbt` / `receipt.mbt`：typed v2 去向/检查状态和实际 bytes 重算验证；独立客户端为 NotChecked；模板设置使用SemanticallyRewritten。
- `spreadsheet_values.mbt`：共享文本与样式索引、单元格类型检查。
- `word_content.mbt` / `word_profile.mbt`：表格、内嵌PNG/JPEG、页眉页脚的元素位置、属性及来源局部引用检查。
- `hyperlink.mbt`：HTTP(S)点击目标、来源局部绑定与工作表网格检查，不访问网络；允许的链接进入报告的allowed_capabilities。
- `ole.mbt`：最多32个独立正文内嵌OLE与已建模预览子树；每次解析建立对象索引；删除独占载荷/预览/关系，流式删源XML对象并核对其余语义；逐对象删除决定绑定各自载荷，源XML共同重写一次；共享/未知依赖拒绝。
- `template.mbt`：按命名空间选择attachedTemplate，用原始XML事件保留其他内容，再独立验证设置语义。
- `opc.mbt`：不依赖操作系统路径的 ASCII OPC URI 子集。拒绝 percent encoding、片段、查询、非 ASCII、反斜杠、等价名称和越界。检测到不支持语法不会继续猜测。
- `xml.mbt`：大小/深度/节点/属性 preflight、命名空间事件读取、元数据形状检查。DTD 在 parser 之前拒绝。单个元素最多 256 个属性、markup（含注释/CDATA/PI）与 text token 最多 65,536 code units。
- `package.mbt`：受限 ZIP、CRC、内容类型、根与 source-local 关系。检查所有条目，包括不可达部件。
- `work.mbt`：共享的运行预算、不可复位的取消状态、字节/事件/配对扫描计费；贯穿解析、执行和核验。
- `profile.mbt`：允许的 part/relationship/XML vocabulary、源 `r:id` 绑定、工作簿/工作表元素位置、VBA 交叉证据和共享/孤儿拒绝。
- `rewrite.mbt`：固定策略的计划、克隆 archive 后有限修改、重新读取输出、对预期 metadata 和每个输入 payload 核验。
- `cmd/main`：原生命令行入口，分发公开命令与内部 `_worker` 子命令；工作进程同样有读取上限。
- `cli/`：MoonBit公开命令行，参数与有界JSON校验、私有快照、受限子进程和配套发布。`native_host/host.mbt`实现读取限额、管道上限及超时轮询，`host.c`只封装Windows/Linux系统调用。

ZIP、XML、SHA-256 均复用公共库。删除 VBA 是 workbook 的隐式关系处理；支持配置禁止任何指向该关系的源 XML 属性，因此正文/工作簿 payload 无需改写。宏格式但无 VBA 时仍转换主类型，并不报告发现宏代码。

验证重新执行限定转换得到预期部件集合，再从真实输出 bytes 建图并比较 metadata、关系和 payload hash。main 接受完整重算一致的 PreparedPlan JSON，不以外部计划为权限；任何字段修改都会拒绝。没有全包垃圾回收；未知孤儿拒绝，已支持的静态孤儿不会仅因不可达被删除。

legacy/v2 报告共用同一次原件、预期输出和实际输出的验证事实，减少重复解析；v2 rebuild 直接执行后进入该验证。报告格式不增加额外完整重建，实际输出仍重新解析，图/逐部件 hash 检查保持一致。

生成 SDK interface 在 `pkg.generated.mbti`。结构 Pass 指本配置声明的包/引用/能力检查，不包含完整 OOXML schema 校验。Open XML SDK 仅用于独立测试，不进入运行时。

无法完成的 ZIP/XML 解析、资源限额和有界写出为 `SieveError::Incomplete`，公开宿主保留该状态，退出码为 3。明确不支持的配置为 Refused/Unsupported；Invalid 表示完整性 Fail，解析未完成时能力为 Unknown。旧 Audit/Receipt 为兼容接口；typed v2 可选，不扩大支持范围。资源数值仍 provisional；WorkControl为整个SDK调用/共享工作流提供计费预算及协作取消，宿主另有60秒进程超时；二者不构成完整堆内存或硬实时保证，见[资源预算](resources.md)。
