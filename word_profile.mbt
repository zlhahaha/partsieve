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
  "image/x-emf",
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
  for r in report.relationships {
    let previews = ole_relationships(pkg).filter(fn(o) {
      ole_preview(pkg, o) == r
    })
    if previews.length() > 0 {
      validate_ole(pkg, previews[0])
      continue
    }
    if ole_declared(r, report.parts, pkg.xml_nodes) {
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
  for part in report.parts {
    if part.name == "[Content_Types].xml" {
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
  } else {
    "webSettings"
  }
  guard nodes[0].element.name.local_name == root else {
    raise Refused("Word XML root/content type mismatch")
  }
  let parents : Array[String] = []
  let mask = if part.name == pkg.audit.main_part &&
    ole_relationships(pkg).length() == 1 {
    ole_mask(nodes)
  } else {
    []
  }
  for ordinal, node in nodes {
    if mask.contains(ordinal) {
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
    let permitted = if ["document", "hdr", "ftr"].contains(root) {
      word_passive_element(node, parent, root)
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
          parent == "shapeDefaults" &&
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
            "listSeparator", "attachedTemplate",
          ].contains(name)
        ) ||
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
        (name == "optimizeForBrowser" && parent == "webSettings")
      )
    } else {
      ns == word_ns &&
      [
        "styles", "docDefaults", "rPrDefault", "pPrDefault", "rPr", "pPr", "latentStyles",
        "lsdException", "style", "name", "basedOn", "next", "link", "uiPriority",
        "semiHidden", "unhideWhenUsed", "qFormat", "rsid", "rFonts", "lang", "sz",
        "szCs", "spacing", "tblPr", "tblInd", "tblCellMar", "top", "left", "bottom",
        "right", "b", "i", "u", "color", "jc", "ind", "keepNext", "keepLines", "widowControl",
      ].contains(name)
    }
    guard permitted else {
      raise Refused("unsupported Word XML feature or placement: " + name)
    }
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
      let ans = a.name.namespace_uri.unwrap_or("")
      if ans == office_rel[0:office_rel.length() - 1].to_owned() {
        validate_word_reference_attribute(pkg, part, node, a)
      } else if [word_drawing_ns, picture_ns, drawing_ns].contains(ns) {
        guard ans == "" &&
          passive_drawing_attribute(ns, name, a.name.local_name) else {
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
          (ns == word_ns && root == "styles" && name == "link") else {
          raise Refused("unsupported Word relationship attribute")
        }
        let permitted_attribute = if ns == word_macro_ns {
          ["macroName", "name", "bEncrypt", "cmg"].contains(a.name.local_name)
        } else if ns == word_ns && name == "hyperlink" {
          ["history", "tooltip", "tgtFrame"].contains(a.name.local_name)
        } else if ns == word_math_ns {
          a.name.local_name == "val"
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
