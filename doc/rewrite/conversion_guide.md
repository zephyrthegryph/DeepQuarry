# Converting a domain to the final forms

A practical guide for whoever converts the next domain (a machine, a structure, an item family). It is written from the two reference
conversions, the **APC** (`code/modules/power/apc.dm`) and the **doors** (`code/game/machinery/doors/`), and it points at their code instead of
repeating it: copy the shape of the reference that is closest to yours. The design is `doc/rewrite/final_api.html` (section 16 has the full
examples, section 17 and `doc/rewrite/api_mapping.tsv` map old forms to new ones, section 11 is the library, section 12 construction);
`doc/rewrite/engine_contracts.md` says what the engine really provides today and under which working names.

## 0. The rules this conversion followed

1. **Behaviour first.** Tests that pin the CURRENT behaviour are written, and pass on unmodified master, before one line of the domain
   changes. The converted code passes the same tests, unchanged except for their adapters (section 2).
2. **Only final forms in converted code.** No `capabilities()`, `reactions()`, `relations()`, `cap_*()`, `cap_state`, `DECLARE_INTERACTIONS`,
   `INTERACT_*`, `DECLARE_EMAG*`, `UI_ACT` rows, `tgui_data()` overrides, `timed_set()`, `om_after()`, `om_task_*()` in the files of the domain.
   The old form of what the domain used is deleted in the same change, and so is every engine shim that nothing uses afterwards.
3. **No ALLOW to dodge a lint.** An annotation is for a site that is right as it is (`AGENTS.md` section 3g), never for debt.
4. **When the engine lacks something the domain needs, build it properly, small, with a test, and list it** (section 6).
5. **Machine-core state stays in its legacy form until phase 4**: the `stat` bits (`BROKEN`, `NOPOWER`, `MAINT`, `EMPED`), `operable()`,
   `TRACKED_BRIDGED` (a setter that also raises the old `CHANGE_*` channel the machine pipeline wakes on) and the legacy `derived` read analysis.
   A converted machine reads them through one bridge contribution (`stat_bits_allow()` in `code/library/machine/machine.dm`) and keeps writing
   them through their own setters. Say so in a comment where you do; phase 4 deletes the bridge.

## 1. The workflow, step by step

1. **Inventory.** List every legacy form in the domain's files. A scan against `api_mapping.tsv` finds them all: tokenise the files, look each
   identifier up in the table, keep the rows whose verdict is not `kept`; the `gone_in_phase` column says whether you must convert it now (2 and 3)
   or it belongs to a later track (4 machine state, 5 life, 6 jobs and waves). Also grep the rest of the tree for the readers of the domain's
   state (`is_bolted(`, `panel_is_open(`, `cap_state`, the map's `cap_state = N` var edits): they move with it (section 5).
2. **Write the behaviour tests** (section 2). Run them on master. Commit them first.
3. **Build the library the domain needs** under `code/library/<area>/` (section 3). A library capability is shared: it takes its params, not the
   type's name. Add what the type itself must say as `extend(...)`, own ops and hooks in its `CAPABILITIES` list.
4. **Convert the type**, in this order, compiling and running `analyze gen` between steps:
   1. vars and tracked state: `TRACKED`, `STAT`, `SOURCE_DEF`, `STAGE_DEF`; one `var/x` per fact, defaults on the var line;
   2. the `CAPABILITIES(T)` block: bundles first (`wall_machine`, `maintenance_hatch`, `cell_bay`, `powered_by`), then links and relations
      (`owns_one`, `links`), then `interface()`, then ops, then `extend`s, then hooks (`on_notice`, `on_change`, `extend(/datum/act/hit/x, ...)`);
      a long block groups the rest under `section(name, "doc")` lines at its end (a window's buttons, the hatch's rules): a section's
      entries are the type's own, so they use `PROC_REF(x)` and `nameof(v)`, and Explain prints `file:line section name` for each. There is
      no `BUNDLE`: what several types share is a library capability, or a plain `/proc/name()` returning `list(entries)` for a small
      parameterless snippet;
   3. each old interaction becomes an op, each old condition a requirement, each old effect `then(PROC_REF(x))` with `x(datum/act/op/A, args...)`;
   4. timers become `after(src, delay, PROC_REF(x), key = "k", with = list(...))`, holds become `hold`/`release` with a `SOURCE_DEF`;
   5. presentation: `look_layer()` and `examine_line()` for plain layers and lines, `draw(look)` for computed ones, `ui_data(A)` for the window;
   6. delete the old procs, the old tests that tested them, the old library files nothing uses, the old ratchet baseline rows (`--update`).
5. **Verify** (section 7). Merge in small steps; do not hold a green piece for the rest of the domain.

## 2. Test first

* Use the test driver (`code/tests/driver/`, `doc/testing.md`): `test_click(actor, target, held)`, `test_ui(actor, window, action, args)`,
  `test_menu`, `test_time`, `test_drain`, `test_record`/`test_recorded`, `test_logs`. Never call `perform_op` with an op key in a test that must
  pass on master: op keys do not exist there.
* Read state through a small **adapter block** at the top of the file (`p2_apc_cover_open(A)` ...). On master the adapters wrap the old accessors;
  after the conversion only their bodies change. Everything else in the tests reads plain vars (`density`, `operating`, `cell`, `loc`).
* **Always settle time after an action** (`test_time(10 SECONDS)`): converted tool ops carry the tool profile's wait (crowbar, screwdriver and
  wirecutters 2 s, multitool 5 s, welder 3 s) where the old code was instant. Do not assert a click result's `.outcome` is non-null at once, and do
  not assert on message text: assert on resulting state, on transfers and on log rows. A timer the test cares about is asserted at explicit times.
