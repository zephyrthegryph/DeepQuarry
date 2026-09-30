# The foundation design

The foundation is the small set of concepts every gameplay feature is written in. It replaces
the object-model (OM) API (`om_*`, `DECLARE_*`, pipelines) and the interaction tables with fewer
ideas that compose. This page is the overview and the vocabulary; each concept has a chapter.

**Status.** Every foundation API is **[in progress]** on branches `rewrite/f-reactions`,
`f-ops`, `f-look`, `f-rust` and `f-kernel` (integration on `rewrite/foundation`). Forms that
exist on `rewrite/dx-framework` today are marked **[built]**. Nothing marked [in progress] or
[planned] may be used in converted code until its branch merges. Old call sites are **not**
migrated by the F batch: the new API is added beside the old forms, and old procs become thin
wrappers where cheap. See [README.md](README.md) for the branch table.

## The one-paragraph model

A type declares what it *is* with three table procs: `capabilities()` (features it has),
`relations()` (what it points at), `reactions()` (what it does when something changes or
happens). State is plain vars; a var others depend on is `TRACKED`. Players act through
*actions* that resolve to *operations*, which check *requirements* and then commit. Things that
happen (a hit landed, an item was taken) are *notices*. Time-driven work is `every()` on the
kernel's host loop. Simulation state lives in Rust and reaches DM through one frame call and one
outbox. Nothing else schedules, listens, or owns.

## Vocabulary

| Concept | One line | Declared by | Chapter |
|---|---|---|---|
| **Capability** | A feature a type has (panel, lock, slot, cell bay). Contributes entries, requirements, reactions, relations and draw. | `capabilities()` | this page, [operations_and_actions.md](operations_and_actions.md) |
| **Relation** | A typed link between datums with a kind and a lifetime rule. Writing one end publishes both. | `relations()` | [state_and_relations.md](state_and_relations.md) |
| **Tracked state** | A var whose setter publishes `(src, key)` when someone reads it. | `TRACKED(type, var)` | [state_and_relations.md](state_and_relations.md) |
| **Reaction** | The single mechanism for "when X, run Y": `before_op`, `after_op`, `on_notice`, `on_change`, `on_cross`, `every`. | `reactions()` (static), `observe()` (dynamic) | [reactions.md](reactions.md) |
| **Notice** | A typed *occurrence* (not a state). Ordered, never coalesced. | `PUBLISH(src, type, args...)` | [reactions.md](reactions.md) |
| **Requirement** | A flyweight predicate returning null or a refusal reason. | `req_*()`, `cap_require()` | [operations_and_actions.md](operations_and_actions.md) |
| **Operation** | An authoritative, non-sleeping state transition with actor, target, provider and route. | `cap_op()` | [operations_and_actions.md](operations_and_actions.md) |
| **Action** | A semantic verb the player means (use, drop-onto, lock). Bound to gestures by profile. | `/datum/action_def`, `/datum/bind_profile` | [operations_and_actions.md](operations_and_actions.md) |
| **Look** | Appearance built from a base state plus naming-convention variants, parts and glows. | `draw(look)` | [look.md](look.md) |
| **Construction** | Build/undo ladders made of primitives and joints. | `cap_construction()` | [construction.md](construction.md) |
| **Pool** | A reusable flyweight datum with automatic reset. | `/datum/pooled` | [pools.md](pools.md) |
| **System / work** | A domain that owns state and API; its repeating work is `every()` items on the host loop. | `/datum/system`, `every()` | [scheduling_and_kernel.md](scheduling_and_kernel.md) |
| **Native** | Rust-owned values: one `vg_frame`, one outbox, `native_read`, no DM mirrors. | `native(key...)` | [rust.md](rust.md) |

## Design rules

1. **Declare, don't register.** Three table procs, built once per type and interned. No macros
   that register at compile time except `TRACKED`/`SETTER`.
2. **One mechanism per intent.** One reaction system (not events + hooks + derived + timers +
   pipelines), one timer (`after`), one repeating form (`every`), one relation store.
3. **State changes immediately; only idempotent follow-up work coalesces.** A synchronous
   reader sees committed state. Occurrences are never merged.
4. **Requirements are re-checked, not trusted.** Once when offered, at commit, and after every
   wait. Refusals are typed reasons, never messages sent from the predicate.
5. **Reads are demand-gated.** A tracked write does nothing unless something reads that key
   (static per-type mask or instance dynamic readers). Generated reads keep the declarations honest.
6. **Rust owns simulation state.** DM reads through `native_read`, never mirrors.
7. **Pooled flyweights** for anything allocated per event (notices, op contexts, damage packets).
8. **Everything is measured.** Per-reaction cost is in `metrics()`; benches gate each wave.

## Target example: the APC on the new system [in progress]

The integration step (W6) rebuilds `code/modules/power/apc.dm` in this shape and deletes
`apc_steps` and its wrappers. Names are the spec's; treat the exact argument lists as provisional
until the branches merge.

```text
/obj/machinery/power/apc
    // type vars: configuration only
    cell_type = /obj/item/cell/apc
    // ...

/obj/machinery/power/apc/capabilities()
    . = ..()
    . += wall_machine(board = /obj/item/circuitboard/apc)
    . += cell_bay(nameof(cell))
    . += power_channels()
    . += cap_construction(insert(/obj/item/circuitboard/apc), wire(5), fasten(TOOL_SCREWDRIVER), ...)
    . += cap_require(ops = OP_CONTROL, needs = req_part(/obj/item/circuitboard/apc))
    . = refine(., "toggle_lock", delay = 1 SECONDS, action = ACT_LOCK)

/obj/machinery/power/apc/relations()
    . = ..()
    . += rel_one(nameof(area), /area, kind = PAIRED)
    . += rel_one(nameof(cell), /obj/item/cell, kind = OWNED)

/obj/machinery/power/apc/reactions()
    . = ..()
    . += on_notice(/datum/notice/emp, PROC_REF(on_emp))      // its own notices only
    // reads, draws, UI and rust pushes are generated from draw()/tgui_data()/push_to_rust()

/obj/machinery/power/apc/draw(datum/look/look)
    ..()
    look.part("charge", charge_level)
    look.glow("charge", charge_level)                         // explicit glows
```

Old forms map to new ones in [migration_guide.md](migration_guide.md) (Part F) and
[dx_conventions.md](dx_conventions.md). The pre-foundation design is in [archive/](archive/).

## What did not change

Damage ([damage.md](damage.md)), the body and afflictions (`doc/body_architecture.md`), containment
([containment.md](containment.md)), temperature ([temperature.md](temperature.md)), rules and
predicates ([rules.md](rules.md)), and destruction as a transaction ([lifecycle.md](lifecycle.md))
remain the domain references. They are re-expressed in foundation terms where a chapter says so
(damage packets become pooled; heat uses the one watch facility; containment edges supply route
policy; lifecycle phases release relations by kind).
