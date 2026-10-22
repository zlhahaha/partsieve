///|
pub(all) suberror HostError {
  Io(String)
  Limit(String)
} derive(Debug)

///|
#external
priv type Process

///|
extern "C" fn last_error_ffi() -> Bytes = "ps_last_error"

///|
extern "C" fn windows_ffi() -> Int = "ps_windows"

///|
#borrow(path)
extern "C" fn open_read_ffi(path : Bytes) -> Int = "ps_open_read"

///|
#borrow(path)
extern "C" fn open_new_ffi(path : Bytes) -> Int = "ps_open_new"

///|
extern "C" fn size_ffi(fd : Int) -> Int64 = "ps_size"

///|
#borrow(data)
extern "C" fn read_ffi(
  fd : Int,
  data : Bytes,
  offset : Int,
  count : Int,
) -> Int = "ps_read"

///|
#borrow(data)
extern "C" fn write_ffi(
  fd : Int,
  data : Bytes,
  offset : Int,
  count : Int,
) -> Int = "ps_write"

///|
extern "C" fn close_ffi(fd : Int) -> Int = "ps_close"

///|
extern "C" fn sync_ffi(fd : Int) -> Int = "ps_sync"

///|
#borrow(path)
extern "C" fn exists_ffi(path : Bytes) -> Int = "ps_exists"

///|
#borrow(source, target)
extern "C" fn link_ffi(source : Bytes, target : Bytes) -> Int = "ps_link"

///|
#borrow(source, target)
extern "C" fn same_ffi(source : Bytes, target : Bytes) -> Int = "ps_same_file"

///|
#borrow(path)
extern "C" fn unlink_ffi(path : Bytes) -> Int = "ps_unlink"

///|
#borrow(path)
extern "C" fn mkdir_ffi(path : Bytes) -> Int = "ps_mkdir_private"

///|
#borrow(path)
extern "C" fn rmdir_ffi(path : Bytes) -> Int = "ps_rmdir"

///|
extern "C" fn temp_root_ffi() -> Bytes = "ps_temp_root"

///|
#borrow(path)
extern "C" fn absolute_ffi(path : Bytes) -> Bytes = "ps_absolute"

///|
extern "C" fn self_ffi() -> Bytes = "ps_self"

///|
extern "C" fn millis_ffi() -> Int64 = "ps_millis"

///|
pub extern "C" fn pause(ms : Int) -> Unit = "ps_pause"

///|
#borrow(executable, args)
extern "C" fn spawn_ffi(executable : Bytes, args : Bytes) -> Process = "ps_spawn"

///|
extern "C" fn null_ffi(process : Process) -> Int = "ps_null"

///|
#borrow(data)
extern "C" fn process_read_ffi(
  process : Process,
  data : Bytes,
  count : Int,
) -> Int = "ps_process_read"

///|
extern "C" fn poll_ffi(process : Process) -> Int = "ps_process_poll"

///|
extern "C" fn process_close_ffi(process : Process) -> Unit = "ps_process_close"

///|
fn os_error() -> HostError {
  Io(@utf8.decode_lossy(last_error_ffi()[:]))
}

///|
pub extend HostError with Debug::{to_repr}

///|
pub extend ProcessResult with Debug::{to_repr}

///|
fn cstring(value : String) -> Bytes raise {
  guard value.length() <= 32768 && !value.code_units().any(fn(c) { c == 0 }) else {
    raise Io("path/argument contains NUL or exceeds length limit")
  }
  @utf8.encode(value[:]) + b"\x00"
}

///|
pub fn read_bounded(path : String, cap : Int) -> Bytes raise {
  guard cap >= 0 && cap <= 67108864 else { raise Io("invalid read limit") }
  let fd = open_read_ffi(cstring(path))
  guard fd >= 0 else { raise os_error() }
  let mut opened = true
  defer (if opened { ignore(close_ffi(fd)) })
  let result = {
    let size = size_ffi(fd)
    guard size >= 0L else { raise os_error() }
    guard size <= cap.to_int64() else {
      raise Limit("input/report exceeds byte limit")
    }
    let output = @buffer.Buffer(size_hint=Int::min(size.to_int(), 65536))
    let chunk = Bytes::make(65536, 0)
    while true {
      let n = read_ffi(fd, chunk, 0, Int::min(65536, cap - output.length() + 1))
      guard n >= 0 else { raise os_error() }
      if n == 0 {
        break
      }
      guard n <= cap - output.length() else {
        raise Limit("file grew beyond byte limit")
      }
      output.write_bytes(chunk[:n])
    }
    output.to_bytes()
  }
  let closed = close_ffi(fd)
  opened = false
  guard closed == 0 else { raise os_error() }
  result
}

