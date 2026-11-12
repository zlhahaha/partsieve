///|
let word_content_types : Array[String] = [
  docm_ct, docx_ct, vba_ct, word_vba_data_ct, "application/vnd.openxmlformats-package.relationships+xml",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml", "application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.fontTable+xml",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.webSettings+xml",
  "application/vnd.openxmlformats-officedocument.theme+xml", "application/vnd.openxmlformats-package.core-properties+xml",
  "application/vnd.openxmlformats-officedocument.extended-properties+xml", "application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml", "image/png",
  "image/jpeg", ole_content_type, "application/vnd.ms-excel", "application/msword",
  "image/x-emf", "application/vnd.openxmlformats-officedocument.wordprocessingml.footnotes+xml",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.endnotes+xml",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml",
  "application/xml", custom_properties_ct,
]

///|
let word_relationship_types : Array[String] = [
  office_rel + "officeDocument",
  office_rel + "styles",
  office_rel + "settings",
  office_rel + "fontTable",
  office_rel + "webSettings",
  office_rel + "theme",
  office_rel + "extended-properties",
  office_rel + "header",
  office_rel + "footer",
  office_rel + "image",
  office_rel + "attachedTemplate",
  office_rel + "footnotes",
  office_rel + "endnotes",
  office_rel + "numbering",
  office_rel + "customXml",
  office_rel + "customXmlProps",
  vba_rel,
  word_vba_data_rel,
  "http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties",
]

///|
let word_attribute_names : Array[String] = [
  "space", "val", "rsidR", "rsidRPr", "rsidRDefault", "rsidP", "rsidDel", "rsidSect",
  "w", "h", "orient", "top", "right", "bottom", "left", "header", "footer", "gutter",
  "num", "equalWidth", "sep", "linePitch", "charSpace", "type", "ascii", "hAnsi",
  "cs", "eastAsia", "asciiTheme", "hAnsiTheme", "cstheme", "eastAsiaTheme", "hint",
  "bidi", "firstLine", "hanging", "before", "after", "line", "lineRule", "styleId",
  "default", "customStyle", "name", "count", "defLockedState", "defUIPriority", "defSemiHidden",
  "defUnhideWhenUsed", "defQFormat", "locked", "uiPriority", "semiHidden", "unhideWhenUsed",
  "qFormat", "percent", "spelling", "grammar", "bg1", "t1", "bg2", "t2", "accent1",
  "accent2", "accent3", "accent4", "accent5", "accent6", "hyperlink", "followedHyperlink",
  "usb0", "usb1", "usb2", "usb3", "csb0", "csb1", "clear", "sz", "color", "fill",
  "themeColor", "themeTint", "themeShade", "gridSpan", "afterAutospacing", "beforeAutospacing",
  "tblLook", "firstRow", "lastRow", "firstColumn", "lastColumn", "noHBand", "noVBand",
  "hRule", "tblStyleRowBandSize",
]

///|
fn controlled_vba_parts(pkg : Package) -> Array[String] {
  let result : Array[String] = []
  for finding in pkg.audit.findings {
    result.push(finding.part)
    if is_word_format(pkg.audit.format) {
      let companion = relationship_part(finding.part)
      if pkg.archive.get(companion[:]) is Some(_) {
        result.push(companion)
        for
          i in pkg.graph.graph.nodes[pkg.graph.node_index[finding.part]].outbound {
          result.push(pkg.audit.relationships[i].resolved)
        }
      }
    }
  }
  result.sort()
  result
}

