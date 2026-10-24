///|
let ole_content_type = "application/vnd.openxmlformats-officedocument.oleObject"

///|
let vml_ns = "urn:schemas-microsoft-com:vml"

///|
fn relationship_attribute(node : Node) -> String raise {
  let ids = node.element.attributes.filter(fn(a) {
    a.name.namespace_uri ==
    Some(office_rel[0:office_rel.length() - 1].to_owned()) &&
    a.name.local_name == "id"
  })
  guard ids.length() == 1 else {
    raise Refused("OLE node requires exactly one source-local relationship")
  }
  ids[0].value
}

///|
// Each group is one independently owned inline subtree; no VML is retained.
fn ole_group(nodes : Array[Node], begin : Int) -> Array[Int] raise {
  let depth = nodes[begin].depth
  guard begin > 0 && depth > 0 else {
    raise Refused("OLE object has no parent run")
  }
  let mut parent = begin - 1
  while parent > 0 && nodes[parent].depth >= depth {
    parent -= 1
  }
  guard nodes[parent].depth == depth - 1 &&
    nodes[parent].element.name.namespace_uri == Some(word_ns) &&
    nodes[parent].element.name.local_name == "r" else {
    raise Refused("OLE object must be inline in a Word run")
  }
  let mut end = begin + 1
  while end < nodes.length() && nodes[end].depth > depth {
    end += 1
  }
  let indices : Array[Int] = []
  for i in begin..<end {
    indices.push(i)
  }
  let shape_index = ole_member(nodes, indices, vml_ns, "shape")
  let image_index = ole_member(nodes, indices, vml_ns, "imagedata")
  let ole_index = ole_member(nodes, indices, word_office_ns, "OLEObject")
  let shape = nodes[shape_index]
  let image = nodes[image_index]
  let ole = nodes[ole_index]
  guard shape.depth == depth + 1 &&
    image.depth == depth + 2 &&
    image_index == shape_index + 1 &&
    ole.depth == depth + 1 &&
    ole_index == end - 1 else {
    raise Refused("unsupported inline OLE/preview shape")
  }
  guard attr(ole, "Type") == "Embed" &&
    attr(ole, "ShapeID") == attr(shape, "id") &&
    attr(shape, "id") != "" else {
    raise Refused("OLE must be embedded and match its preview shape identity")
  }
  if attr_opt(ole, "DrawAspect") is Some(aspect) {
    guard ["Content", "Icon"].contains(aspect) else {
      raise Refused("unsupported OLE draw aspect")
    }
  }
  ignore(relationship_attribute(image))
  ignore(relationship_attribute(ole))
  let parents : Array[String] = []
  let mut type_count = 0
  for i in begin..<end {
    let node = nodes[i]
    let ns = node.element.name.namespace_uri.unwrap_or("")
    let name = node.element.name.local_name
    while parents.length() > node.depth - depth {
      ignore(parents.pop())
    }
    let parent = if parents.length() > 0 {
      parents[parents.length() - 1]
    } else {
      ""
    }
    let permitted = if i == begin {
      true
    } else if ns == vml_ns {
      match name {
        "shape" | "shapetype" => parent == "object"
        "imagedata" => parent == "shape"
        "stroke" | "formulas" | "path" => parent == "shapetype"
        "f" => parent == "formulas"
        _ => false
      }
    } else {
      ns == word_office_ns &&
      (
        (name == "OLEObject" && parent == "object") ||
        (name == "lock" && parent == "shapetype")
      )
    }
    guard permitted && node.text_fragments.all(fn(t) { t.trim() == "" }) else {
      raise Refused("unknown content inside Word OLE object")
    }
    if name == "shapetype" {
      type_count += 1
      guard type_count == 1 &&
        shape_index > i &&
        attr(shape, "type") == "#" + attr(node, "id") else {
        raise Refused("OLE shape type identity mismatch")
      }
    }
    parents.push(name)
    for a in node.element.attributes {
      let ans = a.name.namespace_uri.unwrap_or("")
      let key = a.name.local_name
      let allowed = if i == begin {
        ans == word_ns && ["dxaOrig", "dyaOrig"].contains(key)
      } else if name == "shape" {
        (
          ans == "" &&
          ["id", "type", "style", "filled", "stroked"].contains(key)
        ) ||
        (ans == word_office_ns && key == "ole")
      } else if name == "imagedata" {
        (ans == office_rel[0:office_rel.length() - 1].to_owned() && key == "id") ||
        (ans == word_office_ns && key == "title")
      } else if name == "OLEObject" {
        (
          ans == "" &&
          ["Type", "ProgID", "ShapeID", "DrawAspect", "ObjectID"].contains(key)
        ) ||
        (ans == office_rel[0:office_rel.length() - 1].to_owned() && key == "id")
      } else if name == "shapetype" {
        (
          ans == "" &&
          ["id", "coordsize", "path", "filled", "stroked"].contains(key)
        ) ||
        (ans == word_office_ns && ["spt", "preferrelative"].contains(key))
      } else if name == "stroke" {
        ans == "" && key == "joinstyle"
      } else if name == "f" {
        ans == "" && key == "eqn"
      } else if name == "path" {
        (ans == "" && key == "gradientshapeok") ||
        (ans == word_office_ns && ["extrusionok", "connecttype"].contains(key))
      } else if name == "lock" {
        (ans == vml_ns && key == "ext" && a.value == "edit") ||
        (ans == "" && key == "aspectratio")
      } else {
        false
      }
      guard allowed else { raise Refused("unsupported Word OLE attribute") }
    }
  }
  if attr_opt(shape, "type") is Some(_) {
    guard type_count == 1 else {
      raise Refused("OLE shape-type definition must belong to the same object")
    }
  }
  indices
}

