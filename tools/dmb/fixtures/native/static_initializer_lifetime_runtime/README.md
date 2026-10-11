# Static initializer lifetime runtime contract

Two constructions of the same datum must initialize its static slot once. Both
receivers initially read7; a write through the first is visible as19 through the
second. The instance contrast performs its initialization in `New()`, producing
11 and22 with two initializer calls. This avoids an illegal runtime expression
in an instance field default. These are independent expected values, pending
actual pinned BYOND/native execution; they do not establish historical power
runtime causality.

`run.py` reuses the existing bounded paired runtime launcher and transports the
explicit resource with digest checks. `run_retained.py` reuses the existing
single-daemon contract: initial, unchanged, body return7→13, then an unrelated
instance default insertion. Every revision requires fresh/retained DMB and RSC
byte equality plus independent BYOND runtime marker equality and no runtimes.
Each revision creates a new world; static lifetime is per world, not across DD
processes. No new runtime executor or cache is introduced.

Run either entrypoint with the same explicit native/template/DM/DD pins and an
owned E:/dq-cache output root as callable_semantics_runtime. Root dispatches the
bounded execution. No execution is performed by authoring this fixture.

## Executed evidence

On 2026-10-11, native source `00e44b6e7f` and BYOND 516.1687 matched the paired runtime contract, with zero runtime errors: `E:/dq-cache/dmb-static-lifetime-runtime/6fb283d43d1f4fce8b9fba32182946a5/receipt.json`. All four retained revisions also passed, matching fresh DMB/RSC and reference runtime values: `E:/dq-cache/dmb-static-lifetime-retained/f2c4262f6d0a4a3a895dec9b196a5f7f/receipt.json`. Two harness checks passed. This isolates static lifetime behavior; historical power-bridge causality and full-suite parity remain unproved.
