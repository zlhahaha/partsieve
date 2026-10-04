///|
fn make_plan(pkg : Package) -> RewritePlan {
  let report = pkg.audit
  let ops : Array[Operation] = []
  for f in report.findings {
    let rel = report.relationships.filter(fn(r) {
        r.kind == vba_rel && r.resolved == f.part
      })[0]
    ops.push({
      kind: "RemovePart",
      part: f.part,
      relationship_id: "",
      rule: "vba-v1",
      reason: "Remove VBA payload; macro functionality is lost.",
    })
    ops.push({
      kind: "RemoveRelationship",
      part: rel.source,
      relationship_id: rel.id,
      rule: "vba-v1",
      reason: "VBA is an implicit workbook relationship; no supported source XML references it.",
    })
    ops.push({
      kind: "RewriteRelationshipPart",
      part: relationship_part(rel.source),
      relationship_id: rel.id,
      rule: "vba-v1",
      reason: "Regenerate validated relationship metadata without VBA relation.",
    })
  }
  if report.format == "XLSM" {
    ops.push({
      kind: "ChangeMainContentType",
      part: report.main_part,
      relationship_id: "",
      rule: "format-v1",
      reason: "Convert macro-enabled workbook to ordinary XLSX, including macro-enabled files with no VBA.",
    })
    ops.push({
      kind: "RewriteContentTypes",
      part: "[Content_Types].xml",
      relationship_id: "",
      rule: "format-v1",
      reason: "Remove VBA mappings and change main type; retain other mappings.",
    })
  }
  {
    schema: "partsieve.plan.spike-v1",
    input_hash: report.input_hash,
    policy: "passive-office-v1",
    profile: report.profile,
    operations: ops,
  }
}

///|
pub fn plan(
  input : Bytes,
  limits? : Limits = Limits::default(),
) -> RewritePlan raise {
  make_plan(load_package(input, limits))
}

///|
fn write_relationships(pkg : Package, source : String) -> Bytes raise {
  let writer = @xml.Writer::new()
  writer.start_element("Relationships", [("xmlns", rel_ns)])
  for r in pkg.audit.relationships {
    if r.source != source || r.kind == vba_rel {
      continue
    }
    writer.empty_element("Relationship", [
      ("Id", r.id),
      ("Type", r.kind),
      ("Target", r.target),
    ])
  }
  writer.end_element("Relationships")
  @utf8.encode(writer.to_string()[:])
}

///|
fn write_content_types(pkg : Package) -> Bytes raise {
  let writer = @xml.Writer::new()
  writer.start_element("Types", [("xmlns", ct_ns)])
  let extensions = pkg.defaults.keys().collect()
  extensions.sort()
  for ext in extensions {
    let ct = pkg.defaults[ext]
    if ct != vba_ct {
      writer.empty_element("Default", [("Extension", ext), ("ContentType", ct)])
    }
  }
  let names = pkg.overrides.keys().collect()
  names.sort()
  for name in names {
    let ct = pkg.overrides[name]
    if ct == vba_ct {
      continue
    }
    writer.empty_element("Override", [
      ("PartName", "/" + name),
      ("ContentType", if name == pkg.audit.main_part { xlsx_ct } else { ct }),
    ])
  }
  // The workbook main type can legally come from a default mapping. Convert
  // that case using an explicit override while keeping other XML mappings.
  if !pkg.overrides.contains(pkg.audit.main_part) {
    writer.empty_element("Override", [
      ("PartName", "/" + pkg.audit.main_part),
      ("ContentType", xlsx_ct),
    ])
  }
  writer.end_element("Types")
  @utf8.encode(writer.to_string()[:])
}

///|
fn execute(pkg : Package, limits : Limits) -> Bytes raise {
  let archive = pkg.archive.clone()
  for f in pkg.audit.findings {
    guard archive.remove(f.part[:]) else {
      raise Refused("plan RemovePart precondition failed")
    }
  }
  if pkg.audit.findings.length() > 0 {
    let name = relationship_part(pkg.audit.main_part)
    guard archive.replace(
      name[:],
      write_relationships(pkg, pkg.audit.main_part)[:],
    ) else {
      raise Refused("plan relationship precondition failed")
    }
  }
  if pkg.audit.format == "XLSM" {
    guard archive.replace("[Content_Types].xml", write_content_types(pkg)[:]) else {
      raise Refused("content types precondition failed")
    }
  }
  @zip.write_preserving_limited(archive, max_output_bytes=limits.output_bytes) catch {
    @zip.ZipError(_, message) =>
      raise Incomplete("bounded output writing did not complete: " + message)
  }
}

///|
fn verify_parts(
  before : Package,
  after : Package,
  expected : Package,
) -> Array[Disposition] raise {
  let dispositions : Array[Disposition] = []
  guard after.audit.format == "XLSX" && after.audit.findings.length() == 0 else {
    raise Refused("output has forbidden VBA or macro-enabled type")
  }
  guard after.audit.parts == expected.audit.parts &&
    after.audit.relationships == expected.audit.relationships else {
    raise Refused("unexpected output part/relationship changes")
  }
  for p in before.audit.parts {
    let matches = after.audit.parts.filter(fn(q) { q.name == p.name })
    let out = if matches.length() == 0 { None } else { Some(matches[0]) }
    let removed = before.audit.findings.any(fn(f) { f.part == p.name })
    let metadata = before.audit.format == "XLSM" &&
      (
        p.name == "[Content_Types].xml" ||
        (
          before.audit.findings.length() > 0 &&
          p.name == relationship_part(before.audit.main_part)
        )
      )
    if removed {
      guard out is None else { raise Refused("VBA part retained") }
      dispositions.push({
        part: p.name,
        classification: "RemovedByPolicy",
        before_hash: p.sha256,
        after_hash: None,
      })
    } else {
      guard out is Some(q) else { raise Refused("preserved part missing") }
      guard metadata || q.sha256 == p.sha256 else {
        raise Refused("preserved payload changed")
      }
      dispositions.push({
        part: p.name,
        classification: if metadata {
          "RegeneratedMetadata"
        } else {
          "BytePreserved"
        },
        before_hash: p.sha256,
        after_hash: Some(q.sha256),
      })
    }
  }
  dispositions
}

///|
pub fn verify(
  output : Bytes,
  original : Bytes,
  limits? : Limits = Limits::default(),
) -> Receipt raise {
  guard output.length() <= limits.output_bytes else {
    raise Incomplete("output byte limit")
  }
  let before = load_package(original, limits)
  let expected_bytes = execute(before, limits)
  let expected = load_package(expected_bytes, limits)
  let after = load_package(output, limits)
  let dispositions = verify_parts(before, after, expected)
  {
    schema: "partsieve.receipt.spike-v1",
    tool: "partsieve/0.1.0-spike",
    rules: "spike-rules-v1",
    policy: "passive-office-v1",
    profile: before.audit.profile,
    input_hash: before.audit.input_hash,
    output_hash: digest(output[:]),
    input_size: original.length(),
    output_size: output.length(),
    input_format: before.audit.format,
    output_format: after.audit.format,
    limits,
    audit: before.audit,
    plan: make_plan(before),
    dispositions,
    structure: "Pass",
    preservation: "Pass",
    independent_validation: "NotChecked",
    limitations: before.audit.limitations,
  }
}

///|
pub fn rebuild(
  input : Bytes,
  limits? : Limits = Limits::default(),
) -> Rebuilt raise {
  let before = load_package(input, limits)
  let bytes = execute(before, limits)
  // Reparse serialized bytes; do not trust executor's graph.
  let receipt = verify(bytes, input, limits~)
  { bytes, receipt, }
}
