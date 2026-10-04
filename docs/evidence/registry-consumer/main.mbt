///|
fn main raise {
  let bytes = @fs.read_file_to_bytes("fixture.xlsm")
  let audit = @sieve.audit(bytes)
  let rebuilt = @sieve.rebuild(bytes)
  let rechecked = @sieve.verify(rebuilt.bytes, bytes)
  assert_eq(audit.format, "XLSM")
  assert_eq(audit.findings.length(), 1)
  assert_eq(rechecked.output_format, "XLSX")
  assert_eq(rechecked.preservation, "Pass")
  assert_eq(rechecked.output_hash, "fcc9a0ca93810d894df21c71d5764db7252afd3b1232b5aef55c21f3efcc9e53")
  println("Published SDK: audit/rebuild/verify Pass")
}
