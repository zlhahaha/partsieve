///|
fn object_field(value : Json, name : String) -> Json {
  match value {
    Object(fields) => fields.get(name).unwrap()
    _ => abort("expected object")
  }
}

///|
fn text(value : Json) -> String {
  match value {
    String(s) => s
    _ => abort("expected string")
  }
}

///|
fn array(value : Json) -> Array[Json] {
  match value {
    Array(items) => items
    _ => abort("expected array")
  }
}

///|
fn integer(value : Json) -> Int {
  match value {
    Number(n, ..) => n.to_int()
    _ => abort("expected integer")
  }
}

///|
fn sha(bytes : Bytes) -> String {
  @crypto.bytes_to_hex_string(@crypto.sha256(bytes))
}

///|
// Only the release metadata field is omitted; every behavior field is compared.
fn canonical(value : Json) -> String {
  match value {
    Object(fields) => {
      let keys : Array[String] = fields.keys().collect()
      keys.sort()
      "{" +
      keys
      .iter()
      .filter(fn(k) { k != "tool" })
      .map(fn(k) { @json.to_json(k).stringify() + ":" + canonical(fields[k]) })
      .collect()
      .join(",") +
      "}"
    }
    Array(items) => "[" + items.iter().map(canonical).collect().join(",") + "]"
    _ => value.stringify()
  }
}

///|
fn report_hash(bytes : Bytes) -> String raise {
  sha(@utf8.encode(canonical(@cli.parse_json(bytes))[:]))
}

///|
fn root() -> String raise {
  let mut path = @host.absolute(@env.current_dir().unwrap())
  for _ in 0..<10 {
    if @host.exists(path + "/tests/corpus/commands.json") {
      return path
    }
    path = @host.parent(path)
  }
  fail("run from the PartSieve checkout")
}

///|
fn binary(root : String, pkg_path : String) -> String raise {
  let stem = root + "/_build/native/debug/build/" + pkg_path
  if @host.exists(stem + ".exe") {
    stem + ".exe"
  } else {
    stem
  }
}

///|
test "seven historical integration suites execute through the native CLI" {
  let root = root()
  let exe = binary(root, "cmd/main/main")
  let meta = @cli.parse_json(
    @host.read_bounded(root + "/tests/corpus/commands.json", 16777216),
  )
  let raw = @host.read_bounded(root + "/tests/corpus/commands.zip", 16777216)
  let corpus = @zip.read(
    raw[:],
    limits=@zip.ReadLimits::default()
      .with_entry_limit(67108864)
      .with_total_limit(536870912)
      .with_preserved_source_limit(67108864),
  )
  let version_report = @host.run(exe, [
    "prepare",
    root + "/tests/fixtures/upstream/macro01.xlsm",
  ])
  assert_eq(version_report.code, 0)
  let version = text(
    object_field(@cli.parse_json(version_report.stdout), "tool"),
  )
  let marker = text(object_field(meta, "version_marker"))
  let cases = array(object_field(meta, "cases"))
  assert_true(cases.length() >= 250)
  for case in cases {
    let name = text(object_field(case, "name"))
    let dir = @host.temp_dir()
    let files = array(object_field(case, "files"))
    defer {
      for file in files {
        let path = dir + "/" + text(object_field(file, "name"))
        if @host.exists(path) {
          @host.remove_file(path)
        }
      }
      @host.remove_dir(dir)
    }
    for file in files {
      if object_field(file, "before") is String(id) {
        let data = corpus.get(id[:]).unwrap().to_owned()
        assert_eq(sha(data), id)
        let filename = text(object_field(file, "name"))
        let data = if filename.has_suffix(".json") {
          @utf8.encode(
            @utf8.decode(data[:]).replace_all(old=marker, new=version)[:],
          ) catch {
            _ => data
          }
        } else {
          data
        }
        @host.write_new(dir + "/" + filename, data)
      }
    }
    let args = array(object_field(case, "args")).map(fn(value) {
      let arg = text(value)
      if arg.has_prefix("@") {
        dir + "/" + arg[1:].to_owned()
      } else {
        arg
      }
    })
    let result = @host.run(exe, args)
    assert_eq(
      result.code,
      integer(object_field(case, "code")),
      msg=name + " exit: " + @utf8.decode_lossy(result.stdout[:]),
    )
    assert_eq(
      report_hash(result.stdout),
      text(object_field(case, "report_hash")),
      msg=name + " report " + canonical(@cli.parse_json(result.stdout)),
    )
    for output in array(object_field(case, "outputs")) {
      let path = dir + "/" + text(object_field(output, "name"))
      match object_field(output, "after") {
        Null =>
          assert_false(
            @host.exists(path),
            msg=name + " unexpected published output",
          )
        String(expected) => {
          let data = @host.read_bounded(path, 67108864)
          if object_field(output, "json") == @json.to_json(true) {
            assert_eq(
              report_hash(data),
              text(object_field(output, "report_hash")),
              msg=name + " Receipt",
            )
          } else {
            assert_eq(sha(data), expected, msg=name + " document bytes")
          }
        }
        _ => fail("invalid output expectation")
      }
    }
  }
}

