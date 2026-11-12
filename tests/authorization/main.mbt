///|
fn[T] value(result : Result[T, @sieve.SdkFailure]) -> T raise {
  match result {
    Ok(v) => v
    Err(error) => fail(error.to_json().stringify())
  }
}

///|
fn[T] denied(
  result : Result[T, @sieve.SdkFailure],
  code : @sieve.FailureCode,
  operation : @sieve.SdkOperation,
) -> Unit raise {
  guard result is Err(error) else {
    fail("expected failure without output bytes")
  }
  assert_eq(error.code, code)
  assert_eq(error.operation, operation)
}

///|
priv struct Run {
  directory : String
  cases : Array[String]
}

///|
fn Run::save(self : Run, result : String) -> Unit raise {
  let path = self.directory + "/result.json"
  let report : Json = {
    "schema": "partsieve.authorization-regression.v1",
    "result": result,
    "cases": ToJson::to_json(self.cases),
    "case_count": self.cases.length(),
  }
  // Test-only report replacement in a freshly created directory.
  if @host.exists(path) {
    @host.remove_file(path)
  }
  @host.write_new(path, @utf8.encode(report.stringify()[:]))
}

///|
fn Run::record(self : Run, name : String) -> Unit raise {
  self.cases.push(name)
  self.save("Running")
}

///|
fn fixture(name : String) -> Bytes raise {
  @host.read_bounded("tests/fixtures/business/" + name, 33554432)
}

///|
fn count(summary : @sieve.ChangeSummary, kind : @sieve.ChangeKind) -> Int32 {
  summary.changes
  .filter(change => change.kind == kind)
  .fold(init=0, (sum, change) => sum + change.count)
}

