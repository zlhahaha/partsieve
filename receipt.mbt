///|
fn contract_dispositions(
  basis : Receipt,
  prepared : PreparedPlan,
) -> Array[ContractDisposition] raise {
  let records : Array[ContractDisposition] = []
  for disposition in basis.dispositions {
    let classification = match disposition.classification {
      "BytePreserved" => BytePreservedKind
      "RemovedByPolicy" => RemovedByPolicyKind
      "RegeneratedMetadata" => RegeneratedMetadataKind
      _ =>
        raise Invalid(
          "no accepted semantic preservation handler for this disposition",
        )
    }
    let mut operation : CheckedOperation? = None
    for op in prepared.operations {
      if op.part == disposition.part && operation_writes(op.kind) {
        operation = Some(op)
        break
      }
    }
    if classification != BytePreservedKind {
      guard operation is Some(_) else {
        raise Invalid("changed part has no authorized plan operation")
      }
    }
    records.push({
      part: disposition.part,
      classification,
      before_hash: disposition.before_hash,
      after_hash: disposition.after_hash,
      decision_id: operation.map(fn(op) { op.decision_id }),
      rule_id: operation.map(fn(op) { op.rule_id }),
      reason: match operation {
        Some(op) => op.reason
        None =>
          "Actual output payload SHA-256 equals original; no handler authorizes changing this part."
      },
    })
  }
  records
}

///|
pub fn verify_contract(
  output : Bytes,
  original : Bytes,
  limits? : Limits = Limits::default(),
) -> VerifiedReceipt raise {
  // The compatibility verifier reparses actual serialized output, compares its
  // full graph with independently generated expected changes, and checks every
  // payload. Executor memory and a supplied Receipt cannot produce this result.
  let checked = verify_packages(output, original, limits)
  let basis = legacy_receipt(checked, output, original, limits)
  let before = checked.before
  let after = checked.after
  let prepared = make_prepared_plan(before, limits)
  let assessment = assess_package(after)
  guard assessment.decision.result == Pass &&
    assessment.coverage.parse_complete &&
    assessment.coverage.unchecked_features.length() == 0 &&
    assessment.findings.length() == 0 else {
    raise Invalid("output capability/profile coverage contract not satisfied")
  }
  let checks : Array[VerificationCheck] = []
  for
    (id, detail) in [
      (
        "actual-output-structure", "Reparsed actual output bytes; CRC, OPC targets, content types and plain main type checked.",
      ),
      (
        "actual-output-graph", "Rebuilt source-local relationship/XML index equals the independently regenerated expected graph.",
      ),
      (
        "actual-output-capabilities", "All declared profile rules checked; forbidden declarations absent; unknown features refuse.",
      ),
      (
        "all-part-dispositions", "Every original part has a disposition; no unplanned new/missing part or changed metadata/payload.",
      ),
      (
        "payload-preservation", "BytePreserved payload hashes equal original; metadata equals the exact accepted handler output.",
      ),
      (
        "plan-preconditions", "Input/part hashes, resource configuration, conflicts, closure and decisions recomputed from original.",
      ),
    ] {
    checks.push({ check_id: id, state: Checked, result: Some(Pass), detail, })
  }
  checks.push({
    check_id: "independent-client-schema",
    state: NotChecked,
    result: None,
    detail: "The SDK does not execute independent validators or Office clients; external evidence must bind the actual output hash.",
  })
  {
    schema: "partsieve.receipt.v2-dev",
    tool: "partsieve/0.2.0-spike",
    rules: prepared.rules,
    policy: prepared.policy,
    profile: prepared.profile,
    input_hash: basis.input_hash,
    output_hash: basis.output_hash,
    input_size: original.length(),
    output_size: output.length(),
    input_format: basis.input_format,
    output_format: basis.output_format,
    limits,
    input_coverage: prepared.coverage,
    output_coverage: assessment.coverage,
    findings: prepared.findings,
    output_findings: assessment.findings,
    decisions: prepared.decisions,
    allowed_capabilities: [],
    plan: prepared,
    dispositions: contract_dispositions(basis, prepared),
    checks,
    result: Pass,
    independent_validation: NotChecked,
    independent_tools: [],
    limitations: before.audit.limitations +
    [
      "No accepted source XML rewrite handler: SemanticallyRewritten is not used or certified by this configuration.",
      "Receipt hashes bind bytes; no authenticity signature or general Office safety proof.",
      "Independent schema/client evidence is separate; WPS Word saved-copy ordering failure must not be represented as Pass.",
    ],
  }
}

///|
pub fn rebuild_verified(
  input : Bytes,
  limits? : Limits = Limits::default(),
) -> VerifiedRebuilt raise {
  let bytes = execute(load_package(input, limits), limits)
  { bytes, receipt: verify_contract(bytes, input, limits~), }
}

///|
pub fn rebuild_verified_with_plan(
  input : Bytes,
  supplied : Json,
  limits? : Limits = Limits::default(),
) -> VerifiedRebuilt raise {
  let bytes = execute_supplied_plan(input, supplied, limits)
  { bytes, receipt: verify_contract(bytes, input, limits~), }
}
