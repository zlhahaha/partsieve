///|
fn make_plan(pkg : Package) -> RewritePlan raise {
  pkg.control.checkpoint("plan", 1)
  let report = pkg.audit
  let ops : Array[Operation] = []
  for f in report.findings {
    pkg.control.checkpoint("plan-finding", 1)
    let rel = graph_incoming(pkg.graph, f.part)[0]
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
      reason: if is_word_format(report.format) {
        "VBA is an implicit main-document relationship; no supported source XML references it."
      } else {
        "VBA is an implicit workbook relationship; no supported source XML references it."
      },
    })
    ops.push({
      kind: "RewriteRelationshipPart",
      part: relationship_part(rel.source),
      relationship_id: rel.id,
      rule: "vba-v1",
      reason: "Regenerate validated relationship metadata without VBA relation.",
    })
  }
  for part in controlled_vba_parts(pkg) {
    if !report.findings.any(fn(f) { f.part == part }) {
      ops.push({
        kind: "RemovePart",
        part,
        relationship_id: "",
        rule: "vba-v1",
        reason: "Remove exclusively owned Word VBA supporting metadata and its relationship part.",
      })
    }
  }
  for r in report.relationships {
    pkg.control.checkpoint("plan-relationship", 1)
    if !is_template_relationship(r) {
      continue
    }
    for
      (kind, part, reason) in [
        (
          "RewriteSourceXml",
          r.source,
          "Remove only the validated attachedTemplate element; retain all other settings semantics.",
        ),
        (
          "RemoveRelationship",
          r.source,
          "Remove the settings-local external template relationship without fetching its target.",
        ),
        (
          "RewriteRelationshipPart",
          relationship_part(r.source),
          "Regenerate settings relationships without the removed external template.",
        ),
      ] {
      ops.push({
        kind,
        part,
        relationship_id: r.id,
        rule: "remote-template-v1",
        reason,
      })
    }
  }
  for r in ole_relationships(pkg) {
    let preview = ole_preview(pkg, r)
    for
      (kind, part, id, reason) in [
        (
          "RewriteSourceXml",
          r.source,
          r.id,
          "Remove the validated inline OLE object and its preview; preserve all other Word semantics.",
        ),
        (
          "RemoveRelationship",
          r.source,
          r.id,
          "Remove the embedded OLE relationship.",
        ),
        (
          "RemoveRelationship",
          preview.source,
          preview.id,
          "Remove the exclusively owned OLE preview relationship.",
        ),
        (
          "RemovePart",
          r.resolved,
          "",
          "Remove the embedded OLE container without opening or recursively sanitizing it.",
        ),
        (
          "RemovePart",
          preview.resolved,
          "",
          "Remove the exclusively owned object preview; its displayed content is intentionally lost.",
        ),
      ] {
      if kind != "RewriteSourceXml" ||
        !ops.any(fn(op) { op.kind == kind && op.part == part }) {
        ops.push({ kind, part, relationship_id: id, rule: "ole-v1", reason, })
      }
    }
    let relpart = relationship_part(r.source)
    if !ops.any(fn(op) {
        op.kind == "RewriteRelationshipPart" && op.part == relpart
      }) {
      ops.push({
        kind: "RewriteRelationshipPart",
        part: relpart,
        relationship_id: r.id,
        rule: "ole-v1",
        reason: "Regenerate main-document relationships without the OLE object or its private preview.",
      })
    }
  }
  if is_macro_format(report.format) {
    ops.push({
      kind: "ChangeMainContentType",
      part: report.main_part,
      relationship_id: "",
      rule: "format-v1",
      reason: if is_word_format(report.format) {
        "Convert DOCM to DOCX, including macro-enabled formats without actual VBA."
      } else {
        "Convert macro-enabled workbook to ordinary XLSX, including macro-enabled files with no VBA."
      },
    })
    ops.push({
      kind: "RewriteContentTypes",
      part: "[Content_Types].xml",
      relationship_id: "",
      rule: "format-v1",
      reason: "Remove VBA mappings and change main type; retain other mappings.",
    })
  }
  if ole_relationships(pkg).length() > 0 &&
    !ops.any(fn(op) { op.kind == "RewriteContentTypes" }) {
    ops.push({
      kind: "RewriteContentTypes",
      part: "[Content_Types].xml",
      relationship_id: "",
      rule: "ole-v1",
      reason: "Remove content type mappings for deleted OLE and preview parts.",
    })
  }
  let ops = if ole_relationships(pkg).length() > 0 {
    ops.filter(fn(op) {
      !["RewriteRelationshipPart", "RewriteContentTypes"].contains(op.kind)
    }) +
    ops.filter(fn(op) {
      ["RewriteRelationshipPart", "RewriteContentTypes"].contains(op.kind)
    })
  } else {
    ops
  }
  {
    schema: if is_word_format(report.format) {
      "partsieve.plan.word-dev-v1"
    } else {
      "partsieve.plan.spike-v1"
    },
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
  control? : WorkControl = WorkControl::default(),
) -> RewritePlan raise {
  make_plan(load_package(input, limits, control~))
}