///|
fn ole_groups(nodes : Array[Node]) -> Array[Array[Int]] raise {
  let starts : Array[Int] = []
  for i, node in nodes {
    if node.element.name.namespace_uri == Some(word_ns) &&
      node.element.name.local_name == "object" {
      starts.push(i)
      guard starts.length() <= 32 else {
        raise Refused(
          "at most 32 independent inline Word OLE objects supported",
        )
      }
    }
  }
  let groups : Array[Array[Int]] = []
  let relations : Map[String, Bool] = Map([])
  let identities : Map[String, Bool] = Map([])
  let object_ids : Map[String, Bool] = Map([])
  let mut previous_end = -1
  for begin in starts {
    guard begin > previous_end else {
      raise Refused("nested Word OLE objects unsupported")
    }
    let group = ole_group(nodes, begin)
    previous_end = group[group.length() - 1]
    for (ns, name) in [(word_office_ns, "OLEObject"), (vml_ns, "imagedata")] {
      let id = relationship_attribute(nodes[ole_member(nodes, group, ns, name)])
      guard id != "" && !relations.contains(id) else {
        raise Refused("OLE objects must not share relationship identities")
      }
      relations[id] = true
    }
    for i in group {
      let node = nodes[i]
      if node.element.name.namespace_uri == Some(vml_ns) &&
        ["shape", "shapetype"].contains(node.element.name.local_name) {
        let id = attr(node, "id")
        guard id != "" && !identities.contains(id) else {
          raise Refused("duplicate OLE shape or shape-type identity")
        }
        identities[id] = true
      }
    }
    let ole = nodes[ole_member(nodes, group, word_office_ns, "OLEObject")]
    if attr_opt(ole, "ObjectID") is Some(id) {
      guard valid_ole_object_id(id) && !object_ids.contains(id) else {
        raise Refused("duplicate OLE ObjectID")
      }
      object_ids[id] = true
    }
    groups.push(group)
  }
  groups
}

///|
fn valid_ole_object_id(id : String) -> Bool {
  if !id.has_prefix("_") || id.length() < 2 || id.length() > 11 {
    return false
  }
  if id.length() == 11 && id[1] == '0' {
    return false
  }
  let mut value = 0
  for i in 1..<id.length() {
    let c = id[i]
    if c < '0' || c > '9' {
      return false
    }
    let digit = c.to_int() - 48
    if value > (2147483647 - digit) / 10 {
      return false
    }
    value = value * 10 + digit
  }
  true
}

///|
fn ole_catalog(
  parts : Array[PartRecord],
  nodes : Map[String, Array[Node]],
) -> Map[String, Map[String, Array[Int]]] {
  let catalog : Map[String, Map[String, Array[Int]]] = Map([])
  for part in parts {
    if ![docx_ct, docm_ct].contains(part.content_type) {
      continue
    }
    if nodes.get(part.name) is Some(items) {
      let groups = ole_groups(items) catch { _ => [] }
      let ids : Map[String, Array[Int]] = Map([])
      for group in groups {
        let id = relationship_attribute(
          items[ole_member(items, group, word_office_ns, "OLEObject")],
        ) catch {
          _ => abort("validated OLE identity")
        }
        ids[id] = group
      }
      catalog[part.name] = ids
    }
  }
  catalog
}

///|
fn ole_catalog_mask(
  catalog : Map[String, Map[String, Array[Int]]],
  source : String,
) -> Array[Int] {
  let indices : Array[Int] = []
  if catalog.get(source) is Some(groups) {
    for group in groups.values() {
      for i in group {
        indices.push(i)
      }
    }
  }
  indices
}

///|
fn ole_declared(
  r : Relationship,
  catalog : Map[String, Map[String, Array[Int]]],
) -> Bool {
  !r.external &&
  r.kind == office_rel + "oleObject" &&
  catalog.get(r.source).map(fn(ids) { ids.contains(r.id) }).unwrap_or(false)
}

