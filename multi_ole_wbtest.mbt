///|
fn multi_ole_nodes(count : Int, shape_type? : String = "") -> Array[Node] raise {
  let objects = Array::makei(count, fn(i) {
    let id = i.to_string()
    "<w:r><w:object><v:shape id='s" +
    id +
    "'" +
    (if shape_type == "" { "" } else { " type='" + shape_type + "'" }) +
    "><v:imagedata r:id='p" +
    id +
    "'/></v:shape><o:OLEObject Type='Embed' ShapeID='s" +
    id +
    "' ObjectID='_" +
    id +
    "' r:id='e" +
    id +
    "'/></w:object></w:r>"
  }).join("")
  let text = "<w:document xmlns:w='" +
    word_ns +
    "' xmlns:v='" +
    vml_ns +
    "' xmlns:o='" +
    word_office_ns +
    "' xmlns:r='" +
    office_rel[0:office_rel.length() - 1].to_owned() +
    "'><w:body><w:p>" +
    objects +
    "</w:p></w:body></w:document>"
  read_xml(@utf8.encode(text[:])[:], Limits::default())
}

///|
test "independent OLE subtree catalog accepts 32 and rejects 33" {
  let nodes = multi_ole_nodes(32)
  let groups = ole_groups(nodes)
  assert_eq(groups.length(), 32)
  for group in groups {
    assert_eq(group.length(), 4)
  }
  expect_refused(fn() raise { ignore(ole_groups(multi_ole_nodes(33))) })
}

///|
test "OLE catalog binds local source relationship and rejects external aliases" {
  let source = "word/document.xml"
  let catalog = ole_catalog(
    [{ name: source, content_type: docx_ct, sha256: "test", }],
    Map([(source, multi_ole_nodes(2))]),
  )
  let edge = {
    ..graph_edge(source, "e0", "word/embeddings/a.bin"),
    kind: office_rel + "oleObject",
  }
  assert_true(ole_declared(edge, catalog))
  assert_true(ole_declared({ ..edge, id: "e1", }, catalog))
  assert_eq(ole_declared({ ..edge, id: "absent", }, catalog), false)
  assert_eq(
    ole_declared({ ..edge, source: "word/header1.xml", }, catalog),
    false,
  )
  assert_eq(ole_declared({ ..edge, external: true, }, catalog), false)
  assert_eq(
    ole_declared({ ..edge, kind: office_rel + "image", }, catalog),
    false,
  )
  assert_eq(ole_catalog_mask(catalog, source).length(), 8)
}

///|
test "invalid later OLE object cannot contribute a partial catalog mask" {
  let nodes = multi_ole_nodes(2)
  let second = ole_groups(nodes)[1]
  let shape = second[1]
  // Replacing one object with another's nodes repeats identities and bindings.
  let repeated = nodes.copy()
  repeated[shape] = nodes[ole_groups(nodes)[0][1]]
  expect_refused(fn() raise { ignore(ole_groups(repeated)) })
  let source = "word/document.xml"
  let catalog = ole_catalog(
    [{ name: source, content_type: docx_ct, sha256: "test", }],
    Map([(source, repeated)]),
  )
  assert_eq(ole_catalog_mask(catalog, source).length(), 0)
}

///|
test "OLE ObjectID numeric range follows the removable-object schema" {
  for id in ["_0", "_0001", "_1353480673", "_2147483647"] {
    assert_true(valid_ole_object_id(id))
  }
  for
    id in [
      "", "_", "o1", "_partsieve_object_1", "_-1", "_2147483648", "_0000000001",
      "_99999999999999999999",
    ] {
    assert_eq(valid_ole_object_id(id), false)
  }
}

///|
test "OLE preview shape cannot depend on another object's type definition" {
  expect_refused(fn() raise {
    ignore(ole_groups(multi_ole_nodes(2, shape_type="#foreign")))
  })
}