* Pin what the behaviour is, not how it is reached: a refusal is "the state did not change", not a reason code.
* A behaviour that changes on purpose is not a test failure: it is a line in `doc/rewrite/intended_changes.md` with its reason, and the test
  is edited in the same commit (section 8 lists this conversion's).

## 3. The library you will use (and where it is)

| Piece | File | What it brings |
|---|---|---|
| `cover(open =, remove =, replace =)` | `code/library/machine/cover.dm` | ops `cover.open/remove/replace`, state keys `COVER_OPEN`, `COVER_REMOVED`, look layer, examine lines; `force_pry()` and `component_swap(T)` bundles |
| `panel(tool =)` | `.../panel.dm` | `panel.open`, `PANEL_OPEN` |
| `wires(name =, count =, randomize =, ...)` | `.../wires.dm` | `wires.pulse/cut` behind the panel; the wire list comes from the holder's capabilities (`WIRE_DEF` table); `wire_is_cut(E, W)`; `req_wire()`, `req_wire_cut()`, `cuts_all_wires()` |
| `ai_control()`, `power_wires()`, `shock_wire()`, `id_scan()`, `item_throw()`, `safety_wire()`, `lathe_wires()`; `lock(wire =)`, `bolts(wire =)`; `on_wire(W, cut =, pulse =)` | `.../wire_caps.dm`, `lock.dm`, `door_parts.dm`, `wires.dm` | the capabilities that bring wires: each brings its wire and the wire's effect (holds on the `stat =` it names); `on_wire()` is a type's own wire |
| `lock(...)`, `emag(parts, say =, repeatable =)`, `subversion_reset(parts)` | `code/library/access/` | ID lock (gates every UI and `TAG_CONTROL` op), emag, reset |
| `breakable`, `wall_mount`, `machine_basics`, `wall_machine`, `maintenance_hatch` | `code/library/machine/machine.dm` | the machine core bundles |
| `space`, `latch`, `protrudes`, `req_closed`, `req_space_empty`, `size_is`, `cell_bay`, `telekinesis` | `code/engine/library/spaces.dm` | physical paths (spaces and doors, final_api section 8) and the cell slot |
| `powered`, `powered_by` | `code/domains/power/powered.dm` | the power adapters |
| `look_layer`, `examine_line`, `interface` + `ui_data`, `present_*` | `code/engine/present/outputs.dm` | the presentation bridge |

A capability with code of its own is a datum under `/datum/capability/lib/` (`CAPABILITY_TYPE`); one that is only entries is a
`CAPABILITY_DEF`. Its params are vars on the datum, so a param must not be named like a reserved var (`GLOB.cap_reserved_vars`: `key`, `type`, `at`
was one until phase 2, `joins`, `needs`, `log`, ...). Op keys are namespaced by the constructor name (`cover.open`, `cell_bay.cell.take`).

## 4. Before and after: the APC

The full list is the `CAPABILITIES(/obj/machinery/power/apc)` block in `code/modules/power/apc.dm`; these are the shapes that carry over.

**The hatch.** Before: a `capabilities()` proc listing `wall_machine(...)`, `maintenance_hatch(cover_holds = PROC_REF(cover_holds), wires = ...)`,
`cap_require(CAP_LOCK, needs = list(req_not_subverted(), req_wire(WIRE_IDSCAN), req_working()))`, `refine(CAP_EMAG, delay =, effect =)`. After:

```dm
maintenance_hatch(
	cover = cover(remove = force_pry(), replace = list(component_swap(/obj/item/frame/apc), at(BAY_HATCH))),
	wires = wires(name = "APC", count = 4, status_lines = PROC_REF(wire_lights)),
	emag = list(wait(0.6 SECONDS), then(PROC_REF(emag_sparks)), sets(LOCK_LOCKED, FALSE)),
	emag_say = MSG(apc/emagged),
	panel_needs_cover_closed = TRUE,
	starts_locked = nameof(lock_at_start))
extend(CAP_LOCK, needs(req_not_subverted(), req_wire(WIRE_IDSCAN), req_operable()))
extend("cover.open", needs(req(PROC_REF(cover_free), because = PROC_REF(cover_hold_reason))))   // one extend per key: a list target is not supported
```

**The wires.** Before: a `/datum/wire_set/apc` listing `WIRE_IDSCAN, WIRE_MAIN_POWER1, WIRE_MAIN_POWER2, WIRE_AI_CONTROL`, and an `on_wire()` per wire
with its own procs (`power_wire_cut`, `power_wire_pulsed` and an unkeyed `after()` to end the pulse, `ai_wire_cut`, ...). After: no set and no hooks; the
capabilities bring the wires and the wires' effects, on stats the APC declares:

```dm
STAT(/obj/machinery/power/apc, shorted, ANY)
STAT(/obj/machinery/power/apc, aidisabled, ANY)
maintenance_hatch(wires = wires(name = "APC", count = 4, ...), lock_wire = WIRE_IDSCAN, ...)   // lock(wire =) brings the ID scan wire
power_wires(stat = STAT_SHORTED, count = 2, pulse_lasts = 2 MINUTES, shock = 50)
ai_control(stat = STAT_AIDISABLED, pulse_lasts = 1 SECOND)
```

Converting a holder's wires: delete its `/datum/wire_set`; give `wires()` the set's name, count and randomize; for each wire a library capability
brings (`WIRE_DEF` in `code/library/machine/wires.dm`), declare that capability with the holder's stat (turn the var the hooks wrote into a
`STAT`, delete its `var/` and `TRACKED` lines, and turn its other writers into holds with a source of their own); keep `on_wire()` only for the
type's own wires and for a real deviation on a shared one. Never write a timed pulse with `after()`: it is the capability's `pulse_lasts`.

A condition is `x(datum/act/A)` (or `datum/act/op/A` when it reads `A.actor`/`A.held`), returns TRUE/FALSE, and **never writes, publishes or talks** (the
purity guard fails a test build). A refusal reason is a `MSG_DEF` type, or a proc returning one for a reason that depends on state.

**Starting state of a mapped instance.** Before: `cap_state = CAP_LOCKED` in the type and `cap_state = 0` in nine map entries. After: a plain var
the capability reads (`starts_locked = nameof(lock_at_start)`) and `lock_at_start = 0` in those map entries (a script rewrote them; see section 5).

