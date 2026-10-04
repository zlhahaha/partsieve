///|
/// Entry point for the CLI or runnable program in this template.
/// Keep main focused; move logic into the library package.
/// Run with `moon run cmd/main` from the project root.
fn main {
  try {
    let args = @env.args()
    guard args.length() >= 3 else {
      fail(
        "private worker: audit/assess/graph/plan/rebuild/verify INPUT [OUTPUT]",
      )
    }
    let command = args[1]
    let input = @fs.read_file_to_bytes(args[2])
    if command == "audit" {
      emit(@lib.audit(input).to_json())
    } else if command == "assess" {
      let report = @lib.assess(input)
      emit(report.to_json())
      match report.decision.result {
        @lib.Pass => ()
        @lib.Fail => @sys.exit(2)
        @lib.IncompleteResult | @lib.Unsupported => @sys.exit(3)
      }
    } else if command == "graph" {
      emit(@lib.inspect_graph(input).to_json())
    } else if command == "plan" {
      emit(@lib.plan(input).to_json())
    } else if command == "prepare" {
      emit(@lib.prepare(input).to_json())
    } else if command == "rebuild-plan" || command == "rebuild-plan-v2" {
      guard args.length() == 5 else {
        fail("private worker: rebuild-plan INPUT TEMP_OUTPUT PLAN_SNAPSHOT")
      }
      let plan_bytes = @fs.read_file_to_bytes(args[4])
      let supplied = @json.parse(@utf8.decode(plan_bytes[:])[:]) catch {
        _ => raise @lib.Invalid("malformed supplied plan JSON")
      }
      if command == "rebuild-plan-v2" {
        let result = @lib.rebuild_verified_with_plan(input, supplied)
        @fs.write_bytes_to_file(args[3], result.bytes)
        emit(result.receipt.to_json())
      } else {
        let result = @lib.rebuild_with_plan(input, supplied)
        @fs.write_bytes_to_file(args[3], result.bytes)
        emit(result.receipt.to_json())
      }
    } else if command == "rebuild" || command == "rebuild-v2" {
      guard args.length() == 4 else {
        fail("private worker: rebuild INPUT TEMP_OUTPUT")
      }
      if command == "rebuild-v2" {
        let result = @lib.rebuild_verified(input)
        @fs.write_bytes_to_file(args[3], result.bytes)
        emit(result.receipt.to_json())
      } else {
        let result = @lib.rebuild(input)
        @fs.write_bytes_to_file(args[3], result.bytes)
        emit(result.receipt.to_json())
      }
    } else if command == "verify" || command == "verify-v2" {
      guard args.length() == 4 else {
        fail("private worker: verify OUTPUT ORIGINAL")
      }
      let original = @fs.read_file_to_bytes(args[3])
      emit(
        if command == "verify-v2" {
          @lib.verify_contract(input, original).to_json()
        } else {
          @lib.verify(input, original).to_json()
        },
      )
    } else {
      fail("unknown command")
    }
  } catch {
    @lib.Invalid(reason) => {
      let diagnostic : Json = {
        "schema": "partsieve.error.spike-v1",
        "status": "Fail",
        "error": reason,
      }
      println(diagnostic.stringify())
      @sys.exit(2)
    }
    @lib.Incomplete(reason) => {
      let diagnostic : Json = {
        "schema": "partsieve.error.spike-v1",
        "status": "Incomplete",
        "error": reason,
      }
      println(diagnostic.stringify())
      @sys.exit(3)
    }
    @lib.Refused(reason) => {
      let diagnostic : Json = {
        "schema": "partsieve.error.spike-v1",
        "status": "Unsupported",
        "error": reason,
      }
      println(diagnostic.stringify())
      @sys.exit(3)
    }
    error => {
      let diagnostic : Json = {
        "schema": "partsieve.error.spike-v1",
        "status": "Unsupported",
        "error": error.to_string(),
      }
      println(diagnostic.stringify())
      @sys.exit(3)
    }
  }
}

///|
fn emit(value : Json) -> Unit raise {
  let text = value.stringify()
  guard text.length() <= 8388608 else {
    raise @lib.Incomplete("report character limit")
  }
  println(text)
}
