///|
priv struct GraphFacts {
  graph : PackageGraph
  part_index : Map[String, Int]
  node_index : Map[String, Int]
  local_relationships : Map[String, Map[String, Int]]
}

///|
fn graph_relationship(
  facts : GraphFacts,
  source : String,
  id : String,
) -> Relationship? {
  match facts.local_relationships.get(source) {
    Some(ids) => ids.get(id).map(fn(i) { facts.graph.relationships[i] })
    None => None
  }
}

///|
fn graph_incoming(facts : GraphFacts, target : String) -> Array[Relationship] {
  facts.graph.nodes[facts.node_index[target]].inbound.map(fn(i) {
    facts.graph.relationships[i]
  })
}

///|
fn build_graph(
  parts : Array[PartRecord],
  relationships : Array[Relationship],
  xml_nodes : Map[String, Array[Node]],
) -> GraphFacts raise {
  let part_index : Map[String, Int] = Map([])
  let node_index : Map[String, Int] = Map([("/", 0)])
  let names : Array[String] = ["/"]
  let inbound : Array[Array[Int]] = [[]]
  let outbound : Array[Array[Int]] = [[]]
  let source_refs : Array[Array[Int]] = [[]]
  let type_parts : Map[String, Array[String]] = Map([])
  for i, part in parts {
    guard !part_index.contains(part.name) else {
      raise Invalid("duplicate graph part")
    }
    part_index[part.name] = i
    node_index[part.name] = names.length()
    names.push(part.name)
    inbound.push([])
    outbound.push([])
    source_refs.push([])
    match type_parts.get(part.content_type) {
      Some(names) => names.push(part.name)
      None => type_parts[part.content_type] = [part.name]
    }
  }
  let local_relationships : Map[String, Map[String, Int]] = Map([])
  let implicit : Array[ImplicitReference] = []
  let gaps : Array[String] = []
  for i, r in relationships {
    guard node_index.contains(r.source) else {
      raise Invalid("relationship source missing")
    }
    let ids = match local_relationships.get(r.source) {
      Some(ids) => ids
      None => {
        let ids : Map[String, Int] = Map([])
        local_relationships[r.source] = ids
        ids
      }
    }
    guard !ids.contains(r.id) else {
      raise Invalid("duplicate local graph relationship ID")
    }
    ids[r.id] = i
    outbound[node_index[r.source]].push(i)
    if !r.external {
      guard node_index.contains(r.resolved) && r.resolved != "/" else {
        raise Invalid("internal graph target missing")
      }
      inbound[node_index[r.resolved]].push(i)
    }
    let implicit_semantics = if r.source == "/" &&
      (
        r.kind == office_rel + "officeDocument" ||
        r.kind == office_rel + "extended-properties" ||
        r.kind ==
        "http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties"
      ) {
      Some("package metadata relationship")
    } else if part_index.get(r.source) is Some(source_part) &&
      (
        parts[source_part].content_type == xlsm_ct ||
        parts[source_part].content_type == xlsx_ct ||
        parts[source_part].content_type == docm_ct ||
        parts[source_part].content_type == docx_ct
      ) &&
      (
        r.kind == vba_rel ||
        r.kind == office_rel + "styles" ||
        r.kind == office_rel + "theme" ||
        r.kind == office_rel + "sharedStrings" ||
        r.kind == office_rel + "settings" ||
        r.kind == office_rel + "fontTable" ||
        r.kind == office_rel + "webSettings"
      ) {
      Some(
        "main-document implicit relationship; retained indices are not garbage-collected",
      )
    } else if r.kind == word_vba_data_rel &&
      part_index.get(r.source) is Some(source_part) &&
      parts[source_part].content_type == vba_ct {
      Some("Word VBA supporting metadata owned by its VBA project")
    } else {
      None
    }
    if implicit_semantics is Some(semantics) {
      implicit.push({ source: r.source, relationship_index: i, semantics, })
    } else if r.kind != office_rel + "worksheet" {
      gaps.push("unsupported relationship semantics: " + r.source + "#" + r.id)
    }
  }
  let references : Array[XmlReference] = []
  let relationship_ns = office_rel[0:office_rel.length() - 1].to_owned()
  let known_namespaces = [
    ct_ns, rel_ns, spreadsheet_ns, drawing_ns, word_ns, word_math_ns, word_office_ns,
    word_macro_ns, "http://schemas.openxmlformats.org/package/2006/metadata/core-properties",
    "http://purl.org/dc/elements/1.1/", "http://purl.org/dc/terms/", "http://schemas.openxmlformats.org/officeDocument/2006/extended-properties",
    "http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes",
  ]
  for part in parts {
    if xml_nodes.get(part.name) is Some(nodes) {
      let mut has_opaque_content = false
      for ordinal, node in nodes {
        let ns = node.element.name.namespace_uri.unwrap_or("")
        let local_name = node.element.name.local_name
        if ns == "http://schemas.openxmlformats.org/markup-compatibility/2006" ||
          ns == "urn:schemas-microsoft-com:vml" ||
          !known_namespaces.contains(ns) ||
          local_name == "ext" ||
          local_name == "extLst" {
          has_opaque_content = true
        }
        for a in node.element.attributes {
          let attribute_ns = a.name.namespace_uri.unwrap_or("")
          let inert_shape_attribute = part.content_type ==
            "application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml" &&
            ns == word_office_ns &&
            ["shapedefaults", "shapelayout", "idmap"].contains(local_name) &&
            attribute_ns == "urn:schemas-microsoft-com:vml" &&
            a.name.local_name == "ext" &&
            a.value == "edit"
          if !inert_shape_attribute &&
            attribute_ns != "" &&
            attribute_ns != relationship_ns &&
            attribute_ns != word_ns &&
            attribute_ns != word_math_ns &&
            attribute_ns != word_macro_ns &&
            attribute_ns != "http://www.w3.org/XML/1998/namespace" &&
            attribute_ns != "http://www.w3.org/2001/XMLSchema-instance" {
            has_opaque_content = true
          }
          if a.name.namespace_uri == Some(relationship_ns) &&
            ["id", "embed", "link"].contains(a.name.local_name) {
            guard references.length() < 32768 else {
              raise Incomplete("XML relationship reference limit")
            }
            guard local_relationships.get(part.name) is Some(ids) &&
              ids.get(a.value) is Some(index) else {
              raise Invalid("dangling source-local XML relationship reference")
            }
            source_refs[node_index[part.name]].push(references.length())
            references.push({
              source: part.name,
              element_index: ordinal,
              depth: node.depth,
              element_namespace: ns,
              element_name: local_name,
              attribute_name: a.name.local_name,
              relationship_id: a.value,
              relationship_index: index,
            })
          }
        }
      }
      if has_opaque_content {
        gaps.push(
          "opaque XML namespace/extension (including AlternateContent or VML): " +
          part.name,
        )
      }
    }
  }
  // Iterative traversal tolerates cycles and visits each internal edge once.
  let seen : Map[String, Bool] = Map([("/", true)])
  let queue : Array[String] = ["/"]
  let mut cursor = 0
  while cursor < queue.length() {
    let source = queue[cursor]
    cursor += 1
    for i in outbound[node_index[source]] {
      let edge = relationships[i]
      if !edge.external && !seen.contains(edge.resolved) {
        seen[edge.resolved] = true
        queue.push(edge.resolved)
      }
    }
  }
  // Metadata belongs to the package or its reachable source, not to a GC root.
  for part in parts {
    if part.name == "[Content_Types].xml" {
      seen[part.name] = true
    } else if part.name.has_suffix(".rels") {
      let owner = relationship_source(part.name)
      if seen.contains(owner) {
        seen[part.name] = true
      }
    }
  }
  let reachable : Array[String] = []
  let orphans : Array[String] = []
  let graph_nodes : Array[GraphNode] = []
  for i, name in names {
    let reached = seen.contains(name)
    if reached {
      reachable.push(name)
    } else if !name.has_suffix(".rels") {
      orphans.push(name)
    }
    graph_nodes.push({
      part: name,
      inbound: inbound[i],
      outbound: outbound[i],
      xml_references: source_refs[i],
      reachable: reached,
    })
  }
  reachable.sort()
  orphans.sort()
  gaps.sort()
  let types = type_parts.keys().collect()
  types.sort()
  let content_types = types.map(fn(t) {
    let names = type_parts[t]
    names.sort()
    ContentTypeIndex::{ content_type: t, parts: names, }
  })
  {
    graph: {
      schema: "partsieve.graph.v1",
      root: "/",
      parts,
      relationships,
      xml_references: references,
      implicit_references: implicit,
      nodes: graph_nodes,
      content_types,
      reachable,
      orphan_candidates: orphans,
      coverage_gaps: gaps,
    },
    part_index,
    node_index,
    local_relationships,
  }
}

///|
// Structural inspection may report gaps. It does not authorize a rebuild.
pub fn inspect_graph(
  input : Bytes,
  limits? : Limits = Limits::default(),
) -> PackageGraph raise {
  load_package(input, limits, enforce_profile=false).graph.graph
}
