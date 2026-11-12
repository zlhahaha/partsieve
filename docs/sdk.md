# 开发者接入与稳定失败结果

本文描述 Mooncakes 0.9.1 的结构化 SDK 入口。0.8.0-spike 使用原有抛错 API。大版本发布前保持旧入口兼容，原有Receipt/Plan JSON格式及工具标识不变。

## 选择调用路径

| 场景 | 新入口 | 成功结果 |
| --- | --- | --- |
| 上传接收后立即清理 | `clean_document(input)` | `VerifiedRebuilt`，含实际输出bytes与独立重新计算的receipt |
| 先检查、由业务决定是否执行 | `prepare_document(input)` → `execute_document_plan(input, plan.to_json())` | 先返回原件绑定计划，执行时重新检查计划/源约束，并核验实际输出 |
| 归档或交付前独立核验 | `verify_document(actual_output, original)` | 从真实文件bytes重新计算的`VerifiedReceipt` |
| 需要限制可删除内容 | `preview_document` → `authorize_document` → `execute_authorized_document` | 结构化损失预览、原件/计划绑定的明确授权、已核验输出及单独授权记录 |

所有新入口返回`Result[T, SdkFailure]`。通常直接使用一次清理入口，不必先调用assess/prepare，也不必为了取得已有回执再重复verify。清理内部沿用原有`rebuild_verified`的重建和实际输出核验，没有新增一次解析；需要在持久化或传输之后检查文件时，再调用归档核验入口。

```moonbit
match @sieve.clean_document(input) {
  Ok(cleaned) => {
    // cleaned.bytes：交付内容；cleaned.receipt：本次实际bytes的保留检查。
    // 由应用决定如何存储/返回；保存后若需核对磁盘，另读实际文件再verify。
    println(cleaned.receipt.output_hash)
  }
  Err(failure) => {
    println(failure.code.label())
    println(failure.message)
  }
}
```

`input`是已读入的Bytes；宿主须先有界接收/读取，SDK不能撤销调用前的过大分配。Native宿主可使用`native_host.read_bounded`，文件IO异常仍由宿主处理，不会混入纯bytes SDK的文档错误。运行实例见`examples/business`，三个完整路径及取消分支见`examples/workflows`：

```powershell
moon run examples/business --target native --deny-warn
moon run examples/workflows --target native --deny-warn
```

## 错误契约

`SdkFailure`包含稳定类型`code`、发生调用的`operation`和供人阅读的`message`。业务按枚举或`code.label()`分支，不解析message；message可能随说明改进而变化。`to_json()`形如：

```json
{"code":"cancelled","operation":"clean_document","message":"operation cancelled by caller"}
```

| FailureCode / 稳定label | 判定依据 |
| --- | --- |
| `InvalidConfiguration` / `invalid_configuration` | 配置校验明确拒绝，例如非正值或超过硬上限的Limits |
| `UnsupportedDocument` / `unsupported_document` | 原有Refused类型，当前支持配置无法处理；不是完整格式风险诊断 |
| `ProcessingIncomplete` / `processing_incomplete` | 原有Incomplete类型且控制器未记录取消/预算停止；包括ZIP未完成、XML/结构或生成输出等内部限额 |
| `IntegrityFailure` / `integrity_failure` | 原有Invalid类型：如CRC、计划绑定或保留核验失败 |
| `InputLimitExceeded` / `input_limit_exceeded` | 入口已知input或original的bytes长度超过配置input_bytes |
| `OutputLimitExceeded` / `output_limit_exceeded` | 归档核验入口的现成output bytes超过配置output_bytes；生成阶段的内部上限仍可能是ProcessingIncomplete |
| `Cancelled` / `cancelled` | WorkControl记录明确的调用方取消或取消回调停止 |
| `WorkBudgetExceeded` / `work_budget_exceeded` | WorkControl记录工作量耗尽，包括成对扫描预留失败 |
| `InternalFailure` / `internal_failure` | 非预期错误，单列为内部失败；不冒充不支持或安全通过 |
| `AuthorizationDenied` / `authorization_denied` | 授权路径中，实际计划要求调用方没有允许的删除/格式转换；整个任务拒绝 |

不会用英文关键词推断分类，也不会把所有解析失败判成“文档损坏”。UnsupportedDocument和ProcessingIncomplete目前保留宽分类；尚不提供每个XML元素/ZIP失败的细分代码或源码位置。错误operation是调用边界，不是深层解析阶段。

入口检查顺序为配置有效性→已有停止状态→已知输入/输出长度→原有执行流程，因此同时存在多个问题时可能优先报告配置问题。预检查不消耗工作预算；真正处理使用相同的共享控制器。错误只返回diagnostic，不返回部分输出或成功回执。

## 计划、取消与兼容

准备/执行之间可由应用等待自己的确认，再将**实际原件**和计划交给`execute_document_plan`。计划所有关键约束仍独立重算，修改input_hash或替换源bytes不能授权执行。此旧入口不会限制允许删除的类别；需要“只去宏但不能删除OLE”等约束时，使用[内容损失预览与授权](authorization.md)的完整授权路径，不能用不受限入口替代权限执行。

新SDK尚在GitHub主分支演进，本轮增加AuthorizationDenied及三个授权操作枚举值，业务对枚举作穷尽匹配时需覆盖新增项；已发布的旧抛错API/CLI/Receipt不变。

清理、计划准备/执行、归档核验及损失预览接受可选`limits`与`control`；授权决定入口只接收预览与权限，授权执行锁定预览时的Limits并接受可选`control`。处理阶段可共享同一个WorkControl，使工作量累计。`stop_kind()`返回`CancelRequested`或`AllowanceExhausted`，不依赖`stop_reason()`文本；首次停止原因保持不变。不要对同一个已停止控制器自动重试，也不要把Incomplete当成适合重试的临时错误。

现有`assess`继续用于能力检查；`prepare`、`rebuild_verified`、`rebuild_verified_with_plan`、`verify_contract`和SieveError三种构造保持可用。新SDK是加法接口，成功文件、回执与旧接口一致，CLI行为不变。SDK的格式/客户端独立验证仍为NotChecked，成功不代表任意Office文件安全或视觉保真。

回归验证同时覆盖新旧成功bytes/receipt一致、工作量与旧一次入口完全相等、配置与长度边界、取消/耗尽不可复位、源替换、计划伪造、输出正文篡改及错误文案变化不改变分类。
