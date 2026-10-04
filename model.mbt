///|
pub(all) suberror SieveError {
  Refused(String)
  Incomplete(String)
} derive(Debug)

///|
pub(all) struct Limits {
  input_bytes : Int
  entry_bytes : Int
  total_bytes : Int
  entries : Int
  xml_bytes : Int
  xml_depth : Int
  xml_nodes : Int
  xml_attributes : Int
  output_bytes : Int
} derive(ToJson, Eq, Debug)

///|
pub fn Limits::default() -> Limits {
  {
    input_bytes: 33554432,
    entry_bytes: 33554432,
    total_bytes: 134217728,
    entries: 4096,
    xml_bytes: 8388608,
    xml_depth: 128,
    xml_nodes: 200000,
    xml_attributes: 400000,
    output_bytes: 67108864,
  }
}

///|
fn Limits::validate(self : Limits) -> Unit raise {
  let hard = Limits::default()
  guard self.input_bytes > 0 &&
    self.input_bytes <= hard.input_bytes &&
    self.entry_bytes > 0 &&
    self.entry_bytes <= hard.entry_bytes &&
    self.total_bytes > 0 &&
    self.total_bytes <= hard.total_bytes &&
    self.entries > 0 &&
    self.entries <= hard.entries &&
    self.xml_bytes > 0 &&
    self.xml_bytes <= hard.xml_bytes &&
    self.xml_depth > 0 &&
    self.xml_depth <= hard.xml_depth &&
    self.xml_nodes > 0 &&
    self.xml_nodes <= hard.xml_nodes &&
    self.xml_attributes > 0 &&
    self.xml_attributes <= hard.xml_attributes &&
    self.output_bytes > 0 &&
    self.output_bytes <= hard.output_bytes else {
    raise Refused("invalid limits or limit exceeds prototype hard ceiling")
  }
}

///|
pub(all) struct PartRecord {
  name : String
  content_type : String
  sha256 : String
} derive(ToJson, Eq, Debug)

///|
pub(all) struct Relationship {
  source : String
  id : String
  kind : String
  target : String
  resolved : String
  external : Bool
} derive(ToJson, Eq, Debug)

///|
pub(all) struct Finding {
  rule : String
  capability : String
  part : String
  evidence : Array[String]
} derive(ToJson, Eq, Debug)

///|
pub(all) struct Audit {
  schema : String
  input_hash : String
  format : String
  main_part : String
  coverage : String
  profile : String
  checked_rules : Array[String]
  limitations : Array[String]
  parts : Array[PartRecord]
  relationships : Array[Relationship]
  findings : Array[Finding]
} derive(ToJson, Eq, Debug)

///|
pub(all) struct Operation {
  kind : String
  part : String
  relationship_id : String
  rule : String
  reason : String
} derive(ToJson, Eq, Debug)

///|
pub(all) struct RewritePlan {
  schema : String
  input_hash : String
  policy : String
  profile : String
  operations : Array[Operation]
} derive(ToJson, Eq, Debug)

///|
pub(all) struct Disposition {
  part : String
  classification : String
  before_hash : String
  after_hash : String?
} derive(ToJson, Eq, Debug)

///|
pub(all) struct Receipt {
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
  audit : Audit
  plan : RewritePlan
  dispositions : Array[Disposition]
  structure : String
  preservation : String
  independent_validation : String
  limitations : Array[String]
} derive(ToJson, Eq, Debug)

///|
pub(all) struct Rebuilt {
  bytes : Bytes
  receipt : Receipt
}

///|
pub fn digest(bytes : BytesView) -> String {
  @crypto.bytes_to_hex_string(@crypto.sha256(bytes))
}

///|
let ct_ns = "http://schemas.openxmlformats.org/package/2006/content-types"

///|
let rel_ns = "http://schemas.openxmlformats.org/package/2006/relationships"

///|
let office_rel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/"

///|
let vba_rel = "http://schemas.microsoft.com/office/2006/relationships/vbaProject"

///|
let vba_ct = "application/vnd.ms-office.vbaProject"

///|
let xlsm_ct = "application/vnd.ms-excel.sheet.macroEnabled.main+xml"

///|
let xlsx_ct = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"

///|
pub extend Limits with ToJson::{to_json}

///|
pub extend Limits with Eq::{equal, not_equal}

///|
pub extend Limits with Debug::{to_repr}

///|
pub extend PartRecord with ToJson::{to_json}

///|
pub extend PartRecord with Eq::{equal, not_equal}

///|
pub extend PartRecord with Debug::{to_repr}

///|
pub extend Relationship with ToJson::{to_json}

///|
pub extend Relationship with Eq::{equal, not_equal}

///|
pub extend Relationship with Debug::{to_repr}

///|
pub extend Finding with ToJson::{to_json}

///|
pub extend Finding with Eq::{equal, not_equal}

///|
pub extend Finding with Debug::{to_repr}

///|
pub extend Audit with ToJson::{to_json}

///|
pub extend Audit with Eq::{equal, not_equal}

///|
pub extend Audit with Debug::{to_repr}

///|
pub extend Operation with ToJson::{to_json}

///|
pub extend Operation with Eq::{equal, not_equal}

///|
pub extend Operation with Debug::{to_repr}

///|
pub extend RewritePlan with ToJson::{to_json}

///|
pub extend RewritePlan with Eq::{equal, not_equal}

///|
pub extend RewritePlan with Debug::{to_repr}

///|
pub extend Disposition with ToJson::{to_json}

///|
pub extend Disposition with Eq::{equal, not_equal}

///|
pub extend Disposition with Debug::{to_repr}

///|
pub extend Receipt with ToJson::{to_json}

///|
pub extend Receipt with Eq::{equal, not_equal}

///|
pub extend Receipt with Debug::{to_repr}

///|
pub extend SieveError with Debug::{to_repr}
