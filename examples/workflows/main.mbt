///|
fn main raise {
  let input = @host.read_bounded(
    "tests/fixtures/business/document-template.docm", 33554432,
  )
  // 1. Intake: returned bytes already have an independently recomputed receipt.
  let cleaned = match @sieve.clean_document(input) {
    Ok(value) => value
    Err(error) => fail(error.to_json().stringify())
  }
  assert_eq(cleaned.receipt.result, @sieve.Pass)
  println("Intake Pass: one clean_document call")
  // 2. Caller-reviewed workflow. The example automatically accepts a trusted
  // fixture. A real application can retain the plan pending its own decision.
  let control = @sieve.WorkControl::new(work_units=50000000)
  let plan = match @sieve.prepare_document(input, control~) {
    Ok(value) => value
    Err(error) => fail(error.to_json().stringify())
  }
  let delivered = match
    @sieve.execute_document_plan(input, plan.to_json(), control~) {
    Ok(value) => value
    Err(error) => fail(error.to_json().stringify())
  }
  assert_eq(delivered.bytes, cleaned.bytes)
  println("Prepared plan Pass: shared budget and source-bound execution")
  // 3. Archive: use actual stored bytes and original, not a stored Pass field.
  match @sieve.verify_document(delivered.bytes, input) {
    Ok(receipt) => assert_eq(receipt, delivered.receipt)
    Err(error) => fail(error.to_json().stringify())
  }
  println("Archive Pass: actual bytes verified against original")
  let cancelled = @sieve.WorkControl::default()
  cancelled.cancel()
  match @sieve.clean_document(input, control=cancelled) {
    Err(error) => assert_eq(error.code, @sieve.Cancelled)
    Ok(_) => fail("cancelled processing returned a document")
  }
  println("Business branch Pass: typed cancellation, no message parsing")
}
