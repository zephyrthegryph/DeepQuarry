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
| `on_cross(read, bands, handler, urgent=)` | When a value crosses a band edge (hysteresis in Rust for native values). | Threshold; may request urgent work. |
| `every(interval, handler, while=, members=, phase=, after=, budget=)` | On a cadence, optionally only while a condition reads true. | A scheduled work item on the kernel ([scheduling_and_kernel.md](scheduling_and_kernel.md)). |

`on_change` has sugar that names the output it feeds, replacing the old `derived()` vocabulary:
`drawn_from(...)` (draw and hidden verbs), `ui_from(...)` (open UIs), `derive(var, reads...)` (a
cached value computed by `derive_<var>()`), `rust_push(...)` (push to Rust once per frame) and
`runs_while(...)` (`should_run`). `members = <capability type>` makes an `every` or `on_cross` run
once per member of that capability.

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
    . += every(2 SECONDS, PROC_REF(charge_step), while = nameof(charging))
```

## 3. Notices: occurrences only

A notice is a typed `/datum/notice` (pooled, see [pools.md](pools.md)) describing something that
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
