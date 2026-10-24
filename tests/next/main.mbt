///|
fn fixture(name : String) -> @zip.Archive raise {
  let data = @host.read_bounded("tests/fixtures/" + name, 33554432)
  @zip.read(data[:])
}

///|
fn bytes(archive : @zip.Archive, part : String) -> Bytes {
  archive.get(part[:]).unwrap().to_owned()
}

///|
fn edit(
  archive : @zip.Archive,
  part : String,
  old : String,
  replacement : String,
) -> Unit raise {
  let text = @utf8.decode(bytes(archive, part)[:])
  assert_true(text.contains(old), msg=part + " mutation anchor")
  let payload = @utf8.encode(text.replace(old~, new=replacement)[:])
  assert_true(archive.replace(part[:], payload[:]))
}

///|
fn add(archive : @zip.Archive, part : String, payload : Bytes) -> Unit {
  archive.add(part, payload[:])
}

///|
fn relation(
  archive : @zip.Archive,
  source : String,
  id : String,
  kind : String,
  target : String,
  external? : Bool = false,
) -> Unit raise {
  let split = source.rev_split_once("/").unwrap()
  let part = split.0.to_owned() + "/_rels/" + split.1.to_owned() + ".rels"
  if archive.get(part[:]) is None {
    add(
      archive,
      part,
      @utf8.encode(
        "<Relationships xmlns='http://schemas.openxmlformats.org/package/2006/relationships'></Relationships>"[:],
      ),
    )
  }
  let element = "<Relationship Id='" +
    id +
    "' Type='http://schemas.openxmlformats.org/officeDocument/2006/relationships/" +
    kind +
    "' Target='" +
    target +
    "'" +
    (if external { " TargetMode='External'" } else { "" }) +
    "/>"
  edit(archive, part, "</Relationships>", element + "</Relationships>")
}

///|
fn content_type(
  archive : @zip.Archive,
  name : String,
  ct : String,
) -> Unit raise {
  edit(
    archive,
    "[Content_Types].xml",
    "</Types>",
    "<Override PartName='/" + name + "' ContentType='" + ct + "'/></Types>",
  )
}

///|
fn word_link(
  archive : @zip.Archive,
  source : String,
  id : String,
  target : String,
) -> Unit raise {
  edit(
    archive,
    source,
    "</w:p>",
    "<w:hyperlink r:id='" +
    id +
    "' w:history='1'><w:r><w:rPr><w:color w:val='0563C1'/><w:u w:val='single'/></w:rPr><w:t>官网 链接</w:t></w:r></w:hyperlink></w:p>",
  )
  relation(archive, source, id, "hyperlink", target, external=true)
}

///|
fn word_links() -> @zip.Archive raise {
  let archive = fixture("business/document-template.docm")
  word_link(
    archive, "word/document.xml", "rClick", "https://example.invalid/docs?q=1&amp;lang=zh#section",
  )
  word_link(
    archive, "word/header1.xml", "rClick", "HTTP://example.invalid:8080/header",
  )
  word_link(
    archive, "word/footer1.xml", "rFooterClick", "https://example.invalid/footer",
  )
  archive
}

///|
fn sheet_links() -> @zip.Archive raise {
  let archive = fixture("business/report-1900.xlsm")
  edit(
    archive, "xl/worksheets/sheet1.xml", "<pageMargins", "<hyperlinks><hyperlink ref='A3:A4' r:id='rClick' display='官网 链接' tooltip='交付说明'/></hyperlinks><pageMargins",
  )
  relation(
    archive,
    "xl/worksheets/sheet1.xml",
    "rClick",
    "hyperlink",
    "https://example.invalid/report?q=1&amp;x=2",
    external=true,
  )
  archive
}

///|
fn attach_ole(archive : @zip.Archive, emf : Bool) -> Unit raise {
  let object = @utf8.decode(
      @host.read_bounded("tests/fixtures/poi/EmbeddedObject.xml", 65536)[:],
    )
    .replace_all(old="rId4", new="rOlePreview")
    .replace_all(old="rId5", new="rOle")
  edit(
    archive,
    "word/document.xml",
    "</w:p>",
    "<w:r>" + object + "</w:r></w:p>",
  )
  add(
    archive,
    "word/embeddings/worksheet.xls",
    @host.read_bounded("tests/fixtures/poi/EmbeddedWorksheet.xls", 33554432),
  )
  let name = if emf { "ole-preview.emf" } else { "ole-preview.png" }
  let payload = if emf {
    @host.read_bounded("tests/fixtures/poi/EmbeddedPreview.emf", 33554432)
  } else {
    bytes(archive, "word/media/logo.png")
  }
  add(archive, "word/media/" + name, payload)
  content_type(
    archive, "word/embeddings/worksheet.xls", "application/vnd.ms-excel",
  )
  content_type(
    archive,
    "word/media/" + name,
    if emf {
      "image/x-emf"
    } else {
      "image/png"
    },
  )
  relation(
    archive, "word/document.xml", "rOle", "oleObject", "embeddings/worksheet.xls",
  )
  relation(
    archive,
    "word/document.xml",
    "rOlePreview",
    "image",
    "media/" + name,
  )
}

