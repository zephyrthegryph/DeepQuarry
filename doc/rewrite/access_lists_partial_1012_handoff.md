# Console and locker access policy handoff

Branch: `codex/access-lists-partial-1012`.
Verified lane commit: `fac5d0d4d86d`, master `474304d48a`.

`req_access` and `req_one_access` now have four registered setter entries
across computer and closet families. Setters copy caller lists before
interning; ordinary VV edits, the access viewer, policy interning, emag,
EMP and cascade-unlock writers publish their real policy keys. Four test
writers also use setters. The admin-edit regression warms actual drone-console
and locker menus, edits all-of and any-of policy through VV, and checks
refusal, recovery, empty policy and caller/sibling isolation.

The first gate passed all 34 tests and compilation, but exposed inherited-field
read resolution and four missed routine writes. The approved analyzer repair
recognizes a concrete subclass setter without promoting the field's base or
untracked siblings. Its targeted Rust regression passed (one test, 207 filtered
out), including inherited helpers, generic requirements, empty policy,
plain-object/door negatives and unchanged tracked-base ownership.

The repaired lane-ready gate passed 34 tests, zero failures: production compile
zero errors, DreamChecker clean, analyzer and ratchets clean. Focused selectors:

- `dq_access_admin_menu`
- `dx_cap_access_console`
- `dx_cap_access_lock_shares_providers`
- `dq_hc_computers/robotics_cyborg_cannot_control_others`
- `dq_hc_struct/mftc/log_browser_probes_and_deletes`
- `dq_requirement_protocol_pin`
- `dq_conversion_pin`

Lane-ready added its normal smoke and incremental look checks. No full suite
ran. `untracked_inputs` shrank by 19 baseline rows: stat inputs 420 → 402,
draw inputs 1859 → 1858. No baseline increased and no allowance was added.

This is a partial landing: doors and the shared `/obj` registration remain
unconverted. Full registration still requires ten RCD writer changes in
`walls.dm` and two atmos-control constructor writes, which are reserved for
the other lanes. No initializer or tool-action path was changed here.

The 29 requirement-golden refreshes are the previously audited master changes
from `f5007aa10f5f`; their per-class causes are in `intended_changes.md`. No
golden was blessed to hide an access-policy difference. Generated dependency
files remain uncommitted.
