# Medical capability bridge retirement

Based on the stamped requirements branch. Before: machinery/power production callers were 1 capabilities(), 1 cap_slot(), 1 cap_op(), 0 /datum/interaction references. All three lived in computer/medical.dm. After conversion all four counts are zero. The shared bridge remains untouched.

The old medical pin passed in the preceding 85-test lane-ready batch. Its native replacement preserves card click ranking, the usable held-item records menu, broken/unpowered physical slots and full-hands ejection fallback. The documented pin delta replaces three generated bridge keys and removes eleven duplicate refused menu rows. Verification pending.

First lane-ready: production compile zero errors, DreamChecker zero diagnostics, ratchets/analyze clean; focused 36 passed and one scoped conversion pin failed. Read-only review and the pin diff found silicon/ghost admission differences, restored before retry rather than blessed. A native null-or-reason admission retains the physical provider refusals in the menu, and the card slot retains declared silicon remote reach. Added real AI/robot remote eject regression. Only key sorting, not additional pin rows, was corrected.

Repair batch: 28 passed, one pin failed; real AI/robot remote eject passed. The remaining pin differences were refusal punctuation/case and the ghost menu selecting the hand gate rather than the explicit menu binding. Restored the exact legacy refusal text and selected the menu binding first. Actor kind gates are declared req_actor_kind parts, removing the two silicon_entry lint findings without annotations. Generator preflight rejects were fixed before any further compile/test launch.
