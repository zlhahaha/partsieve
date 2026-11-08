///|
// One-call intake path. File IO remains a host responsibility.
fn main raise {
  for
    name in [
      "business/report-1900.xlsm", "business/report-1904.xlsm", "business/report-inline.xlsm",
      "business/document-layout.docm", "business/document-template.docm", "poi/SampleDoc.docx",
    ] {
    let input = @host.read_bounded("tests/fixtures/" + name, 33554432)
    match @sieve.clean_document(input) {
      Ok(rebuilt) => {
        assert_true(name != "poi/SampleDoc.docx")
        let checked = rebuilt.receipt
        assert_eq(checked.result, @sieve.Pass)
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
      }
      Err(error) => {
        assert_eq(name, "poi/SampleDoc.docx", msg=error.message)
        assert_eq(error.code, @sieve.UnsupportedDocument)
        assert_eq(error.operation, @sieve.CleanDocument)
        println(
          (
            {
              "file": name,
              "code": error.code.to_json(),
              "operation": error.operation.to_json(),
              "reason": error.message,
              "output_published": false,
            } : Json).stringify(),
        )
      }
    }
  }
}
