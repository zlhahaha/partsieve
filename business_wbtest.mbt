///|
test "worksheet metadata survives verified rebuild while child content and missing fonts refuse" {
  fn with_metadata(fragment : String) -> Bytes raise {
    let source = planner_fixture()
    let archive = @zip.read(source[:])
    let xml = "<worksheet xmlns='" +
      spreadsheet_ns +
      "'><sheetData/>" +
      fragment +
      "</worksheet>"
    assert_true(
      archive.replace("xl/worksheets/sheet1.xml", @utf8.encode(xml[:])[:]),
    )
    @zip.write(archive)
  }
  let source = with_metadata("<headerFooter alignWithMargins='false'/>")
  let result = rebuild_verified(source)
  assert_eq(result.receipt.result, Pass)
  let before = @zip.read(source[:])
  let after = @zip.read(result.bytes[:])
  assert_eq(
    get_part(before, "xl/worksheets/sheet1.xml"),
    get_part(after, "xl/worksheets/sheet1.xml"),
  )
  for
    fragment in [
      "<headerFooter><oddHeader>text</oddHeader></headerFooter>", "<headerFooter><drawing/></headerFooter>",
      "<phoneticPr fontId='0'><t>text</t></phoneticPr>",
    ] {
    expect_refused(fn() raise {
      ignore(rebuild_verified(with_metadata(fragment)))
    })
  }
  expect_invalid(fn() raise {
    ignore(rebuild_verified(with_metadata("<phoneticPr fontId='0'/>")))
  })
}

///|
test "worksheet passive metadata requires exact context and bounded attributes" {
  fn metadata(xml : String, parent : String) -> Unit raise {
    let nodes = read_xml(@utf8.encode(xml[:])[:], Limits::default())
    validate_sheet_metadata(nodes[0], parent)
  }
  let prefix = "<phoneticPr xmlns='" + spreadsheet_ns + "' "
  metadata(prefix + "fontId='0' type='noConversion'/>", "worksheet")
  metadata(
    "<headerFooter xmlns='" + spreadsheet_ns + "' alignWithMargins='0'/>",
    "worksheet",
  )
  for
    fragment in [
      "fontId='-1'", "fontId='9999999999'", "fontId='0' type='unknown'", "fontId='0' alignment='right'",
      "fontId='0' href='https://example.invalid'", "type='noConversion'",
    ] {
    expect_refused(fn() raise {
      metadata(prefix + fragment + "/>", "worksheet")
    })
  }
  expect_refused(fn() raise { metadata(prefix + "fontId='0'/>", "c") })
  expect_refused(fn() raise {
    metadata(
      "<headerFooter xmlns='" + spreadsheet_ns + "' alignWithMargins='yes'/>",
      "worksheet",
    )
  })
  expect_refused(fn() raise {
    metadata(
      "<headerFooter xmlns='" + spreadsheet_ns + "'>unexpected</headerFooter>",
      "worksheet",
    )
  })
  expect_refused(fn() raise {
    metadata("<headerFooter xmlns='urn:other'/>", "worksheet")
  })
}

///|
test "spreadsheet indices reject overflow negative boolean and fractional values" {
  assert_eq(checked_index("00012", 13), 12)
  for value in ["", "-1", "true", "1.5", "9999999999", "13"] {
    expect_refused(fn() raise { ignore(checked_index(value, 13)) })
  }
}

///|
test "drawing extension names are namespace and placement sensitive" {
  let xml = "<a:xfrm xmlns:a='" +
    drawing_ns +
    "'><a:ext cx='1' cy='2'/></a:xfrm>"
  let nodes = read_xml(@utf8.encode(xml[:])[:], Limits::default())
  assert_true(word_passive_element(nodes[1], "xfrm", "document"))
  assert_eq(word_passive_element(nodes[1], "body", "document"), false)
  assert_true(passive_drawing_attribute(drawing_ns, "graphicData", "uri"))
  assert_eq(passive_drawing_attribute(drawing_ns, "blip", "href"), false)
}

///|
test "Word content relationship source identity and exact element context are required" {
  let xml = "<w:document xmlns:w='" +
    word_ns +
    "'><w:body><w:tbl><w:tr><w:tc><w:p/></w:tc></w:tr></w:tbl></w:body></w:document>"
  let nodes = read_xml(@utf8.encode(xml[:])[:], Limits::default())
  assert_true(word_passive_element(nodes[2], "body", "document"))
  assert_eq(word_passive_element(nodes[2], "r", "document"), false)
  let relation = {
    ..graph_edge(
      "word/settings.xml",
      "rRemote",
      "https://example.invalid/t",
      external=true,
    ),
    kind: office_rel + "attachedTemplate",
  }
  assert_true(is_template_relationship(relation))
  assert_eq(is_template_relationship({ ..relation, external: false, }), false)
}

///|
test "spreadsheet editing time is preserved and restricted to a single bounded property" {
  fn with_editing_time(fragment : String) -> Bytes raise {
    let source = planner_fixture()
    let archive = @zip.read(source[:])
    let types = get_part(archive, "[Content_Types].xml")
    let types_text = @utf8.decode_lossy(types[:]).replace(
      old="</Types>",
      new="<Override PartName='/docProps/app.xml' ContentType='application/vnd.openxmlformats-officedocument.extended-properties+xml'/></Types>",
    )
    assert_true(
      archive.replace("[Content_Types].xml", @utf8.encode(types_text[:])[:]),
    )
    let relations = get_part(archive, "_rels/.rels")
    let rel_text = @utf8.decode_lossy(relations[:]).replace(
      old="</Relationships>",
      new="<Relationship Id='app' Type='" +
        office_rel +
        "extended-properties' Target='docProps/app.xml'/></Relationships>",
    )
    assert_true(archive.replace("_rels/.rels", @utf8.encode(rel_text[:])[:]))
    let app = "<Properties xmlns='http://schemas.openxmlformats.org/officeDocument/2006/extended-properties'>" +
      fragment +
      "</Properties>"
    archive.add("docProps/app.xml", @utf8.encode(app[:])[:])
    @zip.write(archive)
  }
  let source = with_editing_time("<TotalTime>2</TotalTime>")
  let rebuilt = rebuild_verified(source)
  assert_eq(rebuilt.receipt.result, Pass)
  assert_eq(
    get_part(@zip.read(source[:]), "docProps/app.xml"),
    get_part(@zip.read(rebuilt.bytes[:]), "docProps/app.xml"),
  )
  for
    fragment in [
      "<TotalTime>2</TotalTime><TotalTime>3</TotalTime>", "<TotalTime xmlns='urn:other'>2</TotalTime>",
      "<Application><TotalTime>2</TotalTime></Application>", "<TotalTime><Application>2</Application></TotalTime>",
      "<TotalTime href='https://example.invalid'>2</TotalTime>", "<TotalTime xmlns:r='http://schemas.openxmlformats.org/officeDocument/2006/relationships' r:id='missing'>2</TotalTime>",
    ] {
    expect_refused(fn() raise {
      ignore(rebuild_verified(with_editing_time(fragment)))
    })
  }
  for text in ["-1", "1000000001", "1.5", ""] {
    expect_invalid(fn() raise {
      ignore(
        rebuild_verified(
          with_editing_time("<TotalTime>" + text + "</TotalTime>"),
        ),
      )
    })
  }
}
