///|
fn validate_word_property_vectors(
  nodes : Array[Node],
  control : WorkControl,
) -> Unit raise {
  let vt = "http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes"
  for i, node in nodes {
    control.checkpoint(
      "word-property-vector",
      1 + node.element.attributes.length(),
    )
    let name = node.element.name.local_name
    if node.element.name.namespace_uri != Some(vt) {
      continue
    }
    guard node.element.attributes.all(fn(a) {
      name == "vector" &&
      a.name.namespace_uri is None &&
      ["size", "baseType"].contains(a.name.local_name)
    }) else {
      raise Refused("unsupported document property vector attribute")
    }
    if name == "vector" || name == "variant" {
      let base = if name == "vector" { attr(node, "baseType") } else { "" }
      guard name == "variant" || ["variant", "lpstr"].contains(base) else {
        raise Refused("unsupported document property vector type")
      }
      let mut count = 0
      let mut j = i + 1
      while j < nodes.length() && nodes[j].depth > node.depth {
        control.checkpoint("word-property-vector-child", 1)
        if nodes[j].depth == node.depth + 1 {
          count += 1
          let child = nodes[j]
          guard child.element.name.namespace_uri == Some(vt) &&
            (if name == "vector" {
              child.element.name.local_name == base
            } else {
              ["lpstr", "i4"].contains(child.element.name.local_name)
            }) else {
            raise Invalid("document property vector child/type mismatch")
          }
        }
        j += 1
      }
      guard node.text_fragments.all(fn(t) { t.trim() == "" }) &&
        (if name == "vector" {
          checked_index(attr(node, "size"), 2147483647) == count
        } else {
          count == 1
        }) else {
        raise Invalid("document property vector size mismatch")
      }
    }
  }
}

///|
fn word_attr_opt(node : Node, name : String) -> String? {
  for a in node.element.attributes {
    if a.name.namespace_uri == Some(word_ns) && a.name.local_name == name {
      return Some(a.value)
    }
  }
  None
}

///|
fn word_attr(node : Node, name : String) -> String raise {
  guard word_attr_opt(node, name) is Some(value) else {
    raise Invalid("required Word attribute missing: " + name)
  }
  value
}

///|
fn word_id(value : String, negative~ : Bool = false) -> String raise {
  if negative && value == "-1" {
    return "-1"
  }
  checked_index(value, 2147483647).to_string()
}

///|
fn word_extra_layout_element(name : String, parent : String) -> Bool {
  match name {
    "outlineLvl" | "contextualSpacing" | "tabs" | "pBdr" => parent == "pPr"
    "bCs" | "iCs" | "kern" | "rStyle" | "vertAlign" => parent == "rPr"
    "tab" => parent == "tabs"
    "numPr" => parent == "pPr"
    "numId" | "ilvl" => parent == "numPr"
    "top" | "left" | "bottom" | "right" | "between" | "bar" => parent == "pBdr"
    _ => false
  }
}

///|
fn word_numbering_element(node : Node, parent : String) -> Bool {
  if node.element.name.namespace_uri != Some(word_ns) {
    return false
  }
  match node.element.name.local_name {
    "numbering" => node.depth == 0
    "abstractNum" | "num" => parent == "numbering"
    "nsid" | "multiLevelType" | "tmpl" | "name" => parent == "abstractNum"
    "abstractNumId" | "lvlOverride" => parent == "num"
    "lvl" => parent == "abstractNum" || parent == "lvlOverride"
    "startOverride" => parent == "lvlOverride"
    "start"
    | "numFmt"
    | "lvlText"
    | "lvlJc"
    | "suff"
    | "lvlRestart"
    | "isLgl" => parent == "lvl"
    "pPr" | "rPr" => parent == "lvl"
    "ind" | "spacing" | "jc" => parent == "pPr"
    "rFonts" | "b" | "i" | "sz" | "color" => parent == "rPr"
    _ =>
      !["numPr", "numId", "ilvl"].contains(node.element.name.local_name) &&
      word_extra_layout_element(node.element.name.local_name, parent)
  }
}

