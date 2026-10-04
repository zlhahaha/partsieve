///|
// Conservative ASCII URI subset; encoded and alias cases are refused.
fn valid_segment(segment : String) -> Bool {
  if segment == "" ||
    segment == "." ||
    segment == ".." ||
    segment.has_suffix(".") {
    return false
  }
  for ch in segment {
    if !(ch >= 'a' && ch <= 'z') &&
      !(ch >= 'A' && ch <= 'Z') &&
      !(ch >= '0' && ch <= '9') &&
      ch != '_' &&
      ch != '-' &&
      ch != '.' &&
      ch != '[' &&
      ch != ']' {
      return false
    }
  }
  true
}

///|
fn check_name(name : String) -> Unit raise {
  guard name.length() <= 1024 && !name.has_prefix("/") else {
    raise Refused("invalid or overlong part name")
  }
  guard name == "[Content_Types].xml" || !name.contains_any(chars="[]") else {
    raise Refused("reserved URI characters in part name")
  }
  for segment in name.split("/") {
    guard valid_segment(segment.to_owned()) else {
      raise Refused("ambiguous or unsupported part URI")
    }
  }
}

///|
pub fn resolve_target(source : String, target : String) -> String raise {
  guard target.length() > 0 && target.length() <= 1024 else {
    raise Refused("empty or overlong relationship target")
  }
  let segments : Array[String] = []
  if !target.has_prefix("/") && source != "/" {
    check_name(source)
    for segment in source.split("/") {
      segments.push(segment.to_owned())
    }
    ignore(segments.pop())
  }
  let path = if target.has_prefix("/") { target[1:].to_owned() } else { target }
  for segment in path.split("/") {
    let s = segment.to_owned()
    if s == ".." {
      guard segments.length() > 0 else {
        raise Refused("target escapes package root")
      }
      ignore(segments.pop())
    } else if s == "." {
      continue
    } else {
      guard valid_segment(s) else {
        raise Refused("unsupported target URI encoding or syntax")
      }
      segments.push(s)
    }
  }
  let result = segments.join("/")
  check_name(result)
  result
}

///|
fn relationship_source(name : String) -> String raise {
  if name == "_rels/.rels" {
    return "/"
  }
  guard name.has_suffix(".rels") else {
    raise Refused("invalid relationships part")
  }
  let segments = name.split("/").map(fn(s) { s.to_owned() }).collect()
  let n = segments.length()
  guard n >= 2 && segments[n - 2] == "_rels" else {
    raise Refused("invalid relationships part location")
  }
  let source : Array[String] = []
  for i in 0..<(n - 2) {
    source.push(segments[i])
  }
  source.push(segments[n - 1][:segments[n - 1].length() - 5].to_owned())
  source.join("/")
}

///|
fn relationship_part(source : String) -> String {
  if source == "/" {
    return "_rels/.rels"
  }
  match source.rev_split_once("/") {
    Some((dir, file)) => dir.to_owned() + "/_rels/" + file.to_owned() + ".rels"
    None => "_rels/" + source + ".rels"
  }
}
