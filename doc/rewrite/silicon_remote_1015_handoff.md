# Silicon remote-entry retirement — 2026-10-15

Branch: `codex/silicon-remote`, based on `origin/master` `4ab2e15fe1`.

## Counts and remaining contracts

`silicon_entry` shrank from 103 to 5 rows (98 removed), regenerated with
`analyze baseline --update --lint silicon_entry`. No rows were added. The five
remaining rows are three casino intermediate prompt-effect stages, hoist detach's
refusal-and-success input fallthrough, and the machine-refresh shim's 23 remaining legacy-browser callers. Exact reasons and needed contracts are in
[silicon_remote_module_gaps.md](silicon_remote_module_gaps.md). None is hidden behind
an annotation, renamed predicate, relaxed ceiling or path exemption.

## Converted behavior and proof

Native operations retain AI control authority, remote-access admission and borg
reach. Content providers supply actual credentials, device transactions, inventory
operations, body admission and immutable viewer facts; viewer classification grants
no control authority. Actor-local HUD questions retain their clicked-screen lifetime
and do not require wireless control. Recharge station scripts retain their original
ordered admission and actual transfer behavior. The physical cohort is documented in
[silicon_physical_1015_handoff.md](silicon_physical_1015_handoff.md).

Old-code captures passed before conversion for 35 device types plus three physical
roots, with both AI and borg rows per type. Five original viewer/UI tests also passed.
The only planned physical pin presentation change is native railing rotation menu
operations replacing the old granted verbs; its existing anchored refusal is visible
in the menu. Additional key presentation causes are recorded per class in
`intended_changes.md`; unrelated pin changes must be investigated.

The admin-holder lint now uses a proven receiver type and declared field to exclude
non-client `.holder` references; unknown, mixed and client-compatible receivers remain
checked. Its focused Rust regression passed (1 test). All ratchets passed with the
98-row baseline reduction. The final lane-ready receipt and focused-run JSON are the authoritative runtime and stamp evidence. The source is merged through master `3097a36445`; the focused list includes both mandatory pins, actual AI/borg behavior, the two constructor regressions and telecube cleanup. No full suite is run. The constructor and look cleanup repairs restore the old runtime-free pins; the master `devour` key update is separately documented.
## Merged-code verification repairs

The first merged gate found two real raw writes to public_spin after its new requirement made that field reactive; both now use its generated setter. The union include merge also retained a test include master deleted when retiring ownership(); the absent legacy test include is removed, while the native conditional-start tests remain. That gate launched no test world. Final verification explicitly selects the documented DreamMaker production cross-check, preserving the existing look oracle; native vars-order sampling differences are a separate diagnosed issue, not re-blessed here.
