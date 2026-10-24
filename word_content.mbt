///|
let word_drawing_ns = "http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"

///|
let picture_ns = "http://schemas.openxmlformats.org/drawingml/2006/picture"

///|
fn word_passive_element(node : Node, parent : String, root : String) -> Bool {
  let ns = node.element.name.namespace_uri.unwrap_or("")
  let name = node.element.name.local_name
  if ns == word_ns {
    match name {
      "document" | "hdr" | "ftr" => node.depth == 0 && name == root
      "body" => parent == "document"
      "p" | "tbl" => ["body", "tc", "hdr", "ftr"].contains(parent)
      "sectPr" => ["body", "pPr"].contains(parent) && root == "document"
      "r" => parent == "p" || parent == "hyperlink"
      "hyperlink" | "pPr" => parent == "p"
      "t" | "rPr" | "br" | "cr" | "tab" | "drawing" => parent == "r"
      "b" | "i" | "u" | "sz" | "szCs" | "rFonts" | "lang" | "color" =>
        parent == "rPr"
      "spacing"
      | "jc"
      | "ind"
      | "pStyle"
      | "keepNext"
      | "keepLines"
      | "widowControl" => parent == "pPr" || (name == "jc" && parent == "tblPr")
      "pgSz"
      | "pgMar"
      | "cols"
      | "docGrid"
      | "type"
      | "titlePg"
      | "headerReference"
      | "footerReference" => parent == "sectPr"
      "tblPr" | "tblGrid" | "tr" => parent == "tbl"
      "tblW"
      | "tblLayout"
      | "tblStyle"
      | "tblLook"
      | "tblInd"
      | "tblBorders"
      | "tblCellMar" => parent == "tblPr"
      "gridCol" => parent == "tblGrid"
      "trPr" | "tc" => parent == "tr"
      "trHeight" | "tblHeader" | "cantSplit" => parent == "trPr"
      "tcPr" => parent == "tc"
      "tcW" | "gridSpan" | "vMerge" | "vAlign" | "tcBorders" | "tcMar" =>
        parent == "tcPr"
      "shd" => ["tcPr", "tblPr", "pPr", "rPr"].contains(parent)
      "top" | "left" | "bottom" | "right" | "insideH" | "insideV" =>
        ["tblBorders", "tcBorders", "tblCellMar", "tcMar"].contains(parent)
      _ => false
    }
  } else if ns == word_drawing_ns {
    match name {
      "inline" => parent == "drawing"
      "extent" | "effectExtent" | "docPr" | "cNvGraphicFramePr" =>
        parent == "inline"
      _ => false
    }
  } else if ns == picture_ns {
    match name {
      "pic" => parent == "graphicData"
      "nvPicPr" | "blipFill" | "spPr" => parent == "pic"
      "cNvPr" | "cNvPicPr" => parent == "nvPicPr"
      _ => false
    }
  } else if ns == drawing_ns {
    match name {
      "graphic" => parent == "inline"
      "graphicData" => parent == "graphic"
      "blip" | "stretch" => parent == "blipFill"
      "fillRect" => parent == "stretch"
      "xfrm" | "prstGeom" => parent == "spPr"
      "off" | "ext" => parent == "xfrm"
      "avLst" => parent == "prstGeom"
      "graphicFrameLocks" => parent == "cNvGraphicFramePr"
      "picLocks" => parent == "cNvPicPr"
      _ => false
    }
  } else {
    false
  }
}

///|
fn passive_drawing_attribute(
  ns : String,
  element : String,
  name : String,
) -> Bool {
  if ns == word_drawing_ns {
    match element {
      "inline" => ["distT", "distB", "distL", "distR"].contains(name)
      "extent" => ["cx", "cy"].contains(name)
      "effectExtent" => ["l", "t", "r", "b"].contains(name)
      "docPr" => ["id", "name", "descr", "title", "hidden"].contains(name)
      _ => false
    }
  } else if ns == picture_ns {
    element == "cNvPr" &&
    ["id", "name", "descr", "title", "hidden"].contains(name)
  } else {
    match element {
      "graphicData" => name == "uri"
      "blip" => name == "cstate"
      "xfrm" => ["rot", "flipH", "flipV"].contains(name)
      "off" => ["x", "y"].contains(name)
      "ext" => ["cx", "cy"].contains(name)
      "prstGeom" => name == "prst"
      "graphicFrameLocks" | "picLocks" =>
        ["noChangeAspect", "noChangeArrowheads"].contains(name)
      _ => false
    }
  }
}

///|
fn validate_word_reference_attribute(
  pkg : Package,
  part : PartRecord,
  node : Node,
  attribute : @xml.NamespaceAttribute,
) -> Unit raise {
  let ns = node.element.name.namespace_uri.unwrap_or("")
  let name = node.element.name.local_name
  let kind = if ns == drawing_ns &&
    name == "blip" &&
    attribute.name.local_name == "embed" {
    office_rel + "image"
  } else if ns == word_ns &&
    ["headerReference", "footerReference"].contains(name) &&
    attribute.name.local_name == "id" {
    office_rel + (if name == "headerReference" { "header" } else { "footer" })
  } else if ns == word_ns &&
    name == "attachedTemplate" &&
    attribute.name.local_name == "id" &&
    part.content_type.contains(".settings+") {
    office_rel + "attachedTemplate"
  } else if ns == word_ns &&
    name == "hyperlink" &&
    attribute.name.local_name == "id" {
    office_rel + "hyperlink"
  } else {
    raise Refused("unsupported Word relationship attribute context")
  }
  guard graph_relationship(pkg.graph, part.name, attribute.value) is Some(r) &&
    r.kind == kind &&
    (
      !r.external ||
      is_template_relationship(r) ||
      (kind == office_rel + "hyperlink" && valid_click_url(r.target))
    ) else {
    raise Invalid("Word XML reference is bound to the wrong relationship kind")
  }
}

///|
fn validate_word_references(pkg : Package) -> Unit raise {
  let referenced : Map[String, Bool] = Map([])
  for reference in pkg.graph.graph.xml_references {
    referenced[reference.source + "#" + reference.relationship_id] = true
  }
  for r in pkg.audit.relationships {
    if !removed_relationship(pkg, r) &&
      [office_rel + "header", office_rel + "footer", office_rel + "image"].contains(
        r.kind,
      ) {
      guard referenced.contains(r.source + "#" + r.id) else {
        raise Invalid(
          "Word content relationship is not referenced by its source",
        )
      }
    }
  }
}
