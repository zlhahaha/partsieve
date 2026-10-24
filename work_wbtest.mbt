///|
test "work control validates allowance and never overflows pair accounting" {
  for value in [-1, 1000000001] {
    expect_refused(fn() raise { ignore(WorkControl::new(work_units=value)) })
  }
  let control = WorkControl::new(work_units=10)
  control.checkpoint("exact", 10)
  assert_eq(control.used(), 10)
  assert_eq(control.remaining(), 0)
  expect_incomplete(fn() raise { control.checkpoint("over", 1) })
  assert_eq(control.used(), 10)
  expect_incomplete(fn() raise { control.checkpoint("retry", 0) })
  let pairs = WorkControl::new(work_units=1000000000)
  expect_incomplete(fn() raise {
    pairs.pairs("untrusted-counts", 2147483647, 2147483647)
  })
  assert_eq(pairs.used(), 0)
}

///|
test "pre-cancelled control refuses every document API without reading bytes" {
  let control = WorkControl::default()
  control.cancel()
  let input = b"not even a ZIP"
  expect_incomplete(fn() raise { ignore(audit(input, control~)) })
  expect_incomplete(fn() raise { ignore(inspect_graph(input, control~)) })
  expect_incomplete(fn() raise { ignore(plan(input, control~)) })
  expect_incomplete(fn() raise { ignore(prepare(input, control~)) })
  expect_incomplete(fn() raise { ignore(rebuild(input, control~)) })
  expect_incomplete(fn() raise { ignore(rebuild_verified(input, control~)) })
  expect_incomplete(fn() raise {
    ignore(
      rebuild_with_plan(
        input,
        (Map([]) : Map[String, Json]).to_json(),
        control~,
      ),
    )
  })
  expect_incomplete(fn() raise {
    ignore(
      rebuild_verified_with_plan(
        input,
        (Map([]) : Map[String, Json]).to_json(),
        control~,
      ),
    )
  })
  expect_incomplete(fn() raise { ignore(verify(input, input, control~)) })
  expect_incomplete(fn() raise {
    ignore(verify_contract(input, input, control~))
  })
  let report = assess(input, control~)
  assert_eq(report.decision.result, IncompleteResult)
  assert_eq(report.decision.rebuild_allowed, false)
  assert_eq(report.coverage.parse_complete, false)
  assert_eq(report.input_hash, None)
  assert_eq(control.used(), 0)
}

///|
test "an exact shared audit allowance succeeds and one less never passes" {
  let input = planner_fixture()
  let measured = WorkControl::default()
  let baseline = audit(input, control=measured)
  let used = measured.used()
  assert_true(used > input.length())
  assert_eq(audit(input, control=WorkControl::new(work_units=used)), baseline)
  let short = WorkControl::new(work_units=used - 1)
  expect_incomplete(fn() raise { ignore(audit(input, control=short)) })
  assert_true(short.used() <= used - 1)
  let tiny = WorkControl::new(work_units=0)
  let report = assess(input, control=tiny)
  assert_eq(report.decision.result, IncompleteResult)
  assert_eq(report.graph, None)
  assert_eq(report.input_hash, None)
}

///|
test "callback cancellation reaches ZIP XML graph profile planner and execution" {
  let input = planner_fixture()
  for
    stage in [
      "zip-read", "xml-scan", "xml-event", "graph-part", "graph-xml-node", "profile",
      "spreadsheet-profile-node", "spreadsheet-value", "prepare", "prepare-operation",
      "execute-operation", "zip-write-complete",
    ] {
    let control = WorkControl::new(should_cancel=fn(current) {
      current == stage
    })
    expect_incomplete(fn() raise { ignore(rebuild_verified(input, control~)) })
    assert_eq(control.stop_reason(), Some("operation cancelled by caller"))
  }
}

///|
test "verification cancellation cannot return a success receipt" {
  let input = planner_fixture()
  let output = rebuild_verified(input).bytes
  for
    stage in [
      "verify-contract", "verify-part", "verify-complete", "receipt", "receipt-complete",
    ] {
    let control = WorkControl::new(should_cancel=fn(current) {
      current == stage
    })
    expect_incomplete(fn() raise {
      ignore(verify_contract(output, input, control~))
    })
    assert_eq(control.stop_reason(), Some("operation cancelled by caller"))
  }
}

///|
test "one workflow allowance covers preparation execution and independent reparse" {
  let input = planner_fixture()
  let measured = WorkControl::default()
  let prepared = prepare(input, control=measured)
  let prepare_used = measured.used()
  let baseline = rebuild_verified_with_plan(
    input,
    prepared.to_json(),
    control=measured,
  )
  let full_used = measured.used()
  assert_true(full_used > prepare_used * 2)
  let exact = WorkControl::new(work_units=full_used)
  let saved = prepare(input, control=exact)
  let result = rebuild_verified_with_plan(input, saved.to_json(), control=exact)
  assert_eq(result.bytes, baseline.bytes)
  assert_eq(result.receipt, baseline.receipt)
  assert_eq(exact.used(), full_used)
  let short = WorkControl::new(work_units=full_used - 1)
  let saved = prepare(input, control=short)
  expect_incomplete(fn() raise {
    ignore(rebuild_verified_with_plan(input, saved.to_json(), control=short))
  })
  assert_true(short.stop_reason() is Some(_))
}

///|
test "cancellation during assessment stays incomplete and does not hash again" {
  let input = planner_fixture()
  let control = WorkControl::new(should_cancel=fn(stage) { stage == "profile" })
  let report = assess(input, control~)
  assert_eq(report.decision.result, IncompleteResult)
  assert_eq(report.coverage.parse_complete, false)
  assert_eq(report.coverage.checked_rules.length(), 0)
  assert_eq(report.input_hash, None)
}

///|
test "XML long text and markup loops can cancel before parser allocation" {
  let text = "<a>" + Array::make(50000, "x").join("") + "</a>"
  let comment = "<!--" + Array::make(50000, "x").join("") + "--><a/>"
  let attribute = "<a x='" + Array::make(50000, "x").join("") + "'/>"
  for source in [text, comment, attribute] {
    let mut checks = 0
    let control = WorkControl::new(should_cancel=fn(stage) {
      if stage == "xml-scan" {
        checks += 1
      }
      checks == 2
    })
    expect_incomplete(fn() raise {
      ignore(read_xml(@utf8.encode(source[:])[:], Limits::default(), control~))
    })
    assert_eq(checks, 2)
  }
}

///|
test "cancellation while diagnosing a malformed input overrides failed assessment" {
  let control = WorkControl::new(should_cancel=stage => stage == "hash")
  let report = assess(b"PK\x03\x04", control~)
  assert_eq(report.decision.result, IncompleteResult)
  assert_eq(report.decision.reason, "operation cancelled by caller")
  assert_eq(report.coverage.parse_complete, false)
  assert_eq(report.input_hash, None)
  assert_eq(control.stop_reason(), Some("operation cancelled by caller"))
}
