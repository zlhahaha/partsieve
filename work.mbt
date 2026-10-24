///|
/// A shared, sticky work allowance for one SDK call or a caller-owned workflow.
/// Units are deterministic accounting credits, not milliseconds or heap bytes.
/// The cancellation callback must be quick and must not reenter this control.
pub struct WorkControl {
  allowance : Int
  should_cancel : (String) -> Bool
  mut consumed : Int
  mut stopped : String?
}

///|
pub fn WorkControl::default() -> WorkControl {
  {
    allowance: 500000000,
    should_cancel: _ => false,
    consumed: 0,
    stopped: None,
  }
}

///|
/// The same control may be shared by prepare/rebuild/verify to bound their sum.
/// A cancelled or exhausted control cannot be reset; create a new one to retry.
pub fn WorkControl::new(
  work_units? : Int = 500000000,
  should_cancel? : (String) -> Bool = _ => false,
) -> WorkControl raise {
  guard work_units >= 0 && work_units <= 1000000000 else {
    raise Refused("work allowance must be between 0 and 1000000000")
  }
  { allowance: work_units, should_cancel, consumed: 0, stopped: None, }
}

///|
pub fn WorkControl::cancel(self : WorkControl) -> Unit {
  if self.stopped is None {
    self.stopped = Some("operation cancelled by caller")
  }
}

///|
pub fn WorkControl::used(self : WorkControl) -> Int {
  self.consumed
}

///|
pub fn WorkControl::remaining(self : WorkControl) -> Int {
  self.allowance - self.consumed
}

///|
pub fn WorkControl::stop_reason(self : WorkControl) -> String? {
  self.stopped
}

///|
fn WorkControl::poll(self : WorkControl, stage : String, units : Int) -> Bool {
  if self.stopped is Some(_) {
    return true
  }
  if (self.should_cancel)(stage) {
    self.cancel()
  }
  if self.stopped is Some(_) {
    return true
  }
  if units < 0 || units > self.remaining() {
    self.stopped = Some("work allowance exhausted at " + stage)
    return true
  }
  self.consumed += units
  false
}

///|
fn WorkControl::checkpoint(
  self : WorkControl,
  stage : String,
  units : Int,
) -> Unit raise {
  if self.poll(stage, units) {
    raise Incomplete(self.stopped.unwrap())
  }
}

///|
// Reserve bounded pairwise scans without multiplying untrusted counts first.
fn WorkControl::pairs(
  self : WorkControl,
  stage : String,
  left : Int,
  right : Int,
) -> Unit raise {
  self.checkpoint(stage, 0)
  if left > 0 && right > self.remaining() / left {
    self.stopped = Some("work allowance exhausted at " + stage)
    raise Incomplete(self.stopped.unwrap())
  }
  self.checkpoint(stage, left * right)
}

///|
fn work_digest(data : BytesView, control : WorkControl) -> String raise {
  control.checkpoint("hash", data.length())
  let hash = digest(data)
  control.checkpoint("hash-complete", 0)
  hash
}
