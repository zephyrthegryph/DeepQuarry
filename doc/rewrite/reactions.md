# Reactions and notices

Status: everything here is **[in progress]** on `rewrite/f-reactions` (owner W1) unless marked
[built]. Overview: [foundation.md](foundation.md).

## 1. One mechanism

"When X, run Y" is one thing. It replaces `om_hook`/`om_hooked`, `om_after` users that meant
"react", the event layer, `DAMAGE_REACTION`, `derived()` blocks, `DECLARE_PERIODIC_WHILE`,
pipelines, and `update_rust_device` pushes. A reaction has a **trigger**, a **handler** and a
delivery contract.

| Trigger constructor | Fires | Contract |
|---|---|---|
| `before_op(key_or_type, handler)` | Around an operation, before commit. May veto or return a constrained proposal. | Synchronous, non-sleeping, bounded. A changed proposal is re-validated. |
| `after_op(key_or_type, handler)` | After an operation commits. | Ordered; small handlers only, expensive work requests a run. |
| `on_notice(type, handler)` | When a notice of `type` is published on the source. | Ordered occurrence; never coalesced. |
| `on_change(list/reads, handler)` | When any read in the list changes. | Coalescible: once per entity per output per frame; sees the final value. |
| `on_cross(read, bands, handler, urgent=)` | When a value crosses a band edge (hysteresis in Rust for native values). | Threshold. `urgent = TRUE` is an urgent work item (`request_urgent`, deduped per holder, run from the kernel's U slice); otherwise it runs at the drain. |
| `every(interval, handler, when=, members=, phase=, after=, budget=, lane=)` | On a cadence, optionally only while a condition reads true. | A scheduled work item on the kernel ([scheduling_and_kernel.md](scheduling_and_kernel.md)); see section 1a. |

`on_change` has sugar that names the output it feeds, replacing the old `derived()` vocabulary:
`drawn_from(...)` (draw and hidden verbs), `ui_from(...)` (open UIs), `derive(var, reads...)` (a
cached value computed by `derive_<var>()`), `rust_push(...)` (push to Rust once per frame) and
`runs_while(...)` (`should_run`). `members = <capability type>` makes an `every` or `on_cross` run
once per member of that capability.

## 1a. Work on the kernel [built]

`every`, urgent `on_cross` and `on_notice` produce `/datum/work_item/reaction` items
(`code/datums/reactions/work.dm`), registered with `kernel_register_work()` under the type whose
table declared them when that table is built. One item exists per reaction signature: a type and its
subtypes build their own `/datum/reaction`, and all of them point at the same item (`reaction.work`).

| Declaration | Item | Handler call |
|---|---|---|
| `every(...)` on a holder type | Scheduled; the holder joins the membership key `"rx:<declaring type>:<handler>"` at init (`rx_enrol()`), leaves when destroyed. The item is keyed by (declaring type, handler): a subtype that re-declares the handler replaces the inherited every() (its table keeps the last) and owns its own item. | `handler(dt)` on each live instance |
| `every(..., members = <capability>)` on a holder type | Scheduled; runs per holder of the capability (holders join the capability key at init). | `handler(dt)` on each holder |
| `every(...)` on a `/datum/system` | Scheduled, on the system's singleton. | `handler(dt)`, or `handler(member, dt)` with `members =` |
| `on_cross(..., urgent = TRUE)` | Urgent; never on the cadence. `rx_crossed` calls `request_urgent(holder, item, deadline)`, the holder's `rx.cross_pending` carries the latest band and the first previous band, and `perform()` calls the handler. A crossing that ends where it began delivers nothing. | `handler(band, previous_band)` on the holder |
| `on_notice`, non-urgent `on_cross` | Event item (`event = TRUE`): never scheduled; delivery stays synchronous and in order, and each call adds its cost to the item. | as before |

`when` is the item's `run_when`: a var name (truthy on the holder, or on the system for a system
item) or a proc that answers TRUE (`PROC_REF`, on the holder or, for a system item, on the system,
called with the member when there is one). `phase`, `after`, `budget` and `lane` are the item's.
Enrolment is automatic for any datum whose type is on the boot list (`/datum/New()` for a non-atom, `caps_init()` for an atom); nothing calls `rx_enrol()` by hand.

