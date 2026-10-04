///|
fn planner_fixture() -> Bytes raise {
  let archive = @zip.Archive()
  archive.add(
    "[Content_Types].xml",
    @utf8.encode(
      ("<Types xmlns='" +
      ct_ns +
      "'><Default Extension='rels' ContentType='application/vnd.openxmlformats-package.relationships+xml'/><Override PartName='/xl/workbook.xml' ContentType='" +
      xlsm_ct +
      "'/><Override PartName='/xl/worksheets/sheet1.xml' ContentType='application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml'/></Types>")[:],
    )[:],
  )
  archive.add(
    "_rels/.rels",
    @utf8.encode(
      ("<Relationships xmlns='" +
      rel_ns +
      "'><Relationship Id='main' Type='" +
      office_rel +
      "officeDocument' Target='xl/workbook.xml'/></Relationships>")[:],
    )[:],
  )
  archive.add(
    "xl/_rels/workbook.xml.rels",
    @utf8.encode(
      ("<Relationships xmlns='" +
      rel_ns +
      "'><Relationship Id='sheet' Type='" +
      office_rel +
      "worksheet' Target='worksheets/sheet1.xml'/></Relationships>")[:],
    )[:],
  )
  archive.add(
    "xl/workbook.xml",
    @utf8.encode(
      ("<workbook xmlns='" +
      spreadsheet_ns +
      "' xmlns:r='http://schemas.openxmlformats.org/officeDocument/2006/relationships'><sheets><sheet name='Sheet1' sheetId='1' r:id='sheet'/></sheets></workbook>")[:],
    )[:],
  )
  archive.add(
    "xl/worksheets/sheet1.xml",
    @utf8.encode(
      ("<worksheet xmlns='" + spreadsheet_ns + "'><sheetData/></worksheet>")[:],
    )[:],
  )
  @zip.write(archive)
}

///|
fn expect_invalid(action : () -> Unit raise) -> Unit raise {
  action() catch {
    Invalid(_) => return
    error => fail("expected Invalid, got " + error.to_string())
  }
  fail("expected Invalid")
}

///|
test "prepared SDK binds every part hash limits decisions and actual format" {
  let input = planner_fixture()
  let prepared = prepare(input)
  assert_eq(prepared, prepare(input))
  assert_eq(prepared.preconditions.length(), 5)
  assert_eq(prepared.findings.length(), 0)
  assert_eq(prepared.decisions.length(), 1)
  assert_eq(prepared.decisions[0].finding_index, None)
  assert_eq(prepared.output_format, "XLSX")
  assert_eq(prepared.operations.length(), 2)
  assert_eq(prepared.operations[1].depends_on, ["op-0"])
  let output = rebuild_with_plan(input, prepared.to_json())
  assert_eq(output.bytes, rebuild(input).bytes)
  expect_invalid(fn() raise {
    ignore(
      rebuild_with_plan(input, { ..prepared, input_hash: "changed", }.to_json()),
    )
  })
  expect_invalid(fn() raise {
    ignore(
      rebuild_with_plan(
        input,
        {
          ..prepared,
          limits: { ..prepared.limits, input_bytes: input.length(), },
        }.to_json(),
      ),
    )
  })
}

///|
test "planner rejects duplicate operations payload conflicts and dependency cycles" {
  let operations = prepare(planner_fixture()).operations
  expect_invalid(fn() raise {
    validate_operation_conflicts([operations[0], operations[0]])
  })
  let rewrite = operations[1]
  let removal = {
    ..rewrite,
    operation_id: "another",
    kind: RemovePart,
    depends_on: [],
  }
  expect_invalid(fn() raise {
    validate_operation_conflicts([operations[0], rewrite, removal])
  })
  expect_invalid(fn() raise {
    validate_operation_conflicts([
      { ..operations[0], depends_on: ["op-1"], },
      rewrite,
    ])
  })
  expect_invalid(fn() raise {
    validate_operation_conflicts([{ ..operations[0], depends_on: ["op-0"], }])
  })
}

///|
test "closure protects main parts retained relationships and source XML references" {
  let pkg = load_package(planner_fixture(), Limits::default())
  let prepared = make_prepared_plan(pkg, Limits::default())
  expect_invalid(fn() raise {
    validate_removal_closure(pkg, {
      ..prepared,
      controlled_removals: [pkg.audit.main_part],
    })
  })
  let sheet = "xl/worksheets/sheet1.xml"
  let removed : CheckedOperation = {
    operation_id: "remove-sheet",
    kind: RemovePart,
    part: sheet,
    source: sheet,
    relationship_id: "",
    rule_id: "test-only",
    decision_id: "format",
    before_hash: pkg.audit.parts[pkg.graph.part_index[sheet]].sha256,
    expected_after_hash: None,
    depends_on: [],
    reason: "artificial closure test",
  }
  let relation : CheckedOperation = {
    ..removed,
    operation_id: "remove-relation",
    kind: RemoveRelationship,
    source: pkg.audit.main_part,
    relationship_id: "sheet",
  }
  expect_refused(fn() raise {
    validate_removal_closure(pkg, {
      ..prepared,
      operations: [removed],
      controlled_removals: [sheet],
    })
  })
  expect_refused(fn() raise {
    validate_removal_closure(pkg, {
      ..prepared,
      operations: [removed, relation],
      controlled_removals: [sheet],
    })
  })
}

///|
test "source XML operation cannot bypass the absent accepted handler" {
  let pkg = load_package(planner_fixture(), Limits::default())
  let prepared = make_prepared_plan(pkg, Limits::default())
  let main = pkg.audit.parts[pkg.graph.part_index[pkg.audit.main_part]]
  let source : CheckedOperation = {
    operation_id: "unaccepted-source",
    kind: RewriteSourceXml,
    part: main.name,
    source: main.name,
    relationship_id: "",
    rule_id: "test-only",
    decision_id: "format",
    before_hash: main.sha256,
    expected_after_hash: Some(main.sha256),
    depends_on: [],
    reason: "No source XML handler has passed acceptance.",
  }
  expect_refused(fn() raise {
    ignore(
      execute_prepared(
        pkg,
        { ..prepared, operations: [source], },
        Limits::default(),
      ),
    )
  })
}
