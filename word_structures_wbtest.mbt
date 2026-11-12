///|
test "Word property vectors bind size types children and disallow resource attributes" {
  let ns = "http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes"
  fn check(text : String) -> Unit raise {
    let nodes = read_xml(@utf8.encode(text[:])[:], Limits::default())
    validate_word_property_vectors(nodes, WorkControl::default())
  }
  let prefix = "<vt:vector xmlns:vt='" + ns + "' "
  check(
    prefix + "size='1' baseType='lpstr'><vt:lpstr>title</vt:lpstr></vt:vector>",
  )
  for
    suffix in [
      "size='2' baseType='lpstr'><vt:lpstr>title</vt:lpstr></vt:vector>", "size='1' baseType='unknown'><vt:lpstr>title</vt:lpstr></vt:vector>",
      "size='1' baseType='variant'><vt:lpstr>title</vt:lpstr></vt:vector>", "size='1' baseType='lpstr' href='https://example.invalid'><vt:lpstr>title</vt:lpstr></vt:vector>",
    ] {
    expect_refused(fn() raise { check(prefix + suffix) })
  }
}

///|
test "positional tabs and inert settings have bounded context and values" {
  let body = "<w:p><w:r><w:ptab w:relativeTo='margin' w:alignment='center' w:leader='none'/><w:t>footer</w:t></w:r></w:p>"
  let settings = note_xml(
    "settings", "<w:removePersonalInformation/><w:doNotAutoCompressPictures w:val='true'/><w:compat><w:compatSetting w:name='compatibilityMode' w:uri='http://schemas.microsoft.com/office/word' w:val='12'/></w:compat>",
  )
  assert_eq(
    rebuild_verified(structured_word_fixture(body, settings~)).receipt.result,
    Pass,
  )
  for
    fragment in [
      "<w:removePersonalInformation w:val='unexpected'/>", "<w:compat><w:compatSetting w:name='compatibilityMode' w:uri='https://example.invalid' w:val='12'/></w:compat>",
      "<w:removePersonalInformation w:href='https://example.invalid'/>",
    ] {
    expect_refused(fn() raise {
      ignore(
        rebuild_verified(
          structured_word_fixture(
            "<w:p/>",
            settings=note_xml("settings", fragment),
          ),
        ),
      )
    })
  }
  expect_refused(fn() raise {
    ignore(
      rebuild_verified(
        structured_word_fixture(
          "<w:p><w:ptab w:relativeTo='margin' w:alignment='center' w:leader='none'/></w:p>",
        ),
      ),
    )
  })
  expect_refused(fn() raise {
    ignore(
      rebuild_verified(
        structured_word_fixture(
          "<w:p><w:r><w:ptab w:relativeTo='page' w:alignment='center' w:leader='none'/></w:r></w:p>",
        ),
      ),
    )
  })
}

///|
fn structured_word_fixture(
  body : String,
  notes~ : String = "",
  endnotes~ : String = "",
  numbering~ : String = "",
  settings~ : String = "",
  styles~ : String = "",
  web_settings~ : String = "",
) -> Bytes raise {
  let archive = @zip.Archive()
  let mut types = "<Types xmlns='" +
    ct_ns +
    "'><Default Extension='rels' ContentType='application/vnd.openxmlformats-package.relationships+xml'/><Override PartName='/word/document.xml' ContentType='" +
    docx_ct +
    "'/>"
  let mut relations = "<Relationships xmlns='" + rel_ns + "'>"
  for
    pair in [
      ("footnotes", notes),
      ("endnotes", endnotes),
      ("numbering", numbering),
      ("settings", settings),
      ("styles", styles),
      ("webSettings", web_settings),
    ] {
    let (kind, text) = pair
    if text == "" {
      continue
    }
    types += "<Override PartName='/word/" +
      kind +
      ".xml' ContentType='application/vnd.openxmlformats-officedocument.wordprocessingml." +
      kind +
      "+xml'/>"
    relations += "<Relationship Id='" +
      kind +
      "' Type='" +
      office_rel +
      kind +
      "' Target='" +
      kind +
      ".xml'/>"
    archive.add("word/" + kind + ".xml", @utf8.encode(text[:])[:])
  }
  types += "</Types>"
  relations += "</Relationships>"
  archive.add("[Content_Types].xml", @utf8.encode(types[:])[:])
  archive.add("word/_rels/document.xml.rels", @utf8.encode(relations[:])[:])
  let package_rels = "<Relationships xmlns='" +
    rel_ns +
    "'><Relationship Id='main' Type='" +
    office_rel +
    "officeDocument' Target='word/document.xml'/></Relationships>"
  archive.add("_rels/.rels", @utf8.encode(package_rels[:])[:])
  let document = "<w:document xmlns:w='" +
    word_ns +
    "'><w:body>" +
    body +
    "</w:body></w:document>"
  archive.add("word/document.xml", @utf8.encode(document[:])[:])
  @zip.write(archive)
}