///|
test "bounded process handles unicode, spaces, quotes and trailing backslashes" {
  let exe = binary(root(), "tests/probe/probe")
  let args = ["中文 空格", "", "a\"b", "trailing\\", "\\\"", "x y\\"]
  let result = @host.run(exe, args)
  assert_eq(result.code, 0)
  assert_eq(
    @utf8.decode(result.stdout[:]).replace_all(old="\r\n", new="\n"),
    args.join("\n") + "\n",
  )
}

///|
test "bounded process timeout and stdout flooding fail closed" {
  let exe = binary(root(), "tests/probe/probe")
  let timeout = try {
    ignore(@host.run(exe, ["sleep"], timeout_ms=30))
    false
  } catch {
    @host.Limit(_) => true
    _ => false
  }
  assert_true(timeout)
  let flood = try {
    ignore(@host.run(exe, ["flood"], output_limit=1024))
    false
  } catch {
    @host.Limit(_) => true
    _ => false
  }
  assert_true(flood)
  // A fresh process still works after both forced terminations.
  assert_eq(@host.run(exe, ["alive"]).code, 0)
}

///|
test "exclusive files, cap boundary, nonregular input and guarded rollback" {
  let dir = @host.temp_dir()
  let input = dir + "/中文 input"
  let link = dir + "/published"
  let other = dir + "/other"
  defer {
    for path in [input, link, other] {
      if @host.exists(path) {
        @host.remove_file(path)
      }
    }
    @host.remove_dir(dir)
  }
  @host.write_new(input, b"1234")
  assert_eq(@host.read_bounded(input, 4), b"1234")
  assert_true(
    try {
      ignore(@host.read_bounded(input, 3))
      false
    } catch {
      @host.Limit(_) => true
      _ => false
    },
  )
  assert_true(
    try {
      @host.write_new(input, b"overwrite")
      false
    } catch {
      @host.Io(_) => true
      _ => false
    },
  )
  assert_true(
    try {
      ignore(@host.read_bounded(dir, 8))
      false
    } catch {
      @host.Io(_) => true
      _ => false
    },
  )
  @host.link_new(input, link)
  assert_true(
    try {
      @host.link_new(input, link)
      false
    } catch {
      @host.Io(_) => true
      _ => false
    },
  )
  @host.write_new(other, b"replacement")
  assert_true(
    try {
      @host.remove_same(input, other)
      false
    } catch {
      @host.Io(_) => true
      _ => false
    },
  )
  assert_eq(@host.read_bounded(other, 16), b"replacement")
  @host.remove_same(input, link)
  assert_false(@host.exists(link))
  assert_eq(@host.read_bounded(input, 4), b"1234")
}
