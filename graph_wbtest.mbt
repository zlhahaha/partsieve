///|
fn graph_part(name : String) -> PartRecord {
  { name, content_type: "application/xml", sha256: "unit-test-placeholder", }
}

///|
fn graph_edge(
  source : String,
  id : String,
  target : String,
  external? : Bool = false,
) -> Relationship {
  {
    source,
    id,
    kind: office_rel + "worksheet",
    target,
    resolved: if external {
      ""
    } else {
      target
    },
    external,
  }
}

///|
test "graph indices keep local IDs separate and namespace aliases resolve id embed link" {
  let parts = [graph_part("a.xml"), graph_part("b.xml"), graph_part("c.xml")]
  let edges = [
    graph_edge("/", "root", "a.xml"),
    graph_edge("a.xml", "same", "b.xml"),
    graph_edge("b.xml", "same", "c.xml"),
  ]
  let xml = "<worksheet xmlns='" +
    spreadsheet_ns +
    "' xmlns:alias='http://schemas.openxmlformats.org/officeDocument/2006/relationships' alias:id='same' alias:embed='same' alias:link='same'/>"
  let nodes : Map[String, Array[Node]] = Map([
    ("a.xml", read_xml(@utf8.encode(xml[:])[:], Limits::default())),
    ("b.xml", read_xml(@utf8.encode(xml[:])[:], Limits::default())),
  ])
  let facts = build_graph(parts, edges, nodes)
  assert_eq(graph_relationship(facts, "a.xml", "same"), Some(edges[1]))
  assert_eq(graph_relationship(facts, "b.xml", "same"), Some(edges[2]))
  assert_eq(graph_relationship(facts, "/", "same"), None)
  assert_eq(facts.graph.xml_references.length(), 6)
  assert_eq(facts.graph.xml_references.map(fn(r) { r.relationship_index }), [
    1, 1, 1, 2, 2, 2,
  ])
  assert_eq(facts.graph.xml_references.map(fn(r) { r.attribute_name }), [
    "id", "embed", "link", "id", "embed", "link",
  ])
  assert_eq(facts.graph.nodes[facts.node_index["b.xml"]].inbound, [1])
  assert_eq(facts.graph.nodes[facts.node_index["b.xml"]].outbound, [2])
  assert_eq(facts.graph.nodes[facts.node_index["a.xml"]].xml_references, [
    0, 1, 2,
  ])
  assert_eq(facts.graph, build_graph(parts, edges, nodes).graph)
  assert_eq(facts.graph.content_types, [
    ContentTypeIndex::{
      content_type: "application/xml",
      parts: ["a.xml", "b.xml", "c.xml"],
    },
  ])
}

///|
test "graph rejects missing targets duplicate local IDs and cross-source reference aliases" {
  let parts = [graph_part("a.xml"), graph_part("b.xml")]
  expect_refused(fn() raise {
    ignore(
      build_graph(parts, [graph_edge("a.xml", "r", "missing.xml")], Map([])),
    )
  })
  expect_refused(fn() raise {
    ignore(
      build_graph(
        parts,
        [graph_edge("a.xml", "r", "b.xml"), graph_edge("a.xml", "r", "b.xml")],
        Map([]),
      ),
    )
  })
  let xml = "<worksheet xmlns='" +
    spreadsheet_ns +
    "' xmlns:r='http://schemas.openxmlformats.org/officeDocument/2006/relationships' r:id='root-only'/>"
  expect_refused(fn() raise {
    ignore(
      build_graph(
        parts,
        [graph_edge("/", "root-only", "a.xml")],
        Map([("a.xml", read_xml(@utf8.encode(xml[:])[:], Limits::default()))]),
      ),
    )
  })
  // A matching local attribute name in a different namespace is not r:id.
  let other = "<worksheet xmlns='" +
    spreadsheet_ns +
    "' xmlns:foreign='urn:foreign' foreign:id='absent'/>"
  let g = build_graph(
      parts,
      [],
      Map([("a.xml", read_xml(@utf8.encode(other[:])[:], Limits::default()))]),
    ).graph
  assert_eq(g.xml_references.length(), 0)
  assert_eq(g.coverage_gaps.length(), 1)
}

