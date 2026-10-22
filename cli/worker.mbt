///|
pub fn worker(args : Array[String]) -> (Json, Int) raise {
  guard args.length() >= 2 else { raise Usage("invalid worker arguments") }
  let command = args[0]
  let input = @host.read_bounded(
    args[1],
    if command.has_prefix("verify") {
      67108864
    } else {
      33554432
    },
  )
  match command {
    "audit" => (@lib.audit(input).to_json(), 0)
    "assess" => {
      let report = @lib.assess(input)
      (
        report.to_json(),
        match report.decision.result {
          @lib.Pass => 0
          @lib.Fail => 2
          @lib.Unsupported | @lib.IncompleteResult => 3
        },
      )
    }
    "graph" => (@lib.inspect_graph(input).to_json(), 0)
    "plan" => (@lib.plan(input).to_json(), 0)
    "prepare" => (@lib.prepare(input).to_json(), 0)
    "rebuild" | "rebuild-v2" | "rebuild-plan" | "rebuild-plan-v2" => {
      let planned = command.contains("plan")
      guard args.length() == (if planned { 4 } else { 3 }) else {
        raise Usage("invalid rebuild worker arguments")
      }
      let supplied = if planned {
        Some(parse_json(@host.read_bounded(args[3], 16777216)))
      } else {
        None
      }
      let (bytes, receipt) = if command.has_suffix("v2") {
        let result = match supplied {
          Some(plan) => @lib.rebuild_verified_with_plan(input, plan)
          None => @lib.rebuild_verified(input)
        }
        (result.bytes, result.receipt.to_json())
      } else {
        let result = match supplied {
          Some(plan) => @lib.rebuild_with_plan(input, plan)
          None => @lib.rebuild(input)
        }
        (result.bytes, result.receipt.to_json())
      }
      @host.write_new(args[2], bytes)
      (receipt, 0)
    }
    "verify" | "verify-v2" => {
      guard args.length() == 3 else {
        raise Usage("invalid verify worker arguments")
      }
      let original = @host.read_bounded(args[2], 33554432)
      (
        if command == "verify-v2" {
          @lib.verify_contract(input, original).to_json()
        } else {
          @lib.verify(input, original).to_json()
        },
        0,
      )
    }
    _ => raise Usage("unknown worker command")
  }
}

///|
pub fn diagnostic(error : Error) -> (Json, Int) {
  let (message, code, status) = match error {
    @lib.Invalid(message) => (message, 2, "Fail")
    @lib.Incomplete(message) | @host.Limit(message) =>
      (message, 3, "Incomplete")
    @lib.Refused(message) => (message, 3, "Unsupported")
    Usage(message) | @host.Io(message) => (message, 4, "Fail")
    _ => (error.to_string(), 4, "Fail")
  }
  (
    { "schema": "partsieve.error.spike-v1", "status": status, "error": message },
    code,
  )
}

///|
pub fn bounded_report(report : Json) -> String raise {
  let text = report.stringify()
  guard text.length() <= 8388608 && @utf8.encode(text[:]).length() <= 16777216 else {
    raise @lib.Incomplete("report byte/character limit")
  }
  text
}
