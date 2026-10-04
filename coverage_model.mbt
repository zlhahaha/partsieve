///|
pub(all) enum ResultStatus {
  Pass
  Fail
  IncompleteResult
  Unsupported
} derive(Eq, Debug)

///|
impl ToJson for ResultStatus with fn to_json(self) -> Json {
  (match self {
    Pass => "Pass"
    Fail => "Fail"
    IncompleteResult => "Incomplete"
    Unsupported => "Unsupported"
  }).to_json()
}

///|
pub(all) enum CheckState {
  Checked
  NotChecked
  IncompleteCheck
  Opaque
} derive(Eq, Debug)

///|
impl ToJson for CheckState with fn to_json(self) -> Json {
  (match self {
    Checked => "Checked"
    NotChecked => "NotChecked"
    IncompleteCheck => "Incomplete"
    Opaque => "Opaque"
  }).to_json()
}

///|
pub(all) enum Presence {
  Present
  Absent
  Unknown
} derive(Eq, Debug)

///|
impl ToJson for Presence with fn to_json(self) -> Json {
  (match self {
    Present => "Present"
    Absent => "Absent"
    Unknown => "Unknown"
  }).to_json()
}

///|
pub(all) enum Certainty {
  Declared
  Uncertain
} derive(Eq, Debug)

///|
impl ToJson for Certainty with fn to_json(self) -> Json {
  (match self {
    Declared => "Declared"
    Uncertain => "Unknown"
  }).to_json()
}

///|
pub(all) enum RebuildSupport {
  Supported
  NotSupported
} derive(Eq, Debug)

///|
impl ToJson for RebuildSupport with fn to_json(self) -> Json {
  (match self {
    Supported => "Supported"
    NotSupported => "Unsupported"
  }).to_json()
}

///|
pub(all) enum Capability {
  Vba
  HttpHyperlink
  RemoteTemplate
  ExternalResource
  ExternalData
  Ole
  ActiveX
  UnknownExternalRelationship
  UnknownPotentiallyActiveExtension
} derive(Eq, Debug)

///|
fn Capability::label(self : Capability) -> String {
  match self {
    Vba => "VBA"
    HttpHyperlink => "HTTPHyperlink"
    RemoteTemplate => "RemoteTemplate"
    ExternalResource => "ExternalResource"
    ExternalData => "ExternalData"
    Ole => "OLE"
    ActiveX => "ActiveX"
    UnknownExternalRelationship => "UnknownExternalRelationship"
    UnknownPotentiallyActiveExtension => "UnknownPotentiallyActiveExtension"
  }
}

///|
impl ToJson for Capability with fn to_json(self) -> Json {
  self.label().to_json()
}

///|
pub(all) struct CapabilityFinding {
  rule_id : String
  capability : Capability
  source : String
  part : String
  certainty : Certainty
  rebuild_support : RebuildSupport
  evidence : Array[String]
} derive(ToJson, Eq, Debug)

///|
pub(all) struct RuleCoverage {
  rule_id : String
  capability : Capability
  state : CheckState
  presence : Presence
  rebuild_support : RebuildSupport
  reason : String
} derive(ToJson, Eq, Debug)

///|
pub(all) struct Coverage {
  declared_profile : String
  rules : Array[RuleCoverage]
  checked_rules : Array[String]
  unchecked_features : Array[String]
  parse_complete : Bool
  parse_error : String?
} derive(ToJson, Eq, Debug)

///|
pub(all) struct Decision {
  result : ResultStatus
  rebuild_allowed : Bool
  profile : String
  reason : String
} derive(ToJson, Eq, Debug)

///|
pub(all) struct Assessment {
  schema : String
  input_hash : String?
  findings : Array[CapabilityFinding]
  coverage : Coverage
  decision : Decision
  graph : PackageGraph?
} derive(ToJson, Eq, Debug)

///|
pub extend ResultStatus with ToJson::{to_json}

///|
pub extend ResultStatus with Eq::{equal, not_equal}

///|
pub extend ResultStatus with Debug::{to_repr}

///|
pub extend CheckState with ToJson::{to_json}

///|
pub extend CheckState with Eq::{equal, not_equal}

///|
pub extend CheckState with Debug::{to_repr}

///|
pub extend Presence with ToJson::{to_json}

///|
pub extend Presence with Eq::{equal, not_equal}

///|
pub extend Presence with Debug::{to_repr}

///|
pub extend Certainty with ToJson::{to_json}

///|
pub extend Certainty with Eq::{equal, not_equal}

///|
pub extend Certainty with Debug::{to_repr}

///|
pub extend RebuildSupport with ToJson::{to_json}

///|
pub extend RebuildSupport with Eq::{equal, not_equal}

///|
pub extend RebuildSupport with Debug::{to_repr}

///|
pub extend Capability with ToJson::{to_json}

///|
pub extend Capability with Eq::{equal, not_equal}

///|
pub extend Capability with Debug::{to_repr}

///|
pub extend CapabilityFinding with ToJson::{to_json}

///|
pub extend CapabilityFinding with Eq::{equal, not_equal}

///|
pub extend CapabilityFinding with Debug::{to_repr}

///|
pub extend RuleCoverage with ToJson::{to_json}

///|
pub extend RuleCoverage with Eq::{equal, not_equal}

///|
pub extend RuleCoverage with Debug::{to_repr}

///|
pub extend Coverage with ToJson::{to_json}

///|
pub extend Coverage with Eq::{equal, not_equal}

///|
pub extend Coverage with Debug::{to_repr}

///|
pub extend Decision with ToJson::{to_json}

///|
pub extend Decision with Eq::{equal, not_equal}

///|
pub extend Decision with Debug::{to_repr}

///|
pub extend Assessment with ToJson::{to_json}

///|
pub extend Assessment with Eq::{equal, not_equal}

///|
pub extend Assessment with Debug::{to_repr}
