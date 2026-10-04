///|
/// Entry point for the CLI or runnable program in this template.
/// Keep main focused; move logic into the library package.
/// Run with `moon run cmd/main` from the project root.
fn main {
  try {
    let args = @env.args()
    guard args.length() >= 3 else {
      fail("private worker: audit/graph/plan/rebuild/verify INPUT [OUTPUT]")
    }
    let command = args[1]
    let input = @fs.read_file_to_bytes(args[2])
    if command == "audit" {
      emit(@lib.audit(input).to_json())
    } else if command == "graph" {
      emit(@lib.inspect_graph(input).to_json())
    } else if command == "plan" {
      emit(@lib.plan(input).to_json())
    } else if command == "rebuild" {
      guard args.length() == 4 else {
        fail("private worker: rebuild INPUT TEMP_OUTPUT")
      }
      let result = @lib.rebuild(input)
      @fs.write_bytes_to_file(args[3], result.bytes)
      emit(result.receipt.to_json())
    } else if command == "verify" {
      guard args.length() == 4 else {
        fail("private worker: verify OUTPUT ORIGINAL")
      }
      let original = @fs.read_file_to_bytes(args[3])
      emit(@lib.verify(input, original).to_json())
    } else {
      fail("unknown command")
    }
  } catch {
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
