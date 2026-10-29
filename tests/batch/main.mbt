///|
#borrow(source, target)
extern "C" fn fixture_ffi(source : Bytes, target : Bytes, kind : Int) -> Int = "ps_batch_fixture"

///|
priv struct Run {
  root : String
  exe : String
  cases : Array[Json]
}

///|
fn field(json : Json, key : String) -> Json raise {
  guard json is Object(map) && map.get(key) is Some(value) else {
    fail("missing field: " + key)
  }
  value
}

///|
fn Run::save(self : Run, result : String) -> Unit raise {
  @fs.write_string_to_file(
    "tests/generated/batch-v1.json",
    (
      {
        "schema": "partsieve.batch-regression.v1",
        "result": result,
        "cases": self.cases.to_json(),
        "case_count": self.cases.length(),
      } : Json).stringify(),
  )
}

///|
fn Run::record(
  self : Run,
  name : String,
  result? : String = "Pass",
) -> Unit raise {
  self.cases.push({ "name": name, "result": result })
  self.save("Running")
}

///|
fn Run::directory(self : Run, name : String) -> String raise {
  let path = self.root + "/" + name
  @host.create_directory(path)
  path
}

///|
fn Run::batch(
  self : Run,
  source : String,
  output : String,
  code : Int,
) -> Json raise {
  let process = @host.run(self.exe, ["batch", source, "-o", output, "--json"])
  let report = @cli.parse_json(process.stdout)
  assert_eq(process.code, code, msg=report.stringify())
  if field(report, "schema") == Json::string("partsieve.batch.v1") {
    assert_eq(field(report, "exit_code"), code.to_json())
    assert_eq(
      @cli.parse_json(@host.read_bounded(output + "/batch.json", 16777216)),
      report,
    )
  }
  report
}

///|
fn Run::pair(
  self : Run,
  source : String,
  output : String,
  name : String,
  suffix : String,
) -> Unit raise {
  let original = @host.read_bounded(source + "/" + name, 33554432)
  let document = output + "/" + name + ".cleaned" + suffix
  let receipt = output + "/" + name + ".receipt.json"
  let bytes = @host.read_bounded(document, 67108864)
  let verified = @sieve.verify_contract(bytes, original)
  assert_eq(verified.result, @sieve.Pass)
  assert_eq(@cli.parse_json(@host.read_bounded(receipt, 16777216)), {
    "publication": "pair-complete",
    "receipt": verified.to_json(),
  })
  let cli = @host.run(self.exe, [
    "verify",
    document,
    "--original",
    source + "/" + name,
    "--receipt",
    receipt,
    "--receipt-format",
    "v2",
  ])
  assert_eq(cli.code, 0)
}

///|
fn unsupported(input : Bytes) -> Bytes raise {
  let archive = @zip.read(input[:])
  let part = "word/document.xml"
  let text = @utf8.decode(archive.get(part[:]).unwrap())
  assert_true(text.contains("</w:body>"))
  assert_true(
    archive.replace(
      part[:],
      @utf8.encode(
        text.replace(old="</w:body>", new="<w:altChunk/></w:body>")[:],
      )[:],
    ),
  )
  @zip.write(archive)
}

