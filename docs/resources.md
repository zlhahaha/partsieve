# SDK work allowance and cancellation (0.7.0-spike)

All document SDK entry points accept optional `control : WorkControl`: `assess`,
`audit`, `inspect_graph`, `plan`, `prepare`, both rebuild families and both
verifiers. Existing calls remain valid. Each call creates its own default
control unless a caller supplies one. Share a single instance across calls to
bound an entire prepare/rebuild/verify workflow, including repeated internal
parses and independently generated expected output.

```moonbit
let control = @sieve.WorkControl::new(work_units=50000000)
let prepared = @sieve.prepare(input, control~)
let result = @sieve.rebuild_verified_with_plan(
  input, prepared.to_json(), control~,
)
println(control.used())
```

Run the complete example from the repository root:

```powershell
moon run examples/resources --target native --deny-warn
```

`WorkControl::new` accepts 0–1,000,000,000 units; the default is 500,000,000.
`used()`, `remaining()` and `stop_reason()` expose its state. `cancel()` or a
`should_cancel : (String) -> Bool` callback stops it permanently. Use a new
control to retry. A callback can read a caller-owned cancellation flag or
deadline; keep it quick and do not reenter the SDK with the same control.
The stage string is diagnostic and may change between versions. Controls are
intended for synchronous use, with no cross-thread synchronization guarantee.

```moonbit
let control = @sieve.WorkControl::default()
control.cancel()
let report = @sieve.assess(input, control~)
// report is Incomplete, cannot permit rebuilding, and has no input hash.
```

Allowance exhaustion and cancellation raise `SieveError::Incomplete`. `assess`
returns an incomplete assessment with unchecked capabilities instead of raising.
No successful rebuilt value or Receipt is returned on these paths. Failed
assessment diagnostics must not hash the input outside the shared allowance.
The SDK returns bytes in memory and does not publish files; callers must handle
errors before writing anything. Native CLI workers use the default allowance
and retain their separate process timeout and output publication checks.

## What is counted

Work units are deterministic accounting credits, **not CPU instructions,
milliseconds or heap bytes**. Current charges cover input/readback bytes,
decompressed entry CRC and hashing bytes, XML bytes and 4 KiB scan blocks,
parser events, graph/profile/operation scans, guarded pairwise scan reservations,
source rewrites, output writing and final verification. ZIP cancellation polls
cost 1,024 units each. Pair reservations check division before multiplication
to avoid count overflow. ZIP aggregate expansion is additionally capped by
the smaller of `Limits.total_bytes` and the remaining allowance at read start.
The existing entry, total, XML, count and output limits remain in force.

Checks occur inside ZIP read/decode through flate 0.8.4's cancellation callback,
within long XML scans and between parser events, graph/profile steps, source
rewrite events, plan operations, actual-output checks and final Receipt return.
ZIP writing and individual SHA/UTF-8/parser operations have checks around them;
they cannot be forcibly interrupted mid-call. There is no hard cancellation
latency, wall-clock or total heap guarantee. The caller already owns input
bytes before entering the SDK. Use an isolated process with an external
deadline when a hard stop is needed.

WorkControl is runtime policy, not serialized authority. Saved plans and
Receipts retain their document `Limits`; a supplied JSON plan cannot replenish
or disable the caller's runtime allowance. Work counters are not part of the
preservation Receipt; record them separately if needed. Accounting can change
with future implementations, so avoid hard-coding a measured exact amount as
a cross-version contract.

## Resource regression

```powershell
./tools/check-resources.ps1
```

The driver uses self-constructed derivatives of the existing licensed business
fixtures, without executing macros. Five successful cases exercise Word text
near 1/4/7 MiB and worksheets with 5,000/20,000 rows. Large XML is stored without
compression so input size is exercised too. Each case also checks one-less
work/input/output allowances and cancellation during XML and ZIP processing.
Two further cases exceed the 8 MiB XML ceiling or the 200,000-node ceiling and
must return Incomplete with no successful rebuilt value. These are bounded
sample observations, not a claim that all files up to the byte ceilings pass.

`tests/generated/resources-v7.json` records input/output bytes, hashes, work
usage, elapsed time and available process peak working set. A run includes
fixture creation, a successful rebuild and negative checks. Memory is sampled
while the child is running; a null/zero peak means unavailable. Timing and
memory are observations, not CI thresholds or measured cancellation latency.
Windows and Linux CI run this matrix; generated large documents stay local
and are excluded from the Mooncakes package.