**Boot pass.** `python tools/ci/derived_reads_lint.py --fix-generated` also writes
`rx_boot_types()` (each type whose `reactions()` declares `every` / `on_cross` / `on_notice`, with
`RXB_*` kinds) and `rx_boot_members()` (each capability an `every(members = ...)` runs per member of)
into `code/_generated/reads.dm`; the existing CI freshness check covers both. The kernel reads
`rx_boot_members()` when it is created, so those holders join at init. `caps_init()` enrols an atom only
when its type, or one of its capabilities, is listed, so no table is built for a type that declares no
`every()`. A member key registered after holders exist is backfilled (`kernel_backfill_members()`).
Tests add their own fixture types with `rx_boot_register(type)`.

Membership is torn down with the datum (`member_teardown()` in `rx_teardown()`), whether or not it has
reaction state, and the item forgets its execution token (`kernel().member_left()`).

## 2. Static and dynamic

- **Static:** `reactions()` is a per-type table proc on `/datum` (SHOULD_CALL_PARENT). The composed
  table is the type's own entries, plus each capability's `/datum/capability/proc/reactions()`, plus
  the generated reads (`code/_generated/reads.dm`). It is built once per type and interned. Old
  `derived()` entries stay valid and are folded in. The composed table gives `READERS` its static
  mask, so a tracked write nobody reads costs a mask test.
- **Dynamic:** `observe(source, trigger, listener, handler)` / `unobserve(...)` for per-instance
  subscriptions (a pending do-after watching its actor). Stored as a `LISTENER` relation, so
  teardown on either end is automatic and one of several registrations between the same pair can be
  removed without losing the others.

```text
/obj/machinery/thing/reactions()
    . = ..()
    . += on_notice(/datum/notice/emp, PROC_REF(on_emp))
    . += before_op(OP_OPEN, PROC_REF(sealed_door_veto))
    . += every(2 SECONDS, PROC_REF(charge_step), when = nameof(charging))
```

## 3. Notices: occurrences only

A notice is a typed `/datum/notice` (a `/datum/pooled`, see [pools.md](pools.md): `take_notice()` is
`take()` plus `fill()`, `publish()` releases it, fields reset from the base) describing something that
*happened*: an item was taken, a hit landed, a door opened. State ("the charge changed") is not a
notice; it is a tracked change.

```text
PUBLISH(src, /datum/notice/hit, attacker, damage)
// expands to: if(WANTS(src, type)) publish(src, take_notice(type, ...))
```

Delivery rules:
- Occurrences are **ordered and never coalesced**, and never suppressed in bulk mode. Opening and
  closing a door in one tick can leave its final state unchanged; both occurrences still happened.
- A notice published during delivery is **queued**, and delivery has a **recursion limit**.
- `WANTS(src, type)` avoids the allocation when nothing listens.
- Registrations have deterministic order, automatic teardown and tracing. A reentrant notice that
  deletes its source stops delivery safely.

Notices every atom can publish (code/datums/reactions/notices.dm): `/datum/notice/hit` (`attacker`, `item`: an item was used on it
and nothing answered, from `/atom/proc/attackby`) and `/datum/notice/slashed` (`attacker`: a shredder's claws tore at it, published
by the claw op `claw_op()` (`CAP_CLAW`) that every breakable machine declares through `machine_basics()`; the op is offered only
to an actor with claws, `req_claws()`, and only where something hears the notice, `req_heard()`). The APC listens to both
(`on_notice(/datum/notice/hit, ...)`) instead of overriding `attackby` / `attack_hand`.

