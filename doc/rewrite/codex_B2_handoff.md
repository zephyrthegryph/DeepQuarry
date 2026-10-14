# B2 lighting and planet boundary handoff

The system_boundary baseline shrank146→120 (26 rows,67 private accesses converted;none remain for these owners). Owner APIs preserve append-versus-unique queue semantics, readiness, planet identity and space solar fallback. Added lighting_api.dm in the lighting owner folder and extended planet_api.dm. No tracked setters or ownership declarations changed.

New focused tests: dq_lighting_boundary and dq_planet_boundary; existing system solar/planet and solar assembly tests will run in the serialized lane gate. Verification pending. No push or merge.


## Verification attempt (2026-10-14)

Rebased cleanly onto origin/master a75de08d85; tested source commit 13a29711441f with lane-ready --no-merge --no-pins. The seven requested selectors were validated: dq_lighting_boundary, dq_planet_boundary, dq_system_solars, dq_system_planets, dq_pp/solar_output, round2_sun_visual_lazy_lists, interim_solar_assembly_sticky_tracker. The standard gate also selected its focused smoke/gameplay cases, totaling 44 tests. No full suite or shards were requested.

Generation and preparation passed. The system_boundary check passed with the branch's 26 fingerprint removals (146 to 120). The gate did not stamp the branch:

- Ratchets: master base_vars has 547 sites versus baseline 545. New fingerprints are mob_defines.dm:76 (speak_emote) and :170 (shouldnt_see).
- Production compile: remove_welder_salvage is undefined at code/game/mecha/mecha_wreckage_salvage.dm:30; one error, 87 warnings.
- Test compile: the same missing helper plus add_cards undefined on /obj/item/hand at code/modules/unit_tests/dq_constraint_tests.dm:36; two errors, 107 warnings.
- DreamChecker: two diagnostics for those missing helpers.
- No test world executed, so there are no runtime test results to claim.

All three implicated source files match origin/master byte-for-byte; this branch does not edit them. No protected declarations, annotations or baseline increases were used to bypass the failures. B3 through B6 gates were not started against the known-broken master. Verification ownership was returned to the coordinator after this gate exited.

Evidence retained under data/merge-gates/13a29711441f.tests.log, .dm.log, .ratchets.log and .timings. Gate timings: generation 3s, preparation 106s, test compile job 263s, production/DC job 251s, ratchets 82s, gate wall 381s (initial cold analyzer compilation/generation precede that measurement). Source and proof files were retained; no caches, locks or compile artifacts were pruned.