///|
fn word_structure_attribute(name : String, attribute : String) -> Bool {
  match name {
    "footnote" | "endnote" => ["id", "type"].contains(attribute)
    "footnoteReference" | "endnoteReference" => attribute == "id"
    "abstractNum" => attribute == "abstractNumId"
    "num" => attribute == "numId"
    "lvl" => ["ilvl", "tplc", "tentative"].contains(attribute)
    "lvlOverride" => attribute == "ilvl"
    "tab" => ["pos", "leader"].contains(attribute)
    "bookmarkStart" | "bookmarkEnd" | "div" => attribute == "id"
    "pgSz" => attribute == "code"
    "compatSetting" => attribute == "uri"
    "ptab" => ["relativeTo", "alignment", "leader"].contains(attribute)
    _ => false
  }
}

///|
fn validate_word_structure_attributes(
  node : Node,
  parent : String,
  root : String,
) -> Unit raise {
  if node.element.name.namespace_uri != Some(word_ns) {
    return
  }
  let name = node.element.name.local_name
  let exact : Array[String]? = match name {
    "bookmarkStart" => Some(["id", "name"])
    "bookmarkEnd" => Some(["id"])
    "proofErr" => Some(["type"])
    "div" => Some(["id"])
    "divs" | "divBdr" => Some([])
    "bodyDiv" | "marLeft" | "marRight" | "marTop" | "marBottom" => Some(["val"])
    "ptab" => Some(["relativeTo", "alignment", "leader"])
    "removePersonalInformation"
    | "removeDateAndTime"
    | "doNotAutoCompressPictures"
    | "doNotDisplayPageBoundaries"
    | "doNotIncludeSubdocsInStats" => Some(["val"])
    "compatSetting" => Some(["name", "uri", "val"])
    "footnote" | "endnote" => Some(["id", "type"])
    "footnoteReference" | "endnoteReference" => Some(["id"])
    "footnoteRef" | "endnoteRef" | "separator" | "continuationSeparator" =>
      Some([])
    "numPr" => Some([])
    "numId" | "ilvl" | "abstractNumId" | "outlineLvl" => Some(["val"])
    "abstractNum" => Some(["abstractNumId"])
    "num" => Some(["numId"])
    "lvl" => Some(["ilvl", "tplc", "tentative"])
    "lvlOverride" => Some(["ilvl"])
    "start"
    | "startOverride"
    | "lvlRestart"
    | "numFmt"
    | "lvlText"
    | "lvlJc"
    | "suff"
    | "multiLevelType"
    | "nsid"
    | "tmpl"
    | "isLgl" => if root == "numbering" { Some(["val"]) } else { None }
    _ => None
  }
  if exact is Some(names) {
    guard node.element.attributes.all(fn(a) {
        (
          a.name.namespace_uri == Some(word_ns) &&
          names.contains(a.name.local_name)
        ) ||
        (
          root == "numbering" &&
          name == "abstractNum" &&
          node.depth == 1 &&
          a.name.namespace_uri == Some(word15_ns) &&
          a.name.local_name == "restartNumberingAfterBreak" &&
          ["0", "1", "true", "false", "on", "off"].contains(a.value)
        )
      }) &&
      node.text_fragments.all(fn(t) { t.trim() == "" }) else {
      raise Refused("unsupported Word structural attributes or text")
    }
  }
  if name == "div" {
    ignore(word_id(word_attr(node, "id")))
  }
  if name == "bodyDiv" {
    guard ["0", "1", "true", "false", "on", "off"].contains(
      word_attr(node, "val"),
    ) else {
      raise Invalid("invalid web layout flag")
    }
  }
  if ["marLeft", "marRight", "marTop", "marBottom"].contains(name) {
    ignore(checked_index(word_attr(node, "val"), 2147483647))
  }
  if name == "compatSetting" {
    let setting = word_attr(node, "name")
    let value = word_attr(node, "val")
    guard parent == "compat" &&
      word_attr(node, "uri") == "http://schemas.microsoft.com/office/word" &&
      (if setting == "compatibilityMode" {
        ["12", "14", "15", "16"].contains(value)
      } else {
        [
          "overrideTableStyleFontSizeAndJustification", "enableOpenTypeFeatures",
          "doNotFlipMirrorIndents", "differentiateMultirowTableHeaders",
        ].contains(setting) &&
        ["0", "1", "true", "false"].contains(value)
      }) else {
      raise Refused("unsupported Word compatibility setting")
    }
  }
  if [
      "removePersonalInformation", "removeDateAndTime", "doNotAutoCompressPictures",
      "doNotDisplayPageBoundaries", "doNotIncludeSubdocsInStats",
    ].contains(name) {
    guard parent == "settings" &&
      word_attr_opt(node, "val")
      .map(fn(v) { ["0", "1", "true", "false", "on", "off"].contains(v) })
      .unwrap_or(true) else {
      raise Refused("unsupported Word settings flag")
    }
  }
  if name == "ptab" {
    guard parent == "r" &&
      ["margin", "indent"].contains(word_attr(node, "relativeTo")) &&
      ["left", "center", "right"].contains(word_attr(node, "alignment")) &&
      ["none", "dot", "hyphen", "underscore", "middleDot"].contains(
        word_attr(node, "leader"),
      ) else {
      raise Refused("unsupported positional tab settings")
    }
  }
  if root == "numbering" &&
    ["start", "startOverride", "lvlRestart"].contains(name) {
    ignore(checked_index(word_attr(node, "val"), 2147483647))
  }
  if root == "numbering" && name == "numFmt" {
    guard [
      "decimal", "upperRoman", "lowerRoman", "upperLetter", "lowerLetter", "ordinal",
      "bullet", "none", "decimalZero",
    ].contains(word_attr(node, "val")) else {
      raise Refused("unsupported numbering format")
    }
  }
  if ["outlineLvl", "ilvl"].contains(name) {
    ignore(
      checked_index(
        word_attr(node, "val"),
        if name == "outlineLvl" {
          10
        } else {
          9
        },
      ),
    )
  }
  if name == "lvl" || name == "lvlOverride" {
    ignore(checked_index(word_attr(node, "ilvl"), 9))
  }
  if ["footnoteReference", "endnoteReference", "footnote", "endnote"].contains(
      name,
    ) {
    ignore(word_id(word_attr(node, "id"), negative=true))
    if word_attr_opt(node, "type") is Some(kind) {
      guard parent != "footnotePr" &&
        parent != "endnotePr" &&
        ["normal", "separator", "continuationSeparator", "continuationNotice"].contains(
          kind,
        ) else {
        raise Refused("unsupported note type")
      }
    }
  }
  if (name == "footnoteRef" && root != "footnotes") ||
    (name == "endnoteRef" && root != "endnotes") {
    raise Refused("note marker type does not match its owning part")
  }
}

