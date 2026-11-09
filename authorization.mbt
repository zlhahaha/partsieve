///|
pub(all) enum ChangeKind {
  VbaRemoval
  OleRemoval
  TemplateRemoval
  MacroFormatConversion
} derive(Eq, Debug)

///|
pub extend ChangeKind with Eq::{equal, not_equal}

///|
pub extend ChangeKind with Debug::{to_repr}

///|
pub extend ChangeKind with ToJson::{to_json}

///|
pub fn ChangeKind::label(self : ChangeKind) -> String {
  match self {
    VbaRemoval => "vba_removal"
    OleRemoval => "ole_removal"
    TemplateRemoval => "remote_template_removal"
    MacroFormatConversion => "macro_format_conversion"
  }
}

///|
pub impl ToJson for ChangeKind with fn to_json(self) -> Json {
  self.label().to_json()
}

///|
pub(all) struct ContentChange {
  kind : ChangeKind
  count : Int
  removed_parts : Array[String]
  effect : String
} derive(Eq, Debug, ToJson)

///|
pub extend ContentChange with Eq::{equal, not_equal}

///|
pub extend ContentChange with Debug::{to_repr}

///|
pub extend ContentChange with ToJson::{to_json}

///|
pub(all) struct ChangeSummary {
  changes : Array[ContentChange]
  removed_parts : Array[String]
  rewritten_parts : Array[String]
} derive(Eq, Debug, ToJson)

///|
pub extend ChangeSummary with Eq::{equal, not_equal}

///|
pub extend ChangeSummary with Debug::{to_repr}

///|
pub extend ChangeSummary with ToJson::{to_json}

///|
/// These flags cover only the exact reviewed plan, never arbitrary future inputs.
pub(all) struct RemovalPermissions {
  remove_vba : Bool
  remove_ole : Bool
  remove_remote_template : Bool
  convert_macro_format : Bool
} derive(Eq, Debug, ToJson)

///|
pub extend RemovalPermissions with Eq::{equal, not_equal}

///|
pub extend RemovalPermissions with Debug::{to_repr}

///|
pub extend RemovalPermissions with ToJson::{to_json}

///|
pub fn RemovalPermissions::deny_all() -> RemovalPermissions {
  {
    remove_vba: false,
    remove_ole: false,
    remove_remote_template: false,
    convert_macro_format: false,
  }
}

///|
pub fn RemovalPermissions::macros_only() -> RemovalPermissions {
  {
    remove_vba: true,
    remove_ole: false,
    remove_remote_template: false,
    convert_macro_format: true,
  }
}

///|
pub fn RemovalPermissions::all_supported() -> RemovalPermissions {
  {
    remove_vba: true,
    remove_ole: true,
    remove_remote_template: true,
    convert_macro_format: true,
  }
}

///|
pub fn RemovalPermissions::allows(
  self : RemovalPermissions,
  kind : ChangeKind,
) -> Bool {
  match kind {
    VbaRemoval => self.remove_vba
    OleRemoval => self.remove_ole
    TemplateRemoval => self.remove_remote_template
    MacroFormatConversion => self.convert_macro_format
  }
}

///|
/// Opaque in-memory review. Getters never expose its mutable plan/summary arrays.
pub struct DocumentPreview {
  priv plan : PreparedPlan
  priv changes : ChangeSummary
  priv plan_hash : String
}

///|
/// Trusted application decision, not a signed credential or client JSON token.
pub struct DocumentAuthorization {
  priv plan : PreparedPlan
  priv changes : ChangeSummary
  priv plan_hash : String
  priv permissions : RemovalPermissions
}

///|
pub(all) struct AuthorizationRecord {
  schema : String
  input_hash : String
  plan_hash : String
  output_hash : String
  permissions : RemovalPermissions
  summary : ChangeSummary
} derive(Eq, Debug, ToJson)

///|
pub extend AuthorizationRecord with Eq::{equal, not_equal}

///|
pub extend AuthorizationRecord with Debug::{to_repr}

///|
pub extend AuthorizationRecord with ToJson::{to_json}

