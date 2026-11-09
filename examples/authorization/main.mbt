///|
fn[T] value(result : Result[T, @sieve.SdkFailure]) -> T raise {
  match result {
    Ok(v) => v
    Err(error) => fail(error.to_json().stringify())
  }
}

///|
fn main raise {
  let input = @host.read_bounded(
    "tests/fixtures/business/demo-word-three-objects.docm", 33554432,
  )
  let control = @sieve.WorkControl::new(work_units=50000000)
  let preview = value(@sieve.preview_document(input, control~))
  println(preview.to_json().stringify())
  let losses = preview.summary()
  let objects = losses.changes.filter(change => change.kind == @sieve.OleRemoval)
  assert_eq(objects.length(), 1)
  assert_eq(objects[0].count, 3)
  // Trusted application policy: removing VBA must not silently delete objects.
  match
    @sieve.authorize_document(preview, @sieve.RemovalPermissions::macros_only()) {
    Err(error) => assert_eq(error.code, @sieve.AuthorizationDenied)
    Ok(_) => fail("macro-only policy granted OLE deletion")
  }
  println(
    "Policy Pass: macro-only request refused because additional content would be lost",
  )
  let keep_objects = {
    ..@sieve.RemovalPermissions::all_supported(),
    remove_ole: false,
  }
  match @sieve.authorize_document(preview, keep_objects) {
    Err(error) => assert_eq(error.code, @sieve.AuthorizationDenied)
    Ok(_) => fail("policy allowing every other change silently deleted OLE")
  }
  // Explicit trusted fixture decision. In an application, authenticate the caller
  // and decide permissions there; never treat client-posted preview JSON as authority.
  let approval = value(
    @sieve.authorize_document(
      preview,
      @sieve.RemovalPermissions::all_supported(),
    ),
  )
  let delivered = value(
    @sieve.execute_authorized_document(input, approval, control~),
  )
  assert_eq(delivered.receipt.result, @sieve.Pass)
  assert_eq(delivered.authorization.input_hash, preview.input_hash())
  assert_eq(delivered.authorization.plan_hash, preview.plan_hash())
  assert_eq(delivered.authorization.output_hash, delivered.receipt.output_hash)
  assert_eq(delivered.authorization.summary, losses)
  assert_eq(
    value(@sieve.verify_document(delivered.bytes, input)),
    delivered.receipt,
  )
  println(
    "Delivery Pass: explicitly approved losses, actual output and record verified",
  )
}
