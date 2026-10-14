# Proposal: retiring the `/datum/om/*` carriers

Status: proposal (rewrite/small-forms). Recommendation at the end.

## What is left

`code/datums/om/` holds typed carriers that forward to the engine (`parent_type = /datum/time_scheduler` and so on). After the world-watch conversion
(`world_watch.dm` is gone) these are still live:

| Carrier | Live users |
|---|---|
| `/datum/om/scheduler` | `Kernel.sched`, `km_*` reports, `tick_meter`, the profilers, `SSbehaviours`, the kernel host and native phases (about 15 files) |
| `/datum/om/relation/slot/*` | about 100 containment slot declarations: `code/datums/containment/*`, `code/modules/body/slots.dm` (50), `part_slots.dm` (8), the machine occupant slots (cryopod, clonepod, dna scanner, recharge station, gibber, ...) |
| `/datum/om/edge`, `/datum/om/behaviour`, `/datum/om/check`, `/datum/om/type_table`, `/datum/om/derived`, `/datum/om/clock_def` | the registry (`code/datums/om/registry.dm` maps each to its engine type), the legacy pipelines and tests |
| `global_owner`, `behaviour/internal/timers` | the timer path under `after()` |

## The choice

1. **Rename the engine types in place.** `/datum/time_scheduler` is already the real type, so `/datum/om/scheduler` is a pure alias: replace the 15
   references and delete the alias. Mechanical; no design decision. `/datum/om/ring`, `/datum/om/edge` and `/datum/om/check` are the same kind.
2. **Slots are the real work (KR5).** `slot()` in a `CAPABILITIES` block has no parameters for `drop_resolver()`, `latent_successor()`,
   `keep_with_slot()`, body `roles` and layers, and the occupant-slot hooks (`on_link` / `on_unlink` publish `OCCUPANT_KEY`). Until it has, the
   `/datum/om/relation/slot` base stays, and it is the one carrier that cannot be an alias.

## Recommendation

Do (1) first as a pure alias sweep with a hard ban per carrier name as its last reference goes (the ban list in `lint_scopes.toml` already does this per
name). For (2), extend `slot()` with `drops = PROC_REF(x)`, `successor = PROC_REF(x)`, `keeps_with = ...`, `roles = ...` and an `on_change = PUBLISH(OCCUPANT_KEY)`
default for sealed single-occupant slots (`slot(..., sealed_occupant = TRUE)`), convert machine slots first (they carry the least), then the body and part slots
with the body lane. Delete `code/datums/om/` when `registry.dm` has no row left.
