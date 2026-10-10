# Retirement decoder runtime oracle

This standalone fixture reproduces the historical `process_power` packet loop,
retirement switch branch and `power_regions[events[at]]` lookup. It has no FFI,
game boot, resources or production macros. Cases cover valid numeric indexing,
an out-of-range outer index, an out-of-range inner index, and mixed packets.
Counters and completion markers distinguish branch suppression from a runtime
that aborts only the decoder call.

The current captured procedure inspection found both BYOND and native output
perform two `ListGet` operations at historical line 154. The fixture therefore
tests execution rather than assuming an omitted lookup instruction. It does
not establish the cause of the historical nine BYOND-only errors or gameplay
equivalence.

Run from the worktree, supplying authenticated SHA-256 pins for all four inputs:

```powershell
python tools/dmb/fixtures/native/power_retirement_runtime/run.py `
  --native E:/path/to/frozen/dmbc.exe --native-sha256 <sha256> `
  --template tools/dmb/fixtures/native_template.bin --template-sha256 <sha256> `
  --dm 'D:/Program Files (x86)/BYOND516/bin/dm.exe' --dm-sha256 <sha256> `
  --dd 'D:/Program Files (x86)/BYOND516/bin/dd.exe' `
  --dd-sha256 2e3815875c4dcf3c50de70c1c6e017849efe8697c428f02ab9ee77c306c8abf0
```

The helper checks pinned DreamMaker 516.1687, copies the same committed fixture
into separate owned E: directories, compiles native without daemon/cache using
two workers, and acquires its exact published generation through the compiler.
Children are hidden and bounded: native compilation 300 seconds; BYOND compile,
acquisition and each trusted DreamDaemon run 30 seconds. Only owned children are
terminated on timeout. Each DD child inherits Windows error mode 3, suppressing
critical-error and crash dialogs; the parent's mode is restored in `finally`.
All registered owned children share a sampled 4GB private-memory budget. This
is a 200ms boundary/sample guard, not a strict peak or descendant-memory proof.
Source and executable hashes are checked before/after.
Outputs/logs stay in the new receipt directory for review; no foreign files or
processes are removed. `complete` means this fixture finished, not compiler
coverage. Equality compares ordered markers and exact runtime counts/messages;
standalone runtime source coordinates are explicitly unavailable.
