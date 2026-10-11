# Modified procedure replay across compiler processes

This compiler-only contract starts a new `--no-daemon` compiler process for every
request through the existing `native-iteration.run_child` and 4 GiB OwnedJob.
It uses the existing compiler cache, not a fixture cache implementation.
Each request has a 30-second watchdog; the serial contract has a 300-second bound.
DreamDaemon is never started.

Five revisions cover initial capture, an unrelated body edit, relocated source,
a nested modified field value edit, and nested type deletion. Each is compared
against a separate `--no-cache` fresh compiler request with exact DMB/RSC bytes
or complete current source diagnostics. The unrelated edit and relocation require
an explicit `/proc/modified_value` `DiskHit` explanation, not merely an aggregate
hit count. Fresh output must report that procedure as `Recomputed`; resident hits
are forbidden. Every process and source digest is retained in the receipt.

Run only when the root coordinator releases the compiler gate:

```powershell
python tools/dmb/fixtures/native/modified_procedure_disk_contract/run.py `
  --native E:/dq-cache/dmb-native-v2/frozen-build/NEW.exe --native-sha256 EXACT_SHA `
  --template E:/projects/dq-wt/dmb-review/tools/dmb/fixtures/native_template.bin `
  --template-sha256 EXACT_TEMPLATE_SHA
```

Pure policy fixture: `python -m unittest discover -s
 tools/dmb/fixtures/native/modified_procedure_disk_contract -p test_run.py`.
The contract is implemented but has not been executed. It does not establish
BYOND runtime parity, six-worktree acceptance, or benchmark performance.