///|
fn validate_word_profile(pkg : Package) -> Unit raise {
  let report = pkg.audit
  guard report.relationships.filter(is_template_relationship).length() <= 1 else {
    raise Refused("multiple attached template declarations unsupported")
  }
  guard pkg.graph.graph.coverage_gaps.length() == 0 else {
    raise Refused(
      "Word graph coverage gap: " + pkg.graph.graph.coverage_gaps[0],
    )
  }
  validate_ole_source(pkg)
  let bibliography = validate_word_bibliography(pkg)
  for r in report.relationships {
    if [office_rel + "customXml", office_rel + "customXmlProps"].contains(
        r.kind,
      ) {
      guard bibliography.contains(r.resolved) else {
        raise Invalid("unowned bibliography relationship")
      }
      continue
    }
    let previews = ole_relationships(pkg).filter(fn(o) {
      ole_preview(pkg, o) == r
    })
    if previews.length() > 0 {
      validate_ole(pkg, previews[0])
      continue
    }
    if ole_declared(r, pkg.graph.ole_objects) {
      validate_ole(pkg, r)
      continue
    }
    if hyperlink_declared(r, report.parts, pkg.xml_nodes) {
      validate_hyperlink(pkg, r)
      continue
    }
    if r.kind == office_rel + "attachedTemplate" {
      validate_template_relationship(pkg, r)
      continue
    }
    guard !r.external && word_relationship_types.contains(r.kind) else {
      raise Refused("external or unsupported Word relationship")
    }
    let target = report.parts[pkg.graph.part_index[r.resolved]]
    let expected = if r.kind == vba_rel {
      target.content_type == vba_ct
    } else if r.kind == word_vba_data_rel {
      target.content_type == word_vba_data_ct
    } else if r.kind == office_rel + "officeDocument" {
      target.content_type == docm_ct || target.content_type == docx_ct
    } else if r.kind == office_rel + "image" {
      target.content_type == "image/png" || target.content_type == "image/jpeg"
    } else if r.kind == office_rel + "theme" {
      target.content_type ==
      "application/vnd.openxmlformats-officedocument.theme+xml"
    } else if r.kind == office_rel + "extended-properties" {
      target.content_type ==
      "application/vnd.openxmlformats-officedocument.extended-properties+xml"
    } else if r.kind.has_suffix("/core-properties") {
      target.content_type ==
      "application/vnd.openxmlformats-package.core-properties+xml"
    } else {
      target.content_type ==
      "application/vnd.openxmlformats-officedocument.wordprocessingml." +
      r.kind[office_rel.length():].to_owned() +
      "+xml"
    }
    guard expected else {
      raise Refused("Word relationship/content-type conflict")
    }
    if r.kind == word_vba_data_rel {
      guard report.findings.any(fn(f) { f.part == r.source }) else {
        raise Refused("Word VBA metadata not owned by a declared VBA project")
      }
    } else if [
        office_rel + "officeDocument",
        office_rel + "extended-properties",
        "http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties",
      ].contains(r.kind) {
      guard r.source == "/" else {
        raise Refused("Word package metadata source mismatch")
      }
    } else if r.kind == office_rel + "image" {
      let source_type = match pkg.graph.part_index.get(r.source) {
        Some(i) => report.parts[i].content_type
        None => ""
      }
      guard r.source == report.main_part ||
        source_type ==
        "application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml" ||
        source_type ==
        "application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml" else {
        raise Refused("Word image relationship has unsupported source")
      }
    } else {
      guard r.source == report.main_part else {
        raise Refused("unsupported Word relationship source")
      }
    }
  }
  guard report.findings.length() <= 1 else {
    raise Refused("multiple Word VBA projects unsupported")
  }
  for f in report.findings {
    guard report.format == "DOCM" else {
      raise Refused("VBA in non-macro Word main type")
    }
    let incoming = graph_incoming(pkg.graph, f.part)
    guard incoming.length() == 1 &&
      incoming[0].source == report.main_part &&
      incoming[0].kind == vba_rel else {
      raise Refused("shared/orphan Word VBA or conflicting evidence")
    }
    guard get_part(pkg.archive, f.part).has_prefix(
      b"\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1",
    ) else {
      raise Refused("Word VBA payload is not CFB")
    }
    let outgoing = pkg.graph.graph.nodes[pkg.graph.node_index[f.part]].outbound
    guard outgoing.length() <= 1 else {
      raise Refused("unsupported Word VBA dependency set")
    }
    for i in outgoing {
      let relation = report.relationships[i]
      guard relation.kind == word_vba_data_rel && !relation.external else {
        raise Refused("unsupported Word VBA companion")
      }
      let owners = graph_incoming(pkg.graph, relation.resolved)
      guard owners.length() == 1 && owners[0].source == f.part else {
        raise Refused("shared Word VBA metadata")
      }
      guard pkg.archive.get(relationship_part(relation.resolved)[:]) is None else {
        raise Refused("nested Word VBA metadata dependencies unsupported")
      }
    }
    guard !pkg.graph.graph.xml_references.any(fn(reference) {
      let r = report.relationships[reference.relationship_index]
      r.resolved == f.part ||
      outgoing.any(fn(i) { report.relationships[i].resolved == r.resolved })
    }) else {
      raise Refused("retained XML references Word VBA controlled parts")
    }
  }
  let removed = controlled_vba_parts(pkg)
  validate_word_references(pkg)
  validate_word_structures(pkg)
  for part in report.parts {
    if part.name == "[Content_Types].xml" {
      continue
    }
    if bibliography.contains(part.name) {
      continue
    }
    guard word_content_types.contains(part.content_type) else {
      raise Refused("unknown Word part content type")
    }
    if ole_payload_type(part.content_type) || part.content_type == "image/x-emf" {
      guard controlled_parts(pkg).contains(part.name) else {
        raise Refused("unowned Word OLE part")
      }
      continue
    }
    if part.content_type == vba_ct {
      continue
    }
    if part.content_type == "image/png" || part.content_type == "image/jpeg" {
      let bytes = get_part(pkg.archive, part.name)
      guard (
          part.content_type == "image/png" &&
          bytes.has_prefix(b"\x89PNG\x0d\x0a\x1a\x0a")
        ) ||
        (part.content_type == "image/jpeg" && bytes.has_prefix(b"\xff\xd8\xff")) else {
        raise Invalid("embedded image signature/content-type mismatch")
      }
      continue
    }
    if part.content_type == word_vba_data_ct {
      guard removed.contains(part.name) else {
        raise Refused("orphan Word VBA supporting metadata")
      }
    }
    if part.name.has_suffix(".rels") {
      guard part.content_type ==
        "application/vnd.openxmlformats-package.relationships+xml" else {
        raise Refused("Word relationship part content type mismatch")
      }
      continue
    }
    if part.content_type.contains(".theme+") ||
      part.content_type.contains("core-properties") ||
      part.content_type.contains("extended-properties") {
      validate_static_xml_part(pkg, part)
    } else {
      validate_word_xml_part(pkg, part)
    }
  }
}

