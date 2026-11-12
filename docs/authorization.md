# 内容损失预览与授权

Mooncakes 0.9.0 提供此 SDK 流程。适用于“允许去宏，但不能静默删除嵌入对象”等接收/交付规则。旧清理入口和CLI仍按原有支持配置执行；应用需要限制内容损失时，应选用本页的授权执行入口。

## 三步接入

1. `preview_document(input, limits?, control?)`：检查实际原件并生成完整计划，返回`Result[DocumentPreview, SdkFailure]`，不输出清理文件。
2. `authorize_document(preview, permissions)`：由可信应用在自身决策/确认之后调用，返回`Result[DocumentAuthorization, SdkFailure]`。任一计划变更超出权限，返回`AuthorizationDenied`。
3. `execute_authorized_document(actual_input, authorization, control?)`：重新解析实际原件，重算计划和损失，核对绑定及权限，再执行并核验实际输出；返回`Result[AuthorizedRebuilt, SdkFailure]`。

```moonbit
match @sieve.preview_document(input) {
  Ok(preview) => {
    // summary()为独立副本，可供界面展示；plan_json()仅为计划数据。
    println(preview.to_json().stringify())
    match @sieve.authorize_document(
      preview, @sieve.RemovalPermissions::macros_only(),
    ) {
      Ok(approval) => {
        match @sieve.execute_authorized_document(input, approval) {
          Ok(delivered) => println(delivered.receipt.output_hash)
          Err(error) => println(error.to_json().stringify())
        }
      }
      Err(error) => println(error.to_json().stringify())
    }
  }
  Err(error) => println(error.to_json().stringify())
}
```

完整可运行示例：`moon run examples/authorization --target native --deny-warn`。它先展示三对象Word的损失，证明仅允许去宏或单独禁止OLE删除都会拒绝，再对固定公开样本显式授权全部受支持变更，核验输出及对应记录。示例自动批准的是可信测试样本，不是模拟用户已经确认。

## 预览内容与权限

| ChangeKind | 预览中的count | 对应权限 |
| --- | --- | --- |
| `VbaRemoval` | 实际VBA项目数，不是宏过程/函数数 | `remove_vba` |
| `OleRemoval` | 受支持的独立内嵌OLE对象数 | `remove_ole` |
| `TemplateRemoval` | 将移除的外部附加模板关系数 | `remove_remote_template` |
| `MacroFormatConversion` | DOCM/XLSM转DOCX/XLSX时为1，否则无此项 | `convert_macro_format` |

`preview.summary()`返回`ChangeSummary`：`changes`逐类说明数量、删除的内部文件和功能影响；`removed_parts`列出所有删除项；`rewritten_parts`列出正文/设置及关系、内容类型等将重写的内部文件。OLE载荷、编辑能力和专属预览图会一起丢失；普通图片及无关内容仍按原保留契约检查。外部模板不会被下载。

`RemovalPermissions::deny_all()`四项均false；`macros_only()`只允许删除VBA和宏格式转换；`all_supported()`显式允许当前四项。也可用结构体展开设置单项，例如：

```moonbit
let keep_objects = {
  ..@sieve.RemovalPermissions::all_supported(),
  remove_ole: false,
}
```

`permissions.allows(change.kind)`可用于生成业务端的禁止项列表，无须解析失败message。授权针对**整份固定计划**：有OLE时不给OLE删除权限，整个任务拒绝，不先去宏再返回部分处理结果；暂不提供按单个OLE选择删除或修改核心清理策略。宏格式但无实际VBA时，只报告格式转换，仍需允许该转换。

## 原件绑定、记录与信任边界

DocumentPreview和DocumentAuthorization的内部字段私有，调用方不能构造/改写它们，也不能取得可修改的内部计划引用。summary()/plan_json()/to_json()仅返回独立的展示数据；改动副本不会改变授权判断。执行时仍重算实际计划、损失及计划摘要，拒绝换原件、改计划、改配置或超出权限；未知变更规则也不能由all_supported自动放行。

授权锁定预览时的Limits，执行不接受另外覆盖；预览和执行可共享一个WorkControl，取消或预算不足均不会返回成功。执行末尾在最后一次控制回调之后再核对原件、计划和实际输出的摘要。旧SDK/CLI未被改成全局强制授权模式，应用不能把旧的不受此权限约束的执行入口作为受限服务的替代路径。

成功值包含`bytes`、原有`VerifiedReceipt`和单独的`authorization`记录；记录包含schema、input_hash、plan_hash、output_hash、permissions和summary。旧Receipt格式不变，记录与真实原件/输出/计划绑定，可与文件和回执一起归档。记录不带数字签名，不能单凭其JSON或Pass字段证明授权真实性或内容保留；实际文件保留仍应使用verify_document/verify_contract核验。

这是可信应用对变更范围的决策，不是身份认证，也不证明某个人实际看过界面。不要把客户端提交的预览、计划、权限或授权记录直接当作服务端授权。可以向客户端发送预览JSON，但服务端应保留对应预览及原件；授权对象目前仅在内存中使用，不支持从客户端JSON恢复。进程重启后可重新预览原件，对照可信业务存储中的原件/计划摘要和已确认范围，再由应用重新调用授权入口；摘要变化则重新决策。

同一授权可重复用于同一原件和计划，不是一次性票据，没有过期时间。授权不使未知格式、共享/链接OLE、ActiveX或其他未支持内容变成受支持输入，也不提供Office视觉保真或病毒检测结论。

## 验证

`tests/authorization`使用实际公开Word/Excel样本，逐项关闭权限、篡改展示副本、替换同格式/跨格式原件、核对允许后输出与旧清理字节一致，并从实际落盘输出用原件和CLI重新核验回执。它也验证仅去宏成功、模板单独授权、被动输入无需删除权限和取消拒绝。单元测试补充无VBA转换、伪造内部计划/损失/权限、未知规则、精确共享预算及后期取消。

```powershell
moon build --target native --deny-warn
moon run tests/authorization --target native --deny-warn
```

独立运行会打印新结果目录；完整check使用本次check-runs目录。CI保存本轮记录和实际授权输出，再用独立OpenXML校验该输出。身份/业务审批及签名不属于这些格式校验的结论。
