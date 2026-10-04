///|
test "capability rules distinguish clicking hyperlinks from fetched resources and data" {
  let hyperlink = {
    ..graph_edge(
      "a.xml",
      "r",
      "https://example.invalid/image.png",
      external=true,
    ),
    kind: office_rel + "hyperlink",
  }
  let image = { ..hyperlink, kind: office_rel + "image", }
  assert_eq(relationship_capability(hyperlink), Some(HttpHyperlink))
  assert_eq(relationship_capability(image), Some(ExternalResource))
  assert_eq(
    relationship_capability({
      ..hyperlink,
      kind: office_rel + "attachedTemplate",
    }),
    Some(RemoteTemplate),
  )
  assert_eq(
    relationship_capability({ ..image, kind: office_rel + "externalLinkPath", }),
    Some(ExternalData),
  )
  assert_eq(
    relationship_capability({ ..image, kind: office_rel + "oleObject", }),
    Some(Ole),
  )
  assert_eq(
    relationship_capability({ ..image, kind: office_rel + "control", }),
    Some(ActiveX),
  )
  assert_eq(relationship_capability({ ..image, kind: vba_rel, }), Some(Vba))
  assert_eq(
    relationship_capability({ ..image, kind: "urn:unknown", }),
    Some(UnknownExternalRelationship),
  )
  assert_eq(
    relationship_capability({ ..hyperlink, target: "file:///c:/example", }),
    Some(UnknownExternalRelationship),
  )
  assert_eq(
    relationship_capability({ ..image, external: false, resolved: "b.xml", }),
    None,
  )
}

///|
test "Incomplete assessment never turns an empty finding list into absent capabilities" {
  let report = assess(b"PK\x03\x04")
  assert_eq(report.decision.result, IncompleteResult)
  assert_eq(report.decision.rebuild_allowed, false)
  assert_eq(report.coverage.parse_complete, false)
  assert_eq(report.findings.length(), 0)
  assert_eq(report.graph, None)
  for rule in report.coverage.rules {
    assert_eq(rule.presence, Unknown)
    assert_eq(rule.state, IncompleteCheck)
    assert_eq(rule.rebuild_support, NotSupported)
  }
  assert_eq(report.coverage.checked_rules, [])
  let limited = assess(b"oversized", limits={
    ..Limits::default(),
    input_bytes: 1,
  })
  assert_eq(limited.decision.result, IncompleteResult)
  assert_eq(limited.input_hash, None)
}

///|
test "integrity failures unsupported syntax and incomplete parsing have distinct states" {
  let invalid = failed_assessment(
    b"input",
    Limits::default(),
    Fail,
    "CRC mismatch",
  )
  let unsupported = failed_assessment(
    b"input",
    Limits::default(),
    Unsupported,
    "unmodeled syntax",
  )
  assert_eq(invalid.decision.result, Fail)
  assert_eq(unsupported.decision.result, Unsupported)
  for report in [invalid, unsupported] {
    assert_eq(report.decision.rebuild_allowed, false)
    assert_eq(report.coverage.parse_complete, false)
    for rule in report.coverage.rules {
      assert_eq(rule.presence, Unknown)
      assert_eq(rule.state, NotChecked)
    }
  }
  assert_eq(Pass.to_json(), "Pass".to_json())
  assert_eq(IncompleteResult.to_json(), "Incomplete".to_json())
  assert_eq(NotChecked.to_json(), "NotChecked".to_json())
  assert_eq(Vba.to_json(), "VBA".to_json())
}
