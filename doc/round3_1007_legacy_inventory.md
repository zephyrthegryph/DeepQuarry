# Round 3 machinery/power residue inventory

Snapshot: branch `codex/round3-stun-asks`, starting checkpoint `dc3a7bb630`.
Scope: `code/game/machinery/` and `code/modules/power/`; replacement definitions
and design/lint contracts were inspected across the repository. This is a source
inventory, not a lint or runtime result. No source conversion, build, test,
baseline change or lint run was performed for this document.

## Correct the previous classification

`doc/machinery_final_1007_remaining_legacy.md` inventories real sites, but its
suggested separate loot/cache migrations are superseded by the current design.
`doc/rewrite/final_api.html` section 17 explicitly **keeps** `DECLARE_LOOT` and
the `LOOT_*` language, and **keeps** `DECLARE_SHARED_CACHE*` and `CACHED*`.
Section 18 repeats those decisions. These APIs are not missing replacements.
Do not rename them, wrap them under capabilities, or remove their registries
merely to make an OM-name search empty.

The requirement contract in the actual section 17 is `req(PROC_REF(x),
because = MSG(y))`, with `x(datum/act/A)` returning TRUE/FALSE. The older
null-or-reason rule in AGENTS' target table does not describe this updated
design. A legacy reason-string return cannot be carried into a boolean condition:
it would allow the operation.

## Kept declarations: seven, plus two keyed-cache reads

| API | Count | Paths and source lines | Readiness |
|---|---:|---|---|
| `DECLARE_LOOT` | 4 | `deployable.dm:326`; `paradox.dm:60,76,107` (machinery) | Kept; definition `code/__defines/loot.dm:23`. Preserve chance, subtype selection, portal tables and mob spawn policy. |
| `DECLARE_SHARED_CACHE` | 3 | machinery `floor_light.dm:1`, `pipe/construction.dm:272`; power `lighting.dm:10` | Kept; definition `code/__defines/shared_cache.dm:43`. All three use `SC_NEVER`. |
| `CACHED_KEY` | 2 | machinery `floor_light.dm:160,164` | Kept; retain colour, state and layer in cache identity. These are uses of the first declaration, not two further registries. |

## Compatibility aliases: six call sites

| Name | Count | Paths and source lines | Real implementation and migration gap |
|---|---:|---|---|
| `OM_WORLD` | 1 | machinery `doppler_array.dm:26` | Macro `code/__defines/om.dm:220` resolves `GLOB.om_world`. Design target is `world_owner()`, but inspection finds no executable definition of that accessor under `code/` (only a documentation example). This replacement has not landed; a renamed macro is not migration. |
| `om_native_watch_of` | 1 | machinery `machine_service.dm:247` | `code/datums/om/native.dm:3` forwards to `kernel_native_native_watch_of`, defined `code/engine/hooks/native_watch.dm:79`. Generic watch handle lookup, not the gas-watch hub. Engine functionality exists; retire the compatibility API only with all callers and appropriate public boundary. |
| `om_playsound` | 2 | machinery `computer/atmos_alert.dm:51,54` | `code/datums/om/after_helpers.dm:65` invokes `playsound(src, soundin, vol, vary)`. Timers already use `after()` and keyed replacement. Actual sound-set/effect conversion must preserve major/minor sounds, location, volume, variation and repeat cancellation; replacing the callback's name is insufficient. |
| `om_qdel_self` | 1 | machinery `transportpod.dm:69` | `code/datums/om/after_helpers.dm:16` calls `spent(src)`. Preserve delayed disposal, lifecycle consequences and timer ownership when moving to a genuine declared expiration/effect. |
| `om_step` | 1 | power `singularity/singularity.dm:307` | `code/datums/om/after_helpers.dm:69` calls `step(src, d)`. Preserve delayed single movement and direction capture; do not confuse it with construction graph `stage()`. |

Two occurrences of `om_range` (`cryopod.dm:512` and
`telecomms/telecomunications.dm:695`) are legitimate **overmap range** named
arguments. They are not OM compatibility aliases.

