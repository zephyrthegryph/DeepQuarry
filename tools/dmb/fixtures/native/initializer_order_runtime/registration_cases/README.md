# Registration variants

These seven sources are exact copies of independently compiled BYOND 516.1687
probes. `capture.json` binds source, manifest, compiled DMB, compiler/runtime
executable hashes, expected markers and the preserved discovery receipts.

Run one variant with `../run_registration.py --case NAME` followed by the same
arguments as `power_retirement_runtime/run.py`. The existing launcher pins tools,
acquires the native pair, caps owned memory and disables Windows crash popups.
Each backend must match the captured expectation independently.

`world_bare`, `world_explicit` and `root_proc` distinguish relative registration
from semantic root-global access. `custom_forward` and `custom_defined` differ
in the placement of the same global callback declaration. Their different
expected sequences expose a remaining allocation-stage contract; the current
owner-only ordering implementation is not admitted as general parity.

The two mixed variants preserve an already registered owner when its known and forward callbacks occur in either source order.

These are small startup tests. They do not prove dense variable numbering,
all builtin cases, game boot or full compiler parity.