///|
fn accepted(
  name : String,
  archive : @zip.Archive,
  suffix : String,
  ole : Bool,
  clicks? : Bool = true,
) -> Bytes raise {
  let input = @zip.write(archive)
  let assessed = @sieve.assess(input)
  assert_eq(
    assessed.decision.result,
    @sieve.Pass,
    msg=name + assessed.decision.reason,
  )
  let plan = @sieve.prepare(input)
  assert_eq(
    plan.decisions.any(fn(d) {
      d.action == @sieve.AllowAction && d.rule_id == "http-hyperlink-v1"
    }),
    clicks,
  )
  let rebuilt = @sieve.rebuild_verified_with_plan(input, plan.to_json())
  assert_eq(@sieve.verify_contract(rebuilt.bytes, input), rebuilt.receipt)
  assert_eq(rebuilt.receipt.allowed_capabilities.length() > 0, clicks)
  assert_true(
    rebuilt.receipt.allowed_capabilities.all(fn(f) {
      f.capability == @sieve.HttpHyperlink
    }),
  )
  assert_true(rebuilt.receipt.output_findings.length() == 0)
  let actual = @zip.read(rebuilt.bytes[:])
  for d in rebuilt.receipt.dispositions {
    if d.classification == @sieve.BytePreservedKind {
      assert_eq(
        bytes(archive, d.part),
        bytes(actual, d.part),
        msg=name + " preserved " + d.part,
      )
    }
  }
  assert_eq(
    rebuilt.receipt.findings.any(fn(f) { f.capability == @sieve.Ole }),
    ole,
  )
  if ole {
    assert_true(actual.get("word/embeddings/worksheet.xls") is None)
    assert_true(
      actual.get("word/media/ole-preview.png") is None &&
      actual.get("word/media/ole-preview.emf") is None,
    )
    let document = @utf8.decode(bytes(actual, "word/document.xml")[:])
    assert_false(
      document.contains("OLEObject") || document.contains("<w:object"),
    )
    if clicks {
      assert_true(document.contains("官网 链接"))
    }
    assert_true(
      rebuilt.receipt.dispositions.any(fn(d) {
        d.part == "word/document.xml" &&
        d.classification == @sieve.SemanticallyRewrittenKind
      }),
    )
  }
  let again = @sieve.rebuild_verified(rebuilt.bytes)
  assert_true(
    again.receipt.dispositions.all(fn(d) {
      d.classification == @sieve.BytePreservedKind
    }),
  )
  let repeated = @zip.read(again.bytes[:])
  for entry in actual.entries() {
    assert_eq(entry.data().to_owned(), bytes(repeated, entry.name()))
  }
  let dir = "tests/generated/next-v6/"
  let legacy = @sieve.verify(rebuilt.bytes, input)
  @fs.write_string_to_file(
    dir + name + ".legacy.receipt.json",
    ({ "publication": "pair-complete", "receipt": legacy.to_json() } : Json).stringify(),
  )
  let input_path = dir +
    name +
    ".input" +
    (match @sieve.audit(input).format {
      "DOCX" => ".docx"
      "DOCM" => ".docm"
      "XLSX" => ".xlsx"
      _ => ".xlsm"
    })
  @fs.write_bytes_to_file(input_path, input)
  @fs.write_bytes_to_file(dir + name + suffix, rebuilt.bytes)
  @fs.write_string_to_file(
    dir + name + ".receipt.json",
    (
      { "publication": "pair-complete", "receipt": rebuilt.receipt.to_json() } :
      Json).stringify(),
  )
  let cli_output = dir + name + ".cli" + suffix
  let cli_receipt = dir + name + ".cli.receipt.json"
  for path in [cli_output, cli_receipt] {
    if @host.exists(path) {
      @host.remove_file(path)
    }
  }
  let plan_path = dir + name + ".plan.json"
  @fs.write_string_to_file(plan_path, plan.to_json().stringify())
  let process = @host.run(cli_binary(), [
    "rebuild", input_path, "-o", cli_output, "--receipt", cli_receipt, "--receipt-format",
    "v2", "--plan", plan_path,
  ])
  assert_eq(process.code, 0, msg=@utf8.decode_lossy(process.stdout[:]))
  assert_eq(@cli.parse_json(process.stdout), rebuilt.receipt.to_json())
  assert_eq(@host.read_bounded(cli_output, 67108864), rebuilt.bytes)
  let verified = @host.run(cli_binary(), [
    "verify", cli_output, "--original", input_path, "--receipt", cli_receipt, "--receipt-format",
    "v2",
  ])
  assert_eq(verified.code, 0)
  assert_eq(@cli.parse_json(verified.stdout), rebuilt.receipt.to_json())
  println("Pass: " + name)
  rebuilt.bytes
}

