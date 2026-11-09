///|
fn[T] authorization_ok(result : Result[T, SdkFailure]) -> T raise {
  match result {
    Ok(value) => value
    Err(error) => fail(error.to_json().stringify())
  }
}

///|
test "authorization preview separates format conversion from nonexistent VBA" {
  let input = planner_fixture()
  let review = authorization_ok(preview_document(input))
  let summary = review.summary()
  assert_eq(summary.changes.length(), 1)
  assert_eq(summary.changes[0].kind, MacroFormatConversion)
  assert_eq(summary.changes[0].count, 1)
  assert_eq(summary.removed_parts, [])
  assert_eq(summary.rewritten_parts, ["[Content_Types].xml"])
  sdk_expect_failure(
    authorize_document(review, RemovalPermissions::deny_all()),
    AuthorizationDenied,
    AuthorizeDocument,
  )
  let allowed = {
    ..RemovalPermissions::deny_all(),
    convert_macro_format: true,
  }
  let approval = authorization_ok(authorize_document(review, allowed))
  let delivered = authorization_ok(execute_authorized_document(input, approval))
  let baseline = rebuild_verified(input)
  assert_eq(delivered.bytes, baseline.bytes)
  assert_eq(delivered.receipt, baseline.receipt)
  assert_eq(delivered.authorization.input_hash, review.input_hash())
  assert_eq(delivered.authorization.plan_hash, review.plan_hash())
  assert_eq(delivered.authorization.output_hash, delivered.receipt.output_hash)
  assert_eq(delivered.authorization.permissions, allowed)
  assert_eq(delivered.authorization.summary, summary)
}

///|
test "authorization empty passive plan accepts deny-all and detached previews do not mutate authority" {
  let input = rebuild_verified(planner_fixture()).bytes
  let review = authorization_ok(preview_document(input))
  assert_eq(review.summary().changes, [])
  let approved = authorization_ok(
    authorize_document(review, RemovalPermissions::deny_all()),
  )
  let result = authorization_ok(execute_authorized_document(input, approved))
  assert_eq(result.receipt, verify_contract(result.bytes, input))
  let conversion = authorization_ok(preview_document(planner_fixture()))
  match conversion.plan_json() {
    Object(fields) => fields["operations"] = Json::array([])
    _ => fail("expected plan JSON object")
  }
  let detached = conversion.summary()
  detached.changes.clear()
  detached.rewritten_parts.push("fake.xml")
  assert_eq(conversion.summary().changes.length(), 1)
  assert_eq(conversion.summary().rewritten_parts, ["[Content_Types].xml"])
  sdk_expect_failure(
    authorize_document(conversion, RemovalPermissions::deny_all()),
    AuthorizationDenied,
    AuthorizeDocument,
  )
}

///|
test "authorization refuses unmodeled planner rule categories" {
  let pkg = load_package(planner_fixture(), Limits::default())
  let plan = make_prepared_plan(pkg, Limits::default())
  let operations = plan.operations.copy()
  operations[0] = { ..operations[0], rule_id: "unmodeled-v9", }
  expect_refused(fn() raise {
    ignore(summary_from_plan(pkg, { ..plan, operations, }))
  })
}

///|
test "authorization rejects source substitution forged plan hash and forged loss summary" {
  let input = planner_fixture()
  let review = authorization_ok(preview_document(input))
  let approval = authorization_ok(
    authorize_document(review, RemovalPermissions::macros_only()),
  )
  let changed = @zip.read(input[:])
  changed.set_comment(b"other original")
  sdk_expect_failure(
    execute_authorized_document(@zip.write(changed), approval),
    IntegrityFailure,
    ExecuteAuthorizedDocument,
  )
  sdk_expect_failure(
    execute_authorized_document(input, {
      ..approval,
      plan_hash: "0".repeat(64),
    }),
    IntegrityFailure,
    ExecuteAuthorizedDocument,
  )
  let forged_preview = {
    ..review,
    changes: { changes: [], removed_parts: [], rewritten_parts: [], },
  }
  let forged = authorization_ok(
    authorize_document(forged_preview, RemovalPermissions::deny_all()),
  )
  sdk_expect_failure(
    execute_authorized_document(input, forged),
    IntegrityFailure,
    ExecuteAuthorizedDocument,
  )
  let forged_plan = { ..approval, plan: { ..approval.plan, decisions: [], }, }
  sdk_expect_failure(
    execute_authorized_document(input, forged_plan),
    IntegrityFailure,
    ExecuteAuthorizedDocument,
  )
}

