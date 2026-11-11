///|
let bibliography_ns = "http://schemas.openxmlformats.org/officeDocument/2006/bibliography"

///|
let custom_properties_ns = "http://schemas.openxmlformats.org/officeDocument/2006/customXml"

///|
let custom_properties_ct = "application/vnd.openxmlformats-officedocument.customXmlProperties+xml"

///|
fn word_custom_relationship(
  r : Relationship,
  parts : Array[PartRecord],
  nodes : Map[String, Array[Node]],
) -> Bool {
  if r.external {
    return false
  }
  if r.kind == office_rel + "customXml" {
    parts.any(fn(p) {
      p.name == r.source && [docx_ct, docm_ct].contains(p.content_type)
    }) &&
    parts.any(fn(p) {
      p.name == r.resolved && p.content_type == "application/xml"
    }) &&
    nodes
    .get(r.resolved)
    .map(fn(ns) {
      ns.length() > 0 &&
      ns[0].element.name.namespace_uri == Some(bibliography_ns) &&
      ns[0].element.name.local_name == "Sources"
    })
    .unwrap_or(false)
  } else if r.kind == office_rel + "customXmlProps" {
    parts.any(fn(p) {
      p.name == r.source && p.content_type == "application/xml"
    }) &&
    parts.any(fn(p) {
      p.name == r.resolved && p.content_type == custom_properties_ct
    }) &&
    nodes
    .get(r.source)
    .map(fn(ns) {
      ns.length() > 0 &&
      ns[0].element.name.namespace_uri == Some(bibliography_ns) &&
      ns[0].element.name.local_name == "Sources"
    })
    .unwrap_or(false)
  } else {
    false
  }
}

///|
// Empty built-in APA bibliography metadata only. No general custom XML,
// transformation, stylesheet loading, data binding or schema retrieval.
fn validate_word_bibliography(pkg : Package) -> Map[String, Bool] raise {
  let owned : Map[String, Bool] = Map([])
  let ids : Map[String, Bool] = Map([])
  let data_relations = pkg.audit.relationships.filter(fn(r) {
    r.kind == office_rel + "customXml"
  })
  guard data_relations.length() <= 32 else {
    raise Refused("bibliography item limit")
  }
  for r in data_relations {
    pkg.control.checkpoint("word-bibliography-item", 1)
    guard r.source == pkg.audit.main_part &&
      word_custom_relationship(r, pkg.audit.parts, pkg.xml_nodes) &&
      graph_incoming(pkg.graph, r.resolved).length() == 1 &&
      !owned.contains(r.resolved) else {
      raise Invalid("ambiguous bibliography data ownership")
    }
    let nodes = pkg.xml_nodes[r.resolved]
    guard nodes.length() == 1 &&
      empty_node(nodes[0]) &&
      exact_node_attributes(nodes[0], None, [
        "SelectedStyle", "StyleName", "URI",
      ]) &&
      attr(nodes[0], "SelectedStyle") == "\\APA.XSL" &&
      attr(nodes[0], "StyleName") == "APA" &&
      attr_opt(nodes[0], "URI")
      .map(fn(v) {
        v == "http://schemas.openxmlformats.org/bibliographicStyle/APA"
      })
      .unwrap_or(true) else {
      raise Refused("unsupported bibliography sources or style")
    }
    let outgoing = pkg.audit.relationships.filter(fn(edge) {
      edge.source == r.resolved
    })
    guard outgoing.length() == 1 &&
      outgoing[0].kind == office_rel + "customXmlProps" &&
      word_custom_relationship(outgoing[0], pkg.audit.parts, pkg.xml_nodes) else {
      raise Refused("bibliography properties ownership missing or unsupported")
    }
    let properties = outgoing[0].resolved
    guard graph_incoming(pkg.graph, properties).length() == 1 &&
      !owned.contains(properties) &&
      !pkg.audit.relationships.any(fn(edge) { edge.source == properties }) else {
      raise Invalid("shared or nested bibliography properties")
    }
    let props = pkg.xml_nodes[properties]
    guard props.length() == 3 &&
      props[0].depth == 0 &&
      props[0].element.name.namespace_uri == Some(custom_properties_ns) &&
      props[0].element.name.local_name == "datastoreItem" &&
      exact_node_attributes(props[0], Some(custom_properties_ns), ["itemID"]) &&
      props[0].element.attributes.length() == 1 &&
      props[1].depth == 1 &&
      props[1].element.name.namespace_uri == Some(custom_properties_ns) &&
      props[1].element.name.local_name == "schemaRefs" &&
      props[1].element.attributes.length() == 0 &&
      props[2].depth == 2 &&
      props[2].element.name.namespace_uri == Some(custom_properties_ns) &&
      props[2].element.name.local_name == "schemaRef" &&
      exact_node_attributes(props[2], Some(custom_properties_ns), ["uri"]) &&
      props[2].element.attributes.length() == 1 &&
      props[2].element.attributes[0].value == bibliography_ns &&
      props.all(empty_node) else {
      raise Refused("unsupported bibliography property schema")
    }
    let id = props[0].element.attributes[0].value.to_lower()
    guard valid_guid(id) && !ids.contains(id) else {
      raise Invalid("invalid or duplicate bibliography datastore ID")
    }
    ids[id] = true
    owned[r.resolved] = true
    owned[properties] = true
  }
  for r in pkg.audit.relationships {
    if r.kind == office_rel + "customXmlProps" {
      guard owned.contains(r.source) && owned.contains(r.resolved) else {
        raise Invalid("orphan bibliography properties relation")
      }
    }
  }
  for p in pkg.audit.parts {
    if p.name != "[Content_Types].xml" &&
      ["application/xml", custom_properties_ct].contains(p.content_type) {
      guard owned.contains(p.name) else {
        raise Refused("unmodeled or orphan custom XML part")
      }
    }
  }
  owned
}
