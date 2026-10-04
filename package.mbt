///|
priv struct Package {
  archive : @zip.Archive
  audit : Audit
  xml_nodes : Map[String, Array[Node]]
  defaults : Map[String, String]
  overrides : Map[String, String]
}

///|
fn get_part(archive : @zip.Archive, name : String) -> BytesView raise {
  match archive.get(name[:]) {
    Some(data) => data
    None => raise Refused("required part missing: " + name)
  }
}

///|
fn load_package(input : Bytes, limits : Limits) -> Package raise {
  limits.validate()
  let zl = @zip.ReadLimits::default()
    .with_package_limit(limits.input_bytes)
    .with_entry_limit(limits.entry_bytes)
    .with_total_limit(limits.total_bytes)
    .with_entries_limit(limits.entries)
    .with_preserved_source_limit(limits.input_bytes * 2)
  let archive = @zip.read(input[:], limits=zl) catch {
    @zip.ZipError(_, message) =>
      raise Incomplete("ZIP parsing did not complete: " + message)
  }
  let names : Map[String, Bool] = Map([])
  let aliases : Map[String, Bool] = Map([])
  let ordered : Array[String] = []
  for entry in archive.entries() {
    let name = entry.name()
    check_name(name)
    guard !names.contains(name) && !aliases.contains(name.to_lower()) else {
      raise Refused("duplicate or case-equivalent part name")
    }
    names[name] = true
    aliases[name.to_lower()] = true
    ordered.push(name)
    guard @checksum.crc32(entry.data()) == entry.crc32() else {
      raise Refused("ZIP payload CRC mismatch")
    }
  }
  ordered.sort()
  let defaults : Map[String, String] = Map([])
  let overrides : Map[String, String] = Map([])
  let ct_nodes = metadata_nodes(
    get_part(archive, "[Content_Types].xml"),
    limits,
    ct_ns,
    "Types",
    ["Default", "Override"],
  )
  for i in 1..<ct_nodes.length() {
    let node = ct_nodes[i]
    let ct = attr(node, "ContentType")
    if node.element.name.local_name == "Default" {
      let ext = attr(node, "Extension")
      guard valid_segment(ext) &&
        !ext.contains(".") &&
        ext == ext.to_lower() &&
        !defaults.contains(ext) else {
        raise Refused("duplicate/unsupported default content type")
      }
      defaults[ext] = ct
      validate_metadata_attributes(node, ["Extension", "ContentType"])
    } else {
      let path = attr(node, "PartName")
      guard path.has_prefix("/") else {
        raise Refused("override PartName must be absolute")
      }
      let name = path[1:].to_owned()
      check_name(name)
      guard names.contains(name) && !overrides.contains(name) else {
        raise Refused("duplicate override or override for missing part")
      }
      overrides[name] = ct
      validate_metadata_attributes(node, ["PartName", "ContentType"])
    }
  }
  let parts : Array[PartRecord] = []
  let nodes : Map[String, Array[Node]] = Map([])
  let mut total_nodes = 0
  let mut total_attributes = 0
  for name in ordered {
    let ct = if name == "[Content_Types].xml" {
      "application/xml"
    } else {
      match overrides.get(name) {
        Some(t) => t
        None =>
          match name.rev_split_once(".") {
            Some((_, extension)) =>
              match defaults.get(extension.to_owned()) {
                Some(t) => t
                None => raise Refused("part has no content type")
              }
            None => raise Refused("part has no content type")
          }
      }
    }
    let data = get_part(archive, name)
    parts.push({ name, content_type: ct, sha256: digest(data), })
    if name.has_suffix(".xml") || name.has_suffix(".rels") {
      let parsed = read_xml(data, limits)
      guard parsed.length() > 0 else { raise Refused("XML root missing") }
      total_nodes += parsed.length()
      for node in parsed {
        total_attributes += node.element.attributes.length()
      }
      guard total_nodes <= 1000000 && total_attributes <= 1000000 else {
        raise Incomplete("package XML aggregate limit")
      }
      nodes[name] = parsed
    }
  }
  let relationships : Array[Relationship] = []
  for name in ordered {
    if !name.has_suffix(".rels") {
      continue
    }
    let source = relationship_source(name)
    guard source == "/" || names.contains(source) else {
      raise Refused("relationship source missing")
    }
    let local_ids : Map[String, Bool] = Map([])
    let rels = metadata_nodes(
      get_part(archive, name),
      limits,
      rel_ns,
      "Relationships",
      ["Relationship"],
    )
    for i in 1..<rels.length() {
      guard relationships.length() < 32768 else {
        raise Incomplete("relationship limit")
      }
      let node = rels[i]
      validate_metadata_attributes(node, ["Id", "Type", "Target", "TargetMode"])
      let id = attr(node, "Id")
      guard id.length() > 0 && id.length() <= 1024 && !local_ids.contains(id) else {
        raise Refused("duplicate or invalid local relationship ID")
      }
      local_ids[id] = true
      let kind = attr(node, "Type")
      let target = attr(node, "Target")
      let mode = attr_opt(node, "TargetMode").unwrap_or("Internal")
      guard mode == "Internal" || mode == "External" else {
        raise Refused("invalid target mode")
      }
      let external = mode == "External"
      let resolved = if external { "" } else { resolve_target(source, target) }
      guard external || names.contains(resolved) else {
        raise Refused("internal target missing")
      }
      relationships.push({ source, id, kind, target, resolved, external, })
    }
  }
  let mains = relationships.filter(fn(r) {
    r.source == "/" && r.kind == office_rel + "officeDocument"
  })
  guard mains.length() == 1 && !mains[0].external else {
    raise Refused("exactly one internal office main required")
  }
  let main = mains[0].resolved
  let main_ct = parts.filter(fn(p) { p.name == main })[0].content_type
  guard main_ct == xlsm_ct || main_ct == xlsx_ct else {
    raise Refused("unsupported main document type")
  }
  let findings : Array[Finding] = []
  for p in parts {
    if p.content_type == vba_ct {
      let incoming = relationships.filter(fn(r) {
        !r.external && r.resolved == p.name
      })
      findings.push({
        rule: "vba-v1",
        capability: "VBA",
        part: p.name,
        evidence: ["content-type:" + vba_ct] +
        incoming.map(fn(r) {
          "relationship:" + r.source + "#" + r.id + ":" + r.kind
        }),
      })
    }
  }
  let report : Audit = {
    schema: "partsieve.audit.spike-v1",
    input_hash: digest(input[:]),
    format: if main_ct == xlsm_ct {
      "XLSM"
    } else {
      "XLSX"
    },
    main_part: main,
    coverage: "CompleteWithinProfile",
    profile: "simple-spreadsheet-spike-v1",
    checked_rules: [
      "bounded-zip-v1", "crc-v1", "opc-subset-v1", "namespace-xml-v1", "vba-v1",
      "profile-v1",
    ],
    limitations: [
      "Restricted element/part allowlist; formulas, hyperlinks, drawings, controls, signatures and unknown extensions refused.",
      "No VBA execution or malicious-code analysis. No visual fidelity claim. Client/SDK checks recorded separately.",
    ],
    parts,
    relationships,
    findings,
  }
  let pkg = { archive, audit: report, xml_nodes: nodes, defaults, overrides, }
  validate_profile(pkg)
  pkg
}

///|
fn validate_metadata_attributes(
  node : Node,
  permitted : Array[String],
) -> Unit raise {
  for a in node.element.attributes {
    guard a.name.namespace_uri is None && permitted.contains(a.name.local_name) else {
      raise Refused("unsupported metadata attribute")
    }
  }
}

///|
pub fn audit(
  input : Bytes,
  limits? : Limits = Limits::default(),
) -> Audit raise {
  load_package(input, limits).audit
}
