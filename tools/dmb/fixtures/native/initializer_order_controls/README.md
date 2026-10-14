# New-compiler ordering gate

Run only after the startup and string-registration fixes are included in the
explicit new immutable compiler pin:

    python tools/dmb/fixtures/native/initializer_order_controls/run.py --native NEW_EXE --native-sha256 NEW_SHA --output-root E:/dq-cache/dmb-order-controls-newpin

Five controls: original base, earlier unused field-name literal, earlier unused
number-returning procedure, unused numeric procedure between globals, and after
globals. Each reuses its preserved compile-only BYOND reference and exact source
hashes, then invokes the existing paired runner. That runner uses dm_compile and
fixture-mode test_world machine slots, trusted console dd.exe, independent output
namespace, per-child limits and a 300s aggregate Job. This launcher owns an outer
4GB Job with a 900s deadline, so failures/cancellation reap the whole subtree.

Passing all five requires exact constructor trace, filtered vars order and
ordered typesof output equality; no normalization or old receipt rewriting.
The base/between/after require procedure-static before globals. The early root
procedure controls require globals before procedure-static. Only the early
field-name literal changes BYOND vars order. No full-game/source-closure claim.