///|
pub(all) struct AuthorizedRebuilt {
  bytes : Bytes
  receipt : VerifiedReceipt
  authorization : AuthorizationRecord
}

///|
fn copy_change_summary(summary : ChangeSummary) -> ChangeSummary {
  {
    changes: summary.changes.map(change => {
      ..change,
      removed_parts: change.removed_parts.map(part => part),
    }),
    removed_parts: summary.removed_parts.map(part => part),
    rewritten_parts: summary.rewritten_parts.map(part => part),
  }
}

///|
pub fn DocumentPreview::summary(self : DocumentPreview) -> ChangeSummary {
  copy_change_summary(self.changes)
}

///|
pub fn DocumentPreview::input_hash(self : DocumentPreview) -> String {
  self.plan.input_hash
}

///|
pub fn DocumentPreview::plan_hash(self : DocumentPreview) -> String {
  self.plan_hash
}

///|
/// Detached plan data for display/storage. This JSON is not authorization.
pub fn DocumentPreview::plan_json(self : DocumentPreview) -> Json {
  self.plan.to_json()
}

///|
pub fn DocumentPreview::to_json(self : DocumentPreview) -> Json {
  {
    "schema": "partsieve.document-preview.v1",
    "input_hash": self.plan.input_hash,
    "plan_hash": self.plan_hash,
    "input_format": self.plan.input_format,
    "output_format": self.plan.output_format,
    "summary": self.changes.to_json(),
  }
}

///|
fn summary_from_plan(pkg : Package, plan : PreparedPlan) -> ChangeSummary raise {
  let removed : Array[String] = []
  let rewritten : Array[String] = []
  for op in plan.operations {
    pkg.control.checkpoint("review-operation", 1)
    guard ["vba-v1", "ole-v1", "remote-template-v1", "format-v1"].contains(
      op.rule_id,
    ) else {
      raise Refused("plan contains an unmodeled change category")
    }
    if op.kind == RemovePart && !removed.contains(op.part) {
      removed.push(op.part)
    }
    if op.kind != RemovePart &&
      operation_writes(op.kind) &&
      !rewritten.contains(op.part) {
      rewritten.push(op.part)
    }
  }
  removed.sort()
  rewritten.sort()
  let changes : Array[ContentChange] = []
  for
    (kind, rule, count, effect) in [
      (
        VbaRemoval,
        "vba-v1",
        pkg.audit.parts.filter(part => part.content_type == vba_ct).length(),
        "VBA projects and exclusively owned support data are removed; macro functionality is lost.",
      ),
      (
        OleRemoval,
        "ole-v1",
        ole_relationships(pkg).length(),
        "Embedded contents, object editing capability and exclusively owned preview images are removed.",
      ),
      (
        TemplateRemoval,
        "remote-template-v1",
        pkg.audit.relationships.filter(is_template_relationship).length(),
        "The attached external template and its local reference are removed; the target is not fetched.",
      ),
      (
        MacroFormatConversion,
        "format-v1",
        if is_macro_format(plan.input_format) {
          1
        } else {
          0
        },
        "Macro-enabled main type becomes ordinary DOCX/XLSX; this does not mean VBA was present.",
      ),
    ] {
    if count > 0 {
      let parts = plan.operations
        .filter(op => op.kind == RemovePart && op.rule_id == rule)
        .map(op => op.part)
      parts.sort()
      changes.push({ kind, count, removed_parts: parts, effect, })
    }
    guard !plan.operations.any(op => op.rule_id == rule) || count > 0 else {
      raise Invalid("plan operation has no modeled content change")
    }
  }
  let expected_removed = plan.controlled_removals.map(part => part)
  expected_removed.sort()
  guard removed == expected_removed else {
    raise Invalid(
      "change summary does not account for all controlled deletions",
    )
  }
  { changes, removed_parts: removed, rewritten_parts: rewritten, }
}