///|
fn ole_relationships(pkg : Package) -> Array[Relationship] {
  pkg.audit.relationships.filter(fn(r) {
    ole_declared(r, pkg.graph.ole_objects)
  })
}

///|
fn ole_preview(pkg : Package, r : Relationship) -> Relationship {
  let nodes = pkg.xml_nodes[r.source]
  let indices = pkg.graph.ole_objects[r.source][r.id]
  let id = relationship_attribute(
    nodes[ole_member(nodes, indices, vml_ns, "imagedata")],
  ) catch {
    _ => abort("validated OLE preview")
  }
  graph_relationship(pkg.graph, r.source, id).unwrap()
}

///|
fn validate_ole(pkg : Package, r : Relationship) -> Unit raise {
  let nodes = pkg.xml_nodes[r.source]
  guard pkg.graph.ole_objects.get(r.source) is Some(groups) &&
    groups.get(r.id) is Some(indices) else {
    raise Refused("OLE relationship has no validated group")
  }
  guard r.source == pkg.audit.main_part &&
    ole_declared(r, pkg.graph.ole_objects) &&
    ole_payload_type(
      pkg.audit.parts[pkg.graph.part_index[r.resolved]].content_type,
    ) else {
    raise Refused("only main-document embedded Word OLE objects supported")
  }
  guard get_part(pkg.archive, r.resolved).has_prefix(
    b"\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1",
  ) else {
    raise Invalid("embedded OLE payload is not a CFB container")
  }
  let preview_id = relationship_attribute(
    nodes[ole_member(nodes, indices, vml_ns, "imagedata")],
  )
  guard graph_relationship(pkg.graph, r.source, preview_id) is Some(preview) &&
    !preview.external &&
    preview.kind == office_rel + "image" else {
    raise Invalid("OLE preview must use a local image relationship")
  }
  let image_type = pkg.audit.parts[pkg.graph.part_index[preview.resolved]].content_type
  guard ["image/png", "image/jpeg", "image/x-emf"].contains(image_type) else {
    raise Refused("OLE preview must be PNG, JPEG or removable EMF")
  }
  let bytes = get_part(pkg.archive, preview.resolved)
  guard (
      image_type == "image/png" && bytes.has_prefix(b"\x89PNG\x0d\x0a\x1a\x0a")
    ) ||
    (image_type == "image/jpeg" && bytes.has_prefix(b"\xff\xd8\xff")) ||
    (
      image_type == "image/x-emf" &&
      bytes.length() >= 88 &&
      bytes.has_prefix(b"\x01\x00\x00\x00") &&
      bytes[40:44] == b" EMF"[:]
    ) else {
    raise Invalid("OLE preview signature/content type mismatch")
  }
  for
    (relation, ordinal) in [
      (r, ole_member(nodes, indices, word_office_ns, "OLEObject")),
      (preview, ole_member(nodes, indices, vml_ns, "imagedata")),
    ] {
    let owners = graph_incoming(pkg.graph, relation.resolved)
    guard owners.length() == 1 &&
      owners[0] == relation &&
      pkg.archive.get(relationship_part(relation.resolved)[:]) is None else {
      raise Refused(
        "shared OLE/preview or nested dependencies cannot be removed",
      )
    }
    let references = pkg.graph.graph.xml_references.filter(fn(reference) {
      pkg.audit.relationships[reference.relationship_index].resolved ==
      relation.resolved
    })
    guard references.length() == 1 &&
      references[0].source == r.source &&
      references[0].element_index == ordinal else {
      raise Refused("OLE/preview has a retained or shared XML reference")
    }
  }
}

///|
fn controlled_parts(pkg : Package) -> Array[String] {
  let parts = controlled_vba_parts(pkg)
  for r in ole_relationships(pkg) {
    parts.push(r.resolved)
    parts.push(ole_preview(pkg, r).resolved)
  }
  parts.sort()
  parts
}

///|
fn ole_reference_removed(pkg : Package, reference : XmlReference) -> Bool {
  ole_relationships(pkg).any(fn(r) {
    reference.source == r.source &&
    ole_catalog_mask(pkg.graph.ole_objects, r.source).contains(
      reference.element_index,
    )
  })
}

///|
fn removed_relationship(pkg : Package, r : Relationship) -> Bool {
  r.kind == vba_rel ||
  is_template_relationship(r) ||
  ole_relationships(pkg).any(fn(ole) { r == ole || r == ole_preview(pkg, ole) })
}

///|
fn source_rewritten(pkg : Package, part : String) -> Bool {
  template_rewritten(pkg, part) ||
  ole_relationships(pkg).any(fn(r) { r.source == part })
}