///|
fn word_structure_part(pkg : Package, kind : String) -> String? raise {
  let content_type = "application/vnd.openxmlformats-officedocument.wordprocessingml." +
    kind +
    "+xml"
  let relations = pkg.audit.relationships.filter(fn(r) {
    r.kind == office_rel + kind
  })
  let parts = pkg.audit.parts.filter(fn(p) { p.content_type == content_type })
  guard relations.length() <= 1 && parts.length() == relations.length() else {
    raise Invalid("duplicate or unowned Word " + kind + " part")
  }
  if relations.length() == 0 {
    return None
  }
  let r = relations[0]
  guard !r.external &&
    r.source == pkg.audit.main_part &&
    r.resolved == parts[0].name &&
    graph_incoming(pkg.graph, r.resolved).length() == 1 else {
    raise Invalid("ambiguous Word structural part ownership")
  }
  Some(r.resolved)
}

///|
fn validate_word_notes(pkg : Package, kind : String) -> Unit raise {
  let singular = if kind == "footnotes" { "footnote" } else { "endnote" }
  let definitions : Map[String, String] = Map([])
  let special_types : Map[String, Bool] = Map([])
  if word_structure_part(pkg, kind) is Some(part) {
    let mut current_type = ""
    for node in pkg.xml_nodes[part] {
      pkg.control.checkpoint("word-note-definition", 1)
      if node.depth == 1 && node.element.name.local_name == singular {
        let id = word_id(word_attr(node, "id"), negative=true)
        let note_type = word_attr_opt(node, "type").unwrap_or("normal")
        guard !definitions.contains(id) && (id != "-1" || note_type != "normal") else {
          raise Invalid("duplicate or invalid note definition ID")
        }
        definitions[id] = note_type
        if note_type != "normal" {
          guard !special_types.contains(note_type) else {
            raise Invalid("duplicate note separator type")
          }
          special_types[note_type] = true
        }
        current_type = note_type
      } else if [
          "separator", "continuationSeparator", "footnoteRef", "endnoteRef",
        ].contains(node.element.name.local_name) {
        let marker = node.element.name.local_name
        guard (marker == "separator" && current_type == "separator") ||
          (
            marker == "continuationSeparator" &&
            current_type == "continuationSeparator"
          ) ||
          (marker == singular + "Ref" && current_type == "normal") else {
          raise Invalid("note marker and definition type mismatch")
        }
      }
    }
  }
  let referenced : Map[String, Bool] = Map([])
  let settings_references : Map[String, Bool] = Map([])
  for part in pkg.audit.parts {
    if pkg.xml_nodes.get(part.name) is Some(nodes) {
      for node in nodes {
        pkg.control.checkpoint("word-note-reference", 1)
        if node.element.name.namespace_uri != Some(word_ns) {
          continue
        }
        let name = node.element.name.local_name
        if name == singular + "Reference" {
          let id = word_id(word_attr(node, "id"), negative=true)
          guard part.name == pkg.audit.main_part &&
            definitions.get(id) == Some("normal") &&
            !referenced.contains(id) else {
            raise Invalid(
              "dangling duplicated or wrongly scoped note reference",
            )
          }
          referenced[id] = true
        } else if name == singular && part.content_type.contains(".settings+") {
          let id = word_id(word_attr(node, "id"), negative=true)
          guard definitions.get(id) is Some(note_type) && note_type != "normal" else {
            raise Invalid("settings note separator reference is not defined")
          }
          guard !settings_references.contains(id) else {
            raise Invalid("duplicate settings note separator reference")
          }
          settings_references[id] = true
        }
      }
    }
  }
  for id, kind in definitions {
    pkg.control.checkpoint("word-note-definition-binding", 1)
    guard kind != "normal" || referenced.contains(id) else {
      raise Invalid("unreferenced normal note definition")
    }
  }
}

