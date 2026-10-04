///|
fn expect_refused(action : () -> Unit raise) -> Unit raise {
  action() catch {
    _ => return
  }
  fail("expected rejection")
}

///|
fn expect_incomplete(action : () -> Unit raise) -> Unit raise {
  action() catch {
    Incomplete(_) => return
    error => fail("expected Incomplete, got " + error.to_string())
  }
  fail("expected Incomplete")
}

///|
test "parse truncation and resource exhaustion are incomplete, never Pass" {
  expect_incomplete(fn() raise { ignore(audit(b"PK\x03\x04")) })
  expect_incomplete(fn() raise { ignore(rebuild(b"PK\x03\x04")) })
  expect_incomplete(fn() raise { ignore(read_xml(b"<a>", Limits::default())) })
  expect_incomplete(fn() raise { ignore(read_xml(b"\xff", Limits::default())) })
  expect_incomplete(fn() raise {
    ignore(read_xml(b"<a><b/></a>", { ..Limits::default(), xml_depth: 1, }))
  })
}

///|
test "XML token exact ceiling and ceiling plus one" {
  let exact = "<a x='" + Array::make(65527, "x").join("") + "'/>"
  assert_eq(exact.length(), 65536)
  ignore(read_xml(@utf8.encode(exact[:])[:], Limits::default()))
  let over = "<a x='" + Array::make(65528, "x").join("") + "'/>"
  expect_incomplete(fn() raise {
    ignore(read_xml(@utf8.encode(over[:])[:], Limits::default()))
  })
  let comment = "<!--" + Array::make(65529, "x").join("") + "-->"
  ignore(read_xml(@utf8.encode((comment + "<a/>")[:])[:], Limits::default()))
  let long_comment = "<!--" + Array::make(65530, "x").join("") + "--><a/>"
  expect_incomplete(fn() raise {
    ignore(read_xml(@utf8.encode(long_comment[:])[:], Limits::default()))
  })
  let text = Array::make(65536, "x").join("")
  ignore(
    read_xml(@utf8.encode(("<a>" + text + "</a>")[:])[:], Limits::default()),
  )
  expect_incomplete(fn() raise {
    ignore(
      read_xml(@utf8.encode(("<a>" + text + "x</a>")[:])[:], Limits::default()),
    )
  })
  let cdata = "<![CDATA[" + Array::make(65524, "x").join("") + "]]>"
  ignore(
    read_xml(@utf8.encode(("<a>" + cdata + "</a>")[:])[:], Limits::default()),
  )
  let long_cdata = "<![CDATA[" + Array::make(65525, "x").join("") + "]]>"
  expect_incomplete(fn() raise {
    ignore(
      read_xml(
        @utf8.encode(("<a>" + long_cdata + "</a>")[:])[:],
        Limits::default(),
      ),
    )
  })
  let attrs = Array::makei(256, i => "a\{i}='1'").join(" ")
  ignore(
    read_xml(@utf8.encode(("<a " + attrs + "/>")[:])[:], Limits::default()),
  )
  expect_incomplete(fn() raise {
    ignore(
      read_xml(
        @utf8.encode(("<a " + attrs + " a256='1'/>")[:])[:],
        Limits::default(),
      ),
    )
  })
}