///|
fn authorization_denial(
  summary : ChangeSummary,
  permissions : RemovalPermissions,
  operation : SdkOperation,
) -> SdkFailure? {
  for change in summary.changes {
    if !permissions.allows(change.kind) {
      return Some({
        code: AuthorizationDenied,
        operation,
        message: "permission required for " + change.kind.label(),
      })
    }
  }
  None
}

///|
fn reviewed_plan_hash(
  plan : PreparedPlan,
  control : WorkControl,
) -> String raise {
  work_digest(@utf8.encode(plan.to_json().stringify()[:])[:], control)
}

///|
pub fn preview_document(
  input : Bytes,
  limits? : Limits = Limits::default(),
  control? : WorkControl = WorkControl::default(),
) -> Result[DocumentPreview, SdkFailure] {
  let operation = PreviewDocument
  if sdk_preflight(input, None, limits, control, operation) is Some(error) {
    return Err(error)
  }
  try {
    let pkg = load_package(input, limits, control~)
    let plan = make_prepared_plan(pkg, limits)
    let changes = summary_from_plan(pkg, plan)
    let plan_hash = reviewed_plan_hash(plan, control)
    // Reserve the final source check before the last user callback. Hash after
    // that callback, with no further callbacks before returning the review.
    control.checkpoint("review-complete", input.length())
    guard digest(input[:]) == plan.input_hash else {
      raise Invalid("source changed during content preview")
    }
    Ok({ plan, changes, plan_hash, })
  } catch {
    error => Err(sdk_failure(error, operation, control))
  }
}

///|
/// Called by the trusted application after its own decision/confirmation.
pub fn authorize_document(
  preview : DocumentPreview,
  permissions : RemovalPermissions,
) -> Result[DocumentAuthorization, SdkFailure] {
  if authorization_denial(preview.changes, permissions, AuthorizeDocument)
    is Some(error) {
    return Err(error)
  }
  Ok({
    plan: preview.plan,
    changes: preview.changes,
    plan_hash: preview.plan_hash,
    permissions,
  })
}

///|
/// Recompute the actual plan and losses, enforce permissions, then execute/verify.
pub fn execute_authorized_document(
  input : Bytes,
  authorization : DocumentAuthorization,
  control? : WorkControl = WorkControl::default(),
) -> Result[AuthorizedRebuilt, SdkFailure] {
  let operation = ExecuteAuthorizedDocument
  let limits = authorization.plan.limits
  if sdk_preflight(input, None, limits, control, operation) is Some(error) {
    return Err(error)
  }
  try {
    let pkg = load_package(input, limits, control~)
    let actual = make_prepared_plan(pkg, limits)
    let changes = summary_from_plan(pkg, actual)
    guard actual == authorization.plan &&
      changes == authorization.changes &&
      reviewed_plan_hash(actual, control) == authorization.plan_hash else {
      raise Invalid(
        "authorization differs from the actual source-bound plan or content changes",
      )
    }
    if authorization_denial(changes, authorization.permissions, operation)
      is Some(error) {
      return Err(error)
    }
    control.checkpoint("authorization-checked", 0)
    let bytes = execute_prepared(pkg, actual, limits)
    let receipt = verify_contract(bytes, input, limits~, control~)
    // Callback code can retain a mutable reference to the caller's original.
    // Complete all callbacks first, then rebind the actual bytes without another
    // callback between the final hashes and successful return.
    control.checkpoint(
      "authorization-complete",
      input.length() + bytes.length(),
    )
    guard receipt.input_hash == authorization.plan.input_hash &&
      receipt.plan == actual &&
      digest(input[:]) == authorization.plan.input_hash &&
      digest(bytes[:]) == receipt.output_hash else {
      raise Invalid(
        "authorized source, verified plan or output changed before completion",
      )
    }
    let record : AuthorizationRecord = {
      schema: "partsieve.authorization-record.v1",
      input_hash: receipt.input_hash,
      plan_hash: authorization.plan_hash,
      output_hash: receipt.output_hash,
      permissions: authorization.permissions,
      summary: copy_change_summary(changes),
    }
    Ok({ bytes, receipt, authorization: record, })
  } catch {
    error => Err(sdk_failure(error, operation, control))
  }
}
