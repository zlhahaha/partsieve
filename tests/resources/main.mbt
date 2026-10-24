///|
fn expect_incomplete(action : () -> Unit raise) -> Unit raise {
  action() catch {
    @sieve.Incomplete(_) => return
    error => fail("expected Incomplete: " + error.to_string())
  }
  fail("expected resource refusal")
}

///|
fn make_input(name : String) -> Bytes raise {
  let word = name.has_prefix("word-")
  let archive = @zip.read(
    @host.read_bounded(
      "tests/fixtures/business/" +
      (if word { "document-layout.docm" } else { "report-inline.xlsm" }),
      33554432,
    )[:],
  )
  let (part, text) = if word {
    let chunks = match name {
      "word-1m" => 32
      "word-4m" => 128
      "word-7m" => 224
      "word-xml-over" => 256
      _ => fail("unknown Word size")
    }
    let paragraph = "<w:p><w:r><w:t>" +
      Array::make(32768, "x").join("") +
      "</w:t></w:r></w:p>"
    let original = @utf8.decode(archive.get("word/document.xml").unwrap())
    assert_true(original.contains("<w:body>"))
    (
      "word/document.xml",
      original.replace(
        old="<w:body>",
        new="<w:body>" + Array::make(chunks, paragraph).join(""),
      ),
    )
  } else {
    let rows = match name {
      "sheet-5000" => 5000
      "sheet-20000" => 20000
      "sheet-nodes-over" => 50000
      _ => fail("unknown sheet size")
    }
    let body = Array::makei(rows, fn(i) {
      let row = (i + 1).to_string()
      "<row r='" +
      row +
      "'><c r='A" +
      row +
      "' t='inlineStr'><is><t>Row " +
      row +
      "</t></is></c></row>"
    }).join("")
    (
      "xl/worksheets/sheet1.xml",
      "<worksheet xmlns='http://schemas.openxmlformats.org/spreadsheetml/2006/main'><sheetData>" +
      body +
      "</sheetData></worksheet>",
    )
  }
  let payload = @utf8.encode(text[:])
  // Store the large XML so compressed input size is also exercised.
  assert_true(archive.remove(part[:]))
  archive.add(part, payload[:], compression=@zip.Store)
  @zip.write(archive)
}

///|
fn run_case(name : String) -> Unit raise {
  let input = make_input(name)
  if name.has_suffix("-over") {
    let report = @sieve.assess(input)
    assert_eq(report.decision.result, @sieve.IncompleteResult)
    assert_eq(report.decision.rebuild_allowed, false)
    assert_eq(report.coverage.parse_complete, false)
    expect_incomplete(fn() raise { ignore(@sieve.rebuild_verified(input)) })
    println(
      Json::object({
        "case": name.to_json(),
        "input_bytes": input.length().to_json(),
        "result": "ExpectedIncomplete".to_json(),
        "reason": report.decision.reason.to_json(),
      }).stringify(),
    )
    return
  }
  let control = @sieve.WorkControl::default()
  let rebuilt = @sieve.rebuild_verified(input, control~)
  assert_eq(rebuilt.receipt.result, @sieve.Pass)
  let used = control.used()
  // Every repeated parse consumes this same allowance; losing even one unit
  // from the measured deterministic amount prevents a successful return.
  expect_incomplete(fn() raise {
    ignore(
      @sieve.rebuild_verified(
        input,
        control=@sieve.WorkControl::new(work_units=used - 1),
      ),
    )
  })
  let short_input = {
    ..@sieve.Limits::default(),
    input_bytes: input.length() - 1,
  }
  expect_incomplete(fn() raise {
    ignore(@sieve.rebuild_verified(input, limits=short_input))
  })
  let output_limit = {
    ..@sieve.Limits::default(),
    output_bytes: rebuilt.bytes.length() - 1,
  }
  expect_incomplete(fn() raise {
    ignore(@sieve.rebuild_verified(input, limits=output_limit))
  })
  let mut xml_checks = 0
  let cancelled = @sieve.WorkControl::new(should_cancel=fn(stage) {
    if stage == "xml-event" {
      xml_checks += 1
    }
    xml_checks >= 20
  })
  expect_incomplete(fn() raise {
    ignore(@sieve.rebuild_verified(input, control=cancelled))
  })
  assert_eq(cancelled.stop_reason(), Some("operation cancelled by caller"))
  let mut zip_checks = 0
  let zip_cancelled = @sieve.WorkControl::new(should_cancel=fn(stage) {
    if stage == "zip-read" {
      zip_checks += 1
    }
    zip_checks >= 20
  })
  expect_incomplete(fn() raise {
    ignore(@sieve.rebuild_verified(input, control=zip_cancelled))
  })
  assert_eq(zip_cancelled.stop_reason(), Some("operation cancelled by caller"))
  println(
    Json::object({
      "case": name.to_json(),
      "input_bytes": input.length().to_json(),
      "output_bytes": rebuilt.bytes.length().to_json(),
      "output_sha256": rebuilt.receipt.output_hash.to_json(),
      "work_used": used.to_json(),
      "result": "Pass".to_json(),
      "checks": [
        "verified-rebuild", "work-minus-one", "input-minus-one", "output-minus-one",
        "xml-cancel", "zip-cancel",
      ].to_json(),
    }).stringify(),
  )
}

///|
fn main raise {
  let args = @env.args()
  if args.length() == 2 {
    run_case(args[1])
  } else {
    for name in ["word-1m", "word-4m", "word-7m", "sheet-5000", "sheet-20000"] {
      run_case(name)
    }
  }
}
