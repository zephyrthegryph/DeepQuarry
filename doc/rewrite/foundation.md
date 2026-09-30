# The foundation design

The foundation is the small set of concepts every gameplay feature is written in. It replaces
the object-model (OM) API (`om_*`, `DECLARE_*`, pipelines) and the interaction tables with fewer
ideas that compose. This page is the overview and the vocabulary; each concept has a chapter.

**Status.** The foundation APIs were built on branches `rewrite/f-reactions`,
`f-ops`, `f-look`, `f-rust` and `f-kernel` and integrated on `rewrite/foundation` (the APC is rebuilt on them). Forms that
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

## Target example: the APC on the new system [built]

`code/modules/power/apc.dm` is written in this shape (the integration branch `rewrite/foundation`);
`apc_steps` and its wrappers (`cap_entry_point`, `cap_entry_costs`, `cap_entry_delay`, `cap_hatch_rules`) are deleted.
The excerpt is the real code, trimmed to the declarations:

```text
/obj/machinery/power/apc
    machine_board = /obj/item/module/power_control        // type vars: what it is
    machine_wires = /datum/wires/apc
    req_access = list(ACCESS_ENGINE_EQUIP)

/obj/machinery/power/apc/capabilities()
    . = ..()
    . += wall_machine(dismantle = NONE, repair = NONE, powered = FALSE)
    . += maintenance_hatch(cover_holds = PROC_REF(cover_holds), panel_needs_cover_closed = TRUE, emag_say = "...")
    . += cell_bay(nameof(cell), at = BAY_HATCH, needs = PROC_REF(cell_bay_ready), size = ITEMSIZE_NORMAL)
    . += power_channels()
    . += powered_by(/datum/cap_system/power, role = POWER_ROLE_AREA_SUPPLY)
    . += cap_construction(
        ladder_options(at = BAY_HATCH, undo_delay = 5 SECONDS, dismantle = list(TOOL_WELDER, /obj/item/frame/apc, 1, PROC_REF(frame_ruined), /obj/item/stack/material/steel)),
        stage("frame", desc = "..."), apc_board_stage(), apc_wired_stage(), apc_secured_stage())   // build_insert / build_wire / build_fasten
    . += apc_ops()                                          // cap_control("Open interface"), the cover, the multitool reset
    . += cap_require(list(CAP_LOCK, CAP_LOCK_SWIPE), needs = list(req_clear(CAP_EMAGGED), req_proc(PROC_REF(not_hacked)), req_wire(WIRE_IDSCAN), req_proc(PROC_REF(is_working))))
    . += cap_require(CAP_EMAG, needs = req_proc(PROC_REF(emag_ok)))
    . += refine(CAP_EMAG, delay = 0.6 SECONDS, effect = PROC_REF(on_emag))

/obj/machinery/power/apc/relations()
    . = ..()
    . += rel_one(nameof(cell), /obj/item/cell, kind = RELK_OWNED, policy = OWN_SPILL)
    . += rel_one(nameof(terminal), /obj/machinery/power/terminal, kind = RELK_PAIRED, back = nameof(/obj/machinery/power/terminal::master))

/obj/machinery/power/apc/reactions()                       // only what it hears
    . = ..()
    . += on_notice(/datum/notice/hit, PROC_REF(on_hit))
    . += on_notice(/datum/notice/slashed, PROC_REF(on_slashed))

/obj/machinery/power/apc/draw(datum/look/look)             // reads, redraws, UI refreshes and Rust pushes are generated
    look.part("emagged", apc_bluescreen())
    ..()
    ...
    look.part("channel-3", "[charging]")
    look.glow("channel-3", "[charging]")                   // explicit glows
```

The lock is two ops declared by the hatch (`CAP_LOCK`, ACT_LOCK, the actor's own access, an alt-click; `CAP_LOCK_SWIPE`, an ID
in hand) and the emag one op (`CAP_EMAG`, its handler is the effect; the shared commit is an `after_op` reaction of the emag
capability). The area's lights and consoles are MEMBER relations of the area (`powered_by(POWERED_BY_AREA, role = POWER_ROLE_LIGHTING)`);
the APC reads them with `area_members(area, role)` instead of scanning the area.

Old forms map to new ones in [migration_guide.md](migration_guide.md) (Part F) and
[dx_conventions.md](dx_conventions.md). The pre-foundation design is in [archive/](archive/).

## What did not change

Damage ([damage.md](damage.md)), the body and afflictions (`doc/body_architecture.md`), containment
([containment.md](containment.md)), temperature ([temperature.md](temperature.md)), rules and
predicates ([rules.md](rules.md)), and destruction as a transaction ([lifecycle.md](lifecycle.md))
remain the domain references. They are re-expressed in foundation terms where a chapter says so
(damage packets become pooled; heat uses the one watch facility; containment edges supply route
policy; lifecycle phases release relations by kind).
