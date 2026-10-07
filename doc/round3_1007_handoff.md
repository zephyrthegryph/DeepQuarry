# Round 3 handoff — 2026-10-07

Base: `origin/master` at `dc3a7bb6304accff8344f875d2c3d938ec0740af`.
Branch: `codex/round3-stun-asks`. Worktree: `E:/projects/dq-wt/round3-stun-asks`.

## Delivered

The stun bridge was implemented first. Living actors contribute effective stun,
knockdown, paralysis, sleeping and consciousness state to `STAT_CAN_ACT`. Status
immunities remain effective; releasing one cause does not release another.

Of the 64 original request sites, 32 now use actual declared operation `asks()`
chains and 7 obsolete, unused request sites were deleted. The other 25 remain
unchanged because the engine cannot faithfully express their complete workflow.
No legacy call was renamed or aliased to satisfy a lint.

- Slice A: 21 migrated, 5 obsolete removed, 2 gaps. Original-site table:
  [machinery dispositions](round3_machinery_asks_a.md).
- Slice B: 9 migrated, 2 unused generic machinery helpers removed, 7 gaps.
  Air-control's five questions, embedded-controller board choice, cutout choice,
  and floor/wall frame choices now run through actual operation chains.
- Slice C: 2 migrated, 16 gaps. Petrification tint and text settings use conditional
  questions on the existing UI operation. Detailed gaps:
  [request workflow gaps](round3_1007_request_workflow_gaps.md).

Slice B's seven preserved sites are four camera-assembly questions (preview
creation, rotation mutation and retry between prompts), cryopod occupant consent
(answerer differs from actor), AI-core latejoin choice (source disposal and new
core construction precede the question), and the standalone AI-core admin command
(no native command-to-operation binding). Slice A preserves medical-kiosk busy
ownership established before its question and the raw granted AI status verb.

The principal engine gaps are participant selection/handoff, real effects between
questions with cancellation cleanup, notice/timer/programmatic workflow entry,
and verb/admin-command operation binding. Starting a second operation from a
legacy effect would conceal these gaps, so those workflows remain explicit.

## Remaining legacy inventory

[Inventory](round3_1007_legacy_inventory.md) distinguishes intended kept APIs from
migration debt: 4 loot declarations, 3 shared-cache declarations and 2 cache reads
are kept by the current design. Six compatibility alias calls, 12 legacy
construction requirement tokens on eight rows, and 30 ownership-policy calls
need whole-contract migrations. The 22 appearance bridges remain for the draw
sweep, as requested.

## Verification

All edits were completed before the sole compile/focused batch/lint pass. New
coverage targets overlapping incapacitation and immunities, request cancellation,
notes confirmation, draft editing, frame revalidation, board choices, air-control
branching, timed cutout painting, and petrification settings. The ghost jukebox
fixture now exercises the actual declared rights-refusing operations.

Validation results will be recorded below before push. No full suite or snapshot
blessing is planned; focused coverage does not establish all-workflow parity.
