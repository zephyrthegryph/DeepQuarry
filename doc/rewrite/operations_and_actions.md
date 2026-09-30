# Operations, requirements and actions

Status: **[in progress]** on `rewrite/f-ops` (owner W2) unless marked [built]. The design source is
the Codex proposal, kept verbatim in [archive/unified_operations_work.md](archive/unified_operations_work.md);
this chapter is the maintained form. Overview: [foundation.md](foundation.md).

## 1. Shape

An **operation** is an authoritative, non-sleeping state transition (pick up, open a console,
toggle a lock). It is reached from an **action** (what the player means), selects a **provider** of
the needed **affordance** (the hand or interface that does it), travels a **route** (physical,
interface, UI, ...), and must satisfy **requirements** at every stage. A refusal is a typed reason,
distinct from "this operation does not apply here" (fallthrough).

They share requirements and observations; they are not one mega-datum. An operation has actor,
target, provider and commit semantics; work has timing and budget ([scheduling_and_kernel.md](scheduling_and_kernel.md));
a notice has delivery semantics ([reactions.md](reactions.md)).

## 2. Requirements

`/datum/req` flyweights, interned and shared.

| API | Meaning |
|---|---|
| `test(ctx)` | Returns null (ok) or a refusal message type. Reasons are `MSG_DEF` keys. Predicates never send messages. |
| `reads(ctx)` | State and relations that should wake or cancel a pending operation when they change. |
| `req(type)`, `req_set(bits)`, `req_clear(bits)`, `req_access()`, `req_wire(wire)`, `req_part(type)`, `req_proc(proc, reads=)` | Constructors. |
| `all_of`, `any_of`, `none_of` | Composition. |
| `cap_require(ops = key\|list\|OP_CONTROL..., needs = ...)` | Additive contract in `capabilities()`: a capability contributes requirements to every operation of a class, so each button does not repeat them. |

A machine's structure is a target-side contract: physical controls need the installed interface or
part, and every operation inherits it. Power, broken, access and cover compose by all/any with
per-operation overrides. An emergency operation (`kind = OP_EMERGENCY`) that works unpowered is a
separate operation, not a global exception.

**Requirement order:** provider, route, actor state, target contract, capability contracts,
operation needs. **Re-checked** when offered, immediately before commit, and after every wait
(prompt or do-after). A pending operation also **cancels early** when the reads of its
requirements change. Early cancel is an optimisation; commit re-validation is the guarantee.
Old gating arguments (`behind`, `blocked_by`, `locked_by`, `needs`, `works_broken`,
`works_unpowered`) keep working and map onto requirements. [built as gating; `req` API in progress]

## 3. Operation context and dispatch

`/datum/op_ctx` (pooled, [pools.md](pools.md)): actor, target, held tool, operation, provider
(and port), route, authority, id. It carries the whole context through prompts, including the
original actor when the prompt is shown to another player.

Dispatcher:
1. Find the operations the target offers; choose the intended candidate.
2. Resolve provider and route; evaluate requirements in the order above.
3. Run any prompt or timed phase. If the provider disappears, the operation cancels; silent
   substitution only when the operation explicitly permits rebinding.
4. Immediately before commit, re-check liveness and requirements against current state.
5. Run `before_op` reactions; recheck if they changed the proposal; commit without sleeping.
   The effect enforces its own structural invariants.
6. Publish tracked changes and the `after_op` reactions; presentation is queued.

**Defining operations.**

```text
cap_op(name, handler, using=, by=, via=, action=, needs=, delay=, cost=, start_msg=,
       kind=OP_CONTROL|OP_STRUCTURAL|OP_EMERGENCY, key=, at=, log=)
```

`cap_hand`, `cap_tool`, `cap_use_on`, `cap_insert` and `cap_control` become presets over `cap_op`.
`refine(key, delay=, effect=, input=/action=)` adjusts an inherited operation; redeclaring a key
without `refine`/`replace` becomes an init error. The pickup effect must not fall back to
dropping the item on the floor; server-authority moves (map spawn) use a named authority route,
never a hidden bypass. [in progress; `cap_*` entries [built]]

## 4. Affordances, providers, routes, compartments

