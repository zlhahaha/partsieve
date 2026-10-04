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

///|
test "output growth is checked against output limit rather than original input limit" {
  let archive = @zip.read(planner_fixture()[:])
  let ct = "<Types xmlns='" +
    ct_ns +
    "'><Default Extension='rels' ContentType='application/vnd.openxmlformats-package.relationships+xml'/><Default Extension='xml' ContentType='" +
    xlsm_ct +
    "'/><Override PartName='/xl/worksheets/sheet1.xml' ContentType='application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml'/></Types>"
  assert_true(archive.replace("[Content_Types].xml", @utf8.encode(ct[:])[:]))
  let input = @zip.write(archive)
  let baseline = rebuild(input)
  assert_true(baseline.bytes.length() > input.length())
  let limits = {
    ..Limits::default(),
    input_bytes: input.length(),
    output_bytes: baseline.bytes.length(),
  }
  let actual = rebuild_verified(input, limits~)
  assert_eq(actual.bytes, baseline.bytes)
  assert_eq(rebuild(input, limits~).bytes, baseline.bytes)
  assert_eq(verify(actual.bytes, input, limits~).preservation, "Pass")
  assert_eq(verify_contract(actual.bytes, input, limits~).result, Pass)
  expect_incomplete(fn() raise {
    ignore(
      rebuild_verified(input, limits={
        ..limits,
        output_bytes: limits.output_bytes - 1,
      }),
    )
  })
  expect_incomplete(fn() raise { ignore(audit(actual.bytes, limits~)) })
}