**Window and buttons.** Before: `tgui_id`, a `tgui_data()` override, `act_*` procs and a `ui_allowed()` guard. After: `interface("APC")`, a
`ui_data(datum/act/eval/A)` that returns the data (`A.actor` is the viewer), and one op per button with a `ui_act()` binding; the old action
name stays (`ui_act("charge")`), so the TSX does not change except where the data shape moved (the APC's `caps.power` object became top-level keys).
Who may work the window is the library's (`code/library/access/window_access.dm`): `req_window_usable(remote = PROC_REF(x))` (an admin ghost
always; anyone else awake, free and standing, beside the machine or over a silicon's link, where the machine's own `x(A)` says null or a reason)
and `req_silicon_or_admin()` (the buttons only a silicon has). Write no `can_use()`/`ui_usable()` of your own. A silicon's gesture that does what a
button does is that button with one more binding, `extend("breaker", binds(remote()), gesture(GESTURE_CTRL))`, never a second op.

```dm
op("set_channel", ui_act("channel", arg("channel", int(POWER_CHANNEL_EQUIPMENT, POWER_CHANNEL_ENVIRON)), arg("mode", int(POWERCHAN_OFF, POWERCHAN_ON_AUTO))), then(PROC_REF(ui_set_channel))),
op("breaker", ui_act(), toggles(nameof(operating)), then(PROC_REF(settings_applied)), logs(LOG_GAME)),
extend(TAG_UI, needs(req_window_usable(remote = PROC_REF(remote_control_allowed), remote_because = MSG(apc/ai_disabled)))),   // the old can_use(): the library's window access
extend("breaker", binds(remote()), gesture(GESTURE_CTRL)),   // a silicon's ctrl-click throws the same breaker
extend("nightshift", drop = "lock"),   // this one button works whatever the lock says: relax the lock's requirement by its id
```

**Timed state.** Before: `timed_set(src, nameof(power_failed), TRUE, for_time = d)` plus a `set_power_failed()` setter with side effects, then a
`power_failed` stat of its own. After: "temporarily not operating" is a timed hold on `STAT_OPERABLE`, from the library's `emp_disable()` for a pulse and
from the APC's own source for an event's failure, and what the APC does with it is a stat it feeds and a hook on that stat:

```dm
emp_disable(PROC_REF(emp_outage), extends = TRUE)          // a pulse: hold(STAT_OPERABLE, FALSE, SRC_EMP, outage); emp_outage(severity) scales it (critical APCs)
contributes(STAT_OPERABLE, PROC_REF(electronics_fastened), reads = list("graph:[CAP_CONSTRUCTION]"))   // was the MAINT bit
contributes(STAT_SUPPLYING, STAT_OPERABLE)                   // a var-backed stat: what push_to_rust() and the area read (generated reads see a var)
on_change(nameof(supplying), ANY, then(PROC_REF(supply_changed)))
// energy_fail(): hold(src, STAT_OPERABLE, FALSE, SRC_POWER_FAILURE, lasts); the reboot releases both sources; the UI shows failure_left()
```

The APC overrides `stat_bits_allow()` to read only `BROKEN`: it is its area's supply, so the area going dark (NOPOWER) must not make it inoperable.

**Construction.** Before: `cap_construction(ladder_options(...), stage("frame"), build_insert(...), build_wire(10, ...), build_fasten(...))`. After a
bundle (`apc_frame()`) of `construction(start(STAGE_APC_FRAME), stage(...), ..., dismantle(tool(TOOL_WELDER), becomes(...), ruined(cond, becomes(...))), at(BAY_HATCH))`,
a `STAGE_DEF` + `MSG_DEF(stage/apc/<name>)` per stage, a slot relation for `SLOT_CONSTRUCTION`, and `configure(construction_graph(start = STAGE_APC_SECURED))` on the type
placed finished. Code that makes the thing part-built (the frame item) calls `graph_place(src, STAGE_APC_FRAME)`.

**Hits.** Before: `DAMAGE_REACTION(...)`/`before_op(damage(...))`. After: `extend(/datum/act/hit/blob, instead(cuts_all_wires(), sets(PANEL_OPEN, TRUE)))`
(takes the hit over); an EMP is `emp_disable()`, above. A swing that nothing answered is the attackby action's notice,
`on_notice(/datum/notice/attacked_by, then(PROC_REF(apc_struck)))`; a signaller at the open wire panel is its own op (`item(/obj/item/assembly/signaler)`,
`when(PANEL_OPEN)`), and a silicon's click reaches the window through the interface's `remote()` binding. The bridge is `hit_try()` in `receive_damage()`.

**Links and the night shift.** The area is a link, `links(/obj/machinery/power/apc::area, /area::apc)`: `rel_set(src, nameof(area), A)` writes both ends.
What the area's lights read from its APC is the APC's to say, `contributes_to(nameof(area), STAT_LIGHTS_NIGHTSHIFT, PROC_REF(wants_night_lights))`, where
`wants_night_lights()` reads the night-shift system through its accessor `night_shift_active()` (section 16.11): the system sets one tracked flag and
touches no APC. Registry membership is `membership(joins = REGISTRY_APCS)`.

## 5. Everything that read the old state

Grep the tree for the domain's accessors and fix every reader in the same change: `is_emagged(A)` and `is_broken(A)` now also look at converted holders (kept as
shims for the legacy callers); `panel_is_open(A)` is `panel_open(A)`, `cover_is_open(A)` is `cover_open(A)`, `is_locked(A)` is `lock_locked(A)`, `wires_of(A)` is
`wiring_of(A)` (the record; `wires_all(A)` lists the wires). Map var edits of a deleted var are rewritten by a script over `maps/**/*.dmm` (match the `/type{...}` block, not the line), and the diff is
reviewed (a changed count that is not the count you expected is a bug). Tests of the legacy forms are deleted with them: delete, do not skip.

## 6. Engine pieces this conversion added

See `doc/rewrite/engine_contracts.md`, "Phase 2 additions" for the contracts. In one line each: the hit bridge (`hit_try()`), `ruined()` in `dismantle()`, the
presentation bridge (`look_layer`, `examine_line`, `ui_data`, `interface` to the window, `tgui_act` to ops), `says(PROC)`, `wait(PROC)`, `req_built()`,
`graph_place()`, `cap_keys` accessors in the reads analysis, `req_heard()` that really asks the hooks.

