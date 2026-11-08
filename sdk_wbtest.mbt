///|
fn[T] sdk_expect_failure(
  result : Result[T, SdkFailure],
  code : FailureCode,
  operation : SdkOperation,
) -> Unit raise {
  guard result is Err(error) else { fail("expected SDK failure") }
  assert_eq(error.code, code)
  assert_eq(error.operation, operation)
  assert_true(error.message.length() > 0)
}

///|
test "SDK entry points preserve successful bytes receipts and exact work accounting" {
  let input = planner_fixture()
  let raw_control = WorkControl::default()
  let expected = rebuild_verified(input, control=raw_control)
  let control = WorkControl::new(work_units=raw_control.used())
  guard clean_document(input, control~) is Ok(cleaned) else {
    fail("clean failed")
  }
  assert_eq(cleaned.bytes, expected.bytes)
  assert_eq(cleaned.receipt, expected.receipt)
  assert_eq(control.used(), raw_control.used())
  assert_eq(control.remaining(), 0)
  let shared = WorkControl::default()
  guard prepare_document(input, control=shared) is Ok(plan) else {
    fail("prepare failed")
  }
  assert_eq(plan, prepare(input))
  guard execute_document_plan(input, plan.to_json(), control=shared)
    is Ok(executed) else {
    fail("plan execution failed")
  }
  assert_eq(executed.bytes, expected.bytes)
  assert_eq(executed.receipt, expected.receipt)
  guard verify_document(executed.bytes, input, control=shared) is Ok(receipt) else {
    fail("archive verify failed")
  }
  assert_eq(receipt, expected.receipt)
  assert_eq(receipt.independent_validation, NotChecked)
  assert_true(shared.used() > raw_control.used())
}

///|
test "SDK preflight codes distinguish bad configuration input and output bounds" {
  let input = planner_fixture()
  let limits = Limits::default()
  sdk_expect_failure(
    clean_document(input, limits={ ..limits, entries: 0, }),
    InvalidConfiguration,
    CleanDocument,
  )
  let small = { ..limits, input_bytes: input.length() - 1, }
  sdk_expect_failure(
    clean_document(input, limits=small),
    InputLimitExceeded,
    CleanDocument,
  )
  sdk_expect_failure(
    prepare_document(input, limits=small),
    InputLimitExceeded,
    PrepareDocument,
  )
  sdk_expect_failure(
    execute_document_plan(input, Json::null(), limits=small),
    InputLimitExceeded,
    ExecuteDocumentPlan,
  )
  let output = rebuild_verified(input).bytes
  sdk_expect_failure(
    verify_document(output, input, limits=small),
    InputLimitExceeded,
    VerifyDocument,
  )
  sdk_expect_failure(
    verify_document(output, input, limits={
      ..limits,
      output_bytes: output.length() - 1,
    }),
    OutputLimitExceeded,
    VerifyDocument,
  )
}

///|
test "SDK distinguishes unknown coverage and incomplete parsing without message matching" {
  for input in [b"", b"not a ZIP"] {
    sdk_expect_failure(
      clean_document(input),
      ProcessingIncomplete,
      CleanDocument,
    )
    sdk_expect_failure(
      prepare_document(input),
      ProcessingIncomplete,
      PrepareDocument,
    )
  }
  let archive = @zip.read(planner_fixture()[:])
  let text = @utf8.decode(archive.get("xl/worksheets/sheet1.xml").unwrap())
  assert_true(
    archive.replace(
      "xl/worksheets/sheet1.xml",
      @utf8.encode(
        text.replace(old="</worksheet>", new="<unknown/></worksheet>")[:],
      )[:],
    ),
  )
  let unsupported = @zip.write(archive)
  sdk_expect_failure(
    clean_document(unsupported),
    UnsupportedDocument,
    CleanDocument,
  )
  sdk_expect_failure(
    execute_document_plan(unsupported, Json::null()),
    UnsupportedDocument,
    ExecuteDocumentPlan,
  )
}

