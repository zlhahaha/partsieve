///|
test "click URL policy preserves HTTP(S) intent without accepting ambiguous authority" {
  for
    uri in [
      "https://example.invalid/中文?q=1&x=2#part", "HTTP://example.invalid:8080/x",
      "http://127.0.0.1/x", "https://a-b.example/x",
    ] {
    assert_true(valid_click_url(uri), msg=uri)
  }
  for
    uri in [
      "https:///x", "https://user@example.invalid/x", "https://bad_host/x", "https://-bad/x",
      "https://example.invalid:/x", "https://example.invalid:65536/x", "https://example.invalid:0/x",
      "https://[::1]/x", "file:///x", "javascript:x", "mailto:x@y", "https://example.invalid\\x",
      "https://example.invalid/a b",
    ] {
    assert_false(valid_click_url(uri), msg=uri)
  }
}

///|
test "hyperlink cell ranges stay inside the spreadsheet grid" {
  for range in ["A1", "XFD1048576", "A1:XFD1048576"] {
    validate_click_range(range)
  }
  for
    range in [
      "A0", "A01", "XFE1", "A1048577", "B2:A1", "A1 A2", "$A$1", "a1", "A1:B2:C3",
    ] {
    expect_refused(fn() raise { validate_click_range(range) })
  }
}
