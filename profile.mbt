///|
let spreadsheet_ns = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"

///|
let drawing_ns = "http://schemas.openxmlformats.org/drawingml/2006/main"

///|
fn validate_profile(pkg : Package) -> Unit raise {
  let report = pkg.audit
  let allowed_rels = [
    office_rel + "officeDocument",
    office_rel + "worksheet",
    office_rel + "styles",
    office_rel + "theme",
    office_rel + "sharedStrings",
    office_rel + "extended-properties",
    "http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties",
    vba_rel,
  ]
  for r in report.relationships {
    guard !r.external && allowed_rels.contains(r.kind) else {
      raise Refused("external or unsupported relationship capability")
    }
    let target = report.parts.filter(fn(p) { p.name == r.resolved })[0]
    let expected = if r.kind == office_rel + "officeDocument" {
      target.content_type == xlsx_ct || target.content_type == xlsm_ct
    } else if r.kind == vba_rel {
      target.content_type == vba_ct
    } else if r.kind ==
      "http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" {
      target.content_type ==
      "application/vnd.openxmlformats-package.core-properties+xml"
    } else {
      let suffix = r.kind[office_rel.length():].to_owned()
      let wanted = if suffix == "extended-properties" {
        "application/vnd.openxmlformats-officedocument.extended-properties+xml"
      } else {
        "application/vnd.openxmlformats-officedocument." +
        (if suffix == "theme" { "theme" } else { "spreadsheetml." + suffix }) +
        "+xml"
      }
      target.content_type == wanted
    }
    guard expected else {
      raise Refused("relationship/content-type evidence conflict")
    }
    guard (if r.kind == vba_rel ||
      r.kind == office_rel + "worksheet" ||
      r.kind == office_rel + "styles" ||
      r.kind == office_rel + "theme" ||
      r.kind == office_rel + "sharedStrings" {
      r.source == report.main_part
    } else {
      r.source == "/"
    }) else {
      raise Refused("unsupported relationship source")
    }
  }
  guard report.findings.length() <= 1 else {
    raise Refused("multiple VBA parts unsupported")
  }
  for f in report.findings {
    guard report.format == "XLSM" else {
      raise Refused("VBA in non-macro main type")
    }
    let incoming = report.relationships.filter(fn(r) { r.resolved == f.part })
    guard incoming.length() == 1 &&
      incoming[0].kind == vba_rel &&
      incoming[0].source == report.main_part else {
      raise Refused("orphan/shared VBA or evidence conflict")
    }
    guard pkg.archive.get(relationship_part(f.part)[:]) is None else {
      raise Refused("VBA companion relationship parts unsupported")
    }
    guard get_part(pkg.archive, f.part).has_prefix(
      b"\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1",
    ) else {
      raise Refused("VBA part is not a CFB container")
    }
  }
  let static_types = [
    xlsm_ct, xlsx_ct, vba_ct, "application/vnd.openxmlformats-package.relationships+xml",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml", "application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml",
    "application/vnd.openxmlformats-officedocument.theme+xml", "application/vnd.openxmlformats-package.core-properties+xml",
    "application/vnd.openxmlformats-officedocument.extended-properties+xml",
  ]
  for p in report.parts {
    if p.name == "[Content_Types].xml" {
      continue
    }
    guard static_types.contains(p.content_type) else {
      raise Refused("unknown/unsupported part content type")
    }
    if p.content_type == vba_ct {
      continue
    }
    if p.name.has_suffix(".rels") {
      guard p.content_type ==
        "application/vnd.openxmlformats-package.relationships+xml" else {
        raise Refused("relationship part content type mismatch")
      }
      continue
    }
    guard pkg.xml_nodes.get(p.name) is Some(nodes) else {
      raise Refused("XML content type on unsupported payload name")
    }
    let root = nodes[0].element.name.local_name
    let expected_root = if p.name == report.main_part {
      "workbook"
    } else if p.content_type.contains(".worksheet+") {
      "worksheet"
    } else if p.content_type.contains(".styles+") {
      "styleSheet"
    } else if p.content_type.contains(".sharedStrings+") {
      "sst"
    } else if p.content_type.contains(".theme+") {
      "theme"
    } else if p.content_type.contains("core-properties") {
      "coreProperties"
    } else {
      "Properties"
    }
    guard root == expected_root else {
      raise Refused("part root/content type mismatch")
    }
    let parents : Array[String] = []
    let sheet_refs : Array[String] = []
    let sheet_names : Array[String] = []
    for node in nodes {
      let ns = node.element.name.namespace_uri.unwrap_or("")
      let local_name = node.element.name.local_name
      while parents.length() > node.depth {
        ignore(parents.pop())
      }
      let parent = if parents.length() > 0 {
        parents[parents.length() - 1]
      } else {
        ""
      }
      if expected_root == "workbook" {
        let shape_ok = match local_name {
          "workbook" => node.depth == 0
          "fileVersion" | "workbookPr" | "bookViews" | "sheets" | "calcPr" =>
            parent == "workbook"
          "workbookView" => parent == "bookViews"
          "sheet" => parent == "sheets"
          _ => false
        }
        guard shape_ok else {
          raise Refused("unsupported workbook element placement")
        }
        if local_name == "sheet" {
          let refs = node.element.attributes.filter(fn(a) {
            a.name.namespace_uri ==
            Some(office_rel[0:office_rel.length() - 1].to_owned()) &&
            a.name.local_name == "id"
          })
          guard refs.length() == 1 && !sheet_refs.contains(refs[0].value) else {
            raise Refused("missing or reused worksheet XML relationship ID")
          }
          sheet_refs.push(refs[0].value)
          let sheet_name = attr(node, "name")
          guard sheet_name.length() > 0 &&
            sheet_name.length() <= 31 &&
            !sheet_names.contains(sheet_name.to_lower()) else {
            raise Refused("invalid or duplicate sheet name")
          }
          sheet_names.push(sheet_name.to_lower())
          ignore(attr(node, "sheetId"))
        }
      } else if expected_root == "worksheet" {
        let shape_ok = match local_name {
          "worksheet" => node.depth == 0
          "sheetPr"
          | "dimension"
          | "sheetViews"
          | "sheetFormatPr"
          | "cols"
          | "sheetData"
          | "pageMargins"
          | "pageSetup"
          | "printOptions"
          | "mergeCells" => parent == "worksheet"
          "pageSetUpPr" | "outlinePr" => parent == "sheetPr"
          "sheetView" => parent == "sheetViews"
          "selection" => parent == "sheetView"
          "col" => parent == "cols"
          "row" => parent == "sheetData"
          "c" => parent == "row"
          "v" | "is" => parent == "c"
          "t" => parent == "is" || parent == "r"
          "r" => parent == "is"
          "rPr" => parent == "r"
          "mergeCell" => parent == "mergeCells"
          _ => false
        }
        guard shape_ok else {
          raise Refused("unsupported worksheet element placement")
        }
      }
      parents.push(local_name)
      let permitted = if expected_root == "workbook" {
        ns == spreadsheet_ns &&
        [
          "workbook", "fileVersion", "workbookPr", "bookViews", "workbookView", "sheets",
          "sheet", "calcPr",
        ].contains(local_name)
      } else if expected_root == "worksheet" {
        ns == spreadsheet_ns &&
        [
          "worksheet", "sheetPr", "pageSetUpPr", "outlinePr", "dimension", "sheetViews",
          "sheetView", "selection", "sheetFormatPr", "cols", "col", "sheetData",
          "row", "c", "v", "is", "t", "r", "rPr", "pageMargins", "pageSetup", "printOptions",
          "mergeCells", "mergeCell",
        ].contains(local_name)
      } else if expected_root == "sst" {
        ns == spreadsheet_ns &&
        [
          "sst", "si", "t", "r", "rPr", "b", "i", "u", "sz", "color", "rFont", "family",
          "scheme", "vertAlign",
        ].contains(local_name)
      } else if expected_root == "styleSheet" {
        ns == spreadsheet_ns &&
        [
          "styleSheet", "numFmts", "numFmt", "fonts", "font", "b", "i", "u", "sz",
          "color", "name", "family", "scheme", "vertAlign", "fills", "fill", "patternFill",
          "fgColor", "bgColor", "borders", "border", "left", "right", "top", "bottom",
          "diagonal", "cellStyleXfs", "cellXfs", "xf", "alignment", "protection",
          "cellStyles", "cellStyle", "dxfs", "tableStyles",
        ].contains(local_name)
      } else if expected_root == "theme" {
        ns == drawing_ns &&
        [
          "theme", "themeElements", "clrScheme", "dk1", "lt1", "dk2", "lt2", "accent1",
          "accent2", "accent3", "accent4", "accent5", "accent6", "hlink", "folHlink",
          "sysClr", "srgbClr", "fontScheme", "majorFont", "minorFont", "latin", "ea",
          "cs", "font", "fmtScheme", "fillStyleLst", "solidFill", "schemeClr", "gradFill",
          "gsLst", "gs", "tint", "satMod", "shade", "lin", "path", "fillToRect",
          "lnStyleLst", "ln", "prstDash", "miter", "effectStyleLst", "effectStyle",
          "effectLst", "outerShdw", "alpha", "bgFillStyleLst", "objectDefaults",
          "extraClrSchemeLst", "scene3d", "camera", "lightRig", "rot", "sp3d", "bevelT",
        ].contains(local_name)
      } else if expected_root == "coreProperties" {
        [
          "http://schemas.openxmlformats.org/package/2006/metadata/core-properties",
          "http://purl.org/dc/elements/1.1/", "http://purl.org/dc/terms/",
        ].contains(ns) &&
        [
          "coreProperties", "title", "subject", "creator", "keywords", "description",
          "lastModifiedBy", "revision", "created", "modified", "category", "contentStatus",
          "lastPrinted", "version", "identifier", "language",
        ].contains(local_name)
      } else {
        [
          "http://schemas.openxmlformats.org/officeDocument/2006/extended-properties",
          "http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes",
        ].contains(ns) &&
        [
          "Properties", "Application", "AppVersion", "DocSecurity", "ScaleCrop",
          "HeadingPairs", "TitlesOfParts", "Company", "LinksUpToDate", "SharedDoc",
          "HyperlinksChanged", "vector", "variant", "lpstr", "i4",
        ].contains(local_name)
      }
      guard permitted else {
        raise Refused("unsupported XML namespace or feature: " + local_name)
      }
      for a in node.element.attributes {
        let ans = a.name.namespace_uri.unwrap_or("")
        guard ans == "" ||
          ans == "http://www.w3.org/XML/1998/namespace" ||
          ans == office_rel[0:office_rel.length() - 1].to_owned() ||
          (
            expected_root == "coreProperties" &&
            ans == "http://www.w3.org/2001/XMLSchema-instance"
          ) else {
          raise Refused("unsupported namespaced XML attribute")
        }
        if ans == office_rel[0:office_rel.length() - 1].to_owned() {
          guard expected_root == "workbook" &&
            local_name == "sheet" &&
            a.name.local_name == "id" else {
            raise Refused("unsupported source XML relationship reference")
          }
          let match_rel = report.relationships.filter(fn(r) {
            r.source == p.name && r.id == a.value
          })
          guard match_rel.length() == 1 &&
            match_rel[0].kind == office_rel + "worksheet" else {
            raise Refused("dangling or wrongly-bound source XML reference")
          }
        }
      }
    }
    if expected_root == "workbook" {
      guard sheet_refs.length() > 0 else {
        raise Refused("workbook has no supported sheet")
      }
      for relation in report.relationships {
        if relation.source == p.name &&
          relation.kind == office_rel + "worksheet" {
          guard sheet_refs.contains(relation.id) else {
            raise Refused("unreferenced worksheet relationship")
          }
        }
      }
    }
  }
}