///|
test "single-line Word table style borders are preserved in their original part" {
  let edge = "<w:top w:val='single' w:sz='4' w:space='0' w:color='auto'/>"
  let borders = "<w:tblBorders>" + edge + "</w:tblBorders>"
  let open_style = "<w:style w:type='table' w:styleId='Grid'>"
  let table = "<w:tbl><w:tblPr><w:tblStyle w:val='Grid'/></w:tblPr><w:tr w:rsidTr='A1B2C3D4'><w:tc><w:p/></w:tc></w:tr></w:tbl>"
  let styles = note_xml(
    "styles",
    open_style + "<w:tblPr>" + borders + "</w:tblPr></w:style>",
  )
  let web_settings = note_xml("webSettings", "<w:allowPNG/>")
  let source = structured_word_fixture(table, styles~, web_settings~)
  let rebuilt = rebuild_verified(source)
  assert_eq(rebuilt.receipt.result, Pass)
  assert_eq(rebuilt.bytes, source)

  for
    fragment in [
      open_style + borders + "</w:style>",
      open_style + "<w:tblPr>" + borders + borders + "</w:tblPr></w:style>",
      open_style + "<w:tblPr/>" + "<w:tblPr>" + borders + "</w:tblPr></w:style>",
      open_style + "<w:tblPr>" + borders + "</w:tblPr><w:tblPr/></w:style>",
      "<w:style w:type='paragraph' w:styleId='Grid'><w:tblPr>" +
      borders +
      "</w:tblPr></w:style>",
      open_style +
      "<w:tblPr><w:tblBorders>" +
      edge +
      edge +
      "</w:tblBorders></w:tblPr></w:style>",
      open_style +
      "<w:tblPr><w:tblBorders><w:bottom w:val='single'/>" +
      edge +
      "</w:tblBorders></w:tblPr></w:style>",
      open_style +
      "<w:tblPr><w:tblBorders><w:top w:val='single'><w:top/></w:top></w:tblBorders></w:tblPr></w:style>",
      open_style +
      "<w:tblPr><w:tblBorders><w:top xmlns:w='urn:other'/></w:tblBorders></w:tblPr></w:style>",
      open_style +
      "<w:tblPr><w:tblBorders><w:top w:val='single' xmlns:r='" +
      office_rel[0:office_rel.length() - 1].to_owned() +
      "' r:id='missing'/></w:tblBorders></w:tblPr></w:style>",
    ] {
    expect_refused(fn() raise {
      ignore(
        rebuild_verified(
          structured_word_fixture(table, styles=note_xml("styles", fragment)),
        ),
      )
    })
  }

  for attrs in ["w:sz='1'", "w:sz='97'", "w:space='32'", "w:color='bad'"] {
    expect_invalid(fn() raise {
      ignore(
        rebuild_verified(
          structured_word_fixture(
            table,
            styles=note_xml(
              "styles",
              open_style +
              "<w:tblPr><w:tblBorders><w:top w:val='single' " +
              attrs +
              "/></w:tblBorders></w:tblPr></w:style>",
            ),
          ),
        ),
      )
    })
  }
}

///|
test "Word table row revision and PNG preference reject wrong scope and values" {
  for
    body in [
      "<w:p w:rsidTr='001848E1'/>", "<w:tbl><w:tr w:rsidTr='1234567Z'><w:tc><w:p/></w:tc></w:tr></w:tbl>",
    ] {
    expect_refused(fn() raise {
      ignore(rebuild_verified(structured_word_fixture(body)))
    })
  }
  for
    fragment in [
      "<w:allowPNG/><w:allowPNG/>", "<w:allowPNG w:val='maybe'/>", "<w:allowPNG w:src='https://example.invalid'/>",
      "<w:allowPNG><w:allowPNG/></w:allowPNG>", "<w:allowPNG xmlns:w='urn:other'/>",
    ] {
    expect_refused(fn() raise {
      ignore(
        rebuild_verified(
          structured_word_fixture(
            "<w:p/>",
            web_settings=note_xml("webSettings", fragment),
          ),
        ),
      )
    })
  }
}

