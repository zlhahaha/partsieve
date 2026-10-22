///|
test "strict JSON rejects duplicate decoded keys, malformed UTF8 and bounded resources" {
  for
    raw in [
      b"{\"x\":0,\"x\":1}", b"{\"x\":0,\"\\u0078\":1}", b"\xff", b"NaN", b"Infinity",
      b"1e400", b"{", b"{} trailing",
    ] {
    assert_true(
      try {
        ignore(parse_json(raw))
        false
      } catch {
        @lib.Invalid(_) => true
        _ => false
      },
      msg=@utf8.decode_lossy(raw[:]),
    )
  }
  for
    raw in [
      @utf8.encode(("[".repeat(33) + "0" + "]".repeat(33))[:]),
      @utf8.encode(("\"" + "a".repeat(65537) + "\"")[:]),
      @utf8.encode(("[" + "0,".repeat(200000) + "0]")[:]),
    ] {
    assert_true(
      try {
        ignore(parse_json(raw))
        false
      } catch {
        @lib.Incomplete(_) => true
        _ => false
      },
    )
  }
  assert_false(json_equal(parse_json(b"false"), parse_json(b"0")))
  assert_true(
    json_equal(
      parse_json(b"{\"a\":1,\"b\":2}"),
      parse_json(b"{\"b\":2,\"a\":1}"),
    ),
  )
}

///|
test "argument parser rejects ambiguous or inapplicable flags" {
  for
    args in [
      ["rebuild", "a", "--output", "b", "-o", "c"],
      ["audit", "a", "--unknown"],
      ["audit", "a", "--timeout-ms", "0"],
      ["audit", "a", "--timeout-ms", "60001"],
      ["verify", "a", "--plan", "p"],
      ["prepare", "a", "--receipt-format", "v2"],
      ["rebuild", "a", "--dry-run", "--plan", "p"],
    ] {
    assert_true(
      try {
        ignore(parse_args(args))
        false
      } catch {
        Usage(_) => true
        _ => false
      },
    )
  }
  let options = parse_args(["audit", "--timeout-ms", "200", "--", "-input"])
  assert_eq(options.input, "-input")
  assert_eq(options.timeout_ms, 200)
}
