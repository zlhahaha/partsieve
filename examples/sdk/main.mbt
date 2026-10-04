///|
// Trusted test fixture only. Production hosts must limit file reads first.
fn main raise {
  let input = @fs.read_file_to_bytes("tests/fixtures/upstream/macro01.xlsm")
  let report = @sieve.audit(input)
  let plan = @sieve.plan(input)
  let rebuilt = @sieve.rebuild(input)
  let rechecked = @sieve.verify(rebuilt.bytes, input)
  let summary : Json = {
    "input_format": report.format,
    "findings": report.findings.length(),
    "operations": plan.operations.length(),
    "output_format": rechecked.output_format,
    "preservation": rechecked.preservation,
    "output_hash": rechecked.output_hash,
  }
  println(summary.stringify())
}