///|
fn write_relationships(pkg : Package, source : String) -> Bytes raise {
  pkg.control.checkpoint("metadata-write", 1)
  let writer = @xml.Writer::new()
  writer.start_element("Relationships", [("xmlns", rel_ns)])
  for r in pkg.audit.relationships {
    pkg.control.checkpoint("metadata-relationship", 1)
    if r.source != source || removed_relationship(pkg, r) {
      continue
    }
    let attributes = [("Id", r.id), ("Type", r.kind), ("Target", r.target)]
    if r.external {
      attributes.push(("TargetMode", "External"))
    }
    writer.empty_element("Relationship", attributes)
  }
  writer.end_element("Relationships")
  @utf8.encode(writer.to_string()[:])
}

///|
fn write_content_types(pkg : Package) -> Bytes raise {
  pkg.control.checkpoint("metadata-write", 1)
  let writer = @xml.Writer::new()
  writer.start_element("Types", [("xmlns", ct_ns)])
  let extensions = pkg.defaults.keys().collect()
  extensions.sort()
  for ext in extensions {
    let ct = pkg.defaults[ext]
    if ct != vba_ct &&
      ct != word_vba_data_ct &&
      (!ole_payload_type(ct) || ole_relationships(pkg).length() == 0) {
      writer.empty_element("Default", [("Extension", ext), ("ContentType", ct)])
    }
  }
  let names = pkg.overrides.keys().collect()
  names.sort()
  for name in names {
    pkg.control.checkpoint("metadata-content-type", 1)
    let ct = pkg.overrides[name]
    if ct == vba_ct || controlled_parts(pkg).contains(name) {
      continue
    }
    writer.empty_element("Override", [
      ("PartName", "/" + name),
      (
        "ContentType",
        if name == pkg.audit.main_part {
          plain_content_type(pkg)
        } else {
          ct
        },
      ),
    ])
  }
  // The workbook main type can legally come from a default mapping. Convert
  // that case using an explicit override while keeping other XML mappings.
  if !pkg.overrides.contains(pkg.audit.main_part) {
    writer.empty_element("Override", [
      ("PartName", "/" + pkg.audit.main_part),
      ("ContentType", plain_content_type(pkg)),
    ])
  }
  writer.end_element("Types")
  @utf8.encode(writer.to_string()[:])
}

///|
fn execute(pkg : Package, limits : Limits) -> Bytes raise {
  execute_prepared(pkg, make_prepared_plan(pkg, limits), limits)
}

