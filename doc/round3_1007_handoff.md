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

## Slice B original-site dispositions

Lines refer to the base commit, not shifted final source lines.

| File under `code/game/machinery/` | Original lines | Disposition |
|---|---|---|
| `atmo_control.dm` | 265, 315, 330, 336, 360 | Five questions migrated into the configuration operation. |
| `embedded_controller/construction.dm` | 7 | Board choice migrated. |
| `deployable.dm` | 222 | Cutout choice migrated before the original timed effect. |
| `wall_frames.dm` | 45, 136 | Floor/wall frame choices migrated with type revalidation. |
| `machinery.dm` | 689, 701 | Unused generic frequency/text helper chains removed. |
| `camera/camera_assembly.dm` | 112, 128, 153, 170 | Preserved: preview, rotation mutation and retry between questions. |
| `cryopod.dm` | 689 | Preserved: patient is a different answerer. |
| `computer/ai_core.dm` | 167 | Preserved: source disposal/construction precede latejoin choice. |
| `computer/ai_core.dm` | 311 | Preserved: standalone admin command lacks native operation binding. |

## Final validation results — not ready to merge

The requested single DreamMaker compile was attempted with 21 focused tests
selected. It failed in **5:23** with **3 errors and 45 warnings**. All three
errors came from the unqualified `nameof(stat)` in the new global stun bridge.
That reference was corrected to `nameof(/mob::stat)` afterward. No second compile
was performed, no DreamDaemon test world started, and **zero focused tests ran**.
The corrected bridge therefore has no successful runtime verification yet.

The one `lint` run regenerated successfully and DreamChecker reported
**0 diagnostics** on the corrected consciousness reference. Biome checked 1,320
files without fixes, and TypeScript completed without reported diagnostics; the
aggregate `tgui-lint` target was nevertheless marked failed in the combined run.
Overall lint failed on `check_grep`, `sem/handlers` and `sem/reads`.

- `sem/handlers`: pandemic `release_form_written` lacked the op's declared `index`
  parameter. Corrected after lint; that final signature was not checked again.
- `sem/reads`: **18 findings remain** (15 unknown reads and 3 undeclared relation
  hops), listed below. These are unfinished migration work, not a claim that the
  engine cannot express the workflows. Fix the actual state/dependency contracts.
- Admin-holder ratchet: **108 versus ceiling 106**. The two added matches are
  petrification prompt preparation's typed `/datum/act/op` `OA.holder` reads,
  rather than `/client` admin-holder accesses. The textual lint cannot distinguish
  them. No legacy call was renamed, no annotation added and no baseline edited
  to make this pass. Resolve the lint's receiver/type classification directly.

Generation initially stopped before compilation on missing helper read
contracts. Pure text helpers now declare `READS_FROM()`, and ID name formatting
uses `READS_FROM(I)`. The initial focused-name preflight also found that the two
existing media fixtures lacked explicit discoverable type declarations; those
headers were added. Neither preflight nor generation attempts ran DM tests.

Logs remain in the worktree under `data/round3/`: `focused.log` (initial generation
failure), `focused-final.log` (transitive trim generation failure),
`focused-complete.log` (sole compile), and `lint.log`. Generated outputs and logs
are not committed. No snapshot blessing or full-suite run occurred.

### Remaining semantic dependency failures

| Flow | Missing dependency contract |
|---|---|
| Message monitor `authenticated_server` | `auth` is untracked; `linkedServer` getter is treated as an undeclared hop. |
| Food replicator `print_menu_ready` | `printing` and `products` are untracked. |
| Newscaster `new_channel_ready` | Actor `hand`, `job`, `name`; machine `channel_name` are untracked. |
| Newscaster `wanted_ready` | Actor `hand`, `job`, `name`; machine `channel_name`, `msg` are untracked. |
| Pandemic `release_print_ready` | `printing` is untracked. |
| Frame `frame_type_unchanged`, `needs_floor_choice` | `build_machine_type` is untracked in both query paths. |
| Air-control `sensor_buffer_valid`, `port_buffer_valid` | Multitool `connectable` is not declared as a relation for those hops. |

The 32 migrated-site count describes source conversions, **not passing behavior**.
The branch needs these semantic migrations and a newly authorized compile/focused
batch/lint cycle before integration. The 25 preserved workflow gaps and 22 draw
bridges remain separate from these validation failures.