///|
fn main raise {
  if !@host.exists("tests/generated") {
    @host.create_directory("tests/generated")
  }
  let stem = "_build/native/debug/build/cmd/main/main"
  let run : Run = {
    root: @host.temp_dir(parent="tests/generated"),
    exe: @host.absolute(
      if @host.exists(stem + ".exe") {
        stem + ".exe"
      } else {
        stem
      },
    ),
    cases: [],
  }
  run.save("Running")
  let word = @host.read_bounded(
    "tests/fixtures/business/demo-word-three-objects.docm", 33554432,
  )
  let sheet = @host.read_bounded(
    "tests/fixtures/business/report-1900.xlsm", 33554432,
  )
  let clean = @sieve.rebuild_verified(word).bytes
  let refused = unsupported(word)
  // Alter a stored payload while retaining its declared CRC (exit 2).
  let broken_zip = @zip.read(clean[:])
  let bad_archive = @zip.Archive()
  for file in broken_zip.entries() {
    bad_archive.add(file.name(), file.data(), compression=@zip.Store)
  }
  let stored = @zip.write(bad_archive)
  let offset = 30 +
    stored[26].to_int() +
    stored[27].to_int() * 256 +
    stored[28].to_int() +
    stored[29].to_int() * 256
  let invalid = Bytes::makei(stored.length(), i => {
    if i == offset {
      (stored[i].to_int() ^ 1).to_byte()
    } else {
      stored[i]
    }
  })
  assert_eq(@sieve.assess(invalid).decision.result, @sieve.Fail)
  assert_eq(@sieve.assess(refused).decision.result, @sieve.Unsupported)
  let source = run.directory("混合输入 with spaces")
  for
    (name, bytes) in [
      ("00-broken.docm", invalid),
      ("01-unsupported.docm", refused),
      ("02-wrong.xlsm", word),
      ("03-中文 report.DOCM", word),
      ("same.docm", word),
      ("same.docx", clean),
      ("sheet.xlsm", sheet),
      ("readme.txt", b"ignored"),
      ("~$lock.docx", word),
    ] {
    @host.write_new(source + "/" + name, bytes)
  }
  let nested = source + "/nested.docx"
  @host.create_directory(nested)
  @host.write_new(nested + "/inside.docm", word)
  let out = run.root + "/mixed-output"
  let report = run.batch(source, out, 4)
  for
    (key, count) in [
      ("success", 4),
      ("refused", 1),
      ("failed", 2),
      ("skipped", 3),
    ] {
    assert_eq(field(report, key), count.to_json())
  }
  for
    (name, suffix) in [
      ("03-中文 report.DOCM", ".docx"),
      ("same.docm", ".docx"),
      ("same.docx", ".docx"),
      ("sheet.xlsm", ".xlsx"),
    ] {
    run.pair(source, out, name, suffix)
    run.record("verified-pair-" + name)
  }
  for name in ["00-broken.docm", "01-unsupported.docm", "02-wrong.xlsm"] {
    assert_false(@host.exists(out + "/" + name + ".receipt.json"))
    assert_false(@host.exists(out + "/" + name + ".cleaned.docx"))
    assert_false(@host.exists(out + "/" + name + ".cleaned.xlsx"))
  }
  let names = match field(report, "entries") {
    Array(rows) => rows.map(row => field(row, "input"))
    _ => fail("entries array")
  }
  assert_eq(names[0], "00-broken.docm".to_json())
  assert_eq(names[1], "01-unsupported.docm".to_json())
  assert_false(@host.exists(out + "/inside.docm.cleaned.docx"))
  run.record("mixed-continues-after-failures-sorted-top-level")
  let summary = @host.read_bounded(out + "/batch.json", 16777216)
  ignore(run.batch(source, out, 4))
  assert_eq(@host.read_bounded(out + "/batch.json", 16777216), summary)
  run.pair(source, out, "same.docm", ".docx")
  run.record("existing-output-directory-preserved")
  ignore(run.batch(source, source, 4))
  assert_eq(@host.read_bounded(source + "/same.docm", 33554432), word)
  run.record("input-output-directory-alias-refused")
  for
    (name, bytes, expected) in [
      ("invalid", invalid, 2),
      ("unsupported", refused, 3),
      ("positive", word, 0),
    ] {
    let dir = run.directory(name)
    @host.write_new(dir + "/file.docm", bytes)
    let report = run.batch(dir, run.root + "/out-" + name, expected)
    assert_eq(
      field(
        report,
        if expected == 0 {
          "success"
        } else if expected == 3 {
          "refused"
        } else {
          "failed"
        },
      ),
      (1).to_json(),
    )
    run.record(name + "-exit-code")
  }
  let priority = run.directory("integrity-priority")
  @host.write_new(priority + "/a.docm", invalid)
  @host.write_new(priority + "/b.docm", refused)
  ignore(run.batch(priority, run.root + "/out-priority", 2))
  run.record("integrity-exit-takes-priority-over-refused")
  for name in ["empty", "unselected"] {
    let dir = run.directory(name)
    if name == "unselected" {
      @host.write_new(dir + "/note.txt", b"x")
    }
    assert_eq(
      field(run.batch(dir, run.root + "/out-" + name, 3), "status"),
      "NoInputs".to_json(),
    )
    run.record(name + "-no-inputs")
  }
  let cap = run.directory("entry-cap")
  for i in 0..<1024 {
    @host.write_new(cap + "/" + i.to_string() + ".txt", b"")
  }
  assert_eq(
    field(run.batch(cap, run.root + "/cap-exact", 3), "skipped"),
    (1024).to_json(),
  )
  run.record("entry-cap-exact-counts-ignored")
  @host.write_new(cap + "/excess.txt", b"")
  ignore(run.batch(cap, run.root + "/cap-excess", 3))
  assert_false(@host.exists(run.root + "/cap-excess"))
  run.record("entry-cap-plus-one-no-output-directory")
  ignore(run.batch(run.root + "/missing", run.root + "/missing-out", 4))
  assert_false(@host.exists(run.root + "/missing-out"))
  run.record("missing-source-no-output-directory")
  let existing_file = run.root + "/existing-file"
  @host.write_new(existing_file, b"sentinel")
  ignore(run.batch(source, existing_file, 4))
  assert_eq(@host.read_bounded(existing_file, 100), b"sentinel")
  run.record("existing-output-file-preserved")
  ignore(run.batch(source, run.root + "/absent-parent/out", 4))
  assert_false(@host.exists(run.root + "/absent-parent"))
  run.record("missing-output-parent-no-creation")
  ignore(run.batch(source + "/same.docm", run.root + "/file-source-out", 4))
  assert_false(@host.exists(run.root + "/file-source-out"))
  run.record("regular-file-is-not-input-directory")
  let plain_sheet = run.directory("plain-sheet")
  @host.write_new(
    plain_sheet + "/file.xlsx",
    @sieve.rebuild_verified(sheet).bytes,
  )
  @host.write_new(plain_sheet + "/ignored.txt", b"skip")
  let plain_report = run.batch(plain_sheet, run.root + "/plain-sheet-out", 0)
  assert_eq(field(plain_report, "skipped"), (1).to_json())
  run.pair(plain_sheet, run.root + "/plain-sheet-out", "file.xlsx", ".xlsx")
  run.record("xlsx-and-ignored-files-do-not-fail-batch")
  let special = run.directory("special")
  for (name, kind) in [("link.docm", 0), ("dir.docx", 1), ("pipe.docm", 2)] {
    let target = special + "/" + name
    let original = if kind == 1 { source } else { source + "/same.docm" }
    let made = fixture_ffi(
        @utf8.encode(original[:]) + b"\x00",
        @utf8.encode(target[:]) + b"\x00",
        kind,
      ) ==
      1
    if !run.exe.has_suffix(".exe") {
      assert_true(made, msg="POSIX fixture creation required: " + name)
    }
    if made {
      let rows = @host.list_directory(special)
      assert_true(
        rows.any(entry => {
          entry.name == name &&
          entry.kind == (if kind == 2 { "other" } else { "link" })
        }),
      )
      if kind == 1 {
        ignore(run.batch(target, run.root + "/root-link-out", 4))
        assert_false(@host.exists(run.root + "/root-link-out"))
      }
    }
    run.record(
      name + "-fixture",
      result=if made { "Pass" } else { "UnavailableOnHost" },
    )
  }
  let special_report = run.batch(special, run.root + "/special-output", 3)
  assert_eq(field(special_report, "success"), (0).to_json())
  assert_eq(field(special_report, "failed"), (0).to_json())
  run.record("special-inventory-no-successful-pairs")
  run.save("Pass")
  println(
    "Pass: batch regression " +
    run.cases.length().to_string() +
    " cases; actual CLI and independent receipt verification",
  )
}
