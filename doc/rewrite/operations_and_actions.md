# Operations, requirements and actions

Status: **[built]** on `rewrite/f-ops` and wired to the reaction layer, pools and the input router at foundation integration (`rewrite/foundation-b`), unless marked otherwise. The design source is
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
`works_unpowered`) keep working and map onto requirements. [built]

## 3. Operation context and dispatch

`/datum/op_ctx` (a `/datum/pooled`, [pools.md](pools.md): `op_ctx_take()` / `release()`, fields reset automatically, poisoned on release in test builds; `op_ctx_live_count()` reads the pool's live count): actor, target, held tool, operation, provider
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

**Reactions.** `op_before(ctx)` calls the target's `before_op` reactions (`rx_before_op`, keyed by the op's key,
then by the capability type that built its entry, `ctx.capability_type()`) and its observers. A non-null answer
(a `/datum/msg` type or text) is a refusal: the commit stops, the actor is told, the context is released.
`op_after(ctx)` calls the `after_op` reactions only for an operation that committed (its handler did not refuse;
a form entry that is still asking has not committed yet, so it does not fire either).

**Pending waits.** A timed op registers its context as pending. Each `(datum, key)` its requirements read counts
as a dynamic reader of that key while it waits (`rx_watch_adjust`), so `publish_change()` is called for it and
reaches `op_reads_changed()`; a write nobody reads still publishes nothing. The context is also registered on the
actor, target, held item, provider item and watched datums (`rx_state.pending_ops`), and `rx_teardown()` cancels it
when any of them is deleted (timer cancelled, context released, `GLOB.op_pending` / `GLOB.op_watchers` cleaned).
Datums that never wait on an op carry nothing.

**Defining operations.**

```text
cap_op(name, handler, using=, by=, via=, action=, needs=, offered=, delay=, cost=, start_msg=,
       kind=OP_CONTROL|OP_STRUCTURAL|OP_EMERGENCY, key=, at=, log=, priority=, stance=, entry=)
```

