///|
let mc_ns = "http://schemas.openxmlformats.org/markup-compatibility/2006"

///|
let word14_ns = "http://schemas.microsoft.com/office/word/2010/wordml"

///|
let word15_ns = "http://schemas.microsoft.com/office/word/2012/wordml"

///|
let theme15_ns = "http://schemas.microsoft.com/office/thememl/2012/main"

///|
fn valid_guid(value : String) -> Bool {
  if value.length() != 38 || value[0] != '{' || value[37] != '}' {
    return false
  }
  for i in 1..<37 {
    let c = value[i]
    if [9, 14, 19, 24].contains(i) {
      if c != '-' {
        return false
      }
    } else if !((c >= '0' && c <= '9') ||
      (c >= 'A' && c <= 'F') ||
      (c >= 'a' && c <= 'f')) {
      return false
    }
  }
  true
}

///|
fn empty_node(node : Node) -> Bool {
  node.text_fragments.all(fn(t) { t.trim() == "" })
}

///|
fn hex_text(value : String, length : Int32) -> Bool {
  value.length() == length &&
  value
  .code_units()
  .all(fn(c) {
    (c >= '0' && c <= '9') || (c >= 'A' && c <= 'F') || (c >= 'a' && c <= 'f')
  })
}

///|
fn exact_node_attributes(
  node : Node,
  ns : String?,
  names : Array[String],
) -> Bool {
  node.element.attributes.all(fn(a) {
    a.name.namespace_uri == ns && names.contains(a.name.local_name)
  })
}

///|
fn word_ignorable_attribute(node : Node, a : @xml.NamespaceAttribute) -> Bool {
  if a.name.namespace_uri != Some(mc_ns) ||
    a.name.local_name != "Ignorable" ||
    node.depth != 0 ||
    node.element.name.namespace_uri != Some(word_ns) ||
    a.value.length() > 256 {
    return false
  }
  let prefixes = a.value.split(" ").filter(fn(p) { p != "" }).collect()
  prefixes.length() > 0 &&
  prefixes.length() <= 16 &&
  prefixes.all(fn(prefix) {
    node.element.namespace_declarations.any(fn(d) {
      d.prefix == Some(prefix.to_owned()) &&
      [
        word14_ns, word15_ns, "http://schemas.microsoft.com/office/word/2010/wordprocessingDrawing",
      ].contains(d.namespace_uri)
    })
  })
}

///|
fn word_modern_attribute(
  part : PartRecord,
  node : Node,
  a : @xml.NamespaceAttribute,
) -> Bool {
  word_ignorable_attribute(node, a) ||
  (
    part.content_type ==
    "application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml" &&
    node.element.name.namespace_uri == Some(word_ns) &&
    node.element.name.local_name == "abstractNum" &&
    node.depth == 1 &&
    a.name.namespace_uri == Some(word15_ns) &&
    a.name.local_name == "restartNumberingAfterBreak" &&
    ["0", "1", "true", "false", "on", "off"].contains(a.value)
  )
}

///|
fn namespace_at(
  nodes : Array[Node],
  index : Int32,
  prefix : String,
  control : WorkControl,
) -> String? raise {
  let mut depth = nodes[index].depth + 1
  let mut j = index
  while j >= 0 {
    control.checkpoint("word-namespace-binding", 1)
    if nodes[j].depth < depth {
      for d in nodes[j].element.namespace_declarations {
        if d.prefix == Some(prefix) {
          return Some(d.namespace_uri)
        }
      }
      depth = nodes[j].depth
    }
    j -= 1
  }
  None
}