///|
test "external targets never become package vertices and orphan candidates never delete parts" {
  let parts = [
    graph_part("a.xml"),
    graph_part("b.xml"),
    graph_part("unused.xml"),
  ]
  let edges = [
    graph_edge("/", "root", "a.xml"),
    graph_edge(
      "a.xml",
      "external",
      "https://example.invalid/b.xml",
      external=true,
    ),
  ]
  let facts = build_graph(parts, edges, Map([]))
  assert_eq(facts.graph.reachable, ["/", "a.xml"])
  assert_eq(facts.graph.orphan_candidates, ["b.xml", "unused.xml"])
  assert_eq(facts.graph.nodes[facts.node_index["b.xml"]].inbound, [])
  assert_eq(facts.graph.nodes[facts.node_index["a.xml"]].outbound, [1])
  assert_eq(facts.graph.parts, parts)
}

///|
test "iterative reachability handles a full-size chain with a cycle" {
  let parts = Array::makei(4096, i => graph_part("p\{i}.xml"))
  let edges = [graph_edge("/", "root", "p0.xml")]
  for i in 0..<4095 {
    edges.push(graph_edge("p\{i}.xml", "next", "p\{i + 1}.xml"))
  }
  edges.push(graph_edge("p4095.xml", "cycle", "p0.xml"))
  let g = build_graph(parts, edges, Map([])).graph
  assert_eq(g.reachable.length(), 4097)
  assert_eq(g.orphan_candidates, [])
}

///|
test "metadata reachability and implicit workbook references retain graph ownership" {
  let parts = [
    graph_part("[Content_Types].xml"),
    graph_part("_rels/.rels"),
    graph_part("xl/_rels/workbook.xml.rels"),
    { ..graph_part("xl/workbook.xml"), content_type: xlsm_ct, },
    graph_part("xl/vbaProject.bin"),
  ]
  let main = {
    ..graph_edge("/", "main", "xl/workbook.xml"),
    kind: office_rel + "officeDocument",
  }
  let vba = {
    ..graph_edge("xl/workbook.xml", "vba", "xl/vbaProject.bin"),
    kind: vba_rel,
  }
  let g = build_graph(parts, [main, vba], Map([])).graph
  assert_eq(g.orphan_candidates, [])
  assert_eq(g.reachable.length(), 6)
  assert_eq(g.implicit_references.map(fn(r) { r.relationship_index }), [0, 1])
}

///|
test "AlternateContent VML and unknown extension markup report coverage gaps" {
  let samples = [
    "<mc:AlternateContent xmlns:mc='http://schemas.openxmlformats.org/markup-compatibility/2006'/>",
    "<v:shape xmlns:v='urn:schemas-microsoft-com:vml'/>",
    "<extLst xmlns='" + spreadsheet_ns + "'/>",
    "<unknown xmlns='urn:unknown'/>",
  ]
  for xml in samples {
    let g = build_graph(
        [graph_part("a.xml")],
        [],
        Map([("a.xml", read_xml(@utf8.encode(xml[:])[:], Limits::default()))]),
      ).graph
    assert_eq(g.coverage_gaps.length(), 1)
    assert_eq(g.orphan_candidates, ["a.xml"])
  }
}

///|
test "XML reference index exact ceiling and plus one are bounded" {
  let prefix = "<worksheet xmlns='" +
    spreadsheet_ns +
    "' xmlns:r='http://schemas.openxmlformats.org/officeDocument/2006/relationships'>"
  let text = prefix +
    Array::make(32768, "<row r:id='same'/>").join("") +
    "</worksheet>"
  let nodes = read_xml(@utf8.encode(text[:])[:], Limits::default())
  let parts = [graph_part("a.xml"), graph_part("b.xml")]
  let edges = [graph_edge("a.xml", "same", "b.xml")]
  let g = build_graph(parts, edges, Map([("a.xml", nodes)])).graph
  assert_eq(g.xml_references.length(), 32768)
  let over = prefix +
    Array::make(32769, "<row r:id='same'/>").join("") +
    "</worksheet>"
  let over_nodes = read_xml(@utf8.encode(over[:])[:], Limits::default())
  expect_incomplete(fn() raise {
    ignore(build_graph(parts, edges, Map([("a.xml", over_nodes)])))
  })
}