`priority` (`OP_PRIORITY_*`, higher first) orders the ops of one action for a gesture (§5). `stance` (`I_HELP`,
`I_DISARM`, `I_GRAB`, `I_HURT`, or a list) narrows the op to those stances: an offered requirement, so another stance
falls through to the next op. `entry` (`INTERACTION_ENTRY_*`) keeps a legacy entry proc (`attack_hand`, `attackby`,
`attack_self`, `click_alt`) running the op for callers that still call it directly (a silicon's hand use through
`silicon_use`, a computer's any-item fallback); inside such a proc the provider and reach stages trust the proc's caller.

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
`ROUTE_UI`, `ROUTE_VERB`, `ROUTE_SPEECH`, `ROUTE_MIND`, `ROUTE_AUTHORITY`, `ROUTE_TK`. [built]

- `ROUTE_TK` is a telekinetic reach at range: the telekinesis adapter's click (`input_adapter/op_route()`). Its
  provider is the telekinesis affordance (`AFF_TELEKINESIS`, `mob/has_telegrip()`), not a slot; it stands in for
  manipulating and working controls (`AFF_TK_PROVIDES`) and holds nothing. Reach is `op_tk_reach()`: the same z-level,
  within `TK_MAXRANGE`, not while viewing remotely. An op a mind may do at range says `via = ROUTE_PHYSICAL | ROUTE_TK`.
- A silicon's empty-handed click and its windows travel `ROUTE_INTERFACE` / `ROUTE_UI`; there its interface is the
  provider of `AFF_INTERFACE_PROVIDES` (manipulate, interface), so `cap_control()` works for the AI and a cyborg.
- A ghost's click travels `ROUTE_UI` (`mob/observer/dead/op_route()`): an observer never touches. Reach is a route through
a containment and spatial graph, not adjacency. A belly interior reaches its own contents but not
a machine outside; absorption removes physical providers; a remote interface or speech may cross
the boundary. The containment edge supplies the policy once; pickup, machine use, tool use and
dragging all consult the same route resolver ([containment.md](containment.md)).

**Compartments** model a bay with its own access rules: `compartment(BAY_X, door = CAP_KEY,
route_gate = req)`. Operations, slots and ladders take `at = BAY_X`, replacing `behind =` bit
gating. A boundary capability answers `passes(route, ctx)` and `transmission(effect)` (hooks into
`containment/paths.dm`: `dq_path_step` multiplies a slot's share by `dq_bay_share()` when the slot has `at`).
The boundary is asked in ONE place, `op_at_reason(holder, bay, ctx)`: the op context's route stage and
`cap_gate_reason()` (for legacy entries with `at`) both call it. A holder that declares no such bay refuses an op
(fails closed) and lets a context-less legacy entry through.

## 5. Actions and bind profiles

An **action** is the semantic thing a player means, decoupled from the gesture. The `ACT_*` ids are the **gesture
vocabulary only**: an op is identified by its key (and its name) in the Menu, the radial and the command bar, never by
its action. Most ops answer `ACT_USE`; two ops answering one action is no collision, it is what op priority orders.

- `/datum/action_def/<x>`: `name`, `binds`, `radial_icon`, `category`; constants `ACT_*`. `ACT_ATTACK` is the
  hostile use (hostile ops declare it); `ACT_NONE` is no action at all (no definition, no gesture reaches it).
- `/datum/bind_profile/{default,silicon,observer}` map a **gesture** to a **priority list of
  actions** (`table()`), and a **stance** to the lists that replace some of them (`stance_table()`): the stance is a
  gesture modifier.
- Input resolution: gesture, then actions, then the **first applicable operation**. A plain click is
  `ACT_USE`; a drag is `ACT_DROP_ONTO`. **There is no `alt_action`**; alt-click is just a gesture
  whose profile entry lists (say) `ACT_LOCK` before `ACT_EXAMINE`.
- `perform_action(mob, target, ACT_X)` and `test_action(...)` for code, and `perform_op(mob, target, key or name)` /
  `test_op(...)` for one op by its key or name (`op_entry_named()`); radial/screentip data for
  UI; the UI route `act("action", {id})` (an action id or an op key), a UI action of the capability layer
  (`/datum/capability/entry/proc/act_action`, found by the dispatcher on any holder of op entries; no atom has one); a
  command-bar verb (`Act <action or op name>`).

**Gesture resolution order** [built]. `resolve_gesture()`:

1. the actor's bind profile: `actions_for(gesture, stance)`, the actions the gesture reaches in the actor's stance
   (`mob/input_stance()`), in the listed order;
2. within one action, the op `priority` (higher first: `OP_PRIORITY_DEFAULT` -2000, `OP_PRIORITY_NORMAL` 0,
   `OP_PRIORITY_PART` 10, `OP_PRIORITY_TAKE_OUT` 30, `OP_PRIORITY_CLAW` 40, `OP_PRIORITY_SUBVERT` 50);
3. then the declaration order (`capabilities()` order).

In that order the first op that is meant (`offered`, the held item, the stance) and would run now answers; when none
would run, the first meant one answers with its refusal. An op that does not accept the click's route at all is passed
over, and so is one the actor's adapter never allows. What the gesture does not reach stays in the Menu, the radial
(`action_options()`: one row per op key, with the action it answers) and the command bar. The per-type index is
`op_action_index()`. This replaces the resolver's `_DEFAULT` ordering (`priority = OP_PRIORITY_DEFAULT`) and the
`ROBOT` / `TK` priority 1 (a cyborg-only op is declared before the silicon one it overrides; a TK op is reached by the
telekinetic click's own route).

**The stance modifier.** The default profile's click in harm or disarm is `ACT_ATTACK, ACT_USE, ACT_LOCK`; in help or
grab it is `ACT_USE, ACT_LOCK`. So an attack op is reached by stance and never by a help click, and a harm click still
falls back to the ordinary use (a door opens in combat mode). The silicon profile does the same over its click. An op
narrows itself further with `stance =`: `stance = I_HURT` answers only harm, `stance = list(I_HELP, I_DISARM, I_GRAB)`
every stance but harm.

**ACT_NONE.** `cap_op(..., action = ACT_NONE)` is reached only by its key or name: the Menu, the radial, the command
bar and `act("action", {id: key})`. No profile lists it; the resolver answers no input with it (`default_action` is
null). The command bar runs an op over `ROUTE_VERB` when it takes it, else over the actor's own route (typing at the
thing next to you is your hand on it); a window's act needs `via` to include `ROUTE_UI`.
- **The router.** `try_interaction()` (the click path of use, alternate and tool_act) asks `try_gesture()` first:
  `INPUT_ACTION_USE` is `GESTURE_CLICK`, `INPUT_ACTION_ALTERNATE` is `GESTURE_ALT` (`GESTURE_RIGHT` for a tool's
  secondary click), and `adapter.drag()` asks `try_gesture_drag()` (`GESTURE_DRAG`, the dragged item as `held`)
  before `MouseDrop_T`. `gesture_entry_for()` resolves gesture, actions, op priority and declaration order over the
  real ops (not a `cap_hand`/`cap_tool`/`cap_use_on`/`cap_insert` preset), over the route of the actor's adapter
  (`input_adapter/op_route()`: the telekinesis adapter's is `ROUTE_TK`); that entry runs. When no op answers, the
  interaction resolver and the legacy handlers run as before, so unmigrated `INTERACT_*` content and the presets keep
  their ordering, ties and Menu. A handler that declines (returns FALSE) also falls through to them.

Every operation can therefore be listed, explain why it is unavailable (its refusal reason), and be
bound to a key. `cap_entry_point` and the `INTERACTION_ENTRY_*` entries collapse into
`cap_op(action = ACT_X)`. [built for the click, alt-click and drag gestures; the resolver and Menu remain the fallback only for a target with no matching op: an op that is refused answers the click with its own typed refusal, the legacy resolver is never asked]

**The library builds only ops** [built, G16]. Every entry a library capability builds is a real op with a key, an
action, a priority and requirements (`lib_op()`, the library's `cap_op()` defaults, or `op_attach()` on an entry datum
of its own: a slot's insert and ejects, a ladder step, the deconstruct crowbar, a self-use), so the router ranks it
against the holder's other ops. The cell bay's hand eject is `eject_cell` (`ACT_USE`, `OP_PRIORITY_TAKE_OUT`): on the
APC it wins over the interface by priority, the interface is not hidden (`dx_apc_cell_eject_priority`). A condition
under which the player did not mean the op (nobody is buckled, the held item is no container) is `offered`, so the
gesture falls through as the resolver let a blocked entry fall through; a condition under which the player meant it
(the cover is held shut) is `needs`, and the refusal answers. Library ops take no provider slot (`by = NONE`) until
cyborg modules and simple mobs have provider slots of their own. `dx_cap_library_ops` sweeps the library.

## 5a. INTERACT_* to ops [the codemod in batch A4 implements this table]

| Legacy spec | New form (in `capabilities()`) | Notes |
|---|---|---|
| `INTERACT_USE(name, effect, req...)` | `cap_use_self(name, handler)` | A real op answering `ACT_USE` (the `GESTURE_SELF` action) that offers `req_self_held()`, so a click on the item never means it; `attack_self` keeps running it (entry SELF). Handler `(mob/user)`, returning TRUE. |
| `INTERACT_SELF(...)` | `cap_use_self(name, handler)` | A FALSE return declines to the item's next self-use, as before. |
| `INTERACT_HAND(name, effect, req...)` | `cap_op(name, handler, using = EMPTY_HAND, entry = INTERACTION_ENTRY_HAND)` | On a machine a silicon works too: `cap_control(...)` (its interface route) or keep `entry` (its `silicon_use` hand use calls `attack_hand`). |
| `INTERACT_HAND_UNGATED(...)` | as HAND, plus `works_broken = TRUE, works_unpowered = TRUE` | The router runs no `hand_gate()`; ungated meant "works whatever the machine's state". |
| `INTERACT_ITEM(name, effect, req...)` | `cap_op(name, handler, using = <held type>, entry = INTERACTION_ENTRY_ITEM)` | `using` is the type the effect's `istype()` guard tested (`/obj/item` when none). A FALSE return declines: the click falls through. |
| `INTERACT_INSERT(held_type, effect, name, req...)` | a library slot (`cap_slot()`, `cell_bay()`...) when it stores the item; else `cap_op(name, handler, using = held_type, entry = INTERACTION_ENTRY_ITEM)` | |
| `INTERACT_ALT(name, effect, req...)` | `cap_op(name, handler, action = ACT_TOGGLE, entry = INTERACTION_ENTRY_ALT)` | `ACT_EJECT`, `ACT_OPEN`, `ACT_CLOSE`, `ACT_LOCK`, `ACT_UNLOCK` where one fits: the default alt list is those six. |
| `INTERACT_DRAG(name, effect, req...)` | `cap_op(name, handler, using = <dragged type>, action = ACT_DROP_ONTO, entry = INTERACTION_ENTRY_DRAG)` | The dragged atom is `held`. |
| `INTERACT_VERB(name, effect, req...)` | `cap_op(name, handler, action = ACT_NONE)` | Menu, radial and command bar only, by key or name. `REQ_IN_INVENTORY` becomes `needs = TYPE_PROC_REF(/atom, cap_in_inventory)`; add `via = ROUTE_PHYSICAL \| ROUTE_UI` for a window's act. |
| `INTERACT_SILICON(name, effect, req...)` | `cap_op(name, handler, via = ROUTE_INTERFACE, by = AFF_INTERFACE)` | Or `cap_control()` when a hand does the same. The AI adapter allows ops over `ROUTE_INTERFACE`. |
| `INTERACT_ROBOT(...)` | as SILICON, plus `offered = req(/mob/living/silicon/robot, of = OP_ACTOR)`, declared before the silicon op | Declaration order replaces its priority 1. |
| `INTERACT_OBSERVER(...)` | `cap_op(name, handler, action = ACT_EXAMINE, via = ROUTE_UI, by = NONE)` | The observer profile's click is `ACT_EXAMINE` over `ROUTE_UI`; the ghost adapter allows exactly those ops. |
| `INTERACT_TK(...)` | `cap_op(name, handler, via = ROUTE_TK)` (`ROUTE_PHYSICAL \| ROUTE_TK` when a hand does the same) | The telekinetic click's own route replaces its priority 1; the provider is the telekinesis affordance. |
| `*_AS(I_HURT, ...)`, `*_HOSTILE` | `action = ACT_ATTACK, stance = I_HURT` | |
| `*_AS(I_DISARM, ...)` | `action = ACT_ATTACK, stance = I_DISARM` | |
| `*_AS(I_GRAB, ...)` | `stance = I_GRAB` | ACT_USE. |
| `*_AS(I_HELP, ...)`, `*_PEACEFUL` | `stance = I_HELP` | ACT_USE. Drop the stance when the op may also be the harm click's fallback. |
| several `*_AS` sharing one effect | one op, `stance = list(...)` | Split the handler when the effect read `interaction.stance`. |
| `*_DEFAULT`, `*_DEFAULT_AS` | the same op, `priority = OP_PRIORITY_DEFAULT` | |
| `requires...` (`REQ_*` clauses) | `needs =` (a refusal) or `offered =` (not meant, the input falls through) | `REQ_TARGET_STATE(proc)` / `REQ_ON(proc)` become `PROC_REF(proc)`; reach and adjacency clauses are the route stage's. |

Handlers change from `(mob/user, obj/item/held, datum/interaction/I)` to `(mob/user)` (hand and self shapes) or
`(mob/user, obj/item/held)` (held shapes), and return TRUE (done), FALSE (declined: the input goes on) or
`refuse(user, text)`. `INTERACTION_HANDLED_PASS` has no op form: a router op that ran used the input.

**Worked conversions** (this batch; `dx_op_converted_examples` checks them):

- `code/game/objects/items/devices/megaphone.dm`, an item's USE and VERBs: `INTERACT_USE(null, PROC_REF(interaction_self))`
  became `cap_use_self("Shout", PROC_REF(shout), key = "shout")`; the gigaphone's three `INTERACT_VERB(..., REQ_IN_INVENTORY)`
  became `cap_op("Change Volume", PROC_REF(adjust_volume), action = ACT_NONE, needs = TYPE_PROC_REF(/atom, cap_in_inventory),
  key = "change_volume")` and two more, with the `*_effect` wrapper procs deleted.
- `code/game/machinery/computer/medical.dm`, a machine's ITEM, HAND and VERB: the ID card's `INTERACT_ITEM` and the
  "Eject ID Card" `INTERACT_VERB` became one library slot, `cap_slot(nameof(scan), /obj/item/card/id, eject_via =
  SLOT_VIA_VERB, when_full = SLOT_FULL_PASS, ...)` (ops `insert_scan` and the ACT_NONE `eject_scan_menu`, the old
  "open the records on insert" a `slot_inserted()` hook); `INTERACT_HAND(null, TYPE_PROC_REF(/atom, interaction_open_ui_fingerprint))`
  became `cap_op("Open records", ..., using = EMPTY_HAND, key = "open_records", entry = INTERACTION_ENTRY_HAND)`.
- `code/game/objects/items/bells.dm`, the stance shapes: eight `INTERACT_HAND_AS` / `INTERACT_ITEM_AS` specs became
  four ops: `ring` (`using = EMPTY_HAND, stance = list(I_HELP, I_DISARM, I_GRAB)`), `hammer` (`action = ACT_ATTACK,
  stance = I_HURT`) and their held-item twins, each with its own handler instead of reading `interaction.stance`.

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

## Credentials and the lock op [built]

A lock is one op, `CAP_LOCK` (action `ACT_LOCK`), declared by `lock_op()` (the hatch's `lock_ops` and the swipe are gone). An alt-click reaches it
with anything in hand; a plain click reaches it only while holding a card the lock takes (`click_with`, read with the
gesture in `GLOB.op_gesture_now`), so a click with a wrench stays the wrench's. The credential is a provider found like a hand
(`cap_lock_credential()`): the held card, then the actor's own access (worn ID or PDA, a silicon's access). The op takes no slot provider.

The providers are shared [built, B2]: `access_credential(holder, actor, held, need_all, need_one, id_types)`
(`code/datums/capabilities/library/access.dm`) is the one search, `access_needs(holder, defaults...)` the one rule for
what is required (the holder's own `req_access` / `req_one_access` when set, else the type default). The lock adds lock
state on top; `cap_access(access, req_one_access, ops = ...)` is the same check as a contract on ops with no lock state
(a console that only opens for engineers), through the requirement `req_credential()`.

## Shared requirements and routes [built]

Machine contracts are shared flyweights with standard reasons, not per-type procs: `req_working()` (not broken, not under
maintenance; `/datum/msg/req_not_working`, "It isn't working."), `req_not_subverted()` (the holder's `is_subverted()`: emagged, or
an AI hack on the APC; `req_subverted`, "It doesn't respond."), `req_on_route(routes, req)` (ask `req` only over those routes: an
open cover blocks a hand, `ROUTE_PHYSICAL`, but not a silicon's interface), `req_claws()` and `req_heard(notice)`.

A click travels the actor's route, `mob/op_route(held)`: `ROUTE_PHYSICAL` by default, `ROUTE_INTERFACE` for a silicon's empty-handed
click. An op that does not accept the click's route at all is not what the click means: the router falls through to the resolver.
Every breakable machine carries `claw_op()` (`CAP_CLAW`, from `machine_basics()`), which publishes `/datum/notice/slashed`.