///|
fn main raise {
  if !@host.exists("tests/generated") {
    @host.create_directory("tests/generated")
  }
  let root = @env.get_env_var("PARTSIEVE_TEST_OUTPUT").unwrap_or_else(fn() raise {
    @host.temp_dir(parent="tests/generated")
  })
  let directory = root + "/authorization"
  @host.create_directory(directory)
  let run : Run = { directory, cases: [], }
  run.save("Running")
  println("Authorization results: " + directory)
  let word = fixture("demo-word-three-objects.docm")
  let review = value(@sieve.preview_document(word))
  let summary = review.summary()
  assert_eq(count(summary, @sieve.VbaRemoval), 1)
  assert_eq(count(summary, @sieve.OleRemoval), 3)
  assert_eq(count(summary, @sieve.TemplateRemoval), 1)
  assert_eq(count(summary, @sieve.MacroFormatConversion), 1)
  let ole = summary.changes.filter(change => change.kind == @sieve.OleRemoval)[0]
  assert_eq(ole.removed_parts.length(), 6)
  assert_eq(summary.removed_parts.length(), 7)
  assert_true(summary.rewritten_parts.contains("word/document.xml"))
  assert_true(summary.rewritten_parts.contains("word/settings.xml"))
  run.record("real-word-loss-counts-and-private-previews")
  let all = @sieve.RemovalPermissions::all_supported()
  for
    (name, permissions) in [
      ("deny-vba", { ..all, remove_vba: false, }),
      ("deny-ole", { ..all, remove_ole: false, }),
      ("deny-template", { ..all, remove_remote_template: false, }),
      ("deny-conversion", { ..all, convert_macro_format: false, }),
      ("macro-only", @sieve.RemovalPermissions::macros_only()),
      ("deny-all", @sieve.RemovalPermissions::deny_all()),
    ] {
    denied(
      @sieve.authorize_document(review, permissions),
      @sieve.AuthorizationDenied,
      @sieve.AuthorizeDocument,
    )
    assert_false(@host.exists(directory + "/delivered.docx"))
    run.record(name + "-no-success-output")
  }
  // Mutate every public array layer and serialized plan data. The review must
  // still contain its exact original losses and require the original permissions.
  let detached = review.summary()
  detached.changes[0].removed_parts[0] = "forged.bin"
  detached.changes[1].removed_parts.clear()
  detached.changes.clear()
  detached.removed_parts.clear()
  detached.rewritten_parts.clear()
  match review.plan_json() {
    Object(fields) => fields["operations"] = Json::array([])
    _ => fail("plan object")
  }
  match review.to_json() {
    Object(fields) => {
      fields["input_hash"] = ToJson::to_json("0".repeat(64))
      fields["summary"] = Json::null()
    }
    _ => fail("preview object")
  }
  assert_eq(review.summary(), summary)
  denied(
    @sieve.authorize_document(review, @sieve.RemovalPermissions::macros_only()),
    @sieve.AuthorizationDenied,
    @sieve.AuthorizeDocument,
  )
  run.record("detached-summary-and-json-cannot-hide-losses")
  let approval = value(@sieve.authorize_document(review, all))
  let control = @sieve.WorkControl::new(work_units=50000000)
  let result = value(
    @sieve.execute_authorized_document(word, approval, control~),
  )
  let baseline = @sieve.rebuild_verified(word)
  assert_eq(result.bytes, baseline.bytes)
  assert_eq(result.receipt, baseline.receipt)
  assert_eq(result.authorization.input_hash, review.input_hash())
  assert_eq(result.authorization.plan_hash, review.plan_hash())
  assert_eq(result.authorization.output_hash, result.receipt.output_hash)
  assert_eq(result.authorization.summary, summary)
  assert_eq(result.authorization.permissions, all)
  let plan_hash = @sieve.digest(
    @utf8.encode(result.receipt.plan.to_json().stringify()[:])[:],
  )
  assert_eq(plan_hash, review.plan_hash())
  let removed = result.receipt.dispositions
    .filter(item => item.classification == @sieve.RemovedByPolicyKind)
    .map(item => item.part)
  removed.sort()
  assert_eq(removed, summary.removed_parts)
  @host.write_new(directory + "/delivered.docx", result.bytes)
  @host.write_new(
    directory + "/delivered.receipt.json",
    @utf8.encode(
      (
        { "publication": "pair-complete", "receipt": result.receipt.to_json() } :
        Json).stringify()[:],
    ),
  )
  @host.write_new(
    directory + "/authorization-record.json",
    @utf8.encode(result.authorization.to_json().stringify()[:]),
  )
  @host.write_new(
    directory + "/preview.json",
    @utf8.encode(review.to_json().stringify()[:]),
  )
  assert_eq(
    value(
      @sieve.verify_document(
        @host.read_bounded(directory + "/delivered.docx", 67108864),
        word,
      ),
    ),
    result.receipt,
  )
  let stem = "_build/native/debug/build/cmd/main/main"
  let executable = @host.absolute(
    if @host.exists(stem + ".exe") {
      stem + ".exe"
    } else {
      stem
    },
  )
  let checked = @host.run(executable, [
    "verify",
    directory + "/delivered.docx",
    "--original",
    "tests/fixtures/business/demo-word-three-objects.docm",
    "--receipt",
    directory + "/delivered.receipt.json",
    "--receipt-format",
    "v2",
  ])
  assert_eq(checked.code, 0)
  assert_eq(@cli.parse_json(checked.stdout), result.receipt.to_json())
  run.record("approved-output-record-and-real-cli-receipt-match")
  let other_word = fixture("document-layout.docm")
  denied(
    @sieve.execute_authorized_document(other_word, approval),
    @sieve.IntegrityFailure,
    @sieve.ExecuteAuthorizedDocument,
  )
  run.record("same-format-source-substitution-refused")
  let sheet = fixture("report-1900.xlsm")
  denied(
    @sieve.execute_authorized_document(sheet, approval),
    @sieve.IntegrityFailure,
    @sieve.ExecuteAuthorizedDocument,
  )
  run.record("cross-format-authorization-reuse-refused")
  let macro_review = value(@sieve.preview_document(sheet))
  assert_eq(count(macro_review.summary(), @sieve.VbaRemoval), 1)
  assert_eq(count(macro_review.summary(), @sieve.OleRemoval), 0)
  assert_eq(count(macro_review.summary(), @sieve.TemplateRemoval), 0)
  let macro_approval = value(
    @sieve.authorize_document(
      macro_review,
      @sieve.RemovalPermissions::macros_only(),
    ),
  )
  assert_eq(
    value(@sieve.execute_authorized_document(sheet, macro_approval)).bytes,
    @sieve.rebuild_verified(sheet).bytes,
  )
  run.record("real-excel-macro-only-permission-succeeds")
  let template = fixture("document-template.docm")
  let template_review = value(@sieve.preview_document(template))
  assert_eq(count(template_review.summary(), @sieve.OleRemoval), 0)
  assert_eq(count(template_review.summary(), @sieve.TemplateRemoval), 1)
  denied(
    @sieve.authorize_document(
      template_review,
      @sieve.RemovalPermissions::macros_only(),
    ),
    @sieve.AuthorizationDenied,
    @sieve.AuthorizeDocument,
  )
  let template_permission = {
    ..@sieve.RemovalPermissions::macros_only(),
    remove_remote_template: true,
  }
  let template_approval = value(
    @sieve.authorize_document(template_review, template_permission),
  )
  assert_eq(
    value(@sieve.execute_authorized_document(template, template_approval)).bytes,
    @sieve.rebuild_verified(template).bytes,
  )
  run.record("real-template-removal-requires-separate-permission")
  let passive = @sieve.rebuild_verified(sheet).bytes
  let passive_review = value(@sieve.preview_document(passive))
  assert_eq(passive_review.summary().changes, [])
  let none = value(
    @sieve.authorize_document(
      passive_review,
      @sieve.RemovalPermissions::deny_all(),
    ),
  )
  assert_eq(
    value(@sieve.execute_authorized_document(passive, none)).receipt.result,
    @sieve.Pass,
  )
  run.record("passive-input-needs-no-removal-permissions")
  let invalid = @host.read_bounded(
    "tests/fixtures/business/document-fields.docx", 33554432,
  )
  denied(
    @sieve.preview_document(invalid),
    @sieve.UnsupportedDocument,
    @sieve.PreviewDocument,
  )
  run.record("unsupported-input-cannot-obtain-a-review")
  let cancelled = @sieve.WorkControl::default()
  cancelled.cancel()
  denied(
    @sieve.execute_authorized_document(word, approval, control=cancelled),
    @sieve.Cancelled,
    @sieve.ExecuteAuthorizedDocument,
  )
  run.record("cancelled-approval-cannot-return-success")
  run.save("Pass")
  println(
    "Pass: authorization integration " +
    run.cases.length().to_string() +
    " cases; actual source, losses, permissions and output verified",
  )
}