///|
fn rejected(name : String, archive : @zip.Archive) -> Unit raise {
  let input = @zip.write(archive)
  let report = @sieve.assess(input)
  assert_false(report.decision.rebuild_allowed, msg=name)
  let refused = try {
    ignore(@sieve.rebuild_verified(input))
    false
  } catch {
    _ => true
  }
  assert_true(refused, msg=name)
  let source = "tests/generated/next-v6/" + name + ".bad.docm"
  let output = source + ".docx"
  let receipt = source + ".receipt.json"
  @fs.write_bytes_to_file(source, input)
  assert_false(@host.exists(output) || @host.exists(receipt))
  let process = @host.run(cli_binary(), [
    "rebuild", source, "-o", output, "--receipt", receipt, "--receipt-format", "v2",
  ])
  assert_true(process.code == 2 || process.code == 3)
  assert_false(@host.exists(output) || @host.exists(receipt))
  println("Refuse: " + name)
}

///|
fn main raise {
  for dir in ["tests/generated", "tests/generated/next-v6"] {
    if !@host.exists(dir) {
      @fs.create_dir(dir)
    }
  }
  ignore(accepted("word-links", word_links(), ".docx", false))
  ignore(accepted("sheet-links", sheet_links(), ".xlsx", false))
  ignore(accepted("word-ole-png", word_ole(false), ".docx", true))
  ignore(accepted("word-ole-emf", word_ole(true), ".docx", true))
  let ole_only = fixture("business/document-template.docm")
  attach_ole(ole_only, true)
  ignore(accepted("word-ole-only", ole_only, ".docx", true, clicks=false))
  let clean = @sieve.rebuild_verified(@zip.write(word_links()))
  let no_macro = @zip.read(clean.bytes[:])
  attach_ole(no_macro, true)
  ignore(accepted("word-ole-clean", no_macro, ".docx", true))
  for
    index, target in [
      "file:///C:/blocked", "mailto:test@example.invalid", "javascript:alert(1)",
      "ftp://example.invalid/x", "https:///missing", "https://user@example.invalid",
      "http://bad_host/x", "https://example.invalid:99999/x",
    ] {
    let bad = word_links()
    edit(
      bad, "word/_rels/document.xml.rels", "https://example.invalid/docs?q=1&amp;lang=zh#section",
      target,
    )
    rejected("scheme-" + index.to_string(), bad)
  }
  for
    (name, part, old, replacement) in [
      (
        "word-wrong-binding", "word/document.xml", "r:id='rClick'", "r:id='rImage'",
      ),
      ("word-no-link-id", "word/document.xml", "r:id='rClick'", ""),
      (
        "word-internal-anchor", "word/document.xml", "w:history='1'", "w:anchor='bookmark'",
      ),
      (
        "word-bad-history", "word/document.xml", "w:history='1'", "w:history='2'",
      ),
      (
        "word-missing-relationship", "word/document.xml", "r:id='rClick'", "r:id='missing'",
      ),
    ] {
    let bad = word_links()
    edit(bad, part, old, replacement)
    rejected(name, bad)
  }
  for
    range in ["A0", "XFE1", "A1048577", "A1:A0", "B2:A1", "A1 A3", "$A$3", "a3"] {
    let bad = sheet_links()
    edit(bad, "xl/worksheets/sheet1.xml", "ref='A3:A4'", "ref='" + range + "'")
    rejected(
      "sheet-range-" +
      range.replace_all(old="$", new="abs").replace_all(old=":", new="-"),
      bad,
    )
  }
  for
    (name, part, old, replacement) in [
      ("ole-linked", "word/document.xml", "Type=\"Embed\"", "Type=\"Link\""),
      (
        "ole-wrong-shape", "word/document.xml", "ShapeID=\"_x0000_i1025\"", "ShapeID=\"missing\"",
      ),
      (
        "ole-wrong-type-id", "word/document.xml", "type=\"#_x0000_t75\"", "type=\"#wrong\"",
      ),
      (
        "ole-wrong-kind", "word/_rels/document.xml.rels", "relationships/oleObject",
        "relationships/image",
      ),
      (
        "ole-preview-external", "word/_rels/document.xml.rels", "Target='media/ole-preview.png'",
        "Target='https://example.invalid/preview' TargetMode='External'",
      ),
      (
        "ole-unknown-child", "word/document.xml", "</w:object>", "<o:Unknown/></w:object>",
      ),
      (
        "ole-text-hidden", "word/document.xml", "</w:object>", "HIDDEN</w:object>",
      ),
      (
        "ole-unknown-attribute", "word/document.xml", "ProgID=\"Excel.Sheet.8\"",
        "ProgID=\"Excel.Sheet.8\" Unknown=\"x\"",
      ),
      (
        "ole-activeX", "word/_rels/document.xml.rels", "relationships/oleObject",
        "relationships/control",
      ),
    ] {
    let bad = word_ole(false)
    edit(bad, part, old, replacement)
    rejected(name, bad)
  }
  let shared = word_ole(false)
  relation(
    shared, "word/document.xml", "rSecondOwner", "oleObject", "embeddings/worksheet.xls",
  )
  rejected("ole-shared-payload", shared)
  let shared_image = word_ole(false)
  edit(
    shared_image, "word/document.xml", "r:embed=\"rImage\"", "r:embed=\"rOlePreview\"",
  )
  rejected("ole-shared-preview", shared_image)
  let invalid_cfb = word_ole(false)
  assert_true(invalid_cfb.replace("word/embeddings/worksheet.xls", b"not CFB"))
  rejected("ole-invalid-container", invalid_cfb)
  let invalid_image = word_ole(true)
  assert_true(invalid_image.replace("word/media/ole-preview.emf", b"not EMF"))
  rejected("ole-invalid-preview", invalid_image)
  let nested = word_ole(false)
  add(
    nested,
    "word/embeddings/_rels/worksheet.xls.rels",
    @utf8.encode(
      "<Relationships xmlns='http://schemas.openxmlformats.org/package/2006/relationships'/>"[:],
    ),
  )
  rejected("ole-nested-dependencies", nested)
  let two = word_ole(false)
  let object = @utf8.decode(
      @host.read_bounded("tests/fixtures/poi/EmbeddedObject.xml", 65536)[:],
    )
    .replace_all(old="rId4", new="rOlePreview")
    .replace_all(old="rId5", new="rOle")
  edit(two, "word/document.xml", "</w:p>", "<w:r>" + object + "</w:r></w:p>")
  rejected("ole-multiple-objects", two)
  let original = @host.read_bounded(
    "tests/generated/next-v6/word-links.input.docm", 33554432,
  )
  let changed = @zip.read(
    @host.read_bounded("tests/generated/next-v6/word-links.docx", 33554432)[:],
  )
  edit(
    changed, "word/_rels/document.xml.rels", "https://example.invalid/docs?q=1&amp;lang=zh#section",
    "https://example.invalid/changed",
  )
  let tampered = @zip.write(changed)
  assert_true(
    try {
      ignore(@sieve.verify_contract(tampered, original))
      false
    } catch {
      _ => true
    },
  )
  @fs.write_bytes_to_file(
    "tests/generated/next-v6/tampered-link.docx", tampered,
  )
  let check = @host.run(cli_binary(), [
    "verify", "tests/generated/next-v6/tampered-link.docx", "--original", "tests/generated/next-v6/word-links.input.docm",
    "--receipt-format", "v2",
  ])
  assert_eq(check.code, 2)
  let report = @utf8.decode(
    @host.read_bounded(
      "tests/generated/next-v6/word-links.receipt.json", 16777216,
    )[:],
  )
  @fs.write_string_to_file(
    "tests/generated/next-v6/forged.receipt.json",
    report.replace(old="HTTPHyperlink", new="VBA"),
  )
  let forged = @host.run(cli_binary(), [
    "verify", "tests/generated/next-v6/word-links.docx", "--original", "tests/generated/next-v6/word-links.input.docm",
    "--receipt", "tests/generated/next-v6/forged.receipt.json", "--receipt-format",
    "v2",
  ])
  assert_eq(forged.code, 2)
  println("Pass: URL tampering and forged allowed-capability Receipt refused")
}

///|
fn word_ole(emf : Bool) -> @zip.Archive raise {
  let archive = word_links()
  attach_ole(archive, emf)
  archive
}

///|
fn cli_binary() -> String raise {
  let stem = "_build/native/debug/build/cmd/main/main"
  @host.absolute(if @host.exists(stem + ".exe") { stem + ".exe" } else { stem })
}