## 7. How to verify

```
CARGO_TARGET_DIR=... tools/analyze/target/release/analyze.exe gen          # after every CAPABILITIES edit (every build also runs it; the output is not committed)
bash tools/dq_focused_test.sh 'dq_p2_apc/*' 'dq_p2_lib/*' 'dq_e0_proof/*' 'dq_p1/*'     # the domain's tests and the engine proofs
tools/build/build.sh dm-test --tier=e0                                       # the proofs report
bash tools/ci/check_ratchets.sh && tools/build/build.sh analyze              # BOTH: check_ratchets does not run every analyze lint
tools/build/build.sh dm                                                      # DreamChecker: 0 warnings of yours
```

The full suite is one integration run per merge batch, not per worker.

## 8. Pitfalls found

* **A name that is both a var and a global proc is fine, but a param named like a reserved capability var silently stays null.** `at` was one
  (`cap_build()` skips `GLOB.cap_reserved_vars`): the bay opened for everyone. The legacy `/datum/capability/var/at` became `bay_at`.
* **Heredocs through the shell halve backslashes.** `\improper` and Python regexes written in one break silently. Write DM and doc files with the Write/Edit tools. (The `CAPABILITIES` marker no longer uses backslash continuations; it is a block, below.)
* **The build runs `analyze gen` before compiling** (`GenTarget`), so a unit-test compile never sees a stale `declare.dm`; a DreamMaker run outside `build.sh` does. The generated files are not committed (`doc/rewrite/agent_workflow.md`).
* **A param default must be a constant.** `open = tool(TOOL_CROWBAR)` cannot be a var initialiser: the param is `null` and `entries()` says
  `open || tool(TOOL_CROWBAR)`.
* **Global procs called from a condition need `READS_FROM(...)`** in their body (or a hit in an opaque directory); a call to a state accessor generated by
  `cap_keys` is recognised by the analysis. A helper that calls other globals is followed: annotate the leaf, not every caller.
* **A requirement that reads `A.actor` takes `datum/act/op/A`**, not `datum/act/A` (DM types the var).
* **`TRACKED_BRIDGED` stays only for a var a machine pipeline stage really wakes on**: a plain `TRACKED` setter does not raise the old channel, and the
  missed-wake audit fails the suite when a stage needed it. The APC has no such stage (its work is the Rust power step and its poll), so its breaker,
  charge mode, short and grid check are plain `TRACKED`: check what wakes on the channel before you keep the bridge.
* **A capability key write marks the holder's outputs** (`capability_key_changed()` raises `CHANGE_CAPABILITY`), and a type whose table has a look layer is
  a type that is redrawn (`present_declares_look()`); without both the refresh-drift audit reports a draw that changed unmarked.
* **Op clashes are a build error**: two ops with the same binding and tier need exclusive `when()`s, different tiers or `priority(above(key))`.
* **The more specific binding wins a tie** (same input, intent, tier and side): `item(T)` for T narrower than `/obj/item` (deeper first),
  then `tool(Q)` / `any_of_tools(...)`, then the broad `item(/obj/item)` catch-all, whatever `when()` proc gates it. So a vendor's
  `stock` (`item(/obj/item)`, `when(stockable)`) never needs `priority(below(...))` under its panel's screwdriver, and a narrower
  `item(T)` answers above `storage.put_in` by itself. Write `priority(above(...))` or `click_order()` only to override this.
* **Tool ops wait.** `tool(Q)` brings the profile's wait; an op that only opens a window says `wait(0)`.
* **`options that names a state-dependent message`**: `says(CAP_PROC(x))` with `x(A)` returning a `/datum/msg` type; a toggle says what it did.

## 9. Doors: what the second conversion taught

The doors (`code/game/machinery/doors/`, the library `doors()`, `bolts()`, `weld_shut()`, `door_emergency()`, `multitool_settings()`) were converted in three
steps (base door, airlock, then firedoors, blast doors, windoors, unpowered doors, the assemblies, the buttons, sensors and the brig timer), each a merge of
its own, with 140 behaviour tests written against the legacy code first (`dq_p2_door/*`; the legacy tree is `rewrite/p2-tests-doors`: run a test there when
you must know what the old code did, rather than guess).

