///|
fn output_root() -> String {
  @env.get_env_var("PARTSIEVE_TEST_OUTPUT").unwrap_or("tests/generated")
}

///|
// Bounded deterministic mutations, not an exhaustive fuzzer or a safety proof.
priv struct Run {
  directory : String
  executable : String
  cases : Array[Json]
  mut cli_checks : Int32
  mut positive_cli_checks : Int32
  mut publication_guards : Int32
}

///|
fn Run::save(self : Run, status : String) -> Unit raise {
  @fs.write_string_to_file(
    output_root() + "/robustness-v1.json",
    (
      {
        "schema": "partsieve.robustness.v1",
        "seed": 20261029,
        "result": status,
        "case_count": self.cases.length(),
        "cli_rejection_checks": self.cli_checks,
        "positive_cli_checks": self.positive_cli_checks,
        "publication_guards": self.publication_guards,
        "cases": ToJson::to_json(self.cases),
      } : Json).stringify(),
  )
}

///|
fn fixture(name : String) -> Bytes raise {
  @host.read_bounded("tests/fixtures/business/" + name, 33554432)
}

///|
fn edit(
  input : Bytes,
  part : String,
  old : String,
  replacement : String,
) -> Bytes raise {
  let archive = @zip.read(input[:])
  let text = @utf8.decode(archive.get(part[:]).unwrap())
  assert_true(text.contains(old), msg="mutation anchor: " + part)
  assert_true(
    archive.replace(
      part[:],
      @utf8.encode(text.replace(old~, new=replacement)[:])[:],
    ),
  )
  @zip.write(archive)
}

///|
fn refusal(action : () -> Unit raise) -> String raise {
  action() catch {
    @sieve.Invalid(reason) => return "Invalid: " + reason
    @sieve.Refused(reason) => return "Refused: " + reason
    @sieve.Incomplete(reason) => return "Incomplete: " + reason
    error => fail("unexpected exception: " + error.to_string())
  }
  fail("unexpected successful operation")
}

///|
fn incomplete(action : () -> Unit raise) -> Unit raise {
  action() catch {
    @sieve.Incomplete(_) => return
    error => fail("expected Incomplete, got " + error.to_string())
  }
  fail("expected incomplete operation")
}

///|
fn Run::reject(
  self : Run,
  category : String,
  name : String,
  input : Bytes,
  cli~ : Bool = false,
) -> Unit raise {
  let assessment = @sieve.assess(input)
  // Persist the observation before asserting, so CI failures retain the counterexample hash.
  self.cases.push({
    "category": ToJson::to_json(category),
    "name": ToJson::to_json(name),
    "input_sha256": ToJson::to_json(@sieve.digest(input[:])),
    "assessment": assessment.decision.result.to_json(),
    "reason": ToJson::to_json(assessment.decision.reason),
    "expected": "Reject",
  })
  self.save("Running")
  assert_false(assessment.decision.rebuild_allowed, msg=name)
  assert_true(assessment.decision.result != @sieve.Pass, msg=name)
  if !assessment.coverage.parse_complete {
    assert_true(
      assessment.coverage.rules.all(r => r.presence == @sieve.Unknown),
      msg=name,
    )
  }
  ignore(refusal(fn() raise { ignore(@sieve.prepare(input)) }))
  ignore(refusal(fn() raise { ignore(@sieve.rebuild_verified(input)) }))
  if cli {
    let source = self.directory + "/" + name + ".input"
    let output = self.directory + "/" + name + ".docx"
    let receipt = self.directory + "/" + name + ".receipt.json"
    @host.write_new(source, input)
    assert_false(@host.exists(output) || @host.exists(receipt))
    let process = @host.run(
      self.executable,
      [
        "rebuild", source, "-o", output, "--receipt", receipt, "--receipt-format",
        "v2", "--timeout-ms", "5000",
      ],
      timeout_ms=10000,
    )
    assert_true(process.code == 2 || process.code == 3, msg=name)
    ignore(@cli.parse_json(process.stdout))
    assert_false(@host.exists(output) || @host.exists(receipt), msg=name)
    self.cli_checks += 1
  }
}

