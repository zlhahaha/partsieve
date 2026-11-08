///|
// Trusted test fixture only. Production hosts must limit file reads first.
fn main raise {
  let input = @fs.read_file_to_bytes("tests/fixtures/upstream/macro01.xlsm")
  match @sieve.clean_document(input) {
    Ok(rebuilt) =>
      println(
        (
          {
            "output_format": rebuilt.receipt.output_format,
            "result": rebuilt.receipt.result.to_json(),
            "output_hash": rebuilt.receipt.output_hash,
          } : Json).stringify(),
      )
    Err(error) => println(error.to_json().stringify())
  }
}
