///|
// Stable, serializable facts. Indices refer to this graph's ordered arrays.
pub(all) struct XmlReference {
  source : String
  element_index : Int
  depth : Int
  element_namespace : String
  element_name : String
  attribute_name : String
  relationship_id : String
  relationship_index : Int
} derive(ToJson, Eq, Debug)

///|
pub(all) struct ImplicitReference {
  source : String
  relationship_index : Int
  semantics : String
} derive(ToJson, Eq, Debug)

///|
pub(all) struct GraphNode {
  part : String
  inbound : Array[Int]
  outbound : Array[Int]
  xml_references : Array[Int]
  reachable : Bool
} derive(ToJson, Eq, Debug)

///|
pub(all) struct ContentTypeIndex {
  content_type : String
  parts : Array[String]
} derive(ToJson, Eq, Debug)

///|
pub(all) struct PackageGraph {
  schema : String
  root : String
  parts : Array[PartRecord]
  relationships : Array[Relationship]
  xml_references : Array[XmlReference]
  implicit_references : Array[ImplicitReference]
  nodes : Array[GraphNode]
  content_types : Array[ContentTypeIndex]
  reachable : Array[String]
  orphan_candidates : Array[String]
  coverage_gaps : Array[String]
} derive(ToJson, Eq, Debug)

///|
pub extend XmlReference with ToJson::{to_json}

///|
pub extend XmlReference with Eq::{equal, not_equal}

///|
pub extend XmlReference with Debug::{to_repr}

///|
pub extend ImplicitReference with ToJson::{to_json}

///|
pub extend ImplicitReference with Eq::{equal, not_equal}

///|
pub extend ImplicitReference with Debug::{to_repr}

///|
pub extend GraphNode with ToJson::{to_json}

///|
pub extend GraphNode with Eq::{equal, not_equal}

///|
pub extend GraphNode with Debug::{to_repr}

///|
pub extend ContentTypeIndex with ToJson::{to_json}

///|
pub extend ContentTypeIndex with Eq::{equal, not_equal}

///|
pub extend ContentTypeIndex with Debug::{to_repr}

///|
pub extend PackageGraph with ToJson::{to_json}

///|
pub extend PackageGraph with Eq::{equal, not_equal}

///|
pub extend PackageGraph with Debug::{to_repr}