///|
fn Run::accept(
  self : Run,
  name : String,
  input : Bytes,
  cli~ : Bool = false,
) -> Unit raise {
  let assessed = @sieve.assess(input)
  assert_true(assessed.decision.rebuild_allowed, msg=name)
  let rebuilt = @sieve.rebuild_verified_with_plan(
    input,
    @sieve.prepare(input).to_json(),
  )
  assert_eq(
    @sieve.verify_contract(rebuilt.bytes, input),
    rebuilt.receipt,
    msg=name,
  )
  let before = @zip.read(input[:])
  let after = @zip.read(rebuilt.bytes[:])
  let mut preserved = 0
  for disposition in rebuilt.receipt.dispositions {
    if disposition.classification == @sieve.BytePreservedKind {
      assert_eq(
        before.get(disposition.part[:]),
        after.get(disposition.part[:]),
        msg=name,
      )
      preserved += 1
    }
  }
  assert_true(preserved > 0, msg=name)
  if cli {
    let source = self.directory + "/" + name + ".input"
    let suffix = if rebuilt.receipt.output_format == "DOCX" {
      ".docx"
    } else {
      ".xlsx"
    }
    let output = self.directory + "/" + name + suffix
    let receipt = self.directory + "/" + name + ".receipt.json"
    @host.write_new(source, input)
    let process = @host.run(self.executable, [
      "rebuild", source, "-o", output, "--receipt", receipt, "--receipt-format",
      "v2",
    ])
    assert_eq(process.code, 0, msg=name)
    assert_eq(@cli.parse_json(process.stdout), rebuilt.receipt.to_json())
    assert_eq(@host.read_bounded(output, 67108864), rebuilt.bytes)
    let verified = @host.run(self.executable, [
      "verify", output, "--original", source, "--receipt", receipt, "--receipt-format",
      "v2",
    ])
    assert_eq(verified.code, 0, msg=name)
    assert_eq(@cli.parse_json(verified.stdout), rebuilt.receipt.to_json())
    self.positive_cli_checks += 2
  }
  self.cases.push({
    "category": "positive-control",
    "name": ToJson::to_json(name),
    "input_sha256": ToJson::to_json(@sieve.digest(input[:])),
    "output_sha256": ToJson::to_json(rebuilt.receipt.output_hash),
    "expected": "Pass",
    "actual": rebuilt.receipt.result.to_json(),
  })
  self.save("Running")
}

///|
fn Run::publication_guard(
  self : Run,
  name : String,
  input : Bytes,
) -> Unit raise {
  let source = self.directory + "/" + name + ".input"
  let output = self.directory + "/" + name + ".docx"
  let receipt = self.directory + "/" + name + ".receipt.json"
  let sentinel = b"existing-user-file-must-remain-byte-identical"
  @host.write_new(source, input)
  if name == "existing-output" {
    @host.write_new(output, sentinel)
  }
  if name == "existing-receipt" {
    @host.write_new(receipt, sentinel)
  }
  let destination = if name == "output-receipt-alias" {
    output
  } else if name == "input-receipt-alias" {
    source
  } else {
    receipt
  }
  let process = @host.run(self.executable, [
    "rebuild", source, "-o", output, "--receipt", destination, "--receipt-format",
    "v2",
  ])
  assert_eq(process.code, 4, msg=name)
  assert_eq(@host.read_bounded(source, 33554432), input, msg=name)
  if name == "existing-output" {
    assert_eq(@host.read_bounded(output, 128), sentinel)
    assert_false(@host.exists(receipt))
  } else if name == "existing-receipt" {
    assert_eq(@host.read_bounded(receipt, 128), sentinel)
    assert_false(@host.exists(output))
  } else {
    assert_false(@host.exists(output) || @host.exists(receipt))
  }
  self.publication_guards += 1
  self.cases.push({
    "category": "publication-guard",
    "name": ToJson::to_json(name),
    "expected_exit": 4,
    "actual_exit": ToJson::to_json(process.code),
  })
  self.save("Running")
}

///|
fn find(input : Bytes, needle : Bytes) -> Int32 raise {
  for i in 0..<(input.length() - needle.length() + 1) {
    if input[i:i + needle.length()] == needle[:] {
      return i
    }
  }
  fail("missing ZIP mutation anchor")
}

///|
fn changed_byte(input : Bytes, position : Int32, value : Byte) -> Bytes {
  Bytes::makei(input.length(), i => if i == position { value } else { input[i] })
}

