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