///|
fn validate_word_numbering(pkg : Package) -> Unit raise {
  let abstracts : Map[String, Array[String]] = Map([])
  let instances : Map[String, String] = Map([])
  let overrides : Map[String, Array[String]] = Map([])
  let override_fields : Map[String, Bool] = Map([])
  if word_structure_part(pkg, "numbering") is Some(part) {
    let mut abstract_id = ""
    let mut num_id = ""
    let mut override_level = ""
    for node in pkg.xml_nodes[part] {
      pkg.control.checkpoint("word-numbering-definition", 1)
      let name = node.element.name.local_name
      if node.depth == 1 {
        abstract_id = ""
        num_id = ""
        override_level = ""
        if name == "abstractNum" {
          abstract_id = word_id(word_attr(node, "abstractNumId"))
          guard !abstracts.contains(abstract_id) else {
            raise Invalid("duplicate abstract numbering ID")
          }
          abstracts[abstract_id] = []
        } else if name == "num" {
          num_id = word_id(word_attr(node, "numId"))
          guard num_id != "0" && !instances.contains(num_id) else {
            raise Invalid("duplicate or reserved numbering ID")
          }
          instances[num_id] = ""
          overrides[num_id] = []
        }
      } else if node.depth == 2 && abstract_id != "" && name == "lvl" {
        let level = checked_index(word_attr(node, "ilvl"), 9).to_string()
        guard !abstracts[abstract_id].contains(level) else {
          raise Invalid("duplicate abstract numbering level")
        }
        abstracts[abstract_id].push(level)
      } else if node.depth == 2 && num_id != "" && name == "abstractNumId" {
        guard instances[num_id] == "" else {
          raise Invalid("multiple abstract numbering references")
        }
        instances[num_id] = word_id(word_attr(node, "val"))
      } else if node.depth == 2 && num_id != "" && name == "lvlOverride" {
        override_level = checked_index(word_attr(node, "ilvl"), 9).to_string()
        guard !overrides[num_id].contains(override_level) else {
          raise Invalid("duplicate numbering override")
        }
        overrides[num_id].push(override_level)
      } else if node.depth == 3 &&
        num_id != "" &&
        ["lvl", "startOverride"].contains(name) {
        let key = num_id + "/" + override_level + "/" + name
        guard !override_fields.contains(key) else {
          raise Invalid("duplicate numbering override property")
        }
        override_fields[key] = true
        if name == "lvl" {
          guard checked_index(word_attr(node, "ilvl"), 9).to_string() ==
            override_level else {
            raise Invalid("numbering override level mismatch")
          }
        }
      }
    }
  }
  for id, definition in instances {
    pkg.control.checkpoint("word-numbering-instance-binding", 1)
    guard abstracts.contains(definition) else {
      raise Invalid("dangling abstract numbering reference")
    }
    for level in overrides[id] {
      guard abstracts[definition].contains(level) ||
        override_fields.contains(id + "/" + level + "/lvl") else {
        raise Refused("override without an abstract level unsupported")
      }
    }
  }
  for nodes in pkg.xml_nodes.values() {
    for i, node in nodes {
      pkg.control.checkpoint("word-numbering-reference", 1)
      if node.element.name.namespace_uri != Some(word_ns) ||
        node.element.name.local_name != "numPr" {
        continue
      }
      let mut id : String? = None
      let mut level : String? = None
      let mut j = i + 1
      while j < nodes.length() && nodes[j].depth > node.depth {
        pkg.control.checkpoint("word-numbering-property", 1)
        let child = nodes[j]
        if child.depth == node.depth + 1 {
          if child.element.name.local_name == "numId" {
            guard id is None else {
              raise Invalid("duplicate numbering instance reference")
            }
            id = Some(word_id(word_attr(child, "val")))
          } else if child.element.name.local_name == "ilvl" {
            guard level is None else {
              raise Invalid("duplicate numbering level reference")
            }
            level = Some(checked_index(word_attr(child, "val"), 9).to_string())
          }
        }
        j += 1
      }
      guard id is Some(n) else {
        raise Refused("inherited numbering without explicit numId unsupported")
      }
      if n == "0" {
        continue
      }
      guard instances.get(n) is Some(definition) &&
        (
          abstracts[definition].contains(level.unwrap_or("0")) ||
          override_fields.contains(n + "/" + level.unwrap_or("0") + "/lvl")
        ) else {
        raise Invalid("dangling numbering instance or level reference")
      }
    }
  }
}

