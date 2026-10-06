# Retiring the object-model framework (`code/datums/om`, `code/datums/entity_state`)

Status: **[in progress]** on `rewrite/om-life`. Target API: [final_api.html](final_api.html) (sections 3, 4, 5, 7, 10, 13
and 17). Life history: [archive/life_on_om.md](archive/life_on_om.md), [life_sequences.md](life_sequences.md).

The intermediate object model (OM) was the bridge between the procedural tree and the final API. Most of its public
forms now have a final-API replacement in `code/engine`, `code/controllers/kernel` and `code/datums/reactions`. This
plan moves what is left, then deletes the layer with no shims.

## 1. Inventory (origin/master at the branch point)

Counted outside `code/datums/om`, `code/datums/entity_state` and generated files (`count.sh` in the session notes:
`grep -E` per form, lines and files).

| Form | Lines | Files | Final form | Kind |
|---|---:|---:|---|---|
| `OM_FIELD*(` | 212 | 145 | `TRACKED(T, v)` and its setter; `STAT` where several things force it | codemod |
| `om_after*(` | 161 | 76 | `after()`, `every()`, `hold(lasts =)` | codemod + hand |
| `om_ask*(` | 52 | 21 | `asks()` in an op's Wait, `request()` | hand |
| `EVENT_HANDLER` | 191 | 111 | `on_notice` / `on_change` handlers (the marker goes; the handler stays `SHOULD_NOT_SLEEP`) | codemod |
| `/datum/om/stage` (Life + machine stages) | 839 | 129 | `seq_step()` procs on the mob type (Life); `every()` / `on_change()` (machine) | codemod + hand |
| `/datum/om/pipeline` | 166 | 37 | `/datum/sequence/life`; machine reactions | hand |
| `OM_EMIT` | 186 | 105 | `PUBLISH()` / `ACT_TRY()` (`om_event_map.json`) | codemod |
| any `/datum/om/` | 3691 | 694 | | |
| any `om_*(` call | 3091 | 824 | | |
| framework | 13938 + 13324 | | | |

The five named forms are about a fifth of the coupling. The rest, by framework file (external uses of the procs and
macros it defines):

| File | Uses | What replaces it |
|---|---:|---|
| `relation.dm` (`om_link`, `linked`) | ~760 | `rel_*` / `ref_one` / `link` (section 6) |
| `timer.dm` (`om_after`, `om_callable`, timer slots) | ~570 | `after()` (`reactions/timer.dm` becomes self-contained) |
| `timed_action.dm` (`om_task_timed`, 401) | ~420 | the op `wait(t)` part; the timed task moves into `code/engine` |
| `scheduler.dm` (`scheduler_advance` in tests, `om_scheduler`) | ~370 | the kernel (`kernel().sched` moves under `code/controllers/kernel`) |
| `contribution.dm` (`om_hold`, `om_has`, `om_grant`, clocks) | ~280 | the stat store (`code/engine/stats`), `grant()`, `clock_now()` |
| `entity.dm` (`om_attach`, `om_rec`) | ~230 | `every()` / sequences / membership |
| `ui.dm` (`approach`, `decay`) | ~200 | plain math helpers, moved to `code/__HELPERS` |
| `pipeline.dm` | ~185 | `/datum/sequence` (Life), reactions (machines) |
| `task.dm` (`om_busy`, `om_hold_busy`) | ~130 | a pending op; `STAT(..., ANY)` held with `lasts =` |
| `io.dm` (`om_io`) | ~110 | `request()` / `code/engine/io` |
| the rest (prompts, flow, grants, verbs, watches, events, deadline, periodic, fields, derived, checks) | ~700 | sections 7, 10, 13 |

`__defines/om.dm` (367 macros: `EFFECT_*`, `CHANGE_*`, `OM_*`) goes with the layer: statuses become stats, channels
become published keys.

