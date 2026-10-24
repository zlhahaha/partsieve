///|
fn main raise {
  let input = @host.read_bounded(
    "tests/fixtures/business/report-1900.xlsm", 33554432,
  )
  // A workflow shares one allowance, including all internal verification passes.
  let control = @sieve.WorkControl::new(work_units=50000000)
  let prepared = @sieve.prepare(input, control~)
  let rebuilt = @sieve.rebuild_verified_with_plan(
    input,
    prepared.to_json(),
    control~,
  )
  assert_eq(rebuilt.receipt.result, @sieve.Pass)
  println(
    "Shared workflow Pass; work units used: " + control.used().to_string(),
  )
  // A caller can instead poll a deadline or cancellation flag in this callback.
  let cancelled = @sieve.WorkControl::new(should_cancel=stage => {
    stage == "xml-event"
  })
  let result = @sieve.assess(input, control=cancelled)
  assert_eq(result.decision.result, @sieve.IncompleteResult)
  assert_eq(result.decision.rebuild_allowed, false)
  assert_eq(result.input_hash, None)
  println("Cancellation Pass: " + result.decision.reason)
}