///|
fn note_xml(kind : String, content : String) -> String {
  "<w:" + kind + " xmlns:w='" + word_ns + "'>" + content + "</w:" + kind + ">"
}

///|
fn simple_numbering(
  instance~ : String = "7",
  abstract_id~ : String = "3",
  level~ : String = "0",
  extra~ : String = "",
) -> String {
  note_xml(
    "numbering",
    "<w:num w:numId='" +
    instance +
    "'><w:abstractNumId w:val='" +
    abstract_id +
    "'/></w:num><w:abstractNum w:abstractNumId='3'><w:lvl w:ilvl='" +
    level +
    "'><w:start w:val='1'/><w:numFmt w:val='decimal'/><w:lvlText w:val='%1.'/></w:lvl>" +
    extra +
    "</w:abstractNum>",
  )
}

///|
test "normal footnotes endnotes and numbering retain all original internal bytes" {
  let body = "<w:p><w:pPr><w:numPr><w:ilvl w:val='0'/><w:numId w:val='7'/></w:numPr></w:pPr><w:r><w:t>订单正文</w:t><w:footnoteReference w:id='2'/><w:endnoteReference w:id='3'/></w:r></w:p>"
  let notes = note_xml(
    "footnotes", "<w:footnote w:id='2'><w:p><w:r><w:footnoteRef/><w:t>脚注说明</w:t></w:r></w:p></w:footnote>",
  )
  let endnotes = note_xml(
    "endnotes", "<w:endnote w:id='3'><w:p><w:r><w:endnoteRef/><w:t>尾注说明</w:t></w:r></w:p></w:endnote>",
  )
  let source = structured_word_fixture(
    body,
    notes~,
    endnotes~,
    numbering=simple_numbering(),
  )
  let result = rebuild_verified(source)
  assert_eq(result.receipt.result, Pass)
  let before = @zip.read(source[:])
  let after = @zip.read(result.bytes[:])
  for
    part in [
      "word/document.xml", "word/footnotes.xml", "word/endnotes.xml", "word/numbering.xml",
      "word/_rels/document.xml.rels",
    ] {
    assert_eq(get_part(before, part), get_part(after, part))
  }
}

///|
test "note separator references support modern and legacy IDs with source-bound definitions" {
  for pair in [("-1", "0"), ("0", "1")] {
    let (first, second) = pair
    let notes = note_xml(
      "footnotes",
      "<w:footnote w:id='" +
      first +
      "' w:type='separator'><w:p><w:r><w:separator/></w:r></w:p></w:footnote><w:footnote w:id='" +
      second +
      "' w:type='continuationSeparator'><w:p><w:r><w:continuationSeparator/></w:r></w:p></w:footnote>",
    )
    let settings = note_xml(
      "settings",
      "<w:footnotePr><w:footnote w:id='" +
      first +
      "'/><w:footnote w:id='" +
      second +
      "'/></w:footnotePr>",
    )
    assert_eq(
      rebuild_verified(structured_word_fixture("<w:p/>", notes~, settings~)).receipt.result,
      Pass,
    )
  }
}

///|
test "note dangling duplicate aliased IDs wrong types and unmodeled active contents refuse" {
  let body = "<w:p><w:r><w:footnoteReference w:id='2'/></w:r></w:p>"
  let normal = "<w:footnote w:id='2'><w:p><w:r><w:footnoteRef/><w:t>note</w:t></w:r></w:p></w:footnote>"
  for
    content in [
      "",
      normal + normal,
      normal + "<w:footnote w:id='02'><w:p/></w:footnote>",
      "<w:footnote w:id='2' w:type='separator'><w:p/></w:footnote>",
      "<w:footnote id='2'><w:p/></w:footnote>",
      "<w:footnote w:id='2'><w:p><w:r><w:instrText>INCLUDETEXT</w:instrText></w:r></w:p></w:footnote>",
      "<w:footnote w:id='2'><w:p><w:r><w:separator/></w:r></w:p></w:footnote>",
    ] {
    expect_refused(fn() raise {
      ignore(
        rebuild_verified(
          structured_word_fixture(body, notes=note_xml("footnotes", content)),
        ),
      )
    })
  }
  expect_refused(fn() raise {
    ignore(rebuild_verified(structured_word_fixture(body)))
  })
  expect_refused(fn() raise {
    ignore(
      rebuild_verified(
        structured_word_fixture(
          body + body,
          notes=note_xml("footnotes", normal),
        ),
      ),
    )
  })
  expect_refused(fn() raise {
    ignore(
      rebuild_verified(
        structured_word_fixture("<w:p/>", notes=note_xml("footnotes", normal)),
      ),
    )
  })
}

