///|
pub(all) enum PlanOperationKind {
  RemovePart
  RemoveRelationship
  RewriteSourceXml
  RewriteRelationshipPart
  RewriteContentTypes
  ChangeMainContentType
} derive(Eq, Debug)

///|
fn PlanOperationKind::label(self : PlanOperationKind) -> String {
  match self {
    RemovePart => "RemovePart"
    RemoveRelationship => "RemoveRelationship"
    RewriteSourceXml => "RewriteSourceXml"
    RewriteRelationshipPart => "RewriteRelationshipPart"
    RewriteContentTypes => "RewriteContentTypes"
    ChangeMainContentType => "ChangeMainContentType"
  }
}

///|
impl ToJson for PlanOperationKind with fn to_json(self) -> Json {
  self.label().to_json()
}

///|
pub(all) enum PolicyAction {
  AllowAction
  RemoveAction
  RefuseAction
} derive(Eq, Debug)

///|
impl ToJson for PolicyAction with fn to_json(self) -> Json {
  (match self {
    AllowAction => "Allow"
    RemoveAction => "Remove"
    RefuseAction => "Refuse"
  }).to_json()
}

///|
pub(all) struct PolicyDecision {
  decision_id : String
  finding_index : Int?
  action : PolicyAction
  rule_id : String
  part : String
  reason : String
} derive(ToJson, Eq, Debug)

///|
pub(all) struct CheckedOperation {
  operation_id : String
  kind : PlanOperationKind
  part : String
  source : String
  relationship_id : String
  rule_id : String
  decision_id : String
  before_hash : String
  expected_after_hash : String?
  depends_on : Array[String]
  reason : String
} derive(ToJson, Eq, Debug)

///|
pub(all) struct PreparedPlan {
  schema : String
  tool : String
  rules : String
  input_hash : String
  input_format : String
  output_format : String
  policy : String
  profile : String
  limits : Limits
  preconditions : Array[PartRecord]
  findings : Array[CapabilityFinding]
  decisions : Array[PolicyDecision]
  operations : Array[CheckedOperation]
  controlled_removals : Array[String]
  orphan_candidates : Array[String]
  coverage : Coverage
  gate : Decision
  unavailable_handlers : Array[String]
} derive(ToJson, Eq, Debug)

///|
pub extend PlanOperationKind with ToJson::{to_json}

///|
pub extend PolicyAction with ToJson::{to_json}

///|
pub extend PolicyDecision with ToJson::{to_json}

///|
pub extend CheckedOperation with ToJson::{to_json}

///|
pub extend PreparedPlan with ToJson::{to_json}

///|
pub extend PlanOperationKind with Eq::{equal, not_equal}

///|
pub extend PlanOperationKind with Debug::{to_repr}

///|
pub extend PolicyAction with Eq::{equal, not_equal}

///|
pub extend PolicyAction with Debug::{to_repr}

///|
pub extend PolicyDecision with Eq::{equal, not_equal}

///|
pub extend PolicyDecision with Debug::{to_repr}

///|
pub extend CheckedOperation with Eq::{equal, not_equal}

///|
pub extend CheckedOperation with Debug::{to_repr}

///|
pub extend PreparedPlan with Eq::{equal, not_equal}

///|
pub extend PreparedPlan with Debug::{to_repr}
