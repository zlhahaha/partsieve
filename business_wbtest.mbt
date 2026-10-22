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