By area, the forms concentrate in `modules/mob` (Life stages 535 lines, timed actions 78, fields 20),
`game/objects` (timed actions 137, fields 27), `game/machinery` (machine stages 45, fields 36) and
`modules/unit_tests` (pins of the old runner: 178 stage lines, 39 `om_after`).

`entity_state` is content (crafting, changeling, shadekin, material containers, remote view, trait states), not
framework: it is converted off OM in place and moved to the module it belongs to.

## 2. Mechanical vs hand

- **Codemod** (`tools/dx/codemods/`, one form per commit, compile once per ~50 files): `OM_FIELD` to `TRACKED`;
  `EVENT_HANDLER` removal; `om_after` with a plain proc and no list payload to `after()`; `OM_EMIT` to `PUBLISH`;
  `om_link`/`om_unlink` to `rel_*`; Life stage types to step procs (`life_stage_procs.py`: the bodies move verbatim,
  `self.` becomes `src.`, the frame calls become `F.*`, `order` becomes derived `after =` edges).
- **Hand**: Life idle rules (should_run), anything reading `type ==` on a stage, `om_ask` flows, timers that restore
  state (holds), the machine pipeline, the scheduler/clock/contribution internals the kernel still borrows.

## 3. Order

Each slice is small, lands on its own, and is pinned before it moves.

1. **L1 Life steps** (S3 of life_sequences.md). Every `/datum/om/stage/life/*` becomes a proc on its mob type,
   declared in `life_steps()` with `seq_step()`; trait stages become contributors (`seq_extra_add`); mobs
   `seq_start(/datum/sequence/life)`. The sequence keeps world-time frames (`clock = CLOCK_WORLD`) and the body's
   `advance_stasis()` gate, so stasis keeps slowing biology once (see 4). Deletes `/datum/om/pipeline/life`, the
   stage tree and `life_sequence_edges()`.
2. **L2 Life gate**: `life_sequence` bench compares against the pipeline it replaces; it becomes a gate against the
   pinned pipeline numbers, and `life_sweep` runs on the sequence (same configs).
3. **L3 Life state**: statuses (`EFFECT_*`, `om/status.dm`) become `STAT(/mob/living, x, MAX, units = LIFE_CYCLE)`
   held through the engine store; `has_status`/`status_set` keep their names on the stat layer. Stage bodies that only
   keep a status up (disabilities) become contributions.
4. **F1-F4 forms**: `OM_FIELD` (F1), `EVENT_HANDLER` (F2), `om_after` (F3), `om_ask` (F4).
5. **M machine pipeline** (S1): stages to `every()` / `on_change()` reactions.
6. **I internals**: relations, timers, timed actions, tasks, scheduler, clocks, contribution store, events, prompts,
   io: each moved under `code/engine` or `code/controllers/kernel` with its final name, callers rewritten.
7. **E entity_state**: content converted off OM and moved to its module.
8. **D delete** `code/datums/om`, `code/datums/entity_state`, `__defines/om*.dm`, the OM lints' allowances.

## 4. Life decisions

- **Stasis.** The pipeline ran world-time frames and skipped biology in paused frames (`in_stasis`). L1 keeps that
  (`clock = CLOCK_WORLD`, `begin()` advances the body's stasis counter). Moving to `CLOCK_BIO` (AFK, ambience and
  grabs slowing in stasis too) is a behaviour change recorded for L3.
- **Pre-check.** A woken step asks `should_run()` before it runs. Stages whose `idle()` was always TRUE and relied on
  a rewake (AFK, ambience) are unaffected; others get a `should_run()` that is the negation of their old `idle()`.
- **Variants** are proc overrides; a root that did nothing (`perform` empty, idle `type == root`) declares its step
  only on the mob types that override it.
- **Order** is reproduced by derived `after =` edges; `kernel_sequence_life_order` keeps checking that the human,
  mouse and trait plans come out in the old order until the pipeline is gone, then the edges are the source of truth.

## 5. Pins and gates