///|
fn write_source(pkg : Package, part : String) -> Bytes raise {
  if template_rewritten(pkg, part) {
    return write_template_settings(pkg, part)
  }
  guard ole_relationships(pkg).any(fn(r) { r.source == part }) else {
    raise Refused("no accepted source XML handler")
  }
  let text = @utf8.decode(get_part(pkg.archive, part))
  let raw = @xml.Reader::from_string(text)
  let semantic = @xml.NamespaceReader::from_string(text)
  let writer = @xml.Writer::new()
  let mut skipped = 0
  let mut removed = 0
  while true {
    pkg.control.checkpoint("source-xml-write", 1)
    let event = raw.read_event()
    let meaning = semantic.read_event()
    let omit = match meaning.kind {
      Start(e) =>
        if skipped > 0 {
          skipped += 1
          true
        } else if e.name.namespace_uri == Some(word_ns) &&
          e.name.local_name == "object" {
          skipped = 1
          removed += 1
          true
        } else {
          false
        }
      End(_) =>
        if skipped > 0 {
          skipped -= 1
          true
        } else {
          false
        }
      Empty(e) =>
        if skipped > 0 {
          true
        } else if e.name.namespace_uri == Some(word_ns) &&
          e.name.local_name == "object" {
          raise Invalid("empty OLE object")
        } else {
          false
        }
      Eof => break
      _ => skipped > 0
    }
    if !omit {
      writer.write_event(event)
    }
  }
  guard removed ==
    ole_relationships(pkg).filter(fn(r) { r.source == part }).length() &&
    skipped == 0 else {
    raise Invalid(
      "OLE source rewrite did not remove exactly the validated object set",
    )
  }
  @utf8.encode(writer.to_string()[:])
}

///|
fn verify_source_semantics(
  before : Package,
  after : Package,
  part : String,
) -> Unit raise {
  if template_rewritten(before, part) {
    verify_template_semantics(before, after, part)
    return
  }
  let indices = ole_catalog_mask(before.graph.ole_objects, part)
  let original : Array[Node] = []
  for i, n in before.xml_nodes[part] {
    if !indices.contains(i) {
      original.push(n)
    }
  }
  let actual = after.xml_nodes[part]
  guard original.length() == actual.length() else {
    raise Invalid("OLE removal changed unrelated XML structure")
  }
  for i, node in original {
    before.control.checkpoint("source-semantics", 1)
    let left = node.element
    let right = actual[i].element
    before.control.pairs(
      "source-attribute-comparison",
      left.attributes.length(),
      right.attributes.length(),
    )
    guard node.depth == actual[i].depth &&
      left.name.namespace_uri == right.name.namespace_uri &&
      left.name.local_name == right.name.local_name &&
      left.attributes.length() == right.attributes.length() &&
      left.attributes.all(fn(a) {
        right.attributes.any(fn(b) {
          a.name.namespace_uri == b.name.namespace_uri &&
          a.name.local_name == b.name.local_name &&
          a.value == b.value
        })
      }) &&
      node.text_fragments.join("") == actual[i].text_fragments.join("") else {
      raise Invalid("OLE removal changed unrelated Word semantics")
    }
  }
  guard ole_relationships(after).length() == 0 else {
    raise Invalid("OLE object retained")
  }
}

///|
fn ole_member(
  nodes : Array[Node],
  indices : Array[Int],
  ns : String,
  name : String,
) -> Int raise {
  let matches = indices.filter(fn(i) {
    nodes[i].element.name.namespace_uri == Some(ns) &&
    nodes[i].element.name.local_name == name
  })
  guard matches.length() == 1 else {
    raise Refused("OLE object requires one " + name)
  }
  matches[0]
}

///|
fn ole_payload_type(ct : String) -> Bool {
  [ole_content_type, "application/vnd.ms-excel", "application/msword"].contains(
    ct,
  )
}

///|
fn validate_ole_source(pkg : Package) -> Unit raise {
  let groups = pkg.graph.ole_objects.get(pkg.audit.main_part).unwrap_or(Map([]))
  if groups.length() == 0 {
    return
  }
  guard pkg.xml_nodes.get(pkg.audit.main_part) is Some(nodes) else {
    raise Refused("Word XML payload name unsupported")
  }
  for group in groups.values() {
    pkg.control.checkpoint("ole-object", group.length())
    let id = relationship_attribute(
      nodes[ole_member(nodes, group, word_office_ns, "OLEObject")],
    )
    guard graph_relationship(pkg.graph, pkg.audit.main_part, id) is Some(r) &&
      !r.external &&
      r.kind == office_rel + "oleObject" else {
      raise Refused(
        "every inline OLE object must bind its own embedded OLE relationship",
      )
    }
    validate_ole(pkg, r)
  }
}