## Legacy requirements: twelve tokens on eight rows

| Token | Count | Rows |
|---|---:|---|
| `REQ_INTERACTION_REACH` | 6 | `machinery_interactions.dm:29,34,41,48,54,59` |
| `REQ_ON` | 3 | `machinery_interactions.dm:29`; `frame_construction.dm:130,305` |
| `REQ_PROC` | 1 | `machinery_interactions.dm:59` |
| `REQ_REACH_ADJACENT` | 2 | `frame_construction.dm:130,305` |

The comment mentioning `REQ_PROC` in `machinery_maintenance.dm:75` is not an
executable call and is excluded. These counts are not twelve independent
operations: several requirements share the same row.

Six rows belong to abstract `/datum/interaction/machine_*` bases. Their entry
routes, categories, silicon/telekinesis behavior, hand-gate ordering and ungated
variant remain part of the legacy adapter contract. The old
`can_operate_by_hand(actor, target, held)` can return reason text. A native
conversion needs typed act conditions, actual read dependencies and typed
reasons, with effect-only fumble/sound behavior retained outside requirements.
Do not replace the abstract `requires` list with a spelling alias of `needs()`.

Two rows belong to the **legacy frame construction graph**, not the modern
state-graph implementation. `frame_construction.dm` selects
`/datum/construction_graph/frame` through `construction_graph` and declares
legacy interaction edges. Native `construction()` exists at
`code/engine/declare/graph.dm:251`; `start()` and `stage()` exist at lines 40
and 64. Native `req()` and `req_adjacent()` exist in
`code/engine/parts/cond.dm:164,393`. Availability of those constructors does
not migrate this graph: preserve its initial states, per-frame-class edge
availability, tools/material consumption, transition effects, reverse edges,
refunds and generated menu order. `accepts_board` and `has_all_components`
need act-based boolean wrappers with truthful reads/reasons as part of that
graph conversion, not a call-name substitution.

The inspected hard-ban list (`tools/ci/lint_scopes.toml`,
`[lint.legacy_forms.lists]`) does not list these requirement names or the kept
loot/cache names. Existing definitions are therefore residue requiring a real
conversion, not evidence that a source search alone found a hard-ban failure.
`legacy_forms` is a code-token hard ban, with no baseline, implemented in
`tools/analyze/src/lints/legacy_forms.rs`.

## Adjacent ownership work: thirty calls, separate contract conversion

The earlier inventory also records `own_bring_in` (6), `own_clear` (6),
`own_move` (7), `own_remove` (4) and `own_take_member` (7): thirty sites.
Their complete grouped file/line lists remain in
`doc/machinery_final_1007_remaining_legacy.md`. These are not generic naming
aliases: intake, release, delete and move policies must remain correct.
The seventh textual `own_clear()` match is a comment in power
`fusion/core/_core.dm:78`, excluded from the six executable calls.

Native `rel_remove`, `rel_clear`, `rel_take` and `rel_move` exist in
`code/engine/declare/relations.dm:303,314,334,354`; section 6 specifies their
semantics. Availability does not certify that the thirty destination fields
have the required `owns_*` declarations or matching `on_destroy` policies.
Convert declarations and custody paths together; particularly preserve
explicit `OWN_DELETE` behavior and atomic moves between owners. Do not call a
new `rel_*` wrapper while leaving an undeclared legacy ownership field.
The implementation also deliberately differs from the prose's omitted-member
`rel_take()` example: on a list-shaped field, omitting both member and key takes
nothing; `rel_take_all()` is the actual all-members operation. Preserve the
implemented contract when converting callers.

## Reserved follow-up and verification

The 22 appearance bridges (5 `DECLARE_APPEARANCE`, 17
`DECLARE_APPEARANCE_PROC`) are reserved for the look/draw sweep and were left
untouched. Kept caches can supply that sweep's appearance artifacts.

This document proves only inspected source classification. Root owns the
single final generation/lint/focused-test pass. No runtime parity, dependency
coverage, state-graph round-trip or remaining-sweep completion is claimed here.
