///|
priv struct Workspace {
  dirs : Array[String]
  files : Array[String]
}

///|
fn Workspace::directory(
  self : Workspace,
  parent? : String = "",
) -> String raise {
  let path = @host.temp_dir(parent~)
  self.dirs.push(path)
  path
}

///|
fn Workspace::file(self : Workspace, path : String) -> String {
  self.files.push(path)
  path
}

///|
fn Workspace::cleanup(self : Workspace) -> Unit {
  // Only explicitly tracked paths in freshly created directories; no recursion.
  for path in self.files.rev_iter() {
    try {
      if @host.exists(path) {
        @host.remove_file(path)
      }
    } catch {
      _ => ()
    }
  }
  for dir in self.dirs.rev_iter() {
    @host.remove_dir(dir) catch {
      _ => ()
    }
  }
}

///|
fn run_worker(
  exe : String,
  command : String,
  paths : Array[String],
  timeout : Int,
) -> (Json, Int) raise {
  let result = @host.run(exe, ["_worker", command] + paths, timeout_ms=timeout)
  let report = parse_json(result.stdout)
  if command == "assess" &&
    string_field(report, "schema") == "partsieve.assessment.v1" {
    let expected = match string_field(field(report, "decision"), "result") {
      "Pass" => 0
      "Fail" => 2
      "Unsupported" | "Incomplete" => 3
      _ => raise Usage("invalid assessment result")
    }
    guard result.code == expected else {
      raise Usage("assessment result/exit mismatch")
    }
    return (report, result.code)
  }
  if result.code != 0 {
    let message = string_field(report, "error")
    match result.code {
      2 => raise @lib.Invalid(message)
      3 =>
        if string_field(report, "status") == "Incomplete" {
          raise @lib.Incomplete(message)
        } else {
          raise @lib.Refused(message)
        }
      _ => raise Usage(message)
    }
  }
  (report, 0)
}

///|
fn hash(bytes : Bytes) -> String {
  @crypto.bytes_to_hex_string(@crypto.sha256(bytes))
}

///|
pub fn execute(args : Array[String]) -> (Json, Int) raise {
  let options = parse_args(args)
  let workspace : Workspace = { dirs: [], files: [], }
  defer workspace.cleanup()
  let private_dir = workspace.directory()
  let snapshot = workspace.file(private_dir + "/input.zip")
  @host.write_new(
    snapshot,
    @host.read_bounded(
      options.input,
      if options.command == "verify" {
        67108864
      } else {
        33554432
      },
    ),
  )
  let self = @host.executable().replace_all(old="\\", new="/")
  let exe = if options.release && self.contains("/debug/") {
    let release = self.replace(old="/debug/", new="/release/")
    guard @host.exists(release) else {
      raise Usage("build first: moon build --release --target native")
    }
    release
  } else {
    self
  }
  let timeout = options.timeout_ms
  let command = options.command
  let verify = if options.v2 { "verify-v2" } else { "verify" }
  if ["audit", "assess", "graph", "plan", "prepare"].contains(command) ||
    options.dry_run {
    return run_worker(
      exe,
      if options.dry_run {
        "plan"
      } else {
        command
      },
      [snapshot],
      timeout,
    )
  }
  if command == "verify" {
    guard options.original is Some(original_path) else {
      let (audit, _) = run_worker(exe, "audit", [snapshot], timeout)
      let format = string_field(audit, "format")
      let structure = if ["XLSX", "DOCX"].contains(format) &&
        field(audit, "findings") == Json::array([]) {
        "Pass"
      } else {
        "Fail"
      }
      return (
        {
          "schema": if options.v2 {
            "partsieve.verify.v2-partial"
          } else {
            "partsieve.verify.spike-v1"
          },
          "structure": structure,
          "preservation": "NotChecked",
          "status": "Incomplete",
          "audit": audit,
        },
        3,
      )
    }
    let original = workspace.file(private_dir + "/original.zip")
    @host.write_new(original, @host.read_bounded(original_path, 33554432))
    let (report, _) = run_worker(exe, verify, [snapshot, original], timeout)
    if options.receipt is Some(path) {
      let supplied = parse_json(@host.read_bounded(path, 16777216))
      guard json_equal(supplied, {
        "publication": "pair-complete",
        "receipt": report,
      }) else {
        raise @lib.Invalid(
          "Receipt differs from independently recomputed verification",
        )
      }
    }
    return (report, 0)
  }
  guard options.output is Some(output_path) &&
    options.receipt is Some(receipt_path) else {
    raise Usage("rebuild requires -o and --receipt")
  }
  let output = @host.absolute(output_path)
  let receipt_path = @host.absolute(receipt_path)
  guard [".xlsx", ".docx"].any(fn(suffix) {
    output.to_lower().has_suffix(suffix)
  }) else {
    raise Usage("output must use .xlsx or .docx")
  }
  guard !@host.same_path(output, receipt_path) &&
    !@host.same_path(output, options.input) &&
    !@host.same_path(receipt_path, options.input) else {
    raise Usage("input/document/Receipt paths must differ")
  }
  guard !@host.exists(output) && !@host.exists(receipt_path) else {
    raise Usage("output or Receipt exists; overwrite refused")
  }
  let temp_output = workspace.file(
    workspace.directory(parent=@host.parent(output)) + "/output",
  )
  let worker_paths = [snapshot, temp_output]
  let build_command = if options.plan is Some(path) {
    let plan = workspace.file(private_dir + "/plan.json")
    let bytes = @host.read_bounded(path, 16777216)
    ignore(parse_json(bytes))
    @host.write_new(plan, bytes)
    worker_paths.push(plan)
    if options.v2 {
      "rebuild-plan-v2"
    } else {
      "rebuild-plan"
    }
  } else if options.v2 {
    "rebuild-v2"
  } else {
    "rebuild"
  }
  let (report, _) = run_worker(exe, build_command, worker_paths, timeout)
  let expected_suffix = match string_field(report, "output_format") {
    "XLSX" => ".xlsx"
    "DOCX" => ".docx"
    _ => raise Usage("invalid output format")
  }
  guard output.to_lower().has_suffix(expected_suffix) else {
    raise Usage("output extension differs from verified main document type")
  }
  guard hash(@host.read_bounded(temp_output, 67108864)) ==
    string_field(report, "output_hash") else {
    raise @lib.Invalid("temporary output hash mismatch")
  }
  let (recheck, _) = run_worker(exe, verify, [temp_output, snapshot], timeout)
  guard json_equal(recheck, report) else {
    raise @lib.Invalid("temporary output verification mismatch")
  }
  let payload = @utf8.encode(
    bounded_report({ "publication": "pair-complete", "receipt": report })[:],
  )
  let temp_receipt = workspace.file(
    workspace.directory(parent=@host.parent(receipt_path)) + "/receipt",
  )
  @host.write_new(temp_receipt, payload)
  let published : Array[(String, String)] = []
  let mut committed = false
  defer (if !committed {
    for (source, target) in published.rev_iter() {
      @host.remove_same(source, target) catch {
        _ => ()
      }
    }
  })
  @host.link_new(temp_output, output)
  published.push((temp_output, output))
  @host.link_new(temp_receipt, receipt_path)
  published.push((temp_receipt, receipt_path))
  guard hash(@host.read_bounded(output, 67108864)) ==
    string_field(report, "output_hash") else {
    raise @lib.Invalid("published output hash mismatch")
  }
  guard @host.read_bounded(receipt_path, 16777216) == payload else {
    raise @lib.Invalid("published Receipt mismatch")
  }
  committed = true
  (report, 0)
}