**Affordances** are abilities supplied by a concrete provider, not Booleans on a mob:
`slot_def.provides` bits `AFF_HOLD`, `AFF_MANIPULATE`, `AFF_HOLD_SMALL`, `AFF_INTERFACE`;
`AFF_CONTROL = MANIPULATE | INTERFACE`. The active hand is tried first. Multiple providers can
satisfy a request; the resolver records the chosen one in the context.

| Provider | Offers | Limits |
|---|---|---|
| Human hand | hold, operate controls | needs arm and hand, usable grasp, free slot, route |
| Borg gripper | hold compatible items | exists while the module is installed |
| Feral mouth | carry small items | cannot do fine manipulation |
| Silicon interface | operate compatible machines | no holding slot, no physical reach |
| Telekinesis | manipulate at range | own line-of-effect and containment rules |

**Hands are ports backed by body slots and parts.** A hand slot names its `required_parts` and
provides a stable port; losing a part removes the provider, blocking or restraining leaves the
provider present but unavailable so the refusal reason is accurate. Loss of an occupied port
resolves the held item in the transition (drop or transfer policy), not on the next Life tick. A
two-handed item binds two distinct ports atomically.

**Routes** say how an operation reaches its target: `ROUTE_PHYSICAL`, `ROUTE_INTERFACE`,
`ROUTE_UI`, `ROUTE_VERB`, `ROUTE_SPEECH`, `ROUTE_MIND`, `ROUTE_AUTHORITY`. Reach is a route through
a containment and spatial graph, not adjacency. A belly interior reaches its own contents but not
a machine outside; absorption removes physical providers; a remote interface or speech may cross
the boundary. The containment edge supplies the policy once; pickup, machine use, tool use and
dragging all consult the same route resolver ([containment.md](containment.md)).

**Compartments** model a bay with its own access rules: `compartment(BAY_X, door = CAP_KEY,
route_gate = req)`. Operations, slots and ladders take `at = BAY_X`, replacing `behind =` bit
gating. A boundary capability answers `passes(route, ctx)` and `transmission(effect)` (hooks into
`containment/paths.dm`).

## 5. Actions and bind profiles

An **action** is the semantic thing a player means, decoupled from the gesture.

- `/datum/action_def/<x>`: `name`, `binds`, `radial_icon`, `category`; constants `ACT_*`.
- `/datum/bind_profile/{default,silicon,observer}` map a **gesture** to a **priority list of
  actions**.
- Input resolution: gesture, then actions, then the **first applicable operation**. A plain click is
  `ACT_USE`; a drag is `ACT_DROP_ONTO`. **There is no `alt_action`**; alt-click is just a gesture
  whose profile entry lists (say) `ACT_LOCK` before `ACT_EXAMINE`.
- `perform_action(mob, target, ACT_X)` and `test_action(...)` for code; radial/screentip data for
  UI; the UI route `act("action", {id})`; a command-bar verb for the keyboard.

Every operation can therefore be listed, explain why it is unavailable (its refusal reason), and be
bound to a key. `cap_entry_point` and the `INTERACTION_ENTRY_*` entries collapse into
`cap_op(action = ACT_X)`. [in progress; today's interaction resolver and menu are [built]]

## 6. Containment, prompts, waits

`ask_*` prompts and do-afters retain the whole `op_ctx` and re-validate on answer (built as `ask_*`
re-validation; unified with the context in progress). Prompts and I/O are the only suspension
points in gameplay code.

## 7. Hard cases (acceptance tests)

| Case | Required behaviour |
|---|---|
| Human loses a hand while holding an item | Provider disappears, item resolved immediately, pending actions using that hand cancel |
| Hand blocked, then recovers | Port identity stays; availability and reason change; no stale held item |
| Two-handed item loses one port | Released or degraded once, without selecting the same port twice |
| Borg loses gripper, keeps interface | Pickup fails; compatible machine control works |
| Feral with mouth only | Pickup selects the mouth for accepted items; hand-only controls unavailable |
| Contained or absorbed actor | Physical routes obey the boundary; permitted interior and remote routes remain |
| Prompt returns after target moved or deleted | Cancelled, or final requirements fail; no stale transfer |
| Explosion hits many targets | Every hit applies in order; views refresh once per entity/output |
| Reentrant notice deletes its source | Delivery stops safely; occurrences are not coalesced |
| Two features enrol one entity | Removing one leaves membership until the last contributor leaves |
