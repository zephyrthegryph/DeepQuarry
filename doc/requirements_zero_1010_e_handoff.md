# Requirements burn-down E (2026-10-10)

Branch: `codex/requirements-zero-1010-e`, started from D. C and D are unchanged.

The requirement_bool baseline shrank from **306 to 193 (-113)**: machinery/power 47, food/industrial equipment 36, clothing/mobs 30. The analyzer update removed fingerprints only; no baseline or ceiling grew. Callback and inherited override families return null or their original reason. Ordinary Boolean query consumers retain their contract, with explicit native requirement boundaries where appropriate. No resolver, bridge or keybinding edits were made by this batch.

Five already-converted hydroponics adapters (beehive frame/bee loading, honey extractor shared guard/frame extraction, seed-storage lock) now directly implement their complete null-or-reason checks; their legacy helper bodies and duplicate refusal work are removed. Storage and food callbacks were converted after concrete old-code pins. The equipment-fit/rules tables remain unchanged pending review of `requirement_consumer_protocol_proposal_1010.md`.

Old-code proof: 18 focused test types, initially 17 passed and the pump fixture failed because it used a member ownership take on a non-owning cell view. Correcting the fixture to clear that view via rel_set(null) gave a passing failure-only repair. Thirty newly recorded concrete pin files contain 2,458 rows. Existing pins plus these cover the scoped 73-root cohort. No post-conversion interaction row was blessed for a requirement change.

Fixture cleanup: the sleeper cache is initialized in New before global leak snapshots, and Run preserves GLOB.coalesce_runs. Generator boundary fixtures clear synthetic fuel before deletion, so their actual destruction path does not spill test material.

Merge resolutions preserve master's declared starting contents on the drop pod and RIG modules and our native requirements. Both intended_changes sections are retained. Compile repair gives the new airlock null-or-reason requirement its own name (airlock_power_ready), preserving inherited Boolean power_available used by power contributions. ChemMaster's condi mode is tracked and the fixture uses its setter so native requirement dependencies can invalidate correctly.

## Verification: un-stamped, pin owners need review

Production compile: 0 errors / 43 existing warnings. Test compile: 0 errors / 57 existing warnings. DreamChecker: 0 diagnostics. Ratchets and analyze pass; requirement_bool remains 193, and no unused ALLOW was found.

Lane-ready on source 663cdafd25e1 (master 88a027490e) ran the smoke set plus our focused tests and both required pins: 76 passed, 3 failed, clean boot. Results: data/test-runs/20261010T221233_663cdafd25_focused.json. The 3 failures were snapshot comparisons, not behavior assertions. Master-only refreshes in intended_changes.md remove 45 silicon Use full-pin differences, 26 protocol-pin classes and 3 source-location-only holder files. Floor-light is explicitly excluded, so 74 files are refreshed. No requirement-conversion row was blessed.

Failure-only pin repair reused the compiled build: 1 passed, 2 failed (data/test-runs/20261010T222211_7c24f952ac.json). Full conversion pin has only 3 extinguisher-cabinet rows; the scoped E pin has only 2 Nikki constructor-error rows. The protocol pin passed against the intermediate silicon refresh, but the floor-light golden was subsequently restored exactly at the user's direction. Its fresh isolated check (also cached compile) has 6 silicon Use differences, data/test-runs/20261010T222440_7b7d0f55bd.json. The final protocol golden remains unchanged and final protocol verification therefore fails. No stale Equip row is used or accepted.

The floor-light actual file was cleared; its fresh Oct 10 output is preserved separately under data/codex-machinery/requirements-zero-1010/e-floor-light-fresh-20261010.txt. Fresh AI click is `Click: Use`, not `Click: Equip`; original golden remains `nothing`. The new robot/AI Use rows and silicon_hand key follow master 1b7d651912, separate from the stale Equip evidence. Please review this new class while leaving the original golden unchanged.

## Unaccepted constructor differences

* `/obj/structure/extinguisher_cabinet`: current empty-state wrench menu/click is Unwrench; expected click is Use. Master b744bd7644 moved initial extinguisher creation to conditional ownership starts. The unchanged ops indicate the starting extinguisher is absent. Do not bless; declaration owner should verify/fix starting contents.
* `/obj/item/rig/nikki`: declared chest type is /obj/item/clothing/suit/space/rig, but its configured chest is /obj/item/clothing/suit/fluff/nikki. First capture throws OWN refusal; duplicate error reporting is suppressed thereafter, and the repeated capture throws null.adopt_constraint. This is an existing order-dependent construction defect, not a requirement change. Neither error variant is newly blessed.

All 76 assertion tests passed, including the sleeper and the new requirement boundaries. Sleeper no longer reports its status-policy or coalesce leak. Existing smoke leaks remain in dq_construction_floor (coalesce_runs) and canister_welder (test_prompts); the existing v_nutrition_heal fixture also leaves a contagion watch-index entry. These are reported separately, not claimed fixed.

No lane-ready stamp exists because the required pin gate is not green. No passing behavior test was rerun; only failed pins and the floor-light golden check required by the user's correction ran after the combined batch. No full suite or shard run. No push to master.

Remaining: 193 requirement_bool fingerprints across 131 files. A read-only next audit identifies 27 admin/mob/window rows; client-dependent gates need real old-code coverage and shared topic/remote entry gates require coordination with the resolver owner. Separate REQ_* table-consumer inventory: 160 production source lines / 197 constructor tokens / 45 files; counts exclude definitions, generated files, tests and comments. Equipment-fit/rules migration remains pending; consent/stance/hold tables also require tracing their actual consumer protocol. No unsupported tables were converted by token substitution.