///|
fn validate_word_xml_part(pkg : Package, part : PartRecord) -> Unit raise {
  guard pkg.xml_nodes.get(part.name) is Some(nodes) else {
    raise Refused("Word XML payload name unsupported")
  }
  let root = if part.name == pkg.audit.main_part {
    "document"
  } else if part.content_type == word_vba_data_ct {
    "vbaSuppData"
  } else if part.content_type.contains(".header+") {
    "hdr"
  } else if part.content_type.contains(".footer+") {
    "ftr"
  } else if part.content_type.contains(".styles+") {
    "styles"
  } else if part.content_type.contains(".settings+") {
    "settings"
  } else if part.content_type.contains(".fontTable+") {
    "fonts"
  } else if part.content_type.contains(".footnotes+") {
    "footnotes"
  } else if part.content_type.contains(".endnotes+") {
    "endnotes"
  } else if part.content_type.contains(".numbering+") {
    "numbering"
  } else {
    "webSettings"
  }
  guard nodes[0].element.name.local_name == root else {
    raise Refused("Word XML root/content type mismatch")
  }
  let parents : Array[String] = []
  let mut table_style = false
  let mut style_table_properties = 0
  let mut style_border_seen = false
  let mut validated_end = 0
  let mut allow_png_seen = false
  let mut no_proof_seen = false
  let layout_settings : Map[String, Bool] = Map([])
  let modern = word_modern_catalog(part, nodes, pkg.control)
  let mask = if part.name == pkg.audit.main_part &&
    ole_relationships(pkg).length() > 0 {
    ole_catalog_mask(pkg.graph.ole_objects, part.name)
  } else {
    []
  }
  for ordinal, node in nodes {
    pkg.control.checkpoint(
      "word-profile-node",
      1 + node.element.attributes.length(),
    )
    if ordinal < validated_end ||
      mask.contains(ordinal) ||
      modern.contains(ordinal) {
      continue
    }
    let ns = node.element.name.namespace_uri.unwrap_or("")
    let name = node.element.name.local_name
    while parents.length() > node.depth {
      ignore(parents.pop())
    }
    let parent = if parents.length() > 0 {
      parents[parents.length() - 1]
    } else {
      ""
    }
    if root == "styles" && node.depth == 1 {
      table_style = ns == word_ns &&
        name == "style" &&
        word_attr_opt(node, "type") == Some("table")
      style_table_properties = 0
      style_border_seen = false
    }
    if table_style && node.depth == 2 && ns == word_ns && name == "tblPr" {
      guard !style_border_seen else {
        raise Refused("duplicate table properties in bordered Word style")
      }
      style_table_properties += 1
    }
    if root == "styles" && ns == word_ns && name == "tblBorders" {
      guard table_style &&
        style_table_properties == 1 &&
        node.depth == 3 &&
        parent == "tblPr" &&
        !style_border_seen else {
        raise Refused("misplaced or duplicate Word table style borders")
      }
      validated_end = validate_word_table_style_borders(nodes, ordinal)
      style_border_seen = true
      continue
    }
    if root == "hdr" {
      if ns == word_ns && name == "rPr" {
        no_proof_seen = false
      }
      if ns == word_ns && name == "noProof" {
        guard !no_proof_seen &&
          parent == "rPr" &&
          parents.length() >= 2 &&
          parents[parents.length() - 2] == "r" &&
          word_val_leaf(nodes, ordinal) &&
          ["0", "1", "true", "false", "on", "off"].contains(
            word_attr_opt(node, "val").unwrap_or("true"),
          ) else {
          raise Refused("invalid or duplicate Word header run proofing flag")
        }
        no_proof_seen = true
        continue
      }
      if ns == drawing_ns && name == "srcRect" && parent == "blipFill" {
        validate_header_source_rectangle(nodes, ordinal)
        continue
      }
      if ns == drawing_ns && name == "noFill" && parent == "spPr" {
        validated_end = validate_header_picture_no_fill(nodes, ordinal)
        continue
      }
    }
    if root == "webSettings" && ns == word_ns && name == "allowPNG" {
      guard !allow_png_seen &&
        node.depth == 1 &&
        parent == "webSettings" &&
        word_val_leaf(nodes, ordinal) &&
        ["0", "1", "true", "false", "on", "off"].contains(
          word_attr_opt(node, "val").unwrap_or("true"),
        ) else {
        raise Refused("invalid or duplicate Word allowPNG setting")
      }
      allow_png_seen = true
      continue
    }
    if root == "settings" &&
      ns == word_ns &&
      [
        "embedSystemFonts", "doNotHyphenateCaps", "noPunctuationKerning", "drawingGridHorizontalSpacing",
        "displayHorizontalDrawingGridEvery", "displayVerticalDrawingGridEvery",
      ].contains(name) {
      guard node.depth == 1 &&
        parent == "settings" &&
        !layout_settings.contains(name) &&
        word_val_leaf(nodes, ordinal) else {
        raise Refused("misplaced, malformed or duplicate Word layout setting")
      }
      match name {
        "drawingGridHorizontalSpacing" => {
          guard checked_index(word_attr(node, "val"), 31681) > 0 else {
            raise Invalid("Word drawing grid spacing must be positive")
          }
        }
        "displayHorizontalDrawingGridEvery"
        | "displayVerticalDrawingGridEvery" =>
          ignore(checked_index(word_attr(node, "val"), 256))
        _ => {
          // embedTrueTypeFonts and font payload relationships still refuse.
          guard ["0", "1", "true", "false", "on", "off"].contains(
            word_attr_opt(node, "val").unwrap_or("true"),
          ) else {
            raise Refused("unsupported Word layout flag value")
          }
        }
      }
      layout_settings[name] = true
      continue
    }
    let permitted = if ["document", "hdr", "ftr", "footnotes", "endnotes"].contains(
        root,
      ) {
      word_passive_element(node, parent, root)
    } else if root == "numbering" {
      word_numbering_element(node, parent)
    } else if root == "vbaSuppData" {
      ns == word_macro_ns &&
      (match name {
        "vbaSuppData" => node.depth == 0
        "mcds" => parent == "vbaSuppData"
        "mcd" => parent == "mcds"
        _ => false
      })
    } else if root == "settings" {
      if ns == word_math_ns {
        (name == "mathPr" && parent == "settings") ||
        (
          parent == "mathPr" &&
          [
            "mathFont", "brkBin", "brkBinSub", "smallFrac", "dispDef", "lMargin",
            "rMargin", "defJc", "wrapIndent", "intLim", "naryLim",
          ].contains(name)
        )
      } else if ns == word_office_ns {
        (
          ["shapeDefaults", "hdrShapeDefaults"].contains(parent) &&
          ["shapedefaults", "shapelayout"].contains(name)
        ) ||
        (name == "idmap" && parent == "shapelayout")
      } else if ns == word_ns {
        (name == "settings" && node.depth == 0) ||
        (
          parent == "settings" &&
          [
            "zoom", "proofState", "defaultTabStop", "characterSpacingControl", "compat",
            "rsids", "themeFontLang", "clrSchemeMapping", "shapeDefaults", "decimalSymbol",
            "listSeparator", "attachedTemplate", "hyphenationZone", "footnotePr",
            "endnotePr", "removePersonalInformation", "removeDateAndTime", "doNotAutoCompressPictures",
            "doNotDisplayPageBoundaries", "doNotIncludeSubdocsInStats", "hdrShapeDefaults",
          ].contains(name)
        ) ||
        (parent == "footnotePr" && name == "footnote") ||
        (parent == "endnotePr" && name == "endnote") ||
        (parent == "compat" && name == "compatSetting") ||
        (parent == "rsids" && ["rsidRoot", "rsid"].contains(name))
      } else {
        false
      }
    } else if root == "fonts" {
      ns == word_ns &&
      (
        (name == "fonts" && node.depth == 0) ||
        (name == "font" && parent == "fonts") ||
        (
          parent == "font" &&
          ["panose1", "charset", "family", "pitch", "sig", "altName"].contains(
            name,
          )
        )
      )
    } else if root == "webSettings" {
      ns == word_ns &&
      (
        (name == "webSettings" && node.depth == 0) ||
        (
          ["optimizeForBrowser", "divs"].contains(name) &&
          parent == "webSettings"
        ) ||
        (name == "div" && parent == "divs") ||
        (
          ["bodyDiv", "marLeft", "marRight", "marTop", "marBottom", "divBdr"].contains(
            name,
          ) &&
          parent == "div"
        ) ||
        (
          ["top", "left", "bottom", "right"].contains(name) &&
          parent == "divBdr"
        )
      )
    } else {
      (
        ns == word_ns &&
        [
          "styles", "docDefaults", "rPrDefault", "pPrDefault", "rPr", "pPr", "latentStyles",
          "lsdException", "style", "name", "basedOn", "next", "link", "uiPriority",
          "semiHidden", "unhideWhenUsed", "qFormat", "rsid", "rFonts", "lang", "sz",
          "szCs", "spacing", "tblPr", "tblInd", "tblCellMar", "top", "left", "bottom",
          "right", "b", "i", "u", "color", "jc", "ind", "keepNext", "keepLines",
          "widowControl",
        ].contains(name)
      ) ||
      (ns == word_ns && word_extra_layout_element(name, parent))
    }
    guard permitted else {
      raise Refused("unsupported Word XML feature or placement: " + name)
    }
    validate_word_structure_attributes(node, parent, root)
    if (
        ns == word_ns &&
        ["headerReference", "footerReference", "attachedTemplate", "hyperlink"].contains(
          name,
        )
      ) ||
      (ns == drawing_ns && name == "blip") {
      let required = if ns == drawing_ns { "embed" } else { "id" }
      guard node.element.attributes
        .filter(fn(a) {
          a.name.namespace_uri ==
          Some(office_rel[0:office_rel.length() - 1].to_owned()) &&
          a.name.local_name == required
        })
        .length() ==
        1 else {
        raise Refused(
          "Word content reference requires a source-local relationship",
        )
      }
    }
    if ns == word_ns && name == "hyperlink" {
      guard node.text_fragments.all(fn(t) { t.trim() == "" }) &&
        node.element.attributes.all(fn(a) {
          (
            a.name.namespace_uri ==
            Some(office_rel[0:office_rel.length() - 1].to_owned()) &&
            a.name.local_name == "id"
          ) ||
          (
            a.name.namespace_uri == Some(word_ns) &&
            ["history", "tooltip", "tgtFrame"].contains(a.name.local_name)
          )
        }) else {
        raise Refused("unsupported Word click hyperlink content or attributes")
      }
      for attribute in node.element.attributes {
        if attribute.name.namespace_uri == Some(word_ns) &&
          attribute.name.local_name == "history" {
          let value = attribute.value
          guard ["0", "1", "true", "false", "on", "off"].contains(value) else {
            raise Invalid("invalid hyperlink history flag")
          }
        }
      }
    }
    parents.push(name)
    for a in node.element.attributes {
      if word_modern_attribute(part, node, a) {
        continue
      }
      let ans = a.name.namespace_uri.unwrap_or("")
      if ans == office_rel[0:office_rel.length() - 1].to_owned() {
        validate_word_reference_attribute(pkg, part, node, a)
      } else if [word_drawing_ns, picture_ns, drawing_ns].contains(ns) {
        guard ans == "" &&
          (
            passive_drawing_attribute(ns, name, a.name.local_name) ||
            (
              root == "hdr" &&
              ns == picture_ns &&
              name == "spPr" &&
              a.name.local_name == "bwMode" &&
              a.value == "auto"
            )
          ) else {
          raise Refused("unsupported drawing attribute")
        }
        if ns == drawing_ns &&
          name == "graphicData" &&
          a.name.local_name == "uri" {
          guard a.value == picture_ns else {
            raise Refused("non-picture drawing")
          }
        }
      } else if ns == word_office_ns {
        guard (
            ans == "urn:schemas-microsoft-com:vml" &&
            a.name.local_name == "ext" &&
            a.value == "edit"
          ) ||
          (
            ans == "" &&
            (
              (name == "shapedefaults" && a.name.local_name == "spidmax") ||
              (name == "idmap" && a.name.local_name == "data")
            )
          ) else {
          raise Refused("unsupported Office layout attribute")
        }
      } else {
        guard ans == ns ||
          (
            ans == "http://www.w3.org/XML/1998/namespace" &&
            a.name.local_name == "space" &&
            name == "t"
          ) else {
          raise Refused("unsupported Word XML attribute namespace")
        }
        guard !["id", "embed", "link"].contains(a.name.local_name) ||
          (
            ns == word_ns &&
            (
              (root == "styles" && name == "link") ||
              [
                "footnote", "endnote", "footnoteReference", "endnoteReference", "bookmarkStart",
                "bookmarkEnd", "div",
              ].contains(name)
            )
          ) else {
          raise Refused("unsupported Word relationship attribute")
        }
        let permitted_attribute = if ns == word_ns &&
          a.name.local_name == "rsidTr" {
          name == "tr" && parent == "tbl" && hex_text(a.value, 8)
        } else if ns == word_macro_ns {
          ["macroName", "name", "bEncrypt", "cmg"].contains(a.name.local_name)
        } else if ns == word_ns && name == "hyperlink" {
          ["history", "tooltip", "tgtFrame"].contains(a.name.local_name)
        } else if ns == word_math_ns {
          a.name.local_name == "val"
        } else if ns == word_ns &&
          word_structure_attribute(name, a.name.local_name) {
          true
        } else {
          word_attribute_names.contains(a.name.local_name)
        }
        guard permitted_attribute else {
          raise Refused("unsupported Word attribute: " + a.name.local_name)
        }
      }
    }
  }
}

