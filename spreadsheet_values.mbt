///|
// Bounded decimal indices. Never coerce booleans, signs or floating values.
fn checked_index(text : String, exclusive : Int) -> Int raise {
  guard text.length() > 0 && text.length() <= 10 else {
    raise Invalid("missing/oversized spreadsheet index")
  }
  let mut value = 0
  for c in text.code_units() {
    guard c >= '0' && c <= '9' && value <= 200000000 else {
      raise Invalid("invalid spreadsheet index")
    }
    value = value * 10 + c.to_int() - 48
  }
  guard value < exclusive else {
    raise Invalid("spreadsheet index out of range")
  }
  value
}

///|
fn validate_spreadsheet_values(pkg : Package) -> Unit raise {
  for kind in ["styles", "sharedStrings", "theme"] {
    guard pkg.audit.relationships
      .filter(fn(r) { r.kind == office_rel + kind })
      .length() <=
      1 else {
      raise Invalid("ambiguous spreadsheet supporting table")
    }
  }
  let mut strings = 0
  let mut styles = 0
  let worksheets : Map[String, Bool] = Map([])
  for relation in pkg.audit.relationships {
    if relation.kind == office_rel + "worksheet" {
      guard !worksheets.contains(relation.resolved) else {
        raise Invalid("multiple sheets cannot reuse one worksheet target")
      }
      worksheets[relation.resolved] = true
    } else if relation.kind == office_rel + "sharedStrings" {
      strings = pkg.xml_nodes[relation.resolved]
        .filter(fn(n) { n.depth == 1 && n.element.name.local_name == "si" })
        .length()
    } else if relation.kind == office_rel + "styles" {
      let mut inside = false
      for node in pkg.xml_nodes[relation.resolved] {
        pkg.control.checkpoint("spreadsheet-value", 1)
        if node.depth == 1 {
          inside = node.element.name.local_name == "cellXfs"
        } else if inside &&
          node.depth == 2 &&
          node.element.name.local_name == "xf" {
          styles += 1
        }
      }
    }
  }
  for relation in pkg.audit.relationships {
    if relation.kind != office_rel + "worksheet" {
      continue
    }
    let mut cell_type = "n"
    for node in pkg.xml_nodes[relation.resolved] {
      pkg.control.checkpoint("spreadsheet-value", 1)
      let name = node.element.name.local_name
      if name == "c" {
        cell_type = attr_opt(node, "t").unwrap_or("n")
        guard ["n", "s", "inlineStr", "b"].contains(cell_type) else {
          raise Refused("unsupported cell value type")
        }
        if attr_opt(node, "s") is Some(index) {
          ignore(checked_index(index, styles))
        }
      } else if name == "v" {
        let value = node.text_fragments.join("")
        if cell_type == "s" {
          ignore(checked_index(value, strings))
        } else if cell_type == "b" {
          guard value == "0" || value == "1" else {
            raise Invalid("invalid boolean cell value")
          }
        } else if cell_type == "inlineStr" {
          raise Invalid("inline string has a numeric value child")
        }
      } else if name == "is" && cell_type != "inlineStr" {
        raise Invalid("inline string/cell type mismatch")
      }
    }
  }
}
