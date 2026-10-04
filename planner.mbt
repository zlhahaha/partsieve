///|
fn parse_operation_kind(kind : String) -> PlanOperationKind raise {
  match kind {
    "RemovePart" => RemovePart
    "RemoveRelationship" => RemoveRelationship
    "RewriteSourceXml" => RewriteSourceXml
    "RewriteRelationshipPart" => RewriteRelationshipPart
    "RewriteContentTypes" => RewriteContentTypes
    "ChangeMainContentType" => ChangeMainContentType
    _ => raise Refused("unknown planner operation")
  }
}

///|
fn operation_writes(kind : PlanOperationKind) -> Bool {
  match kind {
    RemovePart
    | RewriteSourceXml
    | RewriteRelationshipPart
    | RewriteContentTypes => true
    RemoveRelationship | ChangeMainContentType => false
  }
}

///|
fn validate_operation_conflicts(
  operations : Array[CheckedOperation],
) -> Unit raise {
  let ids : Map[String, Bool] = Map([])
  let keys : Map[String, Bool] = Map([])
  let writers : Map[String, String] = Map([])
  for operation in operations {
    guard !ids.contains(operation.operation_id) else {
      raise Invalid("duplicate operation identity")
    }
    let key = operation.kind.label() +
      "|" +
      operation.part +
      "|" +
      operation.relationship_id
    guard !keys.contains(key) else { raise Invalid("duplicate plan operation") }
    for dependency in operation.depends_on {
      guard ids.contains(dependency) else {
        raise Invalid("operation dependency missing, cyclic or out of order")
      }
    }
    if operation_writes(operation.kind) {
      guard !writers.contains(operation.part) else {
        raise Invalid("conflicting payload operations: " + operation.part)
      }
      writers[operation.part] = operation.operation_id
    }
    ids[operation.operation_id] = true
    keys[key] = true
  }
}

///|
fn validate_removal_closure(
  pkg : Package,
  prepared : PreparedPlan,
) -> Unit raise {
  let removed : Map[String, Bool] = Map([])
  for part in prepared.controlled_removals {
    guard part != pkg.audit.main_part && part != "[Content_Types].xml" else {
      raise Invalid("protected part selected for deletion")
    }
    guard !removed.contains(part) && pkg.graph.part_index.contains(part) else {
      raise Invalid("duplicate/missing controlled deletion")
    }
    removed[part] = true
    guard prepared.operations.any(fn(op) {
      op.kind == RemovePart && op.part == part
    }) else {
      raise Invalid("controlled deletion missing its operation")
    }
  }
  for r in pkg.audit.relationships {
    if !r.external &&
      removed.contains(r.resolved) &&
      !removed.contains(r.source) {
      guard prepared.operations.any(fn(op) {
        op.kind == RemoveRelationship &&
        op.source == r.source &&
        op.relationship_id == r.id
      }) else {
        raise Refused("retained relationship still requires controlled target")
      }
    }
  }
  for reference in pkg.graph.graph.xml_references {
    let r = pkg.audit.relationships[reference.relationship_index]
    guard !removed.contains(r.resolved) || removed.contains(reference.source) else {
      raise Refused(
        "retained XML reference cannot be repaired by the VBA handler",
      )
    }
  }
}

