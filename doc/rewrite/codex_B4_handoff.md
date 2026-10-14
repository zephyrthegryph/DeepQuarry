# B4 round, jobs and emergency-shuttle boundary handoff

system_boundary baseline146→116 (30 rows removed). Owner APIs replace47 private-state accesses and three external ticker methods. Ticker round-end and trivia implementations moved unchanged, preserving their original manifest positions and compile guards; the empty roundend file and its original include were removed. Readiness, job catalog ordering/identity, restrictions, mind membership, evacuation policy and manual deadline edits retain their semantics.

New tests: dq_ticker_boundary, dq_job_boundary, dq_emergency_boundary. Existing emergency system and timeclock card tests selected for the final serialized lane gate. No remaining production boundary violations found for these owners. Protected declarations and existing setters unchanged; logging preserved. Verification pending; no push or merge.


Source refresh (2026-10-14): rebased onto origin/master a75de08d85, retaining owner APIs, moved ticker methods, current master tracking/setter forms and system-global fixture restoration. Final verification is blocked by the master failures proved on B2: undefined remove_welder_salvage (mecha_wreckage_salvage.dm:30), undefined add_cards (dq_constraint_tests.dm:36), and two new base_vars rows for speak_emote/shouldnt_see (mob_defines.dm:76/170). No B4 compile, test world, generation or analyzer run was started during this refresh, and no lane-ready stamp is claimed. Verification must resume on corrected master; no baseline or ceiling was raised.
