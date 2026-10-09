# Medical capability bridge retirement

Based on the stamped requirements branch. Before: machinery/power production callers were 1 capabilities(), 1 cap_slot(), 1 cap_op(), 0 /datum/interaction references. All three lived in computer/medical.dm. After conversion all four counts are zero. The shared bridge remains untouched.

The old medical pin passed in the preceding 85-test lane-ready batch. Its native replacement preserves card click ranking, the usable held-item records menu, broken/unpowered physical slots and full-hands ejection fallback. The documented pin delta replaces three generated bridge keys and removes eleven duplicate refused menu rows. Verification pending.