///|
fn make_prepared_plan(pkg : Package, limits : Limits) -> PreparedPlan raise {
  let assessment = assess_package(pkg)
  guard assessment.decision.result == Pass &&
    assessment.decision.rebuild_allowed else {
    raise Refused(assessment.decision.reason)
  }
  let decisions : Array[PolicyDecision] = []
  let finding_decisions : Map[String, String] = Map([])
  for i, finding in assessment.findings {
    guard finding.capability == Vba && finding.rebuild_support == Supported else {
      raise Refused("finding has no accepted planner handler")
    }
    let id = "finding-" + i.to_string()
    finding_decisions[finding.part] = id
    decisions.push({
      decision_id: id,
      finding_index: Some(i),
      action: RemoveAction,
      rule_id: finding.rule_id,
      part: finding.part,
      reason: "Remove VBA and its exclusively owned supporting parts under passive-office-v1.",
    })
  }
  if is_macro_format(pkg.audit.format) {
    decisions.push({
      decision_id: "format",
      finding_index: None,
      action: AllowAction,
      rule_id: "format-v1",
      part: pkg.audit.main_part,
      reason: "Convert macro-enabled main type; this does not assert that VBA is present.",
    })
  }
  let operations : Array[CheckedOperation] = []
  let removed = controlled_vba_parts(pkg)
  for i, operation in make_plan(pkg).operations {
    let kind = parse_operation_kind(operation.kind)
    let part = if kind == RemoveRelationship {
      relationship_part(operation.part)
    } else if kind == ChangeMainContentType {
      "[Content_Types].xml"
    } else {
      operation.part
    }
    let before = pkg.audit.parts[pkg.graph.part_index[part]]
    let after = match kind {
      RemovePart => None
      RewriteRelationshipPart =>
        Some(digest(write_relationships(pkg, pkg.audit.main_part)[:]))
      RewriteContentTypes => Some(digest(write_content_types(pkg)[:]))
      RewriteSourceXml =>
        raise Refused("source XML handler has not passed acceptance")
      RemoveRelationship | ChangeMainContentType => Some(before.sha256)
    }
    let depends_on : Array[String] = []
    for previous in operations {
      if (
          kind == RewriteRelationshipPart &&
          previous.kind == RemoveRelationship &&
          previous.part == part
        ) ||
        (
          kind == RewriteContentTypes &&
          (
            previous.kind == RemovePart ||
            previous.kind == ChangeMainContentType
          )
        ) {
        depends_on.push(previous.operation_id)
      }
    }
    let decision_id = if operation.rule == "format-v1" {
      "format"
    } else if finding_decisions.get(operation.part) is Some(id) {
      id
    } else if pkg.audit.findings.length() == 1 &&
      finding_decisions.get(pkg.audit.findings[0].part) is Some(id) {
      id
    } else {
      raise Invalid("operation has no finding/policy decision")
    }
    operations.push({
      operation_id: "op-" + i.to_string(),
      kind,
      part,
      source: operation.part,
      relationship_id: operation.relationship_id,
      rule_id: operation.rule,
      decision_id,
      before_hash: before.sha256,
      expected_after_hash: after,
      depends_on,
      reason: operation.reason,
    })
  }
  let prepared : PreparedPlan = {
    schema: "partsieve.prepared-plan.v1",
    tool: "partsieve/0.2.0-spike",
    rules: "bounded-vba-plan-v1",
    input_hash: pkg.audit.input_hash,
    input_format: pkg.audit.format,
    output_format: if is_word_format(pkg.audit.format) {
      "DOCX"
    } else {
      "XLSX"
    },
    policy: "passive-office-v1",
    profile: pkg.audit.profile,
    limits,
    preconditions: pkg.audit.parts,
    findings: assessment.findings,
    decisions,
    operations,
    controlled_removals: removed,
    orphan_candidates: pkg.graph.graph.orphan_candidates,
    coverage: assessment.coverage,
    gate: assessment.decision,
    unavailable_handlers: [
      "RewriteSourceXml: no source XML rewrite handler has passed acceptance.",
    ],
  }
  validate_operation_conflicts(prepared.operations)
  validate_removal_closure(pkg, prepared)
  prepared
}

///|
pub fn prepare(
  input : Bytes,
  limits? : Limits = Limits::default(),
) -> PreparedPlan raise {
  make_prepared_plan(load_package(input, limits), limits)
}

///|
fn execute_prepared(
  pkg : Package,
  prepared : PreparedPlan,
  limits : Limits,
) -> Bytes raise {
  guard prepared.input_hash == pkg.audit.input_hash &&
    prepared.limits == limits &&
    prepared.preconditions == pkg.audit.parts else {
    raise Invalid("plan input/hash/resource precondition mismatch")
  }
  validate_operation_conflicts(prepared.operations)
  validate_removal_closure(pkg, prepared)
  let archive = pkg.archive.clone()
  for operation in prepared.operations {
    let before = pkg.audit.parts[pkg.graph.part_index[operation.part]]
    guard before.sha256 == operation.before_hash else {
      raise Invalid("operation payload precondition mismatch")
    }
    match operation.kind {
      RemovePart => {
        guard prepared.controlled_removals.contains(operation.part) &&
          archive.remove(operation.part[:]) else {
          raise Invalid("operation controlled removal precondition mismatch")
        }
      }
      RemoveRelationship => {
        guard graph_relationship(
            pkg.graph,
            operation.source,
            operation.relationship_id,
          )
          is Some(r) &&
          r.kind == vba_rel else {
          raise Invalid("relationship operation precondition mismatch")
        }
      }
      ChangeMainContentType => {
        guard is_macro_format(pkg.audit.format) &&
          operation.source == pkg.audit.main_part else {
          raise Invalid("format operation precondition mismatch")
        }
      }
      RewriteSourceXml =>
        raise Refused("source XML handler has not passed acceptance")
      RewriteRelationshipPart | RewriteContentTypes => {
        let payload = if operation.kind == RewriteContentTypes {
          write_content_types(pkg)
        } else {
          write_relationships(pkg, pkg.audit.main_part)
        }
        guard operation.expected_after_hash == Some(digest(payload[:])) &&
          archive.replace(operation.part[:], payload[:]) else {
          raise Invalid("metadata operation postcondition mismatch")
        }
      }
    }
  }
  @zip.write_preserving_limited(archive, max_output_bytes=limits.output_bytes) catch {
    @zip.ZipError(_, message) =>
      raise Incomplete("bounded output writing did not complete: " + message)
  }
}

///|
// A supplied JSON plan is data, not authority. Recompute every field from the
// actual bounded input before execution, then verify the serialized output.
fn execute_supplied_plan(
  input : Bytes,
  supplied : Json,
  limits : Limits,
) -> Bytes raise {
  let pkg = load_package(input, limits)
  let expected = make_prepared_plan(pkg, limits)
  guard supplied == expected.to_json() else {
    raise Invalid("supplied plan differs from independently recomputed plan")
  }
  execute_prepared(pkg, expected, limits)
}

///|
pub fn rebuild_with_plan(
  input : Bytes,
  supplied : Json,
  limits? : Limits = Limits::default(),
) -> Rebuilt raise {
  let bytes = execute_supplied_plan(input, supplied, limits)
  { bytes, receipt: verify(bytes, input, limits~), }
}