///|
pub fn write_new(path : String, bytes : Bytes) -> Unit raise {
  let fd = open_new_ffi(cstring(path))
  guard fd >= 0 else { raise os_error() }
  let mut opened = true
  defer (if opened { ignore(close_ffi(fd)) })
  {
    let mut written = 0
    while written < bytes.length() {
      let n = write_ffi(
        fd,
        bytes,
        written,
        Int::min(65536, bytes.length() - written),
      )
      guard n > 0 else { raise os_error() }
      written += n
    }
    guard sync_ffi(fd) == 0 else { raise os_error() }
  }
  let closed = close_ffi(fd)
  opened = false
  guard closed == 0 else { raise os_error() }
}

///|
pub fn exists(path : String) -> Bool raise {
  let n = exists_ffi(cstring(path))
  guard n >= 0 else { raise os_error() }
  n == 1
}

///|
pub fn link_new(source : String, target : String) -> Unit raise {
  guard link_ffi(cstring(source), cstring(target)) == 0 else {
    raise os_error()
  }
}

///|
pub fn remove_file(path : String) -> Unit raise {
  guard unlink_ffi(cstring(path)) == 0 else { raise os_error() }
}

///|
pub fn remove_dir(path : String) -> Unit raise {
  guard rmdir_ffi(cstring(path)) == 0 else { raise os_error() }
}

///|
pub fn remove_same(source : String, target : String) -> Unit raise {
  guard same_ffi(cstring(source), cstring(target)) == 1 else {
    raise Io(
      "rollback target no longer matches the file published by this process",
    )
  }
  remove_file(target)
}

///|
pub fn absolute(path : String) -> String raise {
  let result = absolute_ffi(cstring(path))
  guard result.length() > 0 else { raise os_error() }
  @utf8.decode(result[:]).replace_all(old="\\", new="/")
}

///|
pub fn parent(path : String) -> String raise {
  let full = absolute(path)
  match full.rev_split_once("/") {
    Some((prefix, _)) => {
      let p = prefix.to_owned()
      if p == "" {
        "/"
      } else if p.has_suffix(":") {
        p + "/"
      } else {
        p
      }
    }
    None => raise Io("destination has no parent")
  }
}

///|
pub fn same_path(a : String, b : String) -> Bool raise {
  let x = absolute(a)
  let y = absolute(b)
  if windows_ffi() == 1 {
    x.to_lower() == y.to_lower()
  } else {
    x == y
  }
}

///|
pub fn temp_dir(parent? : String = "") -> String raise {
  let base = if parent == "" {
    @utf8.decode(temp_root_ffi()[:])
  } else {
    parent
  }
  guard base != "" else { raise os_error() }
  for _ in 0..<16 {
    let random = @env.rand(16)
    guard random is Some(random) else {
      raise Io("OS random generator unavailable")
    }
    let token = random.iter().map(fn(b) { b.to_hex() }).collect().join("")
    let path = base + "/.partsieve-" + token
    if mkdir_ffi(cstring(path)) == 0 {
      return absolute(path)
    }
  }
  raise os_error()
}

///|
pub fn executable() -> String raise {
  let path = self_ffi()
  guard path.length() > 0 else { raise os_error() }
  @utf8.decode(path[:])
}

///|
pub(all) struct ProcessResult {
  code : Int
  stdout : Bytes
} derive(Debug)

///|
pub fn run(
  executable : String,
  args : Array[String],
  timeout_ms? : Int = 60000,
  output_limit? : Int = 16777216,
) -> ProcessResult raise {
  guard timeout_ms > 0 &&
    timeout_ms <= 60000 &&
    output_limit > 0 &&
    output_limit <= 16777216 &&
    args.length() < 32 else {
    raise Io("invalid process resource configuration")
  }
  let block = @buffer.Buffer()
  for arg in args {
    block.write_bytes(cstring(arg)[:])
  }
  guard block.length() <= 32768 else {
    raise Io("process arguments exceed limit")
  }
  let process = spawn_ffi(cstring(executable), block.to_bytes())
  guard null_ffi(process) == 0 else { raise os_error() }
  defer process_close_ffi(process)
  let start = millis_ffi()
  let output = @buffer.Buffer()
  let chunk = Bytes::make(65536, 0)
  let mut result_code = -1
  while true {
    guard millis_ffi() - start < timeout_ms.to_int64() else {
      raise Limit("worker exceeded host timeout")
    }
    let n = process_read_ffi(process, chunk, chunk.length())
    guard n != -1 else { raise os_error() }
    if n > 0 {
      guard n <= output_limit - output.length() else {
        raise Limit("worker report exceeds byte limit")
      }
      output.write_bytes(chunk[:n])
    }
    let code = poll_ffi(process)
    if code >= 0 && n == -2 {
      result_code = code
      break
    }
    if n <= 0 {
      pause(5)
    }
  }
  { code: result_code, stdout: output.to_bytes(), }
}

///|
#borrow(message)
extern "C" fn warning_ffi(message : Bytes) -> Unit = "ps_warning"

///|
pub fn warning(message : String) -> Unit {
  let bounded = if message.length() > 1024 {
    message[:1024].to_owned()
  } else {
    message
  }
  warning_ffi(@utf8.encode(bounded[:]))
}
