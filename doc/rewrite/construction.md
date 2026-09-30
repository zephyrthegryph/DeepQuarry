# Construction: primitives, joints and ladders

Status: **[in progress]** on `rewrite/f-look` (owner W3, construction shares the branch);
`cap_construction`, `stage()`, `cap_frame_ladder()` and the machine/computer frame ladders are
**[built]** (see [migration_guide.md](migration_guide.md) A4). Overview:
[foundation.md](foundation.md).

## 1. Shape

A construction ladder is a table of stages; each stage is an action that advances or undoes it.
Instead of hand-writing every stage as a tool entry with a message, a delay, a refund and an icon,
a ladder is composed from **primitives** and **joints**, and everything derivable is derived.

| Kind | API | Meaning |
|---|---|---|
| Primitive | `insert(part)` | Put a part in. |
| Primitive | `wire(n)` | Add `n` cable lengths. |
| Primitive | `fasten(tool)` | A fastening step (screw, wrench, crowbar). |
| Primitive | `weld()` | A welding step. |
| Joint | `fit(part)` | A part that fits into a stage (a board into a frame). |
| Joint | `plate(sheets, n, name=)` | Cover the assembly with `n` sheets of a material. |
| Joint | `parts(list)` | A set of stock parts installed together. |

Presets: `mech_chassis(result, sprite=, parts=, steps=)`, `machine_frame()`, `computer_frame()`,
`wall_frame(board)`, `girder()`.

## 2. What is derived, not written

- **Undo** comes from the fastener table: fasten forward with a screwdriver, undo with the same
  tool; the removal order is the reverse of the build order.
- **Refunds** equal what was consumed, so build-then-dismantle conserves materials.
- **Messages** come from a verb table (`insert` puts in, `fasten` secures, ...), not from strings
  per stage.
- **Icons** come from the stage index plus a prefix, following the look naming convention
  ([look.md](look.md)).
- **Delays** are per-tool defaults (a welder is slower than a screwdriver); a stage overrides only
  when it differs.
- **State** is owned by the ladder: `built_past(A, stage)` answers "has this passed stage N";
  no separate stage var on the type.
- `ladder_options(at=, undo_delay=, dismantle=)` sets the compartment the ladder works at
  (see [operations_and_actions.md](operations_and_actions.md)), the undo delay, and whether a final
  dismantle step exists.

## 3. Tests

A round-trip conservation unit test walks every ladder: build to completion, undo to the start,
and assert that the consumed and refunded materials match. A ladder that cannot round-trip is a
bug or an explicit declaration (a consumed catalyst).

## 4. Status of existing ladders

`apc_steps` and its wrappers are removed: the APC is built on the primitives (`build_insert`, `build_wire`,
`build_fasten`, `ladder_options(at = BAY_HATCH, undo_delay =, dismantle =)`; [foundation.md](foundation.md), the example). A
`dismantle` list may carry a fourth to sixth element (a holder proc saying the holder is ruined, and what it comes apart
into then). Other ladders keep working through
the current `stage()` form until they are converted.
