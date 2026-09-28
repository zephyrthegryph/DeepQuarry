# The object model in 10 minutes

Read this first. It tells you which piece to reach for; the reference is
[object_model_core.md](object_model_core.md) (section numbers below are from it). For time
and scheduling choices see [time_mechanisms.md](time_mechanisms.md).

The rules everything follows:

1. **Declare, don't register.** Behaviours, events, checks, tasks, prompts and references are
   types or table rows. Boot compiles and validates them.
2. **Nothing runs without a change, a cadence slot or a deadline.** No polling, no
   `process()`, no gameplay `sleep()`.
3. **Every datum has one owner**, and destruction is a framework transaction, not a
   hand-written `Destroy()`.

What is gone and banned by lint: DCS signals/components/elements (`RegisterSignal`,
`AddComponent`, `COMSIG_*`), `addtimer`/SStimer, `spawn`, `sleep`, `INVOKE_ASYNC`,
`do_after`, raw `input()`/`alert()`/`tgui_input_*`, `/datum/weakref`, `/datum/modifier`,
per-type `Destroy()` overrides, and most subsystems (their work is now world services).

## 1. Entities and behaviours (§3, §4.1)

Any datum can be an **entity**. Atoms whose type has a decl join on materialize; other datums
call `om_start(E)`. Logic attaches as **behaviours**: DEF singletons (`/datum/om/behaviour/x`)
whose vars are declarations and whose per-entity state lives on the entity.

```dm
/datum/om/behaviour/geiger
	every = 2 SECONDS                 // cadence: tick(E, dt)
	lane = LANE_PRESENTATION
	wake_on = CHANGE_RADIATION        // on_wake(E, changes) when the channel is raised
	handles = list(/datum/om/event/moved)

/datum/om/behaviour/geiger/tick(obj/item/geiger/E, dt)
	...
```

Most content needs no subclass: a `/datum/om/decl/x` with `of = /type` lists `ticks`,
`reacts`, `events`, `derived`, `tasks`, `effects` rows (§3). Hooks never sleep and return
nothing meaningful. `om_attach(E, B)`, `om_park(E, B)` / `om_unpark(E, B)`.

**Pipelines** (§4.10) are behaviours that run ordered **stages** sharing a frame; each stage
idles and wakes on its own channels (`reads`, `wake_on`, `rewake_delay`), and an entity whose
stages are all idle **parks** off the ring. Mob Life, machines and periodic lanes
(`om_task_periodic()`) are pipelines.

**Change channels.** State a stage or behaviour reads is declared with
`OM_FIELD(type, name, default, CHANGE_X)`, which generates `set_<name>()`; the setter raises the
channel (`om_changed(E, bits)`), which queues wakes. Never assign a declared field directly.

## 2. Events and hooks (§10)

- Something happened now: `OM_EMIT(E, /datum/om/event/x, args...)`. It allocates nothing if
  no one listens and returns the ORed handler results.
- Refusable or result-returning: `/datum/om/event/before/x` (return `EVENT_VETO`).
- Behaviours on E receive it via `handles`. Another object reacting to E's event:
  `om_hook(E, /datum/om/event/x, src, PROC_REF(on_x))`. Both ends hold the hook; deleting either
  drops it. Handlers start with `EVENT_HANDLER`.
- World-wide: `OM_EMIT_WORLD()` / hook `OM_WORLD`.
- Deferred or state-driven reactions use a channel, a watch or `om_after()` instead.

## 3. References: every object var is declared (lifecycle.md §4, §4.11)

An undeclared object-typed var fails lint. Pick the kind by who owns the target:

| Kind | Declare | Use for |
|---|---|---|
| owned child | `REF_OWNED` / `REF_OWNED_LIST` / `REF_OWNED_VALUES`, or one-line `REF_VAR(type, OWNED, vartype, name)` | a datum I created and nothing else owns; deleted with me |
| static | `REF_STATIC` (`REF_DEF` for `DEF_TYPES`, implicit) | singletons, services, materials, decls |
| held | `REF_HELD` | something in my contents with no policy of its own |
| pair | `REF_PAIR` via `link_set()` / `link_clear()` | two-sided links (sleeper and console) |
| back | `REF_BACK(type, list("our_var" = "their_var"))` | a child naming its owner (ownership is a tree) |
| backlist | `REF_BACKLIST` | my membership in another object's list |
| handle | a text var: `om_handle(X)` / `om_resolve(h)` | another live entity whose lifetime someone else manages |
| back via handle | `REF_BACK_HANDLE(type, list("owner_handle" = "panel"))`, `REF_BACKLIST_HANDLE(...)` | a partner I name by handle whose var or list names me back |
| weak list | `REF_WEAK_LIST(type, list("names"))` + `WEAK_LIST_ADD` / `WEAK_LIST_REMOVE` / `WEAK_LIST_HAS` / `weak_list_live()` | a list of live entities I don't own (hearers, sensors, queued items) |
| cache | `declared_cache_vars()` with `CACHE_ON_CHANGE/EVENT/RELATION` | derivable data the core nulls when its rule fires |
| pooled field | `REF_TRANSIENT` on a `POOL_DECLARE`d type | per-use fields of scratch objects |

Relations and slots (§7) are read through typed accessors (`M.buckled_to()`,
`I.slot_item(slot)`). Sets of live instances are registries (`REGISTRY_MEMBERS(REGISTRY_X)`),
not `GLOB` lists. Compare a handle to a dying object with `om_handle_is(h, src)`.

## 4. Lifecycle: destroying things (lifecycle.md §2)

`qdel(D)` runs the destroy transaction: guard, mind transfer, unbind Rust bindings, leave
registries, resolve slot contents by each slot's declared policy, **links**, teardown (OM
timers, tasks, hooks, UIs), declared effects, the core `Destroy()` chain, scrub.

