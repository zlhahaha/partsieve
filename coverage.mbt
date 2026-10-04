///|
let capability_rules : Array[Capability] = [
  Vba,
  HttpHyperlink,
  RemoteTemplate,
  ExternalResource,
  ExternalData,
  Ole,
  ActiveX,
  UnknownExternalRelationship,
  UnknownPotentiallyActiveExtension,
]

///|
fn capability_rule(capability : Capability) -> String {
  match capability {
    Vba => "vba-v1"
    HttpHyperlink => "http-hyperlink-v1"
    RemoteTemplate => "remote-template-v1"
    ExternalResource => "external-resource-v1"
    ExternalData => "external-data-v1"
    Ole => "ole-v1"
    ActiveX => "activex-v1"
    UnknownExternalRelationship => "unknown-external-v1"
    UnknownPotentiallyActiveExtension => "opaque-feature-v1"
  }
}

///|
fn relationship_capability(r : Relationship) -> Capability? {
  if r.kind == vba_rel {
    return Some(Vba)
  }
  if r.kind == office_rel + "attachedTemplate" && r.external {
    return Some(RemoteTemplate)
  }
  if r.kind == office_rel + "oleObject" {
    return Some(Ole)
  }
  if r.kind == office_rel + "control" || r.kind.to_lower().contains("activex") {
    return Some(ActiveX)
  }
  if r.kind == office_rel + "externalLink" ||
    r.kind == office_rel + "externalLinkPath" ||
    r.kind == office_rel + "connections" ||
    r.kind == office_rel + "queryTable" {
    return Some(ExternalData)
  }
  if r.external {
    let uri = r.target.to_lower()
    if r.kind == office_rel + "hyperlink" &&
      (uri.has_prefix("http://") || uri.has_prefix("https://")) {
      return Some(HttpHyperlink)
    }
    if [
        office_rel + "image",
        office_rel + "audio",
        office_rel + "video",
        office_rel + "media",
      ].contains(r.kind) {
      return Some(ExternalResource)
    }
    return Some(UnknownExternalRelationship)
  }
  None
}

///|
fn profile_decision(pkg : Package) -> Decision {
  try {
    validate_profile(pkg)
    {
      result: Pass,
      rebuild_allowed: true,
      profile: pkg.audit.profile,
      reason: "Checks complete within declared simple-spreadsheet profile; supported VBA removal is permitted. This is not a claim that input is passive.",
    }
  } catch {
    Invalid(reason) =>
      {
        result: Fail,
        rebuild_allowed: false,
        profile: pkg.audit.profile,
        reason,
      }
    Incomplete(reason) =>
      {
        result: IncompleteResult,
        rebuild_allowed: false,
        profile: pkg.audit.profile,
        reason,
      }
    Refused(reason) =>
      {
        result: Unsupported,
        rebuild_allowed: false,
        profile: pkg.audit.profile,
        reason,
      }
    error =>
      {
        result: IncompleteResult,
        rebuild_allowed: false,
        profile: pkg.audit.profile,
        reason: error.to_string(),
      }
  }
}

///|
fn require_supported_profile(pkg : Package) -> Unit raise {
  let decision = profile_decision(pkg)
  match decision.result {
    Pass => {
      guard decision.rebuild_allowed else { raise Refused(decision.reason) }
    }
    Fail => raise Invalid(decision.reason)
    IncompleteResult => raise Incomplete(decision.reason)
    Unsupported => raise Refused(decision.reason)
  }
}

///|
fn add_capability_finding(
  findings : Array[CapabilityFinding],
  index : Map[String, Int],
  capability : Capability,
  source : String,
  part : String,
  evidence : String,
  permitted : Bool,
) -> Unit {
  let key = capability.label() + "|" + part
  match index.get(key) {
    Some(i) => findings[i].evidence.push(evidence)
    None => {
      index[key] = findings.length()
      findings.push({
        rule_id: capability_rule(capability),
        capability,
        source,
        part,
        certainty: if capability == UnknownExternalRelationship ||
          capability == UnknownPotentiallyActiveExtension {
          Uncertain
        } else {
          Declared
        },
        rebuild_support: if permitted && capability == Vba {
          Supported
        } else {
          NotSupported
        },
        evidence: [evidence],
      })
    }
  }
}

