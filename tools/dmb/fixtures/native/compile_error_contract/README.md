# Compiler error contract

Eighteen tiny, independent compiler-only controls use the existing
`loop_local_diagnostics` paired driver. No DreamDaemon, alternative executor,
cache, or compiler implementation is added.

The corpus covers missing initializer calls (including a multiline call),
missing body calls/variables/types, malformed signatures/defaults, a missing
default call, duplicate named arguments, local/type static declarations, and
inherited variable/static redeclarations. `valid_control` supplies an ordinary
accepted-case contrast. Names describe the authored construct; BYOND legality
of duplicate and inherited forms is **observed**, not assumed.

## Run

Run from the compiler checkout, providing the immutable native executable and
its exact SHA from its build receipt:

```powershell
python tools/dmb/fixtures/native/compile_error_contract/run.py `
  --native $nativeCompiler --native-sha256 $nativeSha `
  --template E:/projects/dq-wt/dmb-review/tools/dmb/fixtures/native_template.bin `
  --template-sha256 9221528efb715be5b8df23020989e0c2a53ea32bff9894747166dbe04d785540 `
  --dm "D:/Program Files (x86)/BYOND516/bin/dm.exe" `
  --dm-sha256 8cac7e8bd48219f8a7fb622535a1ce1a914d0a9a3e909bc9ceb84b3074709dc0 `
  --output-root E:/dq-cache/dmb-compile-error-contract
```

`--cases NAME ...` selects a bounded subset; `--backend byond-only` records
reference observations without claiming paired parity. Each child has a
30-second limit, the serial run has a 300-second limit, and the existing owned
Job caps aggregate committed memory at 4 GiB and reaps children. Source and
executable/template hashes are checked before and after the run.

## Evidence and acceptance

The receipt retains every backend exit status, raw logs, exact diagnostic
file/line/severity/message, acceptance comparison, rejection-class comparison,
and exact diagnostic comparison. Native exit classes follow the existing
typed `RequestFailure` contract: Source=2, Internal=70, InvalidRequest=64,
Infrastructure=1, Cancelled=75. Signals and unknown exits remain OtherFailure.
An Internal rejection cannot satisfy a BYOND source rejection.

The shared runner currently requires acceptance, rejection class, and exact
diagnostics to agree. No wording normalization, source-error whitelist, or
assumed error-location golden is applied. A demonstrated and documented wording
difference can be considered separately; source acceptance and rejection class
must still agree. Actual paired evidence exists in
`E:/dq-cache/dmb-compile-error-contract/20261011-4bf/df5ca5ee29e34857a489e631f4b16cc8/receipt.json`:
all 18 acceptance/rejection classes agree, while the missing modified type case
had an additional BYOND recovery diagnostic. Exact diagnostics therefore did
not all agree. Fresh reference investigation of identical source bytes did not
reproduce that secondary; see `../modified_initializer_recovery_diagnostics/capture.json`.
This is diagnostic coverage, not runtime or full-suite acceptance.

Pure fixture checks:

```powershell
python -m unittest discover -s tools/dmb/fixtures/native/compile_error_contract -p test_run.py
```