What you write:

- `lifecycle_prerelease()`: teardown that must still read declared vars (end a busy state,
  hand things back). Runs first in the links phase.
- `on_destroy(force)`: real domain consequences; always calls `..()`. Contents are resolved
  but declared links and handles still read.
- `/datum/om/behaviour/proc/on_entity_destroy(E)` for behaviour-side consequences.
- Refuse deletion with `lifecycle_keep(force)` / `LIFECYCLE_KEEP_UNLESS_FORCED(type)`; the GC
  hint is the `destroy_hint` var.
- Delete with a lifecycle verb when one fits: `consume()`, `replace_with()`, `expire()`,
  `slot_clear()`; plain `qdel()` otherwise. Never `del()`.

You do **not** override `Destroy()` (banned outside the core chain), null declared vars,
cancel OM timers, or unhook: the transaction does all of it. Test builds report leaked
cycles (`LIFECYCLE LEAK`) and ownership cycles.

## 5. Interactions and actors (interactions.md)

Player input becomes abstract actions (Use, Alternate, Inspect, ...) routed through an
**actor adapter** (`code/modules/keybindings/adapters.dm`: `hands`, `ghost`, `ai`, `robot`,
`telekinesis`), which decides which interactions that actor may use. A type declares what can
be done to it as data:

```dm
DECLARE_INTERACTIONS(/obj/item/binoculars, \
	INTERACT_USE("Zoom", PROC_REF(zoom)), \
)
```

Shapes: `INTERACT_USE`, `INTERACT_HAND`, `INTERACT_ITEM`, `INTERACT_INSERT`, `INTERACT_ALT`, plus
the full form for tool interactions; `EXTEND_INTERACTIONS` adds to an ancestor's list.
`interactions_for()` / `try_interaction()` resolve them; ties open the Menu. There are no
`attack_ai` / `attack_ghost` / `attack_tk` procs; direct uses go through `actor_use()`.

## 6. Doing things over time: tasks, prompts, flows (§11)

- **Task**: `om_task_start(/datum/om/task/timed/lockpick, user, src, door = D)`. The type
  declares `duration`, `claims`, `requires`, `interrupted_by`, `steps`, `complete_proc`; the
  named args set its typed vars. Cancelled when requires fail, the actor moves, or any datum in
  its state is deleted.
- **Prompt**: `om_ask(answerer, /datum/om/prompt/confirm/x, PROC_REF(cb), var = value...)`.
  Typed prompt kinds (`confirm`, `choice`, text, number, ...); `ask_flags`, `requires` and
  `valid()` are re-checked before `cb` runs, so the callback never re-validates by hand.
- **Flow**: several steps as one type. `om_flow_start(/datum/om/flow/leash, user, pet,
  leash = src)`; each step continues with `wait(d, next)` or `om_ask(...)`; `requires` is
  re-checked between steps; state is held as handles.

## 7. I/O and blocking built-ins (§4.12)

- SQL / HTTP: `om_io(E, /datum/om/io/sql, sql, args, PROC_REF(on_done), ctx...)`, or the
  helpers `om_sql_write()`, `om_http_get()`, `om_sql_view()`. `on_done(result, error, ctx...)`
  runs later on E; nothing waits.
- `winget`, `winexists`, `MeasureText`, `shell`: `dx_winget()`, `dx_winexists()`,
  `dx_measure_text()`, `dx_shell()`, `dx_shelleo()` (DX-exec).

## 8. Containment (containment.md)

Where things are is a ledger of declared slots. Move with `move_into(holder, slot, actor)`,
`slot_remove()`, `slot_transfer()`, `slot_empty()`; read with `slot_item()`, `slot_contents()`,
`slot_used()`, `slot_capacity()`. Never touch `contents` raw: `contents_of(A, type)`,
`FOR_CONTENTS(var/x as anything, A)`, `locate_within()`, `contents_count()`. Each slot declares
its destroy policy (spill, transfer, delete), which the destroy transaction applies.

## 9. World services (object_model_core.md §4.10, `code/datums/om/world_lanes.dm`)

Global state and world-level periodic work that belonged to no entity (the old subsystems) is
a `/datum/world_service` singleton in `GLOB`. Its periodic work is a `lane` behaviour on the
scheduler's global owner, so it shares the OM budget; `service_step(resumed)` may yield and
resume next tick. `on_demand` services park while `has_work()` is FALSE and wake on
`demand()`. Setup is `initialize()` at `boot_after = <subsystem>` (ordered by `order_after`) or
lazily via `LAZY_SERVICE()`; `on_shutdown()` at server stop. Only a small core allowlist of
subsystems may still `fire()`.

## 10. Seeing what it costs

Admin verb **OM Profiler** (Debug > Investigate): per-behaviour runs, ms, lateness, errors,
ring population and parked counts; per-lane cost and queued wakes; per-stage timings; world
services and the Rust world step. Scripts can read `om_diagnostics()`,
`om_world_diagnostics()` and the profiler's `PERF_PROFILE` log lines. Tests use
`om_test_begin()` / `scheduler_advance(seconds)` / `om_test_end()` (§4.9).

## Where to go next

| Topic | Doc |
|---|---|
| Full API | [object_model_core.md](object_model_core.md) (§16: "one way to do X") |
| Time and scheduling | [time_mechanisms.md](time_mechanisms.md) |
| Destruction and references | [lifecycle.md](lifecycle.md) |
| Input | [interactions.md](interactions.md) |
| Containment | [containment.md](containment.md) |
| Mob Life on pipelines | [life_on_om.md](life_on_om.md) |