A `derive()` value is tracked: when the framework recomputes it and it changed, `publish_change()` runs for it, so an
`on_change()` reaction can read it. That is how a value reached through two relation hops reaches a handler: the APC's
tracked `nightshift_lights` is read by its area's `derive(lights_nightshift, rel(apc, ...))`, and each light's
`derive(nightshift_enabled, rel(power_area, /area::lights_nightshift))` feeds its `on_change()` redraw.

| Question | Use |
|---|---|
| It happened; who cares? | `PUBLISH` / `on_notice` |
| Its value changed; recompute later | `TRACKED` setter / `on_change` |
| May this proceed? | `before_op` |
| A native value crossed a line | `on_cross` |
| Do this later or repeatedly | `after` / `every` |

## 4. Timers

`after(owner, delay, handler, key=, clock=)` is the one timer, stored as a `TIMER` relation. It is
dropped with its owner; one pending call per `key` when a key is given; `clock` selects world,
biological (stasis-aware) or machine time. `om_after` and `after_slot` become wrappers. Today's
`after`/`after_slot`/`om_after` are **[built]**; the `key=`/`clock=` unification is **[in
progress]**. `COOLDOWN_*` and `timed_set` remain for their own intents. A datum argument deleted in
the meantime arrives as null (counted, logged); `after_if_alive` drops the call instead.

## 5. Wake, urgent request, direct execution

Three different things. A **wake** clears a parked condition. An **urgent request**
(`request_urgent`, see [scheduling_and_kernel.md](scheduling_and_kernel.md)) queues one
member/work pair with a deadline. A **synchronous operation** finishes before the caller continues
(damage, pickup, transfer invariants). A bounded synchronous observer may update an immediate
safety fact but must not recursively run a whole Life frame.

## 6. Rules for handlers

- Outputs (`draw`, `tgui_data`, `derive_<v>`, `should_run`) must not write state; test builds report
  `OUTPUT WROTE STATE`.
- Handlers do not sleep; hand slow work off.
- Handlers are passed as `PROC_REF`, never a string.
- Requirements for an operation do not live here: see
  [operations_and_actions.md](operations_and_actions.md).

## 7. Event coalescing audit

`/datum/om/event` used to coalesce by default (`coalesce = TRUE`); it is now `FALSE` (an event is an
occurrence), and `skip_in_bulk` is `FALSE` as before (no event sets it). `om_emit()` consults
`coalesce` only for an event that is neither `sync` nor `before`, and only while another delivery is in
progress, so the audit covers exactly the events that are queued. Compared with
`rewrite/dx-framework`, where the default was TRUE, each event type was classified:

| Event type | Decision | Reason |
|---|---|---|
| `material_facts_changed` (`material_composites.dm`) | `coalesce = TRUE` (set explicitly); `skip_in_bulk` stays FALSE | State invalidation: "facts read from a material are stale, recompute", emitted on `GLOB.om_world` in bursts (`material_facts_changed()` from `processed_material.dm`). Only the latest matters. Its shared-cache listeners also clear before the queue, so the flag only merges queued deliveries. |
| `carry_slip`, `moved_down_stairs`, `picked_up_item`, `stun_effect` (`omen.dm`) | stays `coalesce = FALSE` | Occurrences (a slip, a fall, an item taken, a stun landed). |
| `climb_start`, `climb_shake` (`climbable.dm`) | stays `coalesce = FALSE` | Occurrences. |
| `closet_closed` (`bluespace_connection.dm`) | stays `coalesce = FALSE` | Occurrence. |
| `examine`, `moved`, `hitby` (`atom_events.dm`) | stays `coalesce = FALSE` | Occurrences. |
| `native_notice` (`native/system.dm`) | stays `coalesce = FALSE` | A native occurrence delivered in order. |
| the ~150 events of `signal_events.dm` and the other `sync = TRUE` events | no change | Delivered at once, never queued, so coalescing never applied. |
| every `before/` event | no change | Synchronous (`coalesce = FALSE` on the `before` base). |

No event was converted to a tracked change: `material_facts_changed` is emitted by a proc that has no
owning var to track. The scheduler's own wake coalescing (`min_interval` behaviours) is a different
mechanism and is unchanged.