///|
test "authorization rechecks permissions before the first execution operation" {
  let input = planner_fixture()
  let review = authorization_ok(preview_document(input))
  let approval = authorization_ok(
    authorize_document(review, RemovalPermissions::macros_only()),
  )
  // Whitebox forged token: the public caller cannot construct private fields.
  let denied = { ..approval, permissions: RemovalPermissions::deny_all(), }
  let mut executed = false
  let control = WorkControl::new(should_cancel=stage => {
    if stage == "execute-operation" {
      executed = true
    }
    false
  })
  sdk_expect_failure(
    execute_authorized_document(input, denied, control~),
    AuthorizationDenied,
    ExecuteAuthorizedDocument,
  )
  assert_false(executed)
  assert_eq(AuthorizationDenied.label(), "authorization_denied")
}

///|
test "authorization honors cancellation shared budgets limits and late stop checkpoints" {
  let input = planner_fixture()
  let review = authorization_ok(preview_document(input))
  let approval = authorization_ok(
    authorize_document(review, RemovalPermissions::macros_only()),
  )
  let limits = { ..Limits::default(), input_bytes: input.length() - 1, }
  sdk_expect_failure(
    preview_document(input, limits~),
    InputLimitExceeded,
    PreviewDocument,
  )
  let stopped = WorkControl::default()
  stopped.cancel()
  sdk_expect_failure(
    preview_document(input, control=stopped),
    Cancelled,
    PreviewDocument,
  )
  sdk_expect_failure(
    execute_authorized_document(input, approval, control=stopped),
    Cancelled,
    ExecuteAuthorizedDocument,
  )
  let zero = WorkControl::new(work_units=0)
  sdk_expect_failure(
    execute_authorized_document(input, approval, control=zero),
    WorkBudgetExceeded,
    ExecuteAuthorizedDocument,
  )
  for
    stage in [
      "review-complete", "authorization-checked", "authorization-complete",
    ] {
    let control = WorkControl::new(should_cancel=current => current == stage)
    if stage == "review-complete" {
      sdk_expect_failure(
        preview_document(input, control~),
        Cancelled,
        PreviewDocument,
      )
    } else {
      sdk_expect_failure(
        execute_authorized_document(input, approval, control~),
        Cancelled,
        ExecuteAuthorizedDocument,
      )
    }
  }
  let measured = WorkControl::default()
  let preview = authorization_ok(preview_document(input, control=measured))
  let authorization = authorization_ok(
    authorize_document(preview, RemovalPermissions::macros_only()),
  )
  let expected = authorization_ok(
    execute_authorized_document(input, authorization, control=measured),
  )
  let exact = WorkControl::new(work_units=measured.used())
  let preview = authorization_ok(preview_document(input, control=exact))
  let authorization = authorization_ok(
    authorize_document(preview, RemovalPermissions::macros_only()),
  )
  assert_eq(
    authorization_ok(
      execute_authorized_document(input, authorization, control=exact),
    ).receipt,
    expected.receipt,
  )
  assert_eq(exact.remaining(), 0)
  let short = WorkControl::new(work_units=measured.used() - 1)
  let preview = authorization_ok(preview_document(input, control=short))
  let authorization = authorization_ok(
    authorize_document(preview, RemovalPermissions::macros_only()),
  )
  sdk_expect_failure(
    execute_authorized_document(input, authorization, control=short),
    WorkBudgetExceeded,
    ExecuteAuthorizedDocument,
  )
}