- Existing: `dq_life_om_tests.dm`, `kernel_sequence.dm`, the medical, body and status tests.
- Generated: `tools/dq_pin.sh` for the interactive types a slice touches.
- Hand: a frame-order pin per mob family (human, simple mob, robot, AI, pAI, bot) recording the step keys a frame
  runs, written before L1 and kept green through it.
- Bench: `life_sweep` (h32/h128/h512/mix) before and after L1; within 5%.

Behaviour changes go to [intended_changes.md](intended_changes.md).

## 6. Progress

| Slice | State | Notes |
|---|---|---|
| L1 Life steps | landed | `life_steps.dm`, `life_dispatch.dm`; pipeline, stage tree and edge aid deleted; `seq_step(once =)` |
| L1 perf | landed | one rewake timer per member; typed step dispatch (`typed_dispatch`, `run_step()`/`ask_step()`) |
| L2 gate | landed | `life_sequence` pinned against a reference runner; `life_sweep` at or under the pipeline (life_sequences.md section 9) |
| F2 `EVENT_HANDLER` | landed | `tools/dx/codemods/event_handler_attr.py` |
| F3 `om_after` | landed | `tools/dx/codemods/om_after_to_after.py`; drift is `/atom/movable/proc/drift()` on `after()`, staggers are self-rearming `after()` steps |
| L3 statuses | landed | status stats in `code/library/mob/statuses.dm`; godmode a stat; type immunities `immune_to()`; Life runs under the kernel test clock |
| F1 `OM_FIELD` | started | `tools/dx/codemods/om_field_to_tracked.py`: a field nothing names by string becomes a var + `TRACKED_BRIDGED` (same channel); fields named by a periodic gate, `OM_DERIVE_FIELD` input or stage `reads` wait for those to move |
| F4 `om_ask` | with the flows | all 32 sites are flow-bound or prompt subtypes (`analyze codemod om_ask` leaves them as residue) |
| P mob repeats | landed | the mob `DECLARE_REPEAT`s are type-level `every()` gated on a tracked var (`dq_mob_every_tests.dm`); the dizzy/jittery OM behaviours are gone |
| P disabilities | landed | trait disabilities are capabilities with `every(LIFE_CYCLE)`, granted by their trait (`added_capability`); the `handle_disabilities` event is gone |
| P observer upkeep | landed | `every(OBSERVER_UPKEEP_INTERVAL)` in `CAPABILITIES(/mob/observer)`; the OM decl and behaviour are gone |
| R relevance | landed | `STAT_RELEVANCE` (MAX, `/datum`) replaces `EFFECT_RELEVANCE`; `relevance_changed()` keeps the OM cadences in step until the framework goes |
| S suspension | landed | `STAT_SUSPENDED` (ANY, `/datum`) replaces `EFFECT_SUSPENDED`; `suspended_changed()` keeps OM timers and cadences in step |
| C bio clock | landed | CLOCK_BIO runs at `STAT_CLOCK_RATE_BIO`; stasis holds it; `clock_now()` replaces `om_clock_now()`; CLOCK_OWN and the machine/chem clocks are still OM |
| E effects | started | alpha and push blocking are stats; dead library rows deleted; left: `EFFECT_BUCKLED` (the buckle relation), `EFFECT_BODY_EFFECTS` (body), the `GRANT_*` kinds |
| V Life events | landed | status announcements, vision and darksight are FIXED actions (`world_actions.dm`); the mutations veto is deleted; Life has no OM_EMIT left |
| M machine pipeline | owned by `rewrite/machines-full` and `rewrite/pipenet-full` | they move machines off `machine_step()`; the pipeline goes with their last wave |
| `OM_EMIT` / `om_hook` | Phase C codemod track | needs `ACTION()` declarations for `publish_<x>()` |
| I internals, E, D | open | relations and slots, timed actions, scheduler, clocks, contribution store, prompts and flows, io |