///|
test "SDK adapter enforces all configured package bounds at the exact boundary" {
  // Synthetic static package for resource boundaries; not client evidence.
  let archive = @zip.Archive()
  archive.add(
    "[Content_Types].xml",
    @utf8.encode(
      ("<Types xmlns='" +
      ct_ns +
      "'><Default Extension='rels' ContentType='application/vnd.openxmlformats-package.relationships+xml'/><Override PartName='/xl/workbook.xml' ContentType='" +
      xlsx_ct +
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
  let bytes = @zip.write(archive)
  let mut total = 0
  let mut maximum = 0
  for entry in archive.entries() {
    total += entry.data().length()
    maximum = maximum.max(entry.data().length())
  }
  let exact : Limits = {
    ..Limits::default(),
    input_bytes: bytes.length(),
    entry_bytes: maximum,
    total_bytes: total,
    entries: 5,
    xml_bytes: maximum,
    xml_depth: 3,
    xml_nodes: 4,
    xml_attributes: 7,
  }
  assert_eq(audit(bytes, limits=exact).format, "XLSX")
  for
    limits in [
      { ..exact, input_bytes: exact.input_bytes - 1, },
      { ..exact, entry_bytes: maximum - 1, },
      { ..exact, total_bytes: total - 1, },
      { ..exact, entries: 4, },
      { ..exact, xml_bytes: maximum - 1, },
      { ..exact, xml_depth: 2, },
      { ..exact, xml_nodes: 3, },
      { ..exact, xml_attributes: 6, },
    ] {
    expect_incomplete(fn() raise { ignore(audit(bytes, limits~)) })
  }
  let output = rebuild(bytes).bytes
  ignore(
    rebuild(bytes, limits={
      ..Limits::default(),
      output_bytes: output.length(),
    }),
  )
  expect_incomplete(fn() raise {
    ignore(
      rebuild(bytes, limits={
        ..Limits::default(),
        output_bytes: output.length() - 1,
      }),
    )
  })
}

///|
test "OPC resolution is source-relative or package-absolute" {
  assert_eq(
    resolve_target("xl/workbook.xml", "worksheets/sheet1.xml"),
    "xl/worksheets/sheet1.xml",
  )
  assert_eq(resolve_target("xl/sub/book.xml", "../styles.xml"), "xl/styles.xml")
  assert_eq(
    resolve_target("xl/workbook.xml", "/docProps/core.xml"),
    "docProps/core.xml",
  )
  assert_eq(resolve_target("/", "xl/workbook.xml"), "xl/workbook.xml")
}

///|
test "OPC traversal and URI aliases fail closed" {
  for
    target in [
      "../../evil.xml", "a%2fb.xml", "a\\b.xml", "https://x/a", "//host/a", "a.xml#id",
      "a.xml?x=1", "a//b", "a./b", "",
    ] {
    expect_refused(fn() raise {
      ignore(resolve_target("xl/workbook.xml", target))
    })
  }
}

///|
test "relationship ID scope comes from rels location" {
  assert_eq(relationship_source("_rels/.rels"), "/")
  assert_eq(
    relationship_source("xl/_rels/workbook.xml.rels"),
    "xl/workbook.xml",
  )
  assert_eq(relationship_part("xl/workbook.xml"), "xl/_rels/workbook.xml.rels")
  expect_refused(fn() raise { ignore(relationship_source("xl/workbook.rels")) })
}

///|
test "SHA256 known answer" {
  assert_eq(
    digest(b"abc"),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
}

///|
test "namespace prefix is not identity" {
  let a = read_xml(
    b"<q:r xmlns:q='urn:x'><q:c a='1'/></q:r>",
    Limits::default(),
  )
  assert_eq(a[1].element.name.namespace_uri, Some("urn:x"))
  assert_eq(a[1].element.name.local_name, "c")
  assert_eq(attr(a[1], "a"), "1")
}

///|
test "XML depth exact limit and limit plus one" {
  let limits = { ..Limits::default(), xml_depth: 2, }
  ignore(read_xml(b"<a><b/></a>", limits))
  expect_refused(fn() raise { ignore(read_xml(b"<a><b><c/></b></a>", limits)) })
}

///|
test "XML byte node and attribute exact limits" {
  ignore(
    read_xml(b"<a/>", { ..Limits::default(), xml_bytes: 4, xml_nodes: 1, }),
  )
  expect_refused(fn() raise {
    ignore(read_xml(b"<a />", { ..Limits::default(), xml_bytes: 4, }))
  })
  expect_refused(fn() raise {
    ignore(read_xml(b"<a><b/></a>", { ..Limits::default(), xml_nodes: 1, }))
  })
  ignore(read_xml(b"<a x='1'/>", { ..Limits::default(), xml_attributes: 1, }))
  expect_refused(fn() raise {
    ignore(
      read_xml(b"<a x='1' y='2'/>", { ..Limits::default(), xml_attributes: 1, }),
    )
  })
}

///|
test "DTD rejected before expansion; malformed XML and UTF8 rejected" {
  for
    text in [
      "<!DOCTYPE a [<!ENTITY e 'x'>]><a>&e;</a>", "<a>", "<a x='1' x='2'/>", "<p:a/>",
      "<a></b>", "<a/><b/>",
    ] {
    expect_refused(fn() raise {
      ignore(read_xml(@utf8.encode(text[:])[:], Limits::default()))
    })
  }
  expect_refused(fn() raise { ignore(read_xml(b"\xff", Limits::default())) })
}

///|
test "preflight handles comments CDATA and quoted angle brackets" {
  ignore(
    read_xml(b"<a x='&gt;'><![CDATA[<ignored/>]]><!-- <ignored/> --></a>", {
      ..Limits::default(),
      xml_depth: 1,
      xml_nodes: 1,
    }),
  )
}

///|
test "invalid resource configuration refused" {
  expect_refused(fn() raise { { ..Limits::default(), entries: 0, }.validate() })
  expect_refused(fn() raise {
    { ..Limits::default(), xml_depth: 129, }.validate()
  })
}

///|
test "ZIP bounded read exact input entry total and count limits" {
  let archive = @zip.Archive()
  archive.add("a", b"abc", compression=@zip.Deflate)
  let bytes = @zip.write(archive)
  let limits = @zip.ReadLimits::default()
    .with_package_limit(bytes.length())
    .with_entry_limit(3)
    .with_total_limit(3)
    .with_entries_limit(1)
  let read = @zip.read(bytes[:], limits~)
  assert_eq(read.get("a"), Some(b"abc"[:]))
  expect_refused(fn() raise {
    ignore(
      @zip.read(bytes[:], limits=limits.with_package_limit(bytes.length() - 1)),
    )
  })
  expect_refused(fn() raise {
    ignore(@zip.read(bytes[:], limits=limits.with_entry_limit(2)))
  })
  expect_refused(fn() raise {
    ignore(@zip.read(bytes[:], limits=limits.with_total_limit(2)))
  })
  expect_refused(fn() raise {
    ignore(@zip.read(bytes[:], limits=limits.with_entries_limit(0)))
  })
}

///|
test "ZIP preserving API remove replace opaque payload and output bound" {
  let archive = @zip.Archive()
  archive.add("unknown.bin", b"\x00\xffopaque")
  archive.add("old.xml", b"<old/>")
  let original = @zip.write(archive)
  let read = @zip.read(original[:])
  assert_true(read.replace("old.xml", b"<new/>"))
  read.add("remove.bin", b"x")
  assert_true(read.remove("remove.bin"))
  let output = @zip.write_preserving_limited(read, max_output_bytes=4096)
  let rebuilt = @zip.read(output[:])
  assert_eq(rebuilt.get("unknown.bin"), Some(b"\x00\xffopaque"[:]))
  assert_eq(rebuilt.get("old.xml"), Some(b"<new/>"[:]))
  assert_eq(rebuilt.get("remove.bin"), None)
  ignore(@zip.write_preserving_limited(read, max_output_bytes=output.length()))
  expect_refused(fn() raise {
    ignore(
      @zip.write_preserving_limited(read, max_output_bytes=output.length() - 1),
    )
  })
}
