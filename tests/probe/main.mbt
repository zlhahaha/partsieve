///|
fn main {
  let args = @env.args()
  if args.length() > 1 && args[1] == "sleep" {
    @host.pause(2000)
  } else if args.length() > 1 && args[1] == "flood" {
    for _ in 0..<4096 {
      println("x".repeat(1024))
    }
  } else {
    for arg in args[1:] {
      println(arg)
    }
  }
}
