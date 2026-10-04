///|
priv struct Node {
  element : @xml.NamespaceElement
  depth : Int
}

///|
// Literal DTD declarations are rejected before upstream parser allocation.
fn read_xml(
  data : BytesView,
  limits : Limits,
  metadata? : Bool = false,
) -> Array[Node] raise {
  read_xml_checked(data, limits, metadata~) catch {
    Refused(reason) => raise Refused(reason)
    Incomplete(reason) => raise Incomplete(reason)
    error =>
      raise Incomplete("XML parsing did not complete: " + error.to_string())
  }
}

///|
fn read_xml_checked(
  data : BytesView,
  limits : Limits,
  metadata~ : Bool,
) -> Array[Node] raise {
  guard data.length() <= limits.xml_bytes else {
    raise Incomplete("XML byte limit")
  }
  let text = @utf8.decode(data)
  guard !text.contains("<!DOCTYPE") && !text.contains("<!ENTITY") else {
    raise Refused("DTD and entity declarations are forbidden")
  }
  let mut depth = 0
  let mut nodes = 0
  let mut attrs = 0
  let mut i = 0
  let mut text_start = 0
  while i < text.length() {
    if text[i] != '<' {
      i += 1
      guard i - text_start <= 65536 else {
        raise Incomplete("XML text token limit")
      }
      continue
    }
    if text[i:].has_prefix("<!--") ||
      text[i:].has_prefix("<![CDATA[") ||
      text[i:].has_prefix("<?") {
      let end = if text[i:].has_prefix("<!--") {
        "-->"
      } else if text[i:].has_prefix("<![CDATA[") {
        "]]>"
      } else {
        "?>"
      }
      let token_start = i
      i += 2
      while i < text.length() && !text[i:].has_prefix(end) {
        i += 1
        guard i - token_start + end.length() <= 65536 else {
          raise Incomplete("XML markup token limit")
        }
      }
      i += end.length()
      guard i - token_start <= 65536 else {
        raise Incomplete("XML markup token limit")
      }
      text_start = i
      continue
    }
    let closing = i + 1 < text.length() && text[i + 1] == '/'
    let mut quote : UInt16 = 0
    let mut j = i + 1
    let mut tag_attributes = 0
    while j < text.length() {
      let c = text[j]
      if quote != 0 {
        if c == quote {
          quote = 0
        }
      } else if c == '"' || c == '\'' {
        quote = c
      } else if c == '=' {
        attrs += 1
        tag_attributes += 1
        guard tag_attributes <= 256 else {
          raise Incomplete("per-element attribute ceiling")
        }
        guard attrs <= limits.xml_attributes else {
          raise Incomplete("XML attribute limit")
        }
      } else if c == '>' {
        break
      }
      j += 1
      guard j - i + 1 <= 65536 else {
        raise Incomplete("XML markup token limit")
      }
    }
    if !closing {
      nodes += 1
      guard nodes <= limits.xml_nodes && depth + 1 <= limits.xml_depth else {
        raise Incomplete("XML node/depth limit")
      }
      if j == 0 || text[j - 1] != '/' {
        depth += 1
      }
    } else {
      depth -= 1
    }
    i = j + 1
    text_start = i
  }
  let reader = @xml.NamespaceReader::from_string(text)
  let result : Array[Node] = []
  let mut current = 0
  while true {
    let event = reader.read_event()
    match event.kind {
      Start(element) => {
        result.push({ element, depth: current, })
        current += 1
      }
      Empty(element) => result.push({ element, depth: current, })
      End(_) => current -= 1
      DocType(_) => raise Refused("DTD forbidden")
      Decl(encoding~, ..) =>
        if encoding is Some(e) && e != "UTF-8" && e != "utf-8" {
          raise Refused("only UTF-8 XML supported")
        }
      PI(..) => raise Refused("processing instructions unsupported")
      Text(value) =>
        if metadata && value.trim() != "" {
          raise Refused("text in package metadata")
        }
      CData(_) => if metadata { raise Refused("CDATA in package metadata") }
      Eof => break
      _ => ()
    }
  }
  result
}

///|
fn attr(node : Node, name : String) -> String raise {
  for a in node.element.attributes {
    if a.name.namespace_uri is None && a.name.local_name == name {
      return a.value
    }
  }
  raise Refused("required XML attribute missing: " + name)
}

///|
fn attr_opt(node : Node, name : String) -> String? {
  for a in node.element.attributes {
    if a.name.namespace_uri is None && a.name.local_name == name {
      return Some(a.value)
    }
  }
  None
}

///|
fn metadata_nodes(
  data : BytesView,
  limits : Limits,
  ns : String,
  root : String,
  children : Array[String],
) -> Array[Node] raise {
  let nodes = read_xml(data, limits, metadata=true)
  guard nodes.length() > 0 &&
    nodes[0].depth == 0 &&
    nodes[0].element.name.namespace_uri == Some(ns) &&
    nodes[0].element.name.local_name == root else {
    raise Refused("invalid metadata root")
  }
  validate_metadata_attributes(nodes[0], [])
  for i in 1..<nodes.length() {
    let node = nodes[i]
    guard node.depth == 1 &&
      node.element.name.namespace_uri == Some(ns) &&
      children.contains(node.element.name.local_name) else {
      raise Refused("unsupported metadata structure")
    }
  }
  nodes
}
