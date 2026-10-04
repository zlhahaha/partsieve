///|
pub(all) enum PreservationKind {
  BytePreservedKind
  SemanticallyRewrittenKind
  RemovedByPolicyKind
  RegeneratedMetadataKind
} derive(Eq, Debug)

///|
impl ToJson for PreservationKind with fn to_json(self) -> Json {
  (match self {
    BytePreservedKind => "BytePreserved"
    SemanticallyRewrittenKind => "SemanticallyRewritten"
    RemovedByPolicyKind => "RemovedByPolicy"
    RegeneratedMetadataKind => "RegeneratedMetadata"
  }).to_json()
}

///|
pub(all) struct ContractDisposition {
  part : String
  classification : PreservationKind
  before_hash : String
  after_hash : String?
  decision_id : String?
  rule_id : String?
  reason : String
} derive(ToJson, Eq, Debug)

///|
pub(all) struct VerificationCheck {
  check_id : String
  state : CheckState
  result : ResultStatus?
  detail : String
} derive(ToJson, Eq, Debug)

///|
pub(all) struct VerifiedReceipt {
  schema : String
  tool : String
  rules : String
  policy : String
  profile : String
  input_hash : String
  output_hash : String
  input_size : Int
  output_size : Int
  input_format : String
  output_format : String
  limits : Limits
  input_coverage : Coverage
  output_coverage : Coverage
  findings : Array[CapabilityFinding]
  output_findings : Array[CapabilityFinding]
  decisions : Array[PolicyDecision]
  allowed_capabilities : Array[CapabilityFinding]
  plan : PreparedPlan
  dispositions : Array[ContractDisposition]
  checks : Array[VerificationCheck]
  result : ResultStatus
  independent_validation : CheckState
  independent_tools : Array[String]
  limitations : Array[String]
} derive(ToJson, Eq, Debug)

///|
pub(all) struct VerifiedRebuilt {
  bytes : Bytes
  receipt : VerifiedReceipt
}

///|
pub extend PreservationKind with ToJson::{to_json}

///|
pub extend PreservationKind with Eq::{equal, not_equal}

///|
pub extend PreservationKind with Debug::{to_repr}

///|
pub extend ContractDisposition with ToJson::{to_json}

///|
pub extend ContractDisposition with Eq::{equal, not_equal}

///|
pub extend ContractDisposition with Debug::{to_repr}

///|
pub extend VerificationCheck with ToJson::{to_json}

///|
pub extend VerificationCheck with Eq::{equal, not_equal}

///|
pub extend VerificationCheck with Debug::{to_repr}

///|
pub extend VerifiedReceipt with ToJson::{to_json}

///|
pub extend VerifiedReceipt with Eq::{equal, not_equal}

///|
pub extend VerifiedReceipt with Debug::{to_repr}
