# Access-policy prerequisite handoff

Maintenance-vendor admission now checks the actual worn ID against the machine's
all-of policy and the selected entry's any-of policy without temporarily replacing
and then clearing the machine's access list. Three scratch writes became zero.
The refusal remains `Access Denied`. The regression checks permitted, denied and
entry-only credentials, including preservation of the exact original policy lists.

Lane-ready passed on `b62b58556060`, merged with master `3d90c1b8ec`:
30 tests passed, zero failures; production compile zero errors; DreamChecker zero
diagnostics; analyzer and ratchets clean. The test list includes
`dq_maint_vendor_access_policy`, `dq_requirement_protocol_pin`,
`dq_conversion_pin`, smoke tests and incremental appearance checks. No pins were
blessed and no full suite ran.

This is the policy prerequisite, not completion of tracked access lists. Global
object registration still overlaps twelve reserved writes: ten RCD writes in
`code/game/objects/items/weapons/rcd/walls.dm` (the five direct paths and five
deferred windoor-choice writes), plus the two private `/obj` access-check helper
assignments in `code/modules/tgui/modules/atmos_control.dm:22`. Those constructor
and tool-action paths remain for their owning lanes. Registering tracking first
would introduce tracked-write debt. The admin-edit invalidation pin is still pending.
