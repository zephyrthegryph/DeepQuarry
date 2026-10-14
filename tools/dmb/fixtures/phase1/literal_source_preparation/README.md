# Optional literal source preparation

Authored contracts, not paired native execution receipts. These files have not
been compiled or run for this cohort. Backend tests compare ordinary ordered
preprocessing with preparation at 1/2 workers and an excessive worker request.

`project.dme` offers direct literal source candidates. `inactive.dm` is present
but contains an inactive error; `missing.dm` is intentionally absent. Neither
speculative read failure nor lexical preparation of inactive directives becomes
an input diagnostic. Canonically repeated parent includes retain the original
ordered first-visit suppression. The nested include remains an ordinary demand
read, and macro effects plus FILE_DIR push/pop stay in ordered preprocessing.
Only sources actually requested by the frontend enter its captured file ledger.

`macro.dme` demonstrates a nonliteral operand which candidate discovery leaves
alone. The current directive planner rejects macro include operands. The test
preserves that original diagnostic and proves the provider still delegates an
uncaptured path when requested; it does not claim macro includes are supported.
A separate in-memory test simulates a failed prefetch followed by a successful
required read, demonstrating no cached absence/error.

Root CLI wiring must keep NativeInputs and its borrowed provider scoped around
frontend capture, then drop unused prepared candidates before body lowering.
This is one cold request's immutable capture, not a persistent cache.
