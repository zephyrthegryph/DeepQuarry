# Modified initializer recovery diagnostics

Eleven compile-only controls distinguish missing runtime types, empty/multiple
fields, a globally declared proc sharing a field name, known types with missing
fields, referenced versus unused globals, LF versus CRLF, and the exact earlier
fixture source bytes. They reuse the pinned serial paired driver: 30 seconds
per child, 4 GiB owned Job, no DreamDaemon. No golden is invented.

## Actual reference evidence

BYOND **516.1687**, executable SHA
`8cac7e8bd48219f8a7fb622535a1ce1a914d0a9a3e909bc9ceb84b3074709dc0`.
All four reference cohorts completed and reaped; exact receipt paths, hashes and
raw observed diagnostics are recorded in `capture.json`. These are BYOND-only
observations, not native paired acceptance.

The earlier paired receipt
`E:/dq-cache/dmb-compile-error-contract/20261011-4bf/df5ca5ee29e34857a489e631f4b16cc8/receipt.json`
contained a second `amount: undefined proc` error after the primary missing-type
error. A fresh compile of its **exact DM/DME bytes and filename**, with the same
DM executable hash, emitted only `/datum/formerly_missing_type: undefined type`.
Receipt: `E:/dq-cache/dmb-modified-initializer-recovery-diagnostics/41f42220188d40bb85907e4a0ccf37ca/receipt.json`.

The other controls likewise emitted only the missing-type diagnostic; empty
braces used `undefined type path`, and a known type with a missing field emitted
`amount: undefined var`. The historical secondary was not reproduced. Implicit
DLL/environment inputs were not exhaustively authenticated. The current parser
issues an ObjectInitializer with field assignments; it does not issue an
undefined proc call for those field names. No secondary diagnostic is fabricated.

## Run

Use `run.py --backend byond-only --dm DM --dm-sha256 SHA`; optional `--cases`
selects controls. A paired run additionally requires `--native`,
`--native-sha256`, `--template`, and `--template-sha256`. Coordinate execution.
