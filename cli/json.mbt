///|
priv struct JsonScan {
  text : String
  mut pos : Int
  mut items : Int
}

///|
fn JsonScan::spaces(self : JsonScan) -> Unit {
  while self.pos < self.text.length() &&
        [32, 9, 10, 13].contains(self.text[self.pos].to_int()) {
    self.pos += 1
  }
}

///|
fn JsonScan::string_token(self : JsonScan) -> String raise {
  guard self.pos < self.text.length() && self.text[self.pos] == '"' else {
    raise @lib.Invalid("JSON object key must be a string")
  }
  let start = self.pos
  self.pos += 1
  let mut escaped = false
  while self.pos < self.text.length() {
    let c = self.text[self.pos]
    self.pos += 1
    guard self.pos - start <= 65536 else {
      raise @lib.Incomplete("JSON string token limit")
    }
    if escaped {
      escaped = false
    } else if c == '\\' {
      escaped = true
    } else if c == '"' {
      let value = @json.parse(self.text[start:self.pos]) catch {
        _ => raise @lib.Invalid("invalid JSON string")
      }
      match value {
        String(s) => return s
        _ => raise @lib.Invalid("invalid JSON string")
      }
    }
  }
  raise @lib.Invalid("unterminated JSON string")
}

///|
fn JsonScan::value(self : JsonScan, depth : Int) -> Unit raise {
  self.spaces()
  self.items += 1
  guard self.items <= 200000 else { raise @lib.Incomplete("JSON item limit") }
  guard self.pos < self.text.length() else {
    raise @lib.Invalid("truncated JSON")
  }
  let c = self.text[self.pos]
  if c == '"' {
    ignore(self.string_token())
    return
  }
  if c == '[' || c == '{' {
    guard depth < 32 else { raise @lib.Incomplete("JSON depth limit") }
    let object = c == '{'
    let end : UInt16 = if object { '}' } else { ']' }
    self.pos += 1
    self.spaces()
    if self.pos < self.text.length() && self.text[self.pos] == end {
      self.pos += 1
      return
    }
    let keys : Map[String, Bool] = Map([])
    while true {
      if object {
        self.spaces()
        let key = self.string_token()
        guard !keys.contains(key) else {
          raise @lib.Invalid("duplicate JSON key")
        }
        keys[key] = true
        self.spaces()
        guard self.pos < self.text.length() && self.text[self.pos] == ':' else {
          raise @lib.Invalid("missing JSON colon")
        }
        self.pos += 1
      }
      self.value(depth + 1)
      self.spaces()
      guard self.pos < self.text.length() else {
        raise @lib.Invalid("truncated JSON container")
      }
      let next = self.text[self.pos]
      self.pos += 1
      if next == end {
        break
      }
      guard next == ',' else { raise @lib.Invalid("invalid JSON separator") }
    }
  } else {
    let start = self.pos
    while self.pos < self.text.length() &&
          ![44, 125, 93, 32, 9, 13, 10].contains(self.text[self.pos].to_int()) {
      self.pos += 1
      guard self.pos - start <= 65536 else {
        raise @lib.Incomplete("JSON literal token limit")
      }
    }
    guard self.pos > start else { raise @lib.Invalid("missing JSON value") }
  }
}

///|
pub fn parse_json(bytes : Bytes) -> Json raise {
  guard bytes.length() <= 16777216 else {
    raise @lib.Incomplete("JSON byte limit")
  }
  let text = @utf8.decode(bytes[:]) catch {
    _ => raise @lib.Invalid("JSON is not UTF-8")
  }
  let scan : JsonScan = { text, pos: 0, items: 0, }
  scan.value(0)
  scan.spaces()
  guard scan.pos == text.length() else {
    raise @lib.Invalid("trailing JSON data")
  }
  let value = @json.parse(text[:]) catch {
    _ => raise @lib.Invalid("malformed JSON")
  }
  validate_numbers(value)
  value
}

///|
fn field(value : Json, key : String) -> Json raise {
  match value {
    Object(items) =>
      match items.get(key) {
        Some(v) => v
        None => raise Usage("missing worker field: " + key)
      }
    _ => raise Usage("worker returned a non-object report")
  }
}

///|
fn string_field(value : Json, key : String) -> String raise {
  match field(value, key) {
    String(s) => s
    _ => raise Usage("worker returned an invalid string field: " + key)
  }
}

///|
// Structural JSON equality keeps False distinct from 0; object key order is irrelevant.
fn json_equal(left : Json, right : Json) -> Bool {
  match (left, right) {
    (Null, Null) | (True, True) | (False, False) => true
    (String(a), String(b)) => a == b
    (Number(a, ..), Number(b, ..)) => a == b
    (Array(a), Array(b)) => {
      if a.length() != b.length() {
        return false
      }
      for i, x in a {
        if !json_equal(x, b[i]) {
          return false
        }
      }
      true
    }
    (Object(a), Object(b)) => {
      if a.length() != b.length() {
        return false
      }
      for k, x in a {
        match b.get(k) {
          Some(y) => if !json_equal(x, y) { return false }
          None => return false
        }
      }
      true
    }
    _ => false
  }
}

///|
fn validate_numbers(value : Json) -> Unit raise {
  match value {
    Number(n, ..) =>
      if n.is_inf() || n.is_nan() {
        raise @lib.Invalid("non-finite JSON number")
      }
    Array(items) =>
      for item in items {
        validate_numbers(item)
      }
    Object(items) =>
      for _, item in items {
        validate_numbers(item)
      }
    _ => ()
  }
}
