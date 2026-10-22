///|
// Trusted, small public fixtures only. Production hosts must bound file reads.
fn main raise {
  for
    name in [
      "business/report-1900.xlsm", "business/report-1904.xlsm", "business/report-inline.xlsm",
      "business/document-layout.docm", "business/document-template.docm", "poi/SampleDoc.docx",
    ] {
    let input = @fs.read_file_to_bytes("tests/fixtures/" + name)
    let assessment = @sieve.assess(input)
    if assessment.decision.rebuild_allowed {
      let prepared = @sieve.prepare(input)
      let rebuilt = @sieve.rebuild_verified_with_plan(input, prepared.to_json())
      let checked = @sieve.verify_contract(rebuilt.bytes, input)
      println(
        (
          {
            "file": name,
            "result": checked.result.to_json(),
            "output_format": checked.output_format,
            "output_hash": checked.output_hash,
            "changed_parts": checked.dispositions
            .filter(fn(d) { d.classification != @sieve.BytePreservedKind })
            .length(),
          } : Json).stringify(),
      )
    } else {
      println(
        (
          {
            "file": name,
            "result": assessment.decision.result.to_json(),
            "reason": assessment.decision.reason,
            "output_published": false,
          } : Json).stringify(),
      )
    }
  }
}