///|
// A catalog of fully checked passive extensions. It never selects a branch:
// both alternatives are validated, and every original byte is retained.
fn word_modern_catalog(
  part : PartRecord,
  nodes : Array[Node],
  control : WorkControl,
) -> Map[Int32, Bool] raise {
  let allowed : Map[Int32, Bool] = Map([])
  if ![
      "application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml",
      "application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml",
      "application/vnd.openxmlformats-officedocument.theme+xml",
    ].contains(part.content_type) {
    return allowed
  }
  for i, node in nodes {
    control.checkpoint(
      "word-modern-catalog",
      1 + node.element.attributes.length(),
    )
    if allowed.contains(i) {
      continue
    }
    let ns = node.element.name.namespace_uri.unwrap_or("")
    let name = node.element.name.local_name
    if ns == word_ns &&
      name == "stylePaneFormatFilter" &&
      node.depth == 1 &&
      part.content_type ==
      "application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml" {
      let flags = [
        "allStyles", "customStyles", "latentStyles", "stylesInUse", "headingStyles",
        "numberingStyles", "tableStyles", "directFormattingOnRuns", "directFormattingOnParagraphs",
        "directFormattingOnNumbering", "directFormattingOnTables", "clearFormatting",
        "top3HeadingStyles", "visibleStyles", "alternateStyleNames",
      ]
      guard empty_node(node) &&
        (i + 1 == nodes.length() || nodes[i + 1].depth <= node.depth) &&
        node.element.attributes.all(fn(a) {
          a.name.namespace_uri == Some(word_ns) &&
          (if a.name.local_name == "val" {
            hex_text(a.value, 4)
          } else {
            flags.contains(a.name.local_name) &&
            ["0", "1", "true", "false", "on", "off"].contains(a.value)
          })
        }) else {
        raise Refused("unsupported style pane display filter")
      }
      allowed[i] = true
    } else if ns == word15_ns &&
      part.content_type ==
      "application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml" &&
      node.depth == 1 &&
      ["docId", "chartTrackingRefBased"].contains(name) {
      guard (i + 1 == nodes.length() || nodes[i + 1].depth <= node.depth) &&
        empty_node(node) else {
        raise Refused("modern settings metadata must be a leaf")
      }
      if name == "docId" {
        guard exact_node_attributes(node, Some(word15_ns), ["val"]) &&
          node.element.attributes.length() == 1 &&
          valid_guid(node.element.attributes[0].value) else {
          raise Invalid("invalid modern document GUID")
        }
      } else {
        guard exact_node_attributes(node, Some(word_ns), ["val"]) &&
          node.element.attributes.length() <= 1 &&
          node.element.attributes.all(fn(a) {
            ["0", "1", "true", "false", "on", "off"].contains(a.value)
          }) else {
          raise Refused("invalid chart tracking flag")
        }
      }
      allowed[i] = true
    } else if ns == mc_ns &&
      name == "AlternateContent" &&
      part.content_type ==
      "application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml" {
      let mut j = i - 1
      while j >= 0 && nodes[j].depth >= node.depth {
        control.checkpoint("word-alternate-parent", 1)
        j -= 1
      }
      guard j >= 0 &&
        nodes[j].depth == node.depth - 1 &&
        nodes[j].element.name.namespace_uri == Some(word_ns) &&
        nodes[j].element.name.local_name == "lvl" else {
        raise Refused("alternate numbering content has unsupported parent")
      }
      let mut sibling = j + 1
      while sibling < nodes.length() && nodes[sibling].depth > nodes[j].depth {
        control.checkpoint("word-alternate-sibling", 1)
        let other = nodes[sibling]
        guard sibling == i ||
          other.depth != node.depth ||
          !["numFmt", "AlternateContent"].contains(
            other.element.name.local_name,
          ) else {
          raise Invalid("ambiguous numbering format alternatives")
        }
        sibling += 1
      }
      guard i + 4 < nodes.length() &&
        (i + 5 == nodes.length() || nodes[i + 5].depth <= node.depth) else {
        raise Refused("unsupported alternate numbering shape")
      }
      let choice = nodes[i + 1]
      let primary = nodes[i + 2]
      let fallback = nodes[i + 3]
      let secondary = nodes[i + 4]
      guard node.element.attributes.length() == 0 &&
        empty_node(node) &&
        choice.depth == node.depth + 1 &&
        choice.element.name.namespace_uri == Some(mc_ns) &&
        choice.element.name.local_name == "Choice" &&
        exact_node_attributes(choice, None, ["Requires"]) &&
        choice.element.attributes.length() == 1 &&
        empty_node(choice) &&
        namespace_at(nodes, i + 1, attr(choice, "Requires"), control) ==
        Some(word14_ns) &&
        fallback.depth == node.depth + 1 &&
        fallback.element.name.namespace_uri == Some(mc_ns) &&
        fallback.element.name.local_name == "Fallback" &&
        fallback.element.attributes.length() == 0 &&
        empty_node(fallback) else {
        raise Refused("unsupported alternate numbering branches")
      }
      for pair in [(primary, true), (secondary, false)] {
        let (format, modern) = pair
        guard format.depth == node.depth + 2 &&
          format.element.name.namespace_uri == Some(word_ns) &&
          format.element.name.local_name == "numFmt" &&
          empty_node(format) &&
          exact_node_attributes(
            format,
            Some(word_ns),
            if modern {
              ["val", "format"]
            } else {
              ["val"]
            },
          ) else {
          raise Refused("unsupported alternate numbering payload")
        }
        if modern {
          let pattern = word_attr(format, "format")
          guard word_attr(format, "val") == "custom" &&
            pattern.length() > 0 &&
            pattern.length() <= 512 &&
            pattern.code_units().all(fn(c) { c >= 32 && c != 127 }) else {
            raise Refused("unsupported custom numbering format")
          }
        } else {
          guard word_attr(format, "val") == "decimal" else {
            raise Refused("unsupported numbering fallback")
          }
        }
      }
      for offset in 0..<5 {
        allowed[i + offset] = true
      }
    } else if ns == drawing_ns &&
      name == "extLst" &&
      node.depth == 1 &&
      part.content_type ==
      "application/vnd.openxmlformats-officedocument.theme+xml" {
      guard i + 2 < nodes.length() &&
        (i + 3 == nodes.length() || nodes[i + 3].depth <= node.depth) &&
        node.element.attributes.length() == 0 &&
        empty_node(node) else {
        raise Refused("unsupported theme extension list")
      }
      let ext = nodes[i + 1]
      let family = nodes[i + 2]
      guard ext.depth == 2 &&
        ext.element.name.namespace_uri == Some(drawing_ns) &&
        ext.element.name.local_name == "ext" &&
        exact_node_attributes(ext, None, ["uri"]) &&
        ext.element.attributes.length() == 1 &&
        attr(ext, "uri") == "{05A4C25C-085E-4340-85A3-A5531E510DB2}" &&
        empty_node(ext) &&
        family.depth == 3 &&
        family.element.name.namespace_uri == Some(theme15_ns) &&
        family.element.name.local_name == "themeFamily" &&
        exact_node_attributes(family, None, ["name", "id", "vid"]) &&
        family.element.attributes.length() == 3 &&
        valid_guid(attr(family, "id")) &&
        valid_guid(attr(family, "vid")) &&
        attr(family, "name").length() <= 256 &&
        empty_node(family) else {
        raise Refused("unsupported theme family metadata")
      }
      for offset in 0..<3 {
        allowed[i + offset] = true
      }
    }
  }
  allowed
}