///|
fn main raise {
  if !@host.exists("tests/generated") {
    @host.create_directory("tests/generated")
  }
  if @env.get_env_var("PARTSIEVE_TEST_OUTPUT") is None {
    @env.set_env_var(
      "PARTSIEVE_TEST_OUTPUT",
      @host.temp_dir(parent="tests/generated"),
    )
  }
  println("Regression output: " + output_root())
  let stem = "_build/native/debug/build/cmd/main/main"
  let run : Run = {
    directory: @host.temp_dir(parent=output_root()),
    executable: @host.absolute(
      if @host.exists(stem + ".exe") {
        stem + ".exe"
      } else {
        stem
      },
    ),
    cases: [],
    cli_checks: 0,
    positive_cli_checks: 0,
    publication_guards: 0,
  }
  run.save("Running")
  let word = fixture("demo-word-three-objects.docm")
  let sheet = fixture("report-1900.xlsm")
  let table = @host.read_bounded(
    "tests/fixtures/poi/word-modern/TestTableCellAlign.docx", 33554432,
  )
  run.accept("poi-word-table", table, cli=true)
  for
    (name, border) in [
      ("table-border-external-attribute", "<w:tblBorders r:id='dangling'>"),
      ("table-border-unknown-edge", "<w:tblBorders><w:start w:val='single'/>"),
      ("table-border-duplicate-edge", "<w:tblBorders><w:top w:val='single'/>"),
      (
        "table-border-foreign-namespace", "<w:tblBorders><w:top xmlns:w='urn:other'/>",
      ),
      ("table-border-width", "<w:tblBorders><w:top w:val='single' w:sz='97'/>"),
    ] {
    run.reject(
      "word-table-style",
      name,
      edit(table, "word/styles.xml", "<w:tblBorders>", border),
      cli=true,
    )
  }
  let header_picture = @host.read_bounded(
    "tests/fixtures/poi/word-modern/headerPic.docx", 33554432,
  )
  run.accept("poi-header-picture", header_picture, cli=true)
  for
    (name, part, old, replacement) in [
      (
        "header-crop-nondefault", "word/header1.xml", "<a:srcRect/>", "<a:srcRect l='1'/>",
      ),
      (
        "header-crop-duplicate", "word/header1.xml", "<a:srcRect/>", "<a:srcRect/><a:srcRect/>",
      ),
      (
        "header-crop-namespace", "word/header1.xml", "<a:srcRect/>", "<a:srcRect xmlns:a='urn:other'/>",
      ),
      (
        "header-outline-unknown", "word/header1.xml", "<a:headEnd/>", "<a:headEnd type='triangle'/>",
      ),
      (
        "header-outline-bound", "word/header1.xml", "lim=\"800000\"", "lim=\"1000001\"",
      ),
      (
        "header-proofing-duplicate", "word/header1.xml", "<w:noProof/>", "<w:noProof/><w:noProof/>",
      ),
      (
        "header-proofing-child", "word/header1.xml", "<w:noProof/>", "<w:noProof><w:b/></w:noProof>",
      ),
      (
        "header-picture-dangling", "word/header1.xml", "r:embed=\"rId1\"", "r:embed=\"rId999\"",
      ),
      (
        "header-picture-wrong-kind", "word/_rels/header1.xml.rels", "relationships/image",
        "relationships/styles",
      ),
      (
        "header-picture-external", "word/_rels/header1.xml.rels", "Target=\"media/image1.jpeg\"",
        "Target=\"https://example.invalid/photo.jpeg\" TargetMode=\"External\"",
      ),
      (
        "word-layout-grid-bound", "word/settings.xml", "<w:drawingGridHorizontalSpacing w:val=\"100\"/>",
        "<w:drawingGridHorizontalSpacing w:val=\"31681\"/>",
      ),
      (
        "word-layout-flag-duplicate", "word/settings.xml", "<w:doNotHyphenateCaps/>",
        "<w:doNotHyphenateCaps/><w:doNotHyphenateCaps/>",
      ),
      (
        "word-layout-font-embedding", "word/settings.xml", "<w:embedSystemFonts/>",
        "<w:embedTrueTypeFonts/><w:embedSystemFonts/>",
      ),
    ] {
    run.reject(
      "word-header-picture",
      name,
      edit(header_picture, part, old, replacement),
      cli=true,
    )
  }
  run.accept("word-three-objects", word, cli=true)
  run.accept("spreadsheet-business", sheet, cli=true)
  run.accept(
    "word-comment",
    edit(
      word, "word/document.xml", "<w:body>", "<w:body><!-- harmless deterministic control -->",
    ),
  )
  run.accept(
    "changed-normal-text",
    edit(
      word, "word/document.xml", "Between objects 中文 1", "Changed normal text 中文",
    ),
  )
  let stored_archive = @zip.Archive()
  for entry in @zip.read(word[:]).entries() {
    stored_archive.add(entry.name(), entry.data(), compression=@zip.Store)
  }
  let stored = @zip.write(stored_archive)
  run.accept("stored-zip", stored)

  // Remove the end record at many offsets; every sample is genuinely truncated.
  let offsets = [
    0,
    1,
    2,
    3,
    4,
    10,
    30,
    word.length() / 2,
    word.length() - 22,
    word.length() - 1,
  ]
  let mut seed : Int64 = 20261029
  for _ in 0..<24 {
    seed = seed * 48271 % 2147483647
    offsets.push((seed % (word.length() - 1).to_int64()).to_int())
  }
  let seen : Map[Int32, Bool] = Map([])
  for index, offset in offsets {
    if !seen.contains(offset) {
      seen[offset] = true
      run.reject(
        "zip-truncation",
        "cut-" + offset.to_string(),
        word[:offset].to_owned(),
        cli=index < 5,
      )
    }
  }
  // Alter stored document payload while retaining both recorded CRC values.
  let payload = @zip.read(stored[:])
    .get("word/document.xml")
    .unwrap()
    .to_owned()
  let start = find(stored, payload)
  let positions : Map[Int32, Bool] = Map([])
  for index in 0..<32 {
    seed = seed * 48271 % 2147483647
    let offset = (seed % payload.length().to_int64()).to_int()
    if !positions.contains(offset) {
      positions[offset] = true
      let old = stored[start + offset].to_int()
      let bad = changed_byte(
        stored,
        start + offset,
        (if old == 0 { 1 } else { old - 1 }).to_byte(),
      )
      run.reject(
        "zip-crc-corruption",
        "crc-" + offset.to_string(),
        bad,
        cli=index < 3,
      )
    }
  }
  // Mutate local and central bookkeeping separately, not only document XML.
  let central = find(stored, b"PK\x01\x02")
  for
    (name, offset) in [
      ("local-signature", 0),
      ("local-flags", 6),
      ("local-method", 8),
      ("local-crc", 14),
      ("local-size", 18),
      ("local-name", 30),
      ("central-signature", central),
      ("central-crc", central + 16),
      ("central-local-offset", central + 42),
    ] {
    let old = stored[offset].to_int()
    run.reject(
      "zip-headers",
      name,
      changed_byte(stored, offset, ((old + 1) % 256).to_byte()),
      cli=true,
    )
  }
  for
    (name, xml) in [
      ("xml-empty", b""),
      ("xml-truncated", b"<w:document"),
      ("xml-utf8", b"\xff"),
      ("xml-nul", b"<a>\x00</a>"),
      ("xml-two-roots", b"<a/><b/>"),
      ("xml-entity", b"<a>&undefined;</a>"),
      ("xml-dtd", b"<!DOCTYPE a [<!ENTITY e 'x'>]><a>&e;</a>"),
      (
        "xml-external-dtd", b"<!DOCTYPE a SYSTEM 'https://example.invalid/no-fetch'><a/>",
      ),
      ("xml-duplicate-attribute", b"<a x='1' x='2'/>"),
      ("xml-undeclared-prefix", b"<missing:document/>"),
      (
        "xml-wrong-namespace", b"<document xmlns='urn:unknown'><body/></document>",
      ),
      ("xml-character-zero", b"<a>&#0;</a>"),
    ] {
    let archive = @zip.read(word[:])
    assert_true(archive.replace("word/document.xml", xml[:]))
    run.reject(
      "xml-invalid-or-unsupported",
      name,
      @zip.write(archive),
      cli=true,
    )
  }
  for
    index, name in [
      "../escape.xml", "/absolute.xml", "word/../escape.xml", "word//x.xml", "word\\x.xml",
      "word/x%2f.xml", "word/x.xml#fragment", "word/x.xml?query", "word/DOCUMENT.xml",
    ] {
    let archive = @zip.read(word[:])
    archive.add(name, b"<a/>")
    run.reject(
      "opc-invalid-part-name",
      "part-" + index.to_string(),
      @zip.write(archive),
      cli=index < 2,
    )
  }
  let duplicate = @zip.read(word[:])
  duplicate.add(
    "word/document.xml",
    duplicate.get("word/document.xml").unwrap(),
  )
  run.reject("opc-duplicate", "duplicate-main", @zip.write(duplicate), cli=true)
  let missing = @zip.read(word[:])
  assert_true(missing.remove("word/media/logo.png"))
  run.reject(
    "opc-missing-target",
    "missing-image",
    @zip.write(missing),
    cli=true,
  )

  let prepared = @sieve.prepare(word)
  for
    (name, forged) in [
      ("plan-input-hash", { ..prepared, input_hash: "0".repeat(64), }),
      ("plan-parts", { ..prepared, preconditions: [], }),
      ("plan-operations", { ..prepared, operations: [], }),
      (
        "plan-limits",
        { ..prepared, limits: { ..prepared.limits, entries: 1, }, },
      ),
    ] {
    ignore(
      refusal(fn() raise {
        ignore(@sieve.rebuild_verified_with_plan(word, forged.to_json()))
      }),
    )
    run.cases.push({
      "category": "plan-binding",
      "name": ToJson::to_json(name),
      "expected": "Reject",
      "actual": "Reject",
    })
  }
  let rebuilt = @sieve.rebuild_verified(word)
  for
    (name, part, old, replacement) in [
      (
        "body-text", "word/document.xml", "Between objects 中文 1", "Forged output",
      ),
      ("header-text", "word/header1.xml", "header1", "changed"),
      ("footer-text", "word/footer1.xml", "footer1", "changed"),
    ] {
    let changed = edit(rebuilt.bytes, part, old, replacement)
    ignore(
      refusal(fn() raise { ignore(@sieve.verify_contract(changed, word)) }),
    )
    run.cases.push({
      "category": "output-preservation",
      "name": ToJson::to_json(name),
      "input_sha256": ToJson::to_json(@sieve.digest(changed[:])),
      "expected": "Reject",
      "actual": "Reject",
    })
  }
  for stage in ["zip-read", "xml-scan", "profile"] {
    let control = @sieve.WorkControl::new(should_cancel=current => {
      current == stage
    })
    incomplete(fn() raise { ignore(@sieve.rebuild_verified(word, control~)) })
    assert_eq(control.stop_reason(), Some("operation cancelled by caller"))
    let used = control.used()
    incomplete(fn() raise { ignore(@sieve.prepare(word, control~)) })
    assert_eq(control.used(), used)
    run.cases.push({
      "category": "sticky-cancellation",
      "name": ToJson::to_json(stage),
      "expected": "Incomplete",
      "actual": "Incomplete",
    })
  }
  let short = @sieve.WorkControl::new(work_units=word.length() - 1)
  incomplete(fn() raise { ignore(@sieve.rebuild_verified(word, control=short)) })
  assert_true(short.stop_reason() is Some(_))
  run.cases.push({
    "category": "work-budget",
    "name": "input-minus-one",
    "expected": "Incomplete",
    "actual": "Incomplete",
  })
  let measured = @sieve.WorkControl::default()
  let baseline = @sieve.rebuild_verified(word, control=measured)
  let exact = @sieve.WorkControl::new(work_units=measured.used())
  assert_eq(@sieve.rebuild_verified(word, control=exact).bytes, baseline.bytes)
  assert_eq(exact.remaining(), 0)
  run.cases.push({
    "category": "work-budget",
    "name": "exact-work",
    "expected": "Pass",
    "actual": "Pass",
  })
  let minus_one = @sieve.WorkControl::new(work_units=measured.used() - 1)
  incomplete(fn() raise {
    ignore(@sieve.rebuild_verified(word, control=minus_one))
  })
  run.cases.push({
    "category": "work-budget",
    "name": "exact-work-minus-one",
    "expected": "Incomplete",
    "actual": "Incomplete",
  })
  for
    name in [
      "existing-output", "existing-receipt", "input-receipt-alias", "output-receipt-alias",
    ] {
    run.publication_guard(name, word)
  }
  run.save("Pass")
  println(
    "Pass: robustness corpus " +
    run.cases.length().to_string() +
    " cases, " +
    run.cli_checks.to_string() +
    " CLI no-output checks, " +
    run.positive_cli_checks.to_string() +
    " positive CLI checks, " +
    run.publication_guards.to_string() +
    " publication guards; seed 20261029",
  )
}
