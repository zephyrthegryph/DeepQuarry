# Machinery audit handoff — 2026-10-08 (one verification batch completed; prompt correction unverified)

Branch: `codex/machinery-audit-1008`, based on `origin/master` `6cf9e920d7`. The branch contains the card, topic-gate, request-field, timer and supported timed-action work.

## Timed work

Explicit machinery/power calls fell from 27 to 3: `task_timed` 21 → 2, `task_busy` 5 → 0, `task_start` 1 → 1. Thus 24 calls were retired. Master had already retired the cutout call from the earlier 28-call inventory. Two additional indirect camera/assembly timed `use_tool` calls were converted.

Fifteen fully retired files were added to `timed_forms_converted`: bioprinter; camera and camera assembly; cloning; AIcore; doorbell; feeder; food replicator; IV drip; oxygen pump; supply beacon; suit storage unit; VR console; washing machine; breaker box. Cryopod, medical kiosk and suit cycler were not banned. Scoped bans cover the explicit task forms, not every possible legacy helper.

The port retains master's AIcore latejoin/admin asks and cloning deleted-record cleanup. Supporting fixes publish the real aggregate wire dependency, use the suit-storage tracked setter from stumble handling, explicitly cast oxygen-pump human anatomy access, and remove a stale read annotation. No debt ALLOW or ceiling increase was added.

## Remaining blockers

- Medical kiosk `task_start`: reserves the session/power before asking. Native starts run after asks; no reversible pre-question effect exists.
- Cryopod third-party `task_timed`: the passenger must answer consent while the loader remains the actor. Native asks currently force the actor as answerer.
- Suit cycler `task_timed`: immediate shock can abort before the delay. Native starts ignore the handler's return; moving the shock after the wait changes behavior.
- AIcore retains five unpinned helper-driven `use_tool` construction paths. Those were not represented as retired explicit task calls and were not converted without old-code pins.

## Evidence and tests

Historical old-code pins against `059aac8767` are reused with recorded source-equivalence evidence, not represented as a fresh current-base execution. Seventeen of 18 compared files are LF-byte-identical; AIcore's three relevant timed bodies match exactly. Individual hashes are committed in `doc/machinery_audit_1008_old_pin_provenance.json`. The earlier run verified 43 real-input old behavior checks. The prior native run had 55 passes, no failures/skips, clean boot and no state leaks; this is historical evidence only.

Ported focused files are `dq_machinery_timed_simple_pin`, `dq_machinery_timed_material_pin`, `dq_machinery_timed_occupant_pin`, and `dq_machinery_timed_conversion_pin`, plus native breaker checks in `dq_hc_machinery_behaviour`. Eighteen scoped snapshots are reused as reviewed expectations. Faster welder, wire-mending cancellation and electric charge/cancellation regressions were added after native conversion and are not claimed as old-code verified. Per-class causes are appended to `doc/rewrite/intended_changes.md`.

Current-branch generation succeeded, DreamChecker reported 0 diagnostics, and ratchets passed before the prompt-owner correction below. The single compile completed with 0 errors and 50 warnings. No full suite or shard run was performed. The focused capture changes were reviewed and have per-class causes in intended_changes.md.

## Optional energy/cell appearance audit

Native draw supports the required providers; there is no identified framework gap. Full conversion requires tracking cell charge/max-charge and all writers together with energy-gun providers and dependent redraw paths. The read-only inventory found 45 external `.charge` assignment candidates across 29 production files; these are candidates, not a proven complete semantic inventory. Energy-gun providers still mutate icon state/update held icons; thinktank recharge explicitly redraws its gun and its module overlays need joint migration. This is a supported but broader follow-up lane requiring charge, redraw and cell-swap regressions. No optional appearance source was edited.

## Other requested items

1. Teleporter card insertion now has DEFAULT + 1 priority, above the computer fallback. The sticky-card test exercises real clicks and their selected key.
2. Both syndicate-beacon topic checks are operation requirements, including inherited Virgo UI actions. The object wrapper and its lint exemption are deleted. Two tests exercise denied admission, answer-time denial and successful dispatch.
3. Medical/security/skills record prompts replace nine argument-reading computed handlers and fifteen derived fields with six typed request steps using arg_of. Three tests exercise choice and text defaults, cancellation and actual record updates.
4. All twelve machinery keeps_dead sites were audited (zero in power). Three sole-target effects dropped the flag; nine cleanup sites retain it. Twelve regressions cover deletion of users, settings, stacks, records and bodies, and independent transport-destination handle invalidation. The J6 table records each verdict.
5. Supported timed calls: 27 to 3, with fifteen completed files banned. The blockers above remain explicit legacy calls.
6. Optional charge/draw migration is audited but not included; see the coordinated writer inventory above.

The exact 75-test selection is committed in `doc/machinery_audit_1008_focus.txt`. Snapshot tests select only the affected type trees and their recorded subtypes, rather than the complete pin or i7 sweep. No unrelated master pin runtime is accepted through this selection.

Ratchets passed on the compiled revision, before the prompt-owner correction. The update only shrank baselines: usr_use 129 to 128 (oxygen pump actor plumbing), init 1269 to 1266 and dx_look_side_effects 593 to 462 (stale entries already fixed on master). Escape usr_content 134 to 133 and the admin holder ceiling 106 to 105 also shrink. These stale master entries are not claimed as new appearance/lifecycle migrations in this batch.

## Final result and verification limit

The single focused batch ran all 75 selected tests: **71 passed, 4 failed, 0 skipped**. All 49 timed behavior checks, all 12 J6 cleanup checks, the real teleporter click regression, Virgo UI admission, the five existing machinery regressions and the three scoped captures passed. Boot was clean and no STATE LEAK was reported.

Failures: `dq_e2/beacon_topic_gate_request` and the three `dq_e2/machinery_record_arg_fields/{medical,security,skills}` checks. They identified an actual prompt preparation ownership error: `request_open` owns these questions with `/datum/pending_op`, while the console/beacon is `A.holder`. Reading `owner` caused using-machine and edit-field runtimes. All six new record prompt preparations and the pre-existing beacon preparation now obtain the holder through the typed `/datum/act/op`. Tests were not weakened.

**That source correction has not been recompiled, re-linted or rerun**, respecting the one-build/one-ratchet/one-focused-batch limit. This branch is pushed unmerged for review; the four named checks need verification before integration. The branch is not claimed fully green. Reviewed snapshot captures do not depend on executing those question preparations and contain no accepted runtime rows.