///|
fn assess_package(pkg : Package) -> Assessment {
  let decision = profile_decision(pkg)
  let findings : Array[CapabilityFinding] = []
  let index : Map[String, Int] = Map([])
  for part in pkg.audit.parts {
    let ct = part.content_type.to_lower()
    let capability = if part.content_type == vba_ct {
      Some(Vba)
    } else if ct.contains("activex") {
      Some(ActiveX)
    } else if ct.contains("oleobject") {
      Some(Ole)
    } else if ct.contains(".externallink+") ||
      ct.contains(".connections+") ||
      ct.contains(".querytable+") {
      Some(ExternalData)
    } else if part.name != "[Content_Types].xml" &&
      !supported_content_types.contains(part.content_type) {
      Some(UnknownPotentiallyActiveExtension)
    } else {
      None
    }
    if capability is Some(c) {
      add_capability_finding(
        findings,
        index,
        c,
        part.name,
        part.name,
        "content-type:" + part.content_type,
        decision.rebuild_allowed,
      )
    }
  }
  for r in pkg.audit.relationships {
    if relationship_capability(r) is Some(c) {
      add_capability_finding(
        findings,
        index,
        c,
        r.source,
        if r.external {
          r.target
        } else {
          r.resolved
        },
        "relationship:" + r.source + "#" + r.id + ":" + r.kind + ":" + r.target,
        decision.rebuild_allowed,
      )
    } else if !supported_relationship_types.contains(r.kind) {
      add_capability_finding(
        findings,
        index,
        UnknownPotentiallyActiveExtension,
        r.source,
        r.resolved,
        "unmodeled internal relationship:" +
        r.source +
        "#" +
        r.id +
        ":" +
        r.kind,
        false,
      )
    }
  }
  for gap in pkg.graph.graph.coverage_gaps {
    if gap.has_prefix("opaque XML namespace/extension") {
      let part = match gap.rev_split_once(": ") {
        Some((_, part)) => part.to_owned()
        None => pkg.audit.main_part
      }
      add_capability_finding(
        findings,
        index,
        UnknownPotentiallyActiveExtension,
        part,
        part,
        gap,
        false,
      )
    }
  }
  if !decision.rebuild_allowed && findings.length() == 0 {
    add_capability_finding(
      findings,
      index,
      UnknownPotentiallyActiveExtension,
      pkg.audit.main_part,
      pkg.audit.main_part,
      "unsupported profile evidence: " + decision.reason,
      false,
    )
  }
  let rules : Array[RuleCoverage] = []
  let checked : Array[String] = []
  let unchecked = pkg.graph.graph.coverage_gaps.copy()
  if !decision.rebuild_allowed {
    unchecked.push("profile not established: " + decision.reason)
  }
  let observed : Map[String, Bool] = Map([])
  for f in findings {
    observed[f.capability.label()] = true
  }
  for capability in capability_rules {
    let present = observed.contains(capability.label())
    let uncertain = capability == UnknownPotentiallyActiveExtension ||
      capability == UnknownExternalRelationship
    let state = if decision.rebuild_allowed {
      Checked
    } else if present && uncertain {
      Opaque
    } else if present {
      Checked
    } else {
      NotChecked
    }
    let presence = if present && !uncertain {
      Present
    } else if decision.rebuild_allowed && !present {
      Absent
    } else {
      Unknown
    }
    let rule_id = capability_rule(capability)
    if state == Checked {
      checked.push(rule_id)
    }
    if state != Checked {
      unchecked.push("not completely checked: " + capability.label())
    }
    rules.push({
      rule_id,
      capability,
      state,
      presence,
      rebuild_support: if decision.rebuild_allowed && capability == Vba {
        Supported
      } else {
        NotSupported
      },
      reason: if decision.rebuild_allowed {
        "Checked within the strict allowlist; absence applies only within this profile."
      } else if present {
        "Positive declared metadata or opaque-feature evidence; absence and full coverage are not established."
      } else {
        "Unsupported profile; not checked cannot be interpreted as absent."
      },
    })
  }
  {
    schema: "partsieve.assessment.v1",
    input_hash: Some(pkg.audit.input_hash),
    findings,
    coverage: {
      declared_profile: pkg.audit.profile,
      rules,
      checked_rules: checked,
      unchecked_features: unchecked,
      parse_complete: true,
      parse_error: None,
    },
    decision,
    graph: Some(pkg.graph.graph),
  }
}

///|
fn failed_assessment(
  input : Bytes,
  limits : Limits,
  status : ResultStatus,
  reason : String,
) -> Assessment {
  let rules = capability_rules.map(fn(capability) {
    RuleCoverage::{
      rule_id: capability_rule(capability),
      capability,
      state: if status == IncompleteResult {
        IncompleteCheck
      } else {
        NotChecked
      },
      presence: Unknown,
      rebuild_support: NotSupported,
      reason: "Package inspection did not complete.",
    }
  })
  let profile = "simple-spreadsheet-spike-v1"
  {
    schema: "partsieve.assessment.v1",
    input_hash: if input.length() <= limits.input_bytes &&
      input.length() <= Limits::default().input_bytes {
      Some(digest(input[:]))
    } else {
      None
    },
    findings: [],
    coverage: {
      declared_profile: profile,
      rules,
      checked_rules: [],
      unchecked_features: capability_rules.map(fn(c) { c.label() }),
      parse_complete: false,
      parse_error: Some(reason),
    },
    decision: { result: status, rebuild_allowed: false, profile, reason, },
    graph: None,
  }
}

///|
// Detailed assessment returns explicit negative states, never publishable bytes.
pub fn assess(
  input : Bytes,
  limits? : Limits = Limits::default(),
) -> Assessment {
  assess_package(load_package(input, limits, enforce_profile=false)) catch {
    Invalid(reason) => failed_assessment(input, limits, Fail, reason)
    Incomplete(reason) =>
      failed_assessment(input, limits, IncompleteResult, reason)
    Refused(reason) => failed_assessment(input, limits, Unsupported, reason)
    error =>
      failed_assessment(input, limits, IncompleteResult, error.to_string())
  }
}