**The shape.** The base door (`door.dm`) brings `machine_basics`, `doors()` (the touch: a hand or any held thing, by the door's access), the emag and the base
door's own ops (strike, reinforce, repair). A kind of door `without()`s what it does not have and adds its own ops beside its type. The mechanism
(`open()`, `close()`, the swing, the timers) stays plain procs of the door, run by `then()` handlers; timers are keyed `after()` on `CLOCK_WORLD`
(`autoclose`, `swing`, `main_power`, `end`), polling is `every(when =)`, and a thing that must not poll waits on a gas watch (the firedoor).

**Recipes that came out of it.**

* *A refusal that says nothing and does nothing* (a blast door swallowing a held thing, a lift door refusing a sequencer, a windoor ignoring a crowbar):
  an op of the same input at the right tier whose `needs()` can never hold, or whose effect is empty. Never let the click fall through to a touch.
* *Tiers for held things*: emag 50, busy-swallow 48, tools 46, tape 45, welded refusal 44, prying item 43, strike (hostile) 20, the base door's ops 10, the
  doors() touch 0. A click that has two ops at one tier is a build error (`op_clash`); give a different tier, not `priority(above())` across kinds.
* *Dynamic prompt text*: `asks(/datum/prompt/yes_no, fields = list("question" = computed(PROC_REF(x))))`. `x(datum/act/A)` is read when the question opens.
* *A choice and then a question* (multitool settings): the choice op's effect `perform_op(..., ORIGIN_SYSTEM)`s the setting's own op, which asks its own
  question (`multitool_settings()` does this for any machine).
* *Key-only ops* (a simple mob forcing a door, a pilot's mecha bumping one): `op("x", ai(), wait(...), ...)` called as `perform_op(user, src, "x", origin = ORIGIN_SYSTEM)`.
  An op with no input, or a `perform_op()` at the default origin, finds no candidate and says "You can't do that that way".
* *A second worker on the same thing*: `claims()` on the op (it holds the target while it waits; `op_claimed(target)` for the look) and `req_unclaimed()` for
  an op that must not run over one.
* *A construction ladder that ends by replacing itself* (an assembly finishing into a door): build the thing, move what it owns (`own_transfer`), then
  `qdel(src)` in the stage's `then()`; `graph_advance` now skips a holder that is already gone. `replace_with()` deletes what the old holder owned.
* *Emags*: a door that takes none is `without(CAP_EMAG)` plus a refusing op; `emag_target()` (events, a changeling's pick) reaches a capability's emag through
  the cardless `emag.subvert` op.
* *State several hands change* (bolts, current, power, AI control): a `STAT(T, x, ANY)` composed from sourced holds, not a 0/1/-1 int with keyed
  timers. A timer is `hold(E, STAT_X, TRUE, SRC_Y, lasts)`, "until fixed" an untimed hold released by the fix, and a button's own hold has the
  actor as its source (`toggles_hold(STAT_X, source = ON_ACTOR)`), so two hands never undo each other and a pulse running out cannot undo a cut.
  React with `on_change(nameof(x), ...)`. The airlock (16.2) is the reference: `STAT_ELECTRIFIED`, `STAT_MAIN_POWER_OUT`, `STAT_BACKUP_POWER_OUT`,
  `STAT_AI_LOCKED_OUT` and the bolts library's `STAT_BOLTED`.
* *A touch the holder answers with something else* (a live door's shock): one takeover of its click ops,
  `extend(/datum/act/op, instead(when(STAT_X, req_on_origin(ORIGIN_CLICK)), then(PROC_REF(y))))`, run at the start of Do; `y` returns `HOOK_DECLINE` to
  let the op go on. Not an early `then()` on a hand-kept list of op keys.
* *A window button that refuses* says so with `needs(req_wire(...), req_is(...), because = MSG(x))`, never `to_chat()` and `OP_REFUSED` in the effect.
* *Keyed relations*: `ref_many(nameof(v), /type, by = nameof(id))` on the holder; the target needs nothing (the generator lists every keyed target
  so a table built first knows its key). It cannot name two different vars (a button's `id`, an airlock's `id_tag`): that bridge stays `rel_key()`.

**Pitfalls found.**

* A test that the kernel clock passes must not read `world.time` or `ELAPSED(.., CLOCK_WORLD)`; the code under test must use the timers.
* A legacy hibernation (`om_watch_arm_value` on the air) is kept where a test pins that a closed door is event-driven (`dq_closed_firedoor_is_event_driven`):
  no `every()` over a shut firedoor.
* Overriding a legacy proc the old engine bypassed (`on_emag` of a lift door) was dead code for a whole step; grep for overrides of what you replaced.
* `TEST_ASSERT(FALSE, ...)` inside an `if` is an "always true" DreamChecker error; assert the condition instead.
* The xeno claw ops reference `/datum/species/xenos`, which no longer exists; they are kept for parity and can never run.


## The block form

`CAPABILITIES(T)` is a header and its entries are the indented statements under it, one per line, no trailing commas and no backslashes:

```dm
CAPABILITIES(/obj/machinery/button)
	op("press", hand(), then(PROC_REF(pressed)))
	extend("ui_open",
		needs(req_operable()))
```

`STATE_GRAPH(graph)` is the same. The entries compile (nothing calls them) so a misspelt part or a bad named argument is a compile or DreamChecker
error. Differences from the old marker list: `link(A::a, B::b)` is `links(A::a, B::b)`; `configure(CAP_X, param = v)` is
`configure(constructor(param = v))`; `adjusts(packet.amount, ...)` names the path as text, `adjusts("packet.amount", ...)`; and an `ALLOW(...)`
annotation sits on the line above the entry it covers, not above the header. `python tools/dx/codemods/capabilities_block.py` converts a tree still
written as backslash lists.

## 10. Heat: converting a machine that moves heat

DM never computes a heat transfer and never writes a temperature or an energy outside `code/domains/` (the `heat_raw_temperature_writes`
lint is a hard ban). Converting a machine:

1. **Pin it on the old code first** (`dq_heat_machines_behaviour.dm` shows the shape): the temperatures after N seconds of `test_time()`
   and what was paid for them. The test clock advances the heat network with it (`vg_heat_net_advance`), so `test_time()` is enough.
2. **Name the flow, not the arithmetic.** A heat exchange between two things is `heat_link(a, b, conductance)`; a heater or cooler is
   `heat_pump(controlled, other, watts, target, mode, resistive)`; a generator is `heat_engine(...)` or, on per-step gas, `heat_engine_once()`.
   Gate it with the condition under which it exists (`when(nameof(pumping), ...)` with a `TRACKED` var, `when(STAT_OPERABLE, ...)`,
   `while_slotted(..., on = ON_CONTENTS)` for an occupant). Endpoints are `HEAT_PORT(i)` for a pipe machine's gas (never its `air_contents`
   handle, which a network rebuild replaces), `HEAT_AIR`, `HEAT_HOLDER`, `nameof(v)`, `HEAT_AMBIENT` for a hull with nowhere better to go.
3. **Pay with what Rust booked.** `heat_entries_bill(src)` is the electrical energy since the last bill: `cell.use(J * CELLRATE)`, or
   `use_power(-heat_entries_power(src))` for a grid machine. Changing a parameter the entry reads (a thermostat) is a tracked var named in
   `reads =`, or `heat_entries_refresh(src)` after writing it.
4. **One-off events** are `heat_add(thing, joules, HEAT_SOURCE_*)`, `heat_set(thing, kelvin)` (an authority write), `heat_move()` between two
   reservoirs, `heat_equalize()` for "both end at the mixed temperature". Never `mark_dirty()` after heat: Rust wakes what it changed.
5. **Record** every number that moved in `intended_changes.md` ("Heat network"), with before and after.
6. **What the test clock moves.** `test_time()` advances the heat network's declared edges only. Couplings that live in the native world (a
   body's slot coupling to its tile, turf gas diffusion, floor and wall solids) step with `SSair.run_gas_frames(seconds)`, which also steps
   the edges: a pin that involves a room uses it (`dq_body_heat_behaviour.dm`).
7. **Heat a datum holds** (not an atom: a batch, a service) is a heat store (`code/domains/heat/heat_store.dm`): keep its handle, link it with
   `heat_store_link()`, read it with `heat_store_temperature()`, and release it at equilibrium. A sample that covers a stretch of time between
   two reservoirs is `heat_conduct(a, b, conductance, seconds)`, never an exponential in DM.
8. **A gas reaction** never computes its heat in DM: build the mole deltas and call `gas_react(air, GAS_REACTION_*, extent, deltas)`; a new
   reaction adds its kind and enthalpy to `verdigris/domains/gas/src/reaction_energy.rs`.
9. **Mob bodies** are not machines: Life's environment stage calls `set_surroundings(air, surface, sky_area)` (W/K, W/K, m²) and the body's
   links to the plume of air, the floor, the walls and the sky follow it when it moves. Don't add a `heat_link()` to a mob for its
   environment; add to `set_surroundings()`.

## 11. Lifecycle forms: what replaces Initialize() overrides, qdel(src) and usr

Ten declaration forms (`code/engine/lifeforms/`, `doc/rewrite/final_api.html` section 6 "Lifecycle forms", one test file each:
`code/modules/unit_tests/dq_lifeform_*_tests.dm`) take over what an `Initialize()` override, a `qdel(src)` or a read of `usr` did by hand. The
codemods of `tools/codemods/` (`init_overrides.py`, `qdel_src.py`, `usr_sites.py`) do the mechanical half; the table says what to write by hand.

| Old shape | Write instead |
|---|---|
| `pixel_x = rand(-8, 8); pixel_y = rand(-8, 8)` / `randpixel_xy()` in `Initialize()` | `rolls(ROLL_PIXEL, PIXEL_JITTER(8))` |
| `icon_state = pick("a", "b")`, `amount = rand(2, 5)`, `if(prob(30)) broken = TRUE` | `rolls(nameof(icon_state), pick_one(list("a", "b")))`, `rolls(nameof(amount), range_of(2, 5))`, `rolls(nameof(broken), chance(30))` |
| `pickweight(list(...))` into a var | `rolls(nameof(v), pick_weighted(list(a = 3, b = 1)))` |
| a roll that reads another roll | `rolls(nameof(desc), PROC_REF(roll_desc), from = list(nameof(kind)))`, `roll_desc(datum/roller/R)` draws with `R.number()`, `R.choose()`, `R.chance()` |
| `Initialize(mapload, charge)` that stores `charge` | `param(nameof(charge), int(0, 100), pos = 1)`; callers `make(/T, at = loc, charge = 5)` (a positional `new /T(loc, 5)` still lands in `pos = 1`) |
| `Initialize(mapload, list/parts)` of a machine built from a frame | `built_from(nameof(component_parts))`; the frame calls `make(/T, at = loc, parts = ...)` |
| `GLOB.x += src` / `LAZYADD(GLOB.x, src)` with a matching removal | `registry(REGISTRY_X)`; keyed: `registry(REGISTRY_X, key = nameof(id_tag), by = REG_Z)`, readers `registry_get()` / `registry_all()` |
| `set_frequency(frequency)` in `Initialize()` and a hand-written retune | `radio_listen(freq = nameof(frequency), filter = RADIO_X)`; the frequency var must be `TRACKED` |
| `update_neighbours()` / `update_connections(1)` in `Initialize()` and `on_destroy()` | `adjacency(ADJ_KIND_X, into = nameof(connections), changed = PROC_REF(update_icon))` |
| an `Initialize()` that builds the same list for every instance | `per_type(nameof(table), PROC_REF(build_table))` |
| `default_apply_parts()` alone after `..()` in a machine's `Initialize()` | `default_parts()` in its `CAPABILITIES` block (`code/library/machine/parts.dm`; `tools/codemods/default_parts.py`): the parts refresh in `on_holder_init()`, before the type's code after `..()` |
| `apply_variant()` before `..()` in `Initialize()`, copying a variant family's row of vars (`code/datums/variants/`) | `variants(nameof(variant), PROC_REF(variant_table))`, the proc returning the family's table; `/obj/item/apply_variant()` applies it again for a later key |
| `new /obj/item/x(src)` in `Initialize()` | `initial_contents(/obj/item/x)`, `initial_contents(/obj/item/x, count = 3)`, `initial_contents(/obj/item/x, slot = SLOT_X)` |
| `new /obj/item/x(src, src)` (the child told its owner) | `starts_args = list(OWNER)` on the `owns_one`, or `initial_contents(/obj/item/x, args = list(OWNER))` |
| `add_language(LANGUAGE_X)` in a mob's `Initialize()` | `knows(LANGUAGE_X)` |
| `open()` / `toggle()` in a mapped variant's `Initialize()` | `starts_as("door.open")` (an op key) or `starts_as(COVER_OPEN)` (a state key) |
| a var recomputed in every setter of what it reads | `derives(nameof(v), PROC_REF(compute), from = list(nameof(a), nameof(b)))`; the inputs must be `TRACKED` |
| a window, request or condition deleted by its host's `on_destroy()` | `lives_while(nameof(host))`, `lives_while(PROC_REF(still_wanted), watches = list(nameof(answered)))`, `on_ending(PROC_REF(x))` |
| `qdel(src)` after the last charge, bite, dissolve or break | `spent(src, user)`, `consumed(src, eater)`, `dissolved(src)`, `destroyed(src, user, BRUTE)`; timed: `expire(delay)`, now: `lapsed(x)`; transform: `replace_with(/T)`, or `replaced_by(x, successor)` when the successor exists; an owner's teardown: `ended_with(x, src)` |
| `Click()` / `MouseDrop()` overrides reading `usr` | `click_on(PROC_REF(x))` / `drag_onto(PROC_REF(x), onto = /T)`; `x(datum/act/input/A)` reads `A.actor`; an op key binds the op |
| `MouseEntered()` / `MouseExited()` with `openToolTip(usr, ...)` | `tooltip(PROC_REF(x))`, `x(mob/user)` answers `list(title, content)`; `hover(PROC_REF(x))` for anything else |
| admin or callback code that sets `usr` to call a proc as someone | `with_actor(admin_mob, target, PROC_REF(x), args...)` (or a `CALLBACK` where the core allows one) |

What to know:

* **Order.** Params, `per_type` tables and rolls run at the root of the `Initialize()` chain, before the type's code after `..()`; a value a
  map edit, a param or `make()` gave suppresses its roll. `initial_contents()`, `knows()`, `starts_as()`, `derives()`, registries, radio, adjacency
  and scopes run with the capabilities' init. A plain datum runs the same from `New()` (the generator sets `lifeform_declared`).
* **Seeds.** A roll draws from a stream seeded by the round seed and the map position, or by its creator's stream. `rolls_fix_seed(n)` in a
  test makes a map roll the same twice. The distributions do not change; the realisation does (`intended_changes.md`).
* **Watched vars publish.** A registry key, a radio frequency, a `derives()` input, a `lives_while()` watch and an `adjacency(when =)` var are
  followed through their writes: declare them `TRACKED` (or write through a setter that calls `tracked_changed()`).
* **Endings carry a cause.** Every ending publishes `/datum/notice/ended` with `cause` (`END_SPENT`, `END_CONSUMED`, ...) and `by`; a type's
  `on_ending(PROC_REF(x))` runs `x(cause, by)` before the teardown. `qdel()` is the engine's; the `escape_hatches` lint counts what content still
  calls it and bans it once the count reaches 0.
* **Checks.** `analyze` rejects a `make()` naming a param its type does not declare or leaving out a required one, a write to a `per_type` var
  outside its build proc, and an ALLOW whose reason describes one of these forms (`lifeforms` lint). `escape_hatches` keeps the count of the
  remaining `ALLOW(init/...)`, `ALLOW(lifecycle)`, `ALLOW(sys_usr_outside_verb)`, content `qdel(` and content `usr` sites, which only falls.

## 12. Timed actions: task_timed, task_start, task_busy

A timed action a player does is an op with a `wait()` part. The old call sat inside a handler that had already been converted (`then(PROC_REF(interaction_x))`
whose body ends in `task_timed(...)`) or inside a legacy `attack*()` override. The pins `dq_timed_pin/*` record the behaviour on the legacy form
(duration, a move, a dropped item or a lost target cancels, what completion does, what is said); a conversion keeps each assertion.

**Parts.** What the old call said maps one to one:

| Old | Op |
|---|---|
| `task_timed(user, DUR, ...)` | `wait(DUR)` (a runtime duration is `wait(PROC_REF(x))`, `x(datum/act/A)` returns deciseconds) |
| `on_done = PROC_REF(done), done_args = list(user, I)` | `then(PROC_REF(done))`, `done(datum/act/op/A)`: `A.actor`, `A.held`, `A.target`, `A.holder` |
| the "You begin ..." message before the call | `begins(MSG(x))`, `MSG_DEF_SELF(x, "You begin %T% ...")` or `MSG_DEF(x, self, others)` (`%U%` user, `%T%` target, `%I%` item) |
| the finishing message | `says(MSG(x))` or stay in the `then()` proc |
| checks and refusals before the call | `when(...)` if the click is not this op's (falls through), `needs(req(PROC_REF(x), because = MSG(y)))` if the actor is refused |
| `M.use(5)` / `consume` of the held stack | `stack(/obj/item/stack/x, 5)` as the binding (the cost is reserved at the end) |
| `on_fail = ...`, `fail_message` | `on_interrupt(PROC_REF(x))` (`A.reason`) |
| `claims = TRUE`, `busy = X`, `if(task_busy(X)) return` | `claims()` on the op, `req_unclaimed()` for an op that must not run over a claiming one |
| `IGNORE_USER_LOC_CHANGE` / `IGNORE_HELD_ITEM` / `IGNORE_TARGET_LOC_CHANGE` | `wait(DUR, keeps = HELD \| ADJACENT)` (drop `STAY` for a wait the actor may walk away from) |
| `progress = FALSE` | `silent_wait()` |
| `task_start(/datum/task/timed/x, user, target, var = ...)` | the task's vars become the op: `duration` the `wait()`, `complete_proc` the `then()`, `fail_message` the `on_interrupt()`; state it carried is `captures(nameof(v))` on the op or a field of the target |
| a legacy `attack()` / `attack_hand()` / `attackby()` that starts the task | an `op("key", hand() / item(T) / in_hand() / tool(Q) / menu(), ...)` in the type's `CAPABILITIES`; the override is deleted |
| a bot or script starting the action | `op("key", ai(), wait(...), then(...))` and `perform_op(user, target, "key", origin = ORIGIN_SYSTEM)` |

**What does not change.** Exclusivity is `claims()` and nothing else: an op that declares none holds nothing, and a second input from the same player does not
stop the first (the old task refused a second action on the same target; an op that must not be run twice says `claims()`). The start message, the start sound and
a start-time effect (`begins()`, `plays(SFX, at_start = TRUE)`, `starts(PROC_REF(x))`) happen when the wait starts, not at the end. A bot or mob doing a job is an
`ai()` op (`perform_op(actor, target, key, null, ORIGIN_AI, AUTH_AI)` or `ORIGIN_SYSTEM`): the wait registers a pending op of its actor and keeps the default
keeps (`TARGET_PRESENT`, `STAY`), so a target carried off or a mob that moves ends the work. A tool act that refused a state and ended the click
(`ITEM_INTERACT_BLOCKING`) is an op of the same tool with a `when()` for that state and `needs(req(PROC_REF(never), silent = TRUE))`: the tool does not fall through to a hit.
A line that names the held item, the victims or a material is `begins(PROC_REF(x))` with `x` returning `msg_text(self, others, blind)`. A "no" to a
prompt that ends the op is `asks(..., ends_on_no = TRUE)`. A field that must not change during a wait is `captures(nameof(v), resume = CANCEL_IF_CHANGED)`.
A thing that is busy but is not an actor is `hold_busy()` / `work_busy()` / `release_busy()` (code/library/jobs/busy.dm); "is its `every()` armed" is `every_running()`.

**What a `when()` or `req()` may read.** A tracked var (make a plain var `TRACKED` and write it through its setter when it changes in play), a stat, a relation, or
an accessor with `READS_AS`. A value that is effectively fixed while a click is being decided (where an item lies, a player's key, the config, what stands on a
tile) is wrapped in `read_once(x)`. Do not move a read into a global proc with a blanket `READS_FROM()`, and do not rename a var to get past the lint.

**Two entry shapes that blocked about two hundred sites.**

* *A verb, an ability or a prompt answer starts the work* (`*_chosen`, `*_agreed(datum/act/request/A)`, a `/mob/living/proc/verb` that asks and then waits). The actor's own
  op is a `menu(button =, bind =)` binding (origin `ORIGIN_VERB` for the Abilities entry and the action button, `ORIGIN_HOTKEY` for a keybind), on the mob's `CAPABILITIES`
  (or a capability it is granted, `grant(E, capability, source)`). The question is an `asks(/datum/prompt/choice, fields = list(...), ends_on_no = TRUE)` step of the same
  op, the work is the `wait()` after it, the effect is the `then()` reading `A.answer` and `A.captured(nameof(v))`:
  `op("shapeshift", menu(button = "Shapeshift"), asks(/datum/prompt/choice/form), begins(MSG(x)), wait(3 SECONDS), then(PROC_REF(changed)))`. The old `open_request(..,
  PROC_REF(x_chosen))` and the `x_chosen` handler go; the verb stub is deleted. The handler that was reached by a prompt for another reason (an admin window) keeps its
  own op and calls `perform_op(actor, holder, "key", null, ORIGIN_VERB, AUTH_PHYSICAL)`.
* *A held item's `attack()` / `afterattack()` / `*_act()` override does the timed work on another thing.* The timed part is an op of the item's `CAPABILITIES` with an
  `at_target(T)` binding (the item used on a target of type T; `answers(INTENT_USE, ...)` for the intent), or an op of the target's `CAPABILITIES` with `item(T)` / `tool(Q)`
  when the target is the one type that cares. The override keeps only what is instant, or is deleted; a refusal the override ended the click with is a `needs(req(.., silent =
  TRUE))` or a blocked op (see above). Prefer the item side when the item acts on many targets (a lick, a scanner), the target side when many items act on one target (a door).

**Recipe, per file.** (1) Read the type's `CAPABILITIES`, every proc named in it, and every caller of the legacy proc. (2) Write the pin first if `dq_timed_pin`
has no assertion for the shape: drive `test_click(user, target, held)`, `test_time()`, read `test_chat_of(user)`; run it on the legacy form. (3) Convert; delete the
old proc and the done proc it names; keep behaviour. (4) `bash tools/dq_focused_test.sh 'dq_timed_pin/*'` (distinct run dir per agent), then
`bash tools/ci/check_ratchets.sh`.

**Pitfalls found.**

* Two ops on one input (`hand()`) with `when(PROC_REF(a))` / `when(PROC_REF(b))` are an `op_clash` even when the procs exclude each other: give one a tier,
  `priority(OP_PRIORITY_TAKE_OUT)`, not `priority(above(key))` (that is counted by the `op_order` ceiling).
* A `req(PROC_REF(x))` that reads a stack's amount fails the `reads` lint (the amount is untracked): use `stack(T, n)`. An `ALLOW(reads)` that no longer triggers is
  itself an error (`allow_annotations --unused`).
* Heredocs through the shell eat backslashes (`\a`, `\the`): write DM with the Write/Edit tools.
* A pin that reads `timed_tasks_of(user)` only sees the legacy form: use the `running()` / `was_cancelled()` helpers of `dq_timed_pin`, which read a pending op as well.

## 13. Three op forms for questions (rewrite/notices-asks)

* **A step that repeats.** `asks(/datum/prompt/x, fields = ..., step = "job", repeats = PROC_REF(more))`. After each answer and the op's re-checks, `more(datum/act/op/A)` runs (pure,
  reads only); while it returns TRUE the same question is asked again, its `computed()` fields recomputed (`A.step_values("job")` has the answers so far, so the question can name the
  next job). `A.step_values("job")` is the whole list in order, `A.step_value("job")` the latest. A cancel at any round ends the op with nothing written. `when =` composes: a skipped
  step asks nothing. The ban panel is the model (`code/modules/admin/topic/admin_topic_bans.dm`).
* **Claims cover the question phase.** An op's claims (`claims(...)`, or the ones derived from its waits) are held from the moment its first question opens until it ends, not only
  during a timed wait. `CLAIM_TARGET`: another actor's op on the same target is refused with `MSG(op/claimed)` ("in use") while the question is open and allowed once it is cancelled,
  answered or impossible. `CLAIM_HANDS` / `CLAIM_BODY`: the actor's other input is refused as busy (an AI) or stops the open question (a player). Deleting the actor releases them.
* **A question for someone else.** `asks(/datum/prompt/yes_no, fields = ..., step = "consent", answerer = PROC_REF(patient), ends_on_no = TRUE)`: `patient(datum/act/op/A)` returns the mob
  the question goes to. The answer is read as `A.step_value("consent")`. A decline (a no, a closed prompt), a deleted answerer, one who is no longer conscious or who moves out of reach of the
  actor ends the op with the usual feedback to the actor; so does the actor going. A handler that returns no mob ends the op as failed.
* **`starts(PROC_REF(x))` may refuse.** Return a `/datum/msg` type from `x(datum/act/op/A)` and the op ends with that message before the wait begins (no begins() message, no bar, no timer);
  any other return value is ignored, so existing handlers are unchanged.
