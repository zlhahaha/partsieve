///|
fn is_template_relationship(r : Relationship) -> Bool {
  r.external && r.kind == office_rel + "attachedTemplate"
}

///|
fn validate_template_relationship(
  pkg : Package,
  r : Relationship,
) -> Unit raise {
  guard is_template_relationship(r) &&
    (r.target.has_prefix("https://") || r.target.has_prefix("http://")) &&
    pkg.graph.part_index.get(r.source) is Some(i) &&
    pkg.audit.parts[i].content_type ==
    "application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml" else {
    raise Refused(
      "only settings-local HTTP(S) attached templates can be removed",
    )
  }
  let references = pkg.graph.graph.xml_references.filter(fn(reference) {
    reference.source == r.source && reference.relationship_id == r.id
  })
  guard references.length() == 1 &&
    references[0].element_namespace == word_ns &&
    references[0].element_name == "attachedTemplate" &&
    references[0].depth == 1 else {
    raise Invalid(
      "external template must have exactly one settings-local reference",
    )
  }
}

///|
fn is_template_element(element : @xml.NamespaceElement) -> Bool {
  element.name.namespace_uri == Some(word_ns) &&
  element.name.local_name == "attachedTemplate"
}

///|
// Namespace-aware selection, raw event writing: preserve all other settings,
// text, comments and namespace declarations. No network dereference occurs.
fn write_template_settings(pkg : Package, part : String) -> Bytes raise {
  let text = @utf8.decode(get_part(pkg.archive, part))
  let raw = @xml.Reader::from_string(text)
  let semantic = @xml.NamespaceReader::from_string(text)
  let writer = @xml.Writer::new()
  let mut skipped = 0
  let mut removed = 0
  while true {
    let event = raw.read_event()
    let meaning = semantic.read_event()
    let omit = match meaning.kind {
      Start(element) =>
        if skipped > 0 {
          skipped += 1
          true
        } else if is_template_element(element) {
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
      Empty(element) =>
        if skipped > 0 {
          true
        } else if is_template_element(element) {
          removed += 1
          true
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
  guard removed == 1 && skipped == 0 else {
    raise Invalid(
      "template rewrite did not remove exactly one validated element",
    )
  }
  @utf8.encode(writer.to_string()[:])
}

///|
fn template_rewritten(pkg : Package, part : String) -> Bool {
  pkg.audit.relationships.any(fn(r) {
    r.source == part && is_template_relationship(r)
  })
}

///|
fn verify_template_semantics(
  before : Package,
  after : Package,
  part : String,
) -> Unit raise {
  let original = before.xml_nodes[part].filter(fn(node) {
    !is_template_element(node.element)
  })
  let actual = after.xml_nodes[part]
  guard original.length() == actual.length() else {
    raise Invalid("template rewrite changed unrelated settings structure")
  }
  for i, node in original {
    let left = node.element
    let right = actual[i].element
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
      node.text_fragments == actual[i].text_fragments else {
      raise Invalid("template rewrite changed unrelated settings semantics")
    }
  }
  guard !after.audit.relationships.any(is_template_relationship) else {
    raise Invalid("external attached template retained")
  }
}
