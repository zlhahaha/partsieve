///|
pub(all) suberror Usage {
  Usage(String)
} derive(Debug)

///|
pub extend Usage with Debug::{to_repr}

///|
priv struct Options {
  command : String
  input : String
  output : String?
  receipt : String?
  original : String?
  plan : String?
  v2 : Bool
  dry_run : Bool
  release : Bool
  timeout_ms : Int
}

///|
fn parse_args(args : Array[String]) -> Options raise {
  let positional : Array[String] = []
  let values : Map[String, String] = Map([])
  let flags : Map[String, Bool] = Map([])
  let mut i = 0
  let mut literal = false
  while i < args.length() {
    let arg = args[i]
    if arg == "--" && !literal {
      literal = true
      i += 1
      continue
    }
    if literal || !arg.has_prefix("-") {
      positional.push(arg)
      i += 1
      continue
    }
    if ["--json", "--dry-run", "--release"].contains(arg) {
      guard !flags.contains(arg) else { raise Usage("duplicate flag: " + arg) }
      flags[arg] = true
      i += 1
      continue
    }
    let key = if arg == "-o" { "--output" } else { arg }
    guard [
      "--output", "--receipt", "--original", "--plan", "--receipt-format", "--policy",
      "--timeout-ms",
    ].contains(key) else {
      raise Usage("unknown option: " + arg)
    }
    guard !values.contains(key) && i + 1 < args.length() else {
      raise Usage("duplicate/missing option value: " + key)
    }
    values[key] = args[i + 1]
    i += 2
  }
  guard positional.length() == 2 &&
    [
      "audit", "assess", "graph", "plan", "prepare", "rebuild", "verify", "batch",
    ].contains(positional[0]) else {
    raise Usage(
      "usage: partsieve audit|assess|graph|plan|prepare|rebuild|verify|batch INPUT [options]",
    )
  }
  guard values.get("--policy").unwrap_or("passive-office-v1") ==
    "passive-office-v1" else {
    raise Usage("unknown policy")
  }
  let command = positional[0]
  let format = values
    .get("--receipt-format")
    .unwrap_or(if command == "batch" { "v2" } else { "legacy" })
  guard ["legacy", "v2"].contains(format) else {
    raise Usage("unknown Receipt format")
  }
  let dry_run = flags.contains("--dry-run")
  if command == "batch" &&
    (
      dry_run ||
      format != "v2" ||
      !values.contains("--output") ||
      ["--receipt", "--original", "--plan"].any(fn(key) { values.contains(key) })
    ) {
    raise Usage(
      "batch requires -o NEW_DIRECTORY; uses v2 receipts and does not accept dry-run/receipt/original/plan",
    )
  }
  if dry_run && ["assess", "graph", "prepare"].contains(command) {
    raise Usage("dry-run does not apply to structural inspection")
  }
  if values.contains("--plan") && (command != "rebuild" || dry_run) {
    raise Usage("plan applies only to rebuild without dry-run")
  }
  if format == "v2" &&
    (!["rebuild", "verify", "batch"].contains(command) || dry_run) {
    raise Usage("Receipt format applies only to rebuild/verify")
  }
  let mut timeout = 60000
  if values.get("--timeout-ms") is Some(text) {
    timeout = 0
    guard text.length() > 0 && text.length() <= 5 else {
      raise Usage("timeout must be 1..60000 milliseconds")
    }
    for c in text.code_units() {
      guard c >= '0' && c <= '9' else { raise Usage("invalid timeout") }
      timeout = timeout * 10 + c.to_int() - 48
    }
    guard timeout >= 1 && timeout <= 60000 else {
      raise Usage("timeout must be 1..60000 milliseconds")
    }
  }
  {
    command,
    input: positional[1],
    output: values.get("--output"),
    receipt: values.get("--receipt"),
    original: values.get("--original"),
    plan: values.get("--plan"),
    v2: format == "v2",
    dry_run,
    release: flags.contains("--release"),
    timeout_ms: timeout,
  }
}
