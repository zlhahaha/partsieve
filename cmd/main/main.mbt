///|
fn main {
  let argv = @env.args()
  let args = argv[1:].to_owned()
  let (report, code) = try {
    if args.length() > 0 && args[0] == "_worker" {
      @cli.worker(args[1:].to_owned())
    } else {
      @cli.execute(args)
    }
  } catch {
    error => @cli.diagnostic(error)
  }
  let text = @cli.bounded_report(report) catch {
    error => {
      let (fallback, code) = @cli.diagnostic(error)
      println(fallback.stringify())
      @sys.exit(code)
      ""
    }
  }
  println(text)
  if code != 0 {
    @sys.exit(code)
  }
}
