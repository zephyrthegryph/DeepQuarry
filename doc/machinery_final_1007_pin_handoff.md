# Machinery final pin repair — 2026-10-07

Production source remains the machinery-final tip 5a09c4e569 (the same tree as integration merge 8d0de1539c). This follow-up repairs the test producer, completes the pin records and documents their class causes.

- Conversion pins: 155 files, 2,513 differing rows refreshed; the subsequent global conversion capture completed without failure.
- Hit pins: 40 files, 468 differing rows refreshed after producer repair (49 added, 419 removed). Twenty-six classes now record actual public `is_emagged: 0 -> 1` effects. Cache allocation identities are excluded; nine real chameleon fixtures warm persistent choice caches before global measurement.
- Every class cause is documented in `doc/rewrite/intended_changes.md`, including `gen_robot_interaction_swallow` → `robot_remote_blocked`.
- Wish granter nothing → Touch and mob spawner button nothing → Spawn mob are intended native screentip exposure of existing legacy hand interactions. Source parity was reviewed; their effects were not separately executed in this repair.

## Validation and preserved issues

One actual DreamMaker compile: 0 errors, 42 existing warnings. DreamChecker: 0 diagnostics. Build lint and ratchets passed; engine_layering remains enabled at zero. No baselines, ceilings or ALLOW annotations changed.

Focused names: `/datum/unit_test/dq_conversion_pin` and `/datum/unit_test/dq_hit_pin`. The initial batch reused the unchanged test binary and captured the expected mismatches. The user approved one additional combined batch for the repaired producer; that batch compiled the changes, booted cleanly and had no STATE LEAK lines. Conversion-pin comparison completed without failure; hit-pin comparison failed only on the 468 differences subsequently reviewed and accepted. It is not reported as a post-refresh runtime pass. No third test run, full suite or shards were used.

After acceptance, an independent file/row audit confirms all 195 refreshed files exactly match their real capture outputs. All 62 master EMP-1 refresh_queued rows remain unchanged, including the four reported inherited master failures. Electronic-assembly op-clash and anomalock-heart runtime pin files are byte-identical to origin/master; neither is blessed away. The existing stardog and Nikki-rig construction-failure rows still record their same faults, with only the moved diagnostic source path updated.

Evidence: `data/codex-machinery/pin-repair-capture.log`, `pin-repair-verified-capture.log`, `pin-repair-lint.log`, `pin-repair-ratchets.log`; final test result `data/test-runs/20261007T205236_5a09c4e569.json`.

## Follow-up finding

Source review suggests a separate repeat-emag gibber bug: its on_emag handler toggles the subversion state off, but native emag completion sets that key true again. The one-hit capture proves first-use subversion, not this second-use behavior. A two-use behavior test is needed before fixing it. No production fix or appearance-bridge edit was made here.

## Worktree cleanup and C: audit

Removed the archived, merged and clean obsolete checkouts `E:/projects/DeepQuarry-interim` and `C:/Users/bmene/.codex/worktrees/om-retirement-codex/CHOMPStation2`. Their ignored drafts/configuration were archived with verified ZIP integrity under the current worktree's `data/retired-worktrees/`; Git history and branches were retained. The C: removal initially hit a locked empty directory, which was subsequently removed without terminating another agent's processes.

C: still contains the active compiler-architecture and native-v2 checkouts, both with unfinished work during audit. Compiler-architecture also has a registered detached history-smoke worktree under its target directory. Those belong to the compiler lane and were preserved. Other C: names (dmb-format, lean-modularization-merge-check and wave2 remnants) are unregistered, mostly empty or metadata-only directories; they are not additional full Git worktrees. A recursive size scan was stopped as unnecessarily expensive; no unverified directory sizes or exclusive reclaimed-byte count is claimed amid concurrent cleanup/activity.

Round 3 remains queued after this branch is integrated. This repair pushes only the branch and stops.