///|
test "SDK plan tampering source substitution and actual output changes cannot pass" {
  let input = planner_fixture()
  let prepared = prepare(input)
  let forged = { ..prepared, input_hash: "0".repeat(64), }
  sdk_expect_failure(
    execute_document_plan(input, forged.to_json()),
    IntegrityFailure,
    ExecuteDocumentPlan,
  )
  let other = @zip.read(input[:])
  other.set_comment(b"different serialized original")
  sdk_expect_failure(
    execute_document_plan(@zip.write(other), prepared.to_json()),
    IntegrityFailure,
    ExecuteDocumentPlan,
  )
  let rebuilt = rebuild_verified(input)
  let modified = @zip.read(rebuilt.bytes[:])
  let xml = "<worksheet xmlns='" +
    spreadsheet_ns +
    "'><sheetData><row r='1'><c r='A1'><v>999</v></c></row></sheetData></worksheet>"
  assert_true(
    modified.replace("xl/worksheets/sheet1.xml", @utf8.encode(xml[:])[:]),
  )
  sdk_expect_failure(
    verify_document(@zip.write(modified), input),
    IntegrityFailure,
    VerifyDocument,
  )
}

///|
test "SDK stop codes are typed sticky and preserve original error compatibility" {
  let input = planner_fixture()
  let cancelled = WorkControl::default()
  cancelled.cancel()
  sdk_expect_failure(
    clean_document(input, control=cancelled),
    Cancelled,
    CleanDocument,
  )
  sdk_expect_failure(
    prepare_document(input, control=cancelled),
    Cancelled,
    PrepareDocument,
  )
  sdk_expect_failure(
    execute_document_plan(input, Json::null(), control=cancelled),
    Cancelled,
    ExecuteDocumentPlan,
  )
  sdk_expect_failure(
    verify_document(b"bad", input, control=cancelled),
    Cancelled,
    VerifyDocument,
  )
  assert_eq(cancelled.stop_kind(), Some(CancelRequested))
  assert_eq(cancelled.used(), 0)
  expect_incomplete(fn() raise {
    ignore(rebuild_verified(input, control=cancelled))
  })
  let exhausted = WorkControl::new(work_units=0)
  sdk_expect_failure(
    clean_document(input, control=exhausted),
    WorkBudgetExceeded,
    CleanDocument,
  )
  exhausted.cancel()
  assert_eq(exhausted.stop_kind(), Some(AllowanceExhausted))
  sdk_expect_failure(
    prepare_document(input, control=exhausted),
    WorkBudgetExceeded,
    PrepareDocument,
  )
  let pairs = WorkControl::new(work_units=1)
  expect_incomplete(fn() raise { pairs.pairs("pairs", 2, 2) })
  assert_eq(pairs.stop_kind(), Some(AllowanceExhausted))
  sdk_expect_failure(
    clean_document(input, control=pairs),
    WorkBudgetExceeded,
    CleanDocument,
  )
  for stage in ["xml-event", "receipt-complete"] {
    let control = WorkControl::new(should_cancel=current => current == stage)
    sdk_expect_failure(
      clean_document(input, control~),
      Cancelled,
      CleanDocument,
    )
    assert_eq(control.stop_kind(), Some(CancelRequested))
  }
}

///|
test "SDK diagnostics do not infer codes from human messages or conceal unexpected errors" {
  let control = WorkControl::default()
  assert_eq(
    sdk_failure(
      Refused("cancelled or CRC or exhausted"),
      CleanDocument,
      control,
    ).code,
    UnsupportedDocument,
  )
  assert_eq(
    sdk_failure(
      Incomplete("arbitrary explanatory text"),
      VerifyDocument,
      control,
    ).code,
    ProcessingIncomplete,
  )
  assert_eq(
    sdk_failure(Invalid("new wording"), ExecuteDocumentPlan, control).code,
    IntegrityFailure,
  )
  assert_eq(
    sdk_failure(Failure("unexpected callback failure"), CleanDocument, control).code,
    InternalFailure,
  )
  let labels = [
    InvalidConfiguration,
    UnsupportedDocument,
    ProcessingIncomplete,
    IntegrityFailure,
    InputLimitExceeded,
    OutputLimitExceeded,
    Cancelled,
    WorkBudgetExceeded,
    InternalFailure,
  ].map(code => code.label())
  assert_eq(labels, [
    "invalid_configuration", "unsupported_document", "processing_incomplete", "integrity_failure",
    "input_limit_exceeded", "output_limit_exceeded", "cancelled", "work_budget_exceeded",
    "internal_failure",
  ])
  assert_eq(
    SdkFailure::{
      code: Cancelled,
      operation: CleanDocument,
      message: "detail",
    }.to_json(),
    { "code": "cancelled", "operation": "clean_document", "message": "detail" },
  )
}
