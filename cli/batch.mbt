///|
fn execute_batch(options : Options) -> (Json, Int) raise {
  let input = @host.absolute(options.input)
  let output = @host.absolute(options.output.unwrap())
  // Inventory completes before creating any outputs, including limit checks.
  let entries = @host.list_directory(input)
  @host.create_directory(output)
  let rows : Array[Json] = []
  let mut success = 0
  let mut refused = 0
  let mut failed = 0
  let mut skipped = 0
  let mut exit_code = 0
  for entry in entries {
    let name = entry.name
    let lower = name.to_lower()
    let suffix = if [".docx", ".docm"].any(fn(s) { lower.has_suffix(s) }) {
      ".docx"
    } else if [".xlsx", ".xlsm"].any(fn(s) { lower.has_suffix(s) }) {
      ".xlsx"
    } else {
      ""
    }
    let skip_reason = if entry.kind != "file" {
      entry.kind
    } else if name.contains("\\") {
      "unsupported path character"
    } else if name.has_prefix("~$") {
      "Office lock file"
    } else if suffix == "" {
      "unselected extension"
    } else {
      ""
    }
    if skip_reason != "" {
      skipped += 1
      rows.push({ "input": name, "status": "Skipped", "reason": skip_reason })
      continue
    }
    let document = name + ".cleaned" + suffix
    let receipt = name + ".receipt.json"
    let args = [
      "rebuild",
      input + "/" + name,
      "-o",
      output + "/" + document,
      "--receipt",
      output + "/" + receipt,
      "--receipt-format",
      "v2",
      "--timeout-ms",
      options.timeout_ms.to_string(),
    ]
    if options.release {
      args.push("--release")
    }
    try {
      let (report, code) = execute(args)
      guard code == 0 else { raise Usage("unexpected rebuild exit") }
      success += 1
      rows.push({
        "input": name,
        "status": "Success",
        "exit_code": 0,
        "output": document,
        "receipt": receipt,
        "input_hash": string_field(report, "input_hash"),
        "output_hash": string_field(report, "output_hash"),
      })
    } catch {
      error => {
        let (report, code) = diagnostic(error)
        let status = if code == 3 {
          refused += 1
          "Refused"
        } else {
          failed += 1
          "Failed"
        }
        // IO/publication > integrity > unsupported/incomplete > success.
        if code == 4 || (code == 2 && exit_code != 4) || exit_code == 0 {
          exit_code = code
        }
        let reason = string_field(report, "error")
        rows.push({
          "input": name,
          "status": status,
          "exit_code": code,
          "decision": string_field(report, "status"),
          "reason": if reason.length() <= 1024 {
            reason
          } else {
            reason[:1024].to_owned()
          },
        })
      }
    }
  }
  let no_inputs = success + refused + failed == 0
  if no_inputs {
    exit_code = 3
  }
  let report : Json = {
    "schema": "partsieve.batch.v1",
    "input_directory": input,
    "output_directory": output,
    "recursive": false,
    "entry_limit": 1024,
    "timeout_ms_per_worker": options.timeout_ms,
    "receipt_format": "v2",
    "status": if no_inputs {
      "NoInputs"
    } else if exit_code == 0 {
      "Pass"
    } else {
      "PartialFailure"
    },
    "exit_code": exit_code,
    "success": success,
    "refused": refused,
    "failed": failed,
    "skipped": skipped,
    "entries": Json::array(rows),
  }
  // Publish the summary without overwriting; each successful pair is committed
  // independently. A later file or summary failure does not undo earlier pairs.
  let workspace : Workspace = { dirs: [], files: [], }
  defer workspace.cleanup()
  try {
    let temp = workspace.file(
      workspace.directory(parent=output) + "/batch.json",
    )
    @host.write_new(temp, @utf8.encode(bounded_report(report)[:]))
    @host.link_new(temp, output + "/batch.json")
  } catch {
    error => {
      let (detail, _) = diagnostic(error)
      return (
        {
          "schema": "partsieve.batch.summary-failure.v1",
          "status": "SummaryWriteFailed",
          "exit_code": 4,
          "error": detail,
          "batch": report,
        },
        4,
      )
    }
  }
  (report, exit_code)
}
