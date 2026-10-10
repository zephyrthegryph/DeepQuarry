# Safe receiver and catch declaration controls

Ten independent paired compiler-only controls cover safe-dot calls on untyped and
typed receivers, source-declared and native methods, missing methods, and catch
bindings that collide with parameters or locals. Distinct and typed catch bindings
are positive controls. No native outcomes are assumed before capture.

Run `python run.py --native EXE --native-sha256 SHA --template DMB
--template-sha256 SHA --dm EXE --dm-sha256 SHA` with explicit authenticated files.
DreamMaker must match pinned 516.1687. Outputs default to
`E:/dq-cache/dmb-safe-receiver-catch-diagnostics`.

The existing ownership helper runs compiler children serially under one 4GiB Job,
with 30 second child and 90 second total watchdogs and unconditional reap. No
DreamDaemon starts. Receipts preserve exact source and executable hashes, status,
all diagnostic locations/messages, acceptance, source-rejection classification,
and exact diagnostic agreement separately. Exit requires acceptance and rejection
classification agreement; diagnostic mismatches remain visible without rewriting.

`--backend byond-only` captures authenticated reference observations without a
native compiler or template; only DM and its SHA flags are required. Default
`both` still requires all pins. `byond_observations.json` freezes the captured
reference outcomes; runner rejects changes without claiming paired parity.
