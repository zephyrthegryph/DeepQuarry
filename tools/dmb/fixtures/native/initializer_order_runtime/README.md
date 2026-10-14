# Initializer startup ordering oracle

The first included declaration reproduces the generated game bootstrap's
procedure-static `world.Genesis()` call. Later declarations interleave constructors,
semicolon-separated cache declarations and procedure statics. Genesis checks typed
availability without dereferencing HiddenInitializer values.

`discovery_receipt.json` preserves the original independent BYOND 516.1687 capture,
including executable pins, exact source hashes and observations. Its native result
is the historical discrepancy, not a passing gate. `run.py` authenticates the current
fixture against those source hashes and requires **each** backend to match the exact
captured BYOND sequence. Matching but incorrect backend results are rejected.

Run with the same native/template/DM/DD path and SHA arguments as
`../power_retirement_runtime/run.py`. The reused launcher bounds compilation to
300 seconds and runtime to 30 seconds, samples owned private memory against 4GB,
uses trusted hidden mode with inherited error-popup suppression, and preserves
owned evidence. No compiler fallback is used.

The separate owner/root/forward-reference probes investigate allocation partitioning.
Their original evidence remains under `E:/dq-cache/dmb-initializer-order/`; these
sources do not themselves establish a passing native gate. Native dense variable-record
allocation still differs from BYOND: the production ordering fix targets symbolic
startup execution and shared-variable membership, not byte-identical dense table IDs.
This fixture does not establish game boot or whole-program runtime parity.