///|
test "numbering references require existing instances abstract IDs and levels" {
  let body = "<w:p><w:pPr><w:numPr><w:numId w:val='7'/></w:numPr></w:pPr><w:r><w:t>item</w:t></w:r></w:p>"
  for
    numbering in [
      simple_numbering(instance="8"),
      simple_numbering(abstract_id="4"),
      simple_numbering(level="1"),
      simple_numbering(extra="<w:lvl w:ilvl='00'/>"),
    ] {
    expect_refused(fn() raise {
      ignore(rebuild_verified(structured_word_fixture(body, numbering~)))
    })
  }
  expect_refused(fn() raise {
    ignore(rebuild_verified(structured_word_fixture(body)))
  })
  let cancelled = "<w:p><w:pPr><w:numPr><w:numId w:val='0'/></w:numPr></w:pPr></w:p>"
  assert_eq(
    rebuild_verified(structured_word_fixture(cancelled)).receipt.result,
    Pass,
  )
}

///|
test "numbering overrides are retained but mismatched or duplicated levels refuse" {
  let body = "<w:p><w:pPr><w:numPr><w:numId w:val='7'/></w:numPr></w:pPr></w:p>"
  let abstract_part = "<w:abstractNum w:abstractNumId='3'><w:lvl w:ilvl='0'><w:numFmt w:val='decimal'/><w:lvlText w:val='%1.'/></w:lvl></w:abstractNum>"
  for
    pair in [
      (
        "<w:lvlOverride w:ilvl='0'><w:startOverride w:val='5'/></w:lvlOverride>",
        true,
      ),
      ("<w:lvlOverride w:ilvl='0'><w:lvl w:ilvl='1'/></w:lvlOverride>", false),
      ("<w:lvlOverride w:ilvl='0'/><w:lvlOverride w:ilvl='00'/>", false),
      ("<w:lvlOverride w:ilvl='9'/>", false),
      (
        "<w:lvlOverride w:ilvl='0'><w:lvl w:ilvl='0'/><w:lvl w:ilvl='0'/></w:lvlOverride>",
        false,
      ),
      (
        "<w:lvlOverride w:ilvl='0'><w:startOverride w:val='5'/><w:startOverride w:val='6'/></w:lvlOverride>",
        false,
      ),
    ] {
    let (replacement, permitted) = pair
    let numbering = note_xml(
      "numbering",
      abstract_part +
      "<w:num w:numId='7'><w:abstractNumId w:val='3'/>" +
      replacement +
      "</w:num>",
    )
    if permitted {
      assert_eq(
        rebuild_verified(structured_word_fixture(body, numbering~)).receipt.result,
        Pass,
      )
    } else {
      expect_refused(fn() raise {
        ignore(rebuild_verified(structured_word_fixture(body, numbering~)))
      })
    }
  }
}

///|
test "new paragraph styles require exact element contexts and bounded outline levels" {
  let styles = note_xml(
    "styles", "<w:style w:type='paragraph' w:styleId='Heading1'><w:name w:val='Heading 1'/><w:pPr><w:outlineLvl w:val='0'/><w:contextualSpacing/><w:tabs><w:tab w:val='left' w:pos='720'/></w:tabs></w:pPr><w:rPr><w:bCs/><w:iCs/><w:kern w:val='28'/></w:rPr></w:style>",
  )
  assert_eq(
    rebuild_verified(structured_word_fixture("<w:p/>", styles~)).receipt.result,
    Pass,
  )
  for
    body in [
      "<w:p><w:pPr><w:outlineLvl w:val='10'/></w:pPr></w:p>", "<w:p><w:kern w:val='28'/></w:p>",
      "<w:p><w:pPr><w:numPr><w:ilvl w:val='9'/><w:numId w:val='0'/></w:numPr></w:pPr></w:p>",
    ] {
    expect_refused(fn() raise {
      ignore(rebuild_verified(structured_word_fixture(body)))
    })
  }
}