///|
fn verify_parts(
  before : Package,
  after : Package,
  expected : Package,
) -> Array[Disposition] raise {
  let dispositions : Array[Disposition] = []
  guard after.audit.format ==
    (if is_word_format(before.audit.format) { "DOCX" } else { "XLSX" }) &&
    after.audit.findings.length() == 0 else {
    raise Invalid("output has forbidden VBA or macro-enabled type")
  }
  guard after.graph.graph == expected.graph.graph else {
    raise Invalid("unexpected output part/relationship changes")
  }
  before.control.pairs(
    "verify-parts-scan",
    before.audit.parts.length(),
    after.audit.parts.length(),
  )
  for p in before.audit.parts {
    before.control.checkpoint("verify-part", 1)
    let matches = after.audit.parts.filter(fn(q) { q.name == p.name })
    let out = if matches.length() == 0 { None } else { Some(matches[0]) }
    let removed = controlled_parts(before).contains(p.name)
    let semantic = source_rewritten(before, p.name)
    let metadata = is_macro_format(before.audit.format) &&
      (
        p.name == "[Content_Types].xml" ||
        (
          before.audit.findings.length() > 0 &&
          p.name == relationship_part(before.audit.main_part)
        )
      )
    let metadata = metadata ||
      (
        ole_relationships(before).length() > 0 &&
        (
          p.name == "[Content_Types].xml" ||
          p.name == relationship_part(before.audit.main_part)
        )
      ) ||
      before.audit.relationships.any(fn(r) {
        is_template_relationship(r) && p.name == relationship_part(r.source)
      })
    if removed {
      guard out is None else { raise Invalid("VBA part retained") }
      dispositions.push({
        part: p.name,
        classification: "RemovedByPolicy",
        before_hash: p.sha256,
        after_hash: None,
      })
    } else {
      guard out is Some(q) else { raise Invalid("preserved part missing") }
      guard metadata || semantic || q.sha256 == p.sha256 else {
        raise Invalid("preserved payload changed")
      }
      if semantic {
        verify_source_semantics(before, after, p.name)
      }
      dispositions.push({
        part: p.name,
        classification: if semantic {
          "SemanticallyRewritten"
        } else if metadata {
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
priv struct VerifiedPackages {
  before : Package
  after : Package
  dispositions : Array[Disposition]
}

///|
fn verify_packages(
  output : Bytes,
  original : Bytes,
  limits : Limits,
  control : WorkControl,
) -> VerifiedPackages raise {
  guard output.length() <= limits.output_bytes else {
    raise Incomplete("output byte limit")
  }
  let before = load_package(original, limits, control~)
  let expected_bytes = execute(before, limits)
  let expected = load_package(expected_bytes, limits, output=true, control~)
  let after = load_package(output, limits, output=true, control~)
  control.checkpoint("verify-parts", 0)
  let dispositions = verify_parts(before, after, expected)
  control.checkpoint("verify-complete", 0)
  { before, after, dispositions, }
}

///|
fn legacy_receipt(
  checked : VerifiedPackages,
  output : Bytes,
  original : Bytes,
  limits : Limits,
) -> Receipt raise {
  let before = checked.before
  let after = checked.after
  {
    schema: if is_word_format(before.audit.format) {
      "partsieve.receipt.word-dev-v1"
    } else {
      "partsieve.receipt.spike-v1"
    },
    tool: if is_word_format(before.audit.format) {
      "partsieve/0.7.1-spike"
    } else {
      "partsieve/0.7.1-spike"
    },
    rules: if is_word_format(before.audit.format) {
      "word-business-v1"
    } else {
      "business-rules-v1"
    },
    policy: "passive-office-v1",
    profile: before.audit.profile,
    input_hash: before.audit.input_hash,
    output_hash: work_digest(output[:], before.control),
    input_size: original.length(),
    output_size: output.length(),
    input_format: before.audit.format,
    output_format: after.audit.format,
    limits,
    audit: before.audit,
    plan: make_plan(before),
    dispositions: checked.dispositions,
    structure: "Pass",
    preservation: "Pass",
    independent_validation: "NotChecked",
    limitations: before.audit.limitations,
  }
}

///|
pub fn verify(
  output : Bytes,
  original : Bytes,
  limits? : Limits = Limits::default(),
  control? : WorkControl = WorkControl::default(),
) -> Receipt raise {
  legacy_receipt(
    verify_packages(output, original, limits, control),
    output,
    original,
    limits,
  )
}

///|
pub fn rebuild(
  input : Bytes,
  limits? : Limits = Limits::default(),
  control? : WorkControl = WorkControl::default(),
) -> Rebuilt raise {
  let before = load_package(input, limits, control~)
  let bytes = execute(before, limits)
  // Reparse serialized bytes; do not trust executor's graph.
  let receipt = verify(bytes, input, limits~, control~)
  { bytes, receipt, }
}