///|
fn validate_word_structures(pkg : Package) -> Unit raise {
  validate_word_notes(pkg, "footnotes")
  validate_word_notes(pkg, "endnotes")
  validate_word_numbering(pkg)
  validate_word_markers(pkg)
}

///|
fn validate_word_markers(pkg : Package) -> Unit raise {
  for nodes in pkg.xml_nodes.values() {
    let bookmarks : Map[String, Bool] = Map([])
    let names : Map[String, Bool] = Map([])
    let proof : Map[String, Int32] = Map([("spell", 0), ("gram", 0)])
    for node in nodes {
      pkg.control.checkpoint("word-range-marker", 1)
      if node.element.name.namespace_uri != Some(word_ns) {
        continue
      }
      let name = node.element.name.local_name
      if name == "bookmarkStart" {
        let id = word_id(word_attr(node, "id"))
        let label = word_attr(node, "name").to_lower()
        guard !bookmarks.contains(id) &&
          !names.contains(label) &&
          label.length() > 0 &&
          label.length() <= 40 &&
          label
          .code_units()
          .all(fn(c) {
            (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_'
          }) else {
          raise Invalid("invalid or duplicate bookmark identity")
        }
        bookmarks[id] = true
        names[label] = true
      } else if name == "bookmarkEnd" {
        let id = word_id(word_attr(node, "id"))
        guard bookmarks.get(id) == Some(true) else {
          raise Invalid("unpaired or duplicate bookmark end")
        }
        bookmarks[id] = false
      } else if name == "proofErr" {
        let kind = word_attr(node, "type")
        guard ["spellStart", "spellEnd", "gramStart", "gramEnd"].contains(kind) else {
          raise Refused("unsupported proofing marker")
        }
        let key = if kind.has_prefix("spell") { "spell" } else { "gram" }
        proof[key] = proof[key] +
          (if kind.has_suffix("Start") { 1 } else { -1 })
        guard proof[key] >= 0 else {
          raise Invalid("unpaired proofing end marker")
        }
      }
    }
    guard bookmarks.values().all(fn(open) { !open }) &&
      proof.values().all(fn(count) { count == 0 }) else {
      raise Invalid("unpaired Word range marker")
    }
  }
}