///|
fn word_val_leaf(nodes : Array[Node], ordinal : Int32) -> Bool {
  let node = nodes[ordinal]
  exact_node_attributes(node, Some(word_ns), ["val"]) &&
  empty_node(node) &&
  (ordinal + 1 == nodes.length() || nodes[ordinal + 1].depth <= node.depth)
}

///|
fn validate_word_table_style_borders(
  nodes : Array[Node],
  ordinal : Int32,
) -> Int32 raise {
  let container = nodes[ordinal]
  guard container.element.attributes.is_empty() && empty_node(container) else {
    raise Refused("unsupported Word table style borders attributes or text")
  }
  let sides = ["top", "left", "bottom", "right", "insideH", "insideV"]
  let mut last_side = -1
  let mut cursor = ordinal + 1
  while cursor < nodes.length() && nodes[cursor].depth > container.depth {
    let side = nodes[cursor]
    guard side.depth == container.depth + 1 &&
      side.element.name.namespace_uri == Some(word_ns) &&
      sides.search(side.element.name.local_name) is Some(index) &&
      index > last_side &&
      exact_node_attributes(side, Some(word_ns), ["val", "sz", "space", "color"]) &&
      word_attr_opt(side, "val") == Some("single") &&
      empty_node(side) else {
      raise Refused("unsupported, duplicate or out-of-order Word table border")
    }
    if word_attr_opt(side, "sz") is Some(size) {
      guard checked_index(size, 97) >= 2 else {
        raise Invalid("Word table border size out of range")
      }
    }
    if word_attr_opt(side, "space") is Some(space) {
      ignore(checked_index(space, 32))
    }
    if word_attr_opt(side, "color") is Some(color) {
      guard color == "auto" || hex_text(color, 6) else {
        raise Invalid("invalid Word table border color")
      }
    }
    last_side = index
    cursor += 1
  }
  guard last_side >= 0 else { raise Refused("empty Word table style borders") }
  cursor
}
