///|
fn hyperlink_source(parts : Array[PartRecord], source : String) -> Bool {
  parts.any(fn(p) {
    p.name == source &&
    [
      docx_ct, docm_ct, "application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml",
      "application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml",
      "application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml",
    ].contains(p.content_type)
  })
}

///|
fn hyperlink_node(node : Node) -> Bool {
  node.element.name.local_name == "hyperlink" &&
  [Some(word_ns), Some(spreadsheet_ns)].contains(
    node.element.name.namespace_uri,
  )
}

///|
fn hyperlink_declared(
  r : Relationship,
  parts : Array[PartRecord],
  nodes : Map[String, Array[Node]],
) -> Bool {
  r.external &&
  r.kind == office_rel + "hyperlink" &&
  hyperlink_source(parts, r.source) &&
  nodes
  .get(r.source)
  .unwrap_or([])
  .any(fn(n) {
    hyperlink_node(n) &&
    n.element.attributes.any(fn(a) {
      a.name.namespace_uri ==
      Some(office_rel[0:office_rel.length() - 1].to_owned()) &&
      a.name.local_name == "id" &&
      a.value == r.id
    })
  })
}

///|
// URI classification only. Never resolve DNS, fetch, follow redirects or normalize the saved target.
fn valid_click_url(target : String) -> Bool {
  let uri = target.to_lower()
  let start = if uri.has_prefix("https://") {
    8
  } else if uri.has_prefix("http://") {
    7
  } else {
    return false
  }
  if target.length() > 8192 || target.length() <= start {
    return false
  }
  if target.code_units().any(fn(c) { c <= 32 || c == 127 || c == '\\' }) {
    return false
  }
  let mut end = start
  while end < target.length() && ![47, 63, 35].contains(target[end].to_int()) {
    end += 1
  }
  let authority = target[start:end].to_owned()
  // Deliberately narrow ASCII DNS / IPv4 authority, optional decimal port. No credentials or IPv6 literals.
  if authority == "" || authority.contains("@") {
    return false
  }
  let fields = authority.split(":").collect()
  if fields.length() > 2 {
    return false
  }
  let host = fields[0]
  if host.length() > 253 || host.has_prefix(".") || host.has_suffix(".") {
    return false
  }
  for label in host.split(".") {
    if label.length() == 0 ||
      label.length() > 63 ||
      label.has_prefix("-") ||
      label.has_suffix("-") {
      return false
    }
    if label
      .code_units()
      .any(fn(c) {
        !((c >= 'a' && c <= 'z') ||
        (c >= 'A' && c <= 'Z') ||
        (c >= '0' && c <= '9') ||
        c == '-')
      }) {
      return false
    }
  }
  if fields.length() == 2 {
    let port = fields[1]
    if port.length() == 0 || port.length() > 5 {
      return false
    }
    let mut number = 0
    for c in port.code_units() {
      if c < '0' || c > '9' {
        return false
      }
      number = number * 10 + c.to_int() - 48
    }
    if number == 0 || number > 65535 {
      return false
    }
  }
  true
}

///|
fn validate_hyperlink(pkg : Package, r : Relationship) -> Unit raise {
  guard hyperlink_declared(r, pkg.audit.parts, pkg.xml_nodes) &&
    valid_click_url(r.target) else {
    raise Refused(
      "only source-bound HTTP(S) click hyperlinks with supported authority are permitted",
    )
  }
  let references = pkg.graph.graph.xml_references.filter(fn(reference) {
    reference.source == r.source && reference.relationship_id == r.id
  })
  guard references.length() > 0 &&
    references.all(fn(reference) {
      reference.element_name == "hyperlink" &&
      reference.attribute_name == "id" &&
      [word_ns, spreadsheet_ns].contains(reference.element_namespace)
    }) else {
    raise Invalid("hyperlink relationship has a non-click XML reference")
  }
}

///|
fn extended_office(pkg : Package) -> Bool {
  pkg.audit.profile.has_suffix("-v2")
}

///|
fn click_cell(text : String) -> (Int, Int) raise {
  guard text.length() > 1 && text.length() <= 10 else {
    raise Invalid("invalid hyperlink cell reference")
  }
  let mut i = 0
  let mut col = 0
  while i < text.length() && text[i] >= 'A' && text[i] <= 'Z' {
    col = col * 26 + text[i].to_int() - 64
    i += 1
    guard i <= 3 else { raise Invalid("hyperlink column overflow") }
  }
  guard col > 0 && col <= 16384 && i < text.length() && text[i] != '0' else {
    raise Invalid("hyperlink reference outside grid")
  }
  let mut row = 0
  while i < text.length() {
    let c = text[i]
    guard c >= '0' && c <= '9' else { raise Invalid("invalid hyperlink row") }
    row = row * 10 + c.to_int() - 48
    i += 1
    guard row <= 1048576 else { raise Invalid("hyperlink row overflow") }
  }
  guard row > 0 else { raise Invalid("hyperlink row is zero") }
  (col, row)
}

///|
fn validate_click_range(text : String) -> Unit raise {
  let parts = text.split(":").collect()
  guard parts.length() == 1 || parts.length() == 2 else {
    raise Invalid("invalid hyperlink range")
  }
  let (c1, r1) = click_cell(parts[0].to_owned())
  if parts.length() == 2 {
    let (c2, r2) = click_cell(parts[1].to_owned())
    guard c1 <= c2 && r1 <= r2 else {
      raise Invalid("reversed hyperlink range")
    }
  }
}
