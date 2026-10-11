# Protected entry compiler observations

Five independent controls observe goto entry into try/iterator bodies, an ordinary
within-try goto, an iterator exit, and nested catch returns. No BYOND acceptance,
error wording or runtime value is assumed. Nothing has been executed yet.

`run.py` delegates to the existing `loop_local_diagnostics/run.py` launcher: serial
compiler children, 30-second child and 90-second overall watchdogs, owned 4GiB Job,
explicit compiler/template pins, source hash checks, unconditional reaping, E-only
outputs. It never starts DreamDaemon. Use `--backend both` with `--native`,
`--native-sha256`, `--template`, `--template-sha256`, `--dm`, `--dm-sha256`, and a
fresh `--output-root E:/dq-cache/dmb-protected-entry-diagnostics`.
`--backend byond-only` needs only the pinned DM pair.

Receipts preserve exact exits and diagnostics, acceptance comparison, rejection
classification, and exact diagnostic comparison separately. Native Unsupported or
internal rejection must not count as SourceError parity when BYOND rejects source;
BYOND acceptance versus native Unsupported is explicitly an acceptance mismatch.
The shared driver retains its generic compiler-control scope wording. These are
compiler observations only, not proof of correct protected-frame runtime behavior.
A runtime fixture requires actual reference evidence first; no lowering is relaxed.
