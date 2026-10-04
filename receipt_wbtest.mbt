///|
test "typed Receipt reports checked scope and independently not checked clients" {
  let input = planner_fixture()
  let rebuilt = rebuild_verified(input)
  let receipt = rebuilt.receipt
  assert_eq(receipt, verify_contract(rebuilt.bytes, input))
  assert_eq(receipt.result, Pass)
  assert_eq(receipt.input_format, "XLSM")
  assert_eq(receipt.output_format, "XLSX")
  assert_eq(receipt.findings.length(), 0)
  assert_eq(receipt.output_findings.length(), 0)
  assert_eq(receipt.dispositions.length(), 5)
  assert_eq(
    receipt.dispositions
    .filter(fn(d) { d.classification == BytePreservedKind })
    .length(),
    4,
  )
  assert_eq(
    receipt.dispositions
    .filter(fn(d) { d.classification == RegeneratedMetadataKind })
    .length(),
    1,
  )
  assert_eq(
    receipt.checks
    .filter(fn(c) { c.result == Some(Pass) && c.state == Checked })
    .length(),
    6,
  )
  assert_eq(receipt.independent_validation, NotChecked)
  assert_eq(receipt.independent_tools.length(), 0)
  assert_true(
    receipt.dispositions.all(fn(d) {
      d.classification != SemanticallyRewrittenKind
    }),
  )
  assert_true(
    receipt.output_coverage.rules.all(fn(r) {
      r.state == Checked && r.presence == Absent
    }),
  )
}

///|
test "typed rebuild binds supplied plan and incomplete output never returns a Receipt" {
  let input = planner_fixture()
  let prepared = prepare(input)
  let rebuilt = rebuild_verified_with_plan(input, prepared.to_json())
  assert_eq(rebuilt.bytes, rebuild(input).bytes)
  expect_invalid(fn() raise {
    ignore(
      rebuild_verified_with_plan(
        input,
        { ..prepared, input_hash: "fake", }.to_json(),
      ),
    )
  })
  expect_incomplete(fn() raise { ignore(verify_contract(b"PK\x03\x04", input)) })
}
