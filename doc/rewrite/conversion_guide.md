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
| `wires(WiresType)` | `.../wires.dm` | `wires.pulse/cut` behind the panel; `wire_set_of(E)`, `wire_is_cut(E, W)`; `req_wire()`, `req_wire_cut()`, `cuts_all_wires()` |
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
	wires = /datum/wires/apc,
	emag = list(wait(0.6 SECONDS), then(PROC_REF(emag_sparks)), sets(LOCK_LOCKED, FALSE)),
	emag_say = MSG(apc/emagged),
	panel_needs_cover_closed = TRUE,
	starts_locked = nameof(lock_at_start))
extend(CAP_LOCK, needs(req_not_subverted(), req_wire(WIRE_IDSCAN), req_operable()))
extend("cover.open", needs(req(PROC_REF(cover_free), because = PROC_REF(cover_hold_reason))))   // one extend per key: a list target is not supported
```

A condition is `x(datum/act/A)` (or `datum/act/op/A` when it reads `A.actor`/`A.held`), returns TRUE/FALSE, and **never writes, publishes or talks** (the
purity guard fails a test build). A refusal reason is a `MSG_DEF` type, or a proc returning one for a reason that depends on state.

**Starting state of a mapped instance.** Before: `cap_state = CAP_LOCKED` in the type and `cap_state = 0` in nine map entries. After: a plain var
the capability reads (`starts_locked = nameof(lock_at_start)`) and `lock_at_start = 0` in those map entries (a script rewrote them; see section 5).

**Window and buttons.** Before: `tgui_id`, a `tgui_data()` override, `act_*` procs and a `ui_allowed()` guard. After: `interface("APC")`, a
`ui_data(datum/act/eval/A)` that returns the data (`A.actor` is the viewer), and one op per button with a `ui_act()` binding; the old action
name stays (`ui_act("charge")`), so the TSX does not change except where the data shape moved (the APC's `caps.power` object became top-level keys).

```dm
op("set_channel", ui_act("channel", arg("channel", int(POWER_CHANNEL_EQUIPMENT, POWER_CHANNEL_ENVIRON)), arg("mode", int(POWERCHAN_OFF, POWERCHAN_ON_AUTO))), then(PROC_REF(ui_set_channel))),
op("breaker", ui_act(), toggles(nameof(operating)), then(PROC_REF(settings_applied)), logs(LOG_GAME)),
extend(TAG_UI, needs(req(PROC_REF(ui_usable), because = PROC_REF(ui_unusable_reason)))),   // the old can_use(), as a pure requirement
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
`wire_set_of(A)`. Map var edits of a deleted var are rewritten by a script over `maps/**/*.dmm` (match the `/type{...}` block, not the line), and the diff is
reviewed (a changed count that is not the count you expected is a bug). Tests of the legacy forms are deleted with them: delete, do not skip.

## 6. Engine pieces this conversion added

See `doc/rewrite/engine_contracts.md`, "Phase 2 additions" for the contracts. In one line each: the hit bridge (`hit_try()`), `ruined()` in `dismantle()`, the
presentation bridge (`look_layer`, `examine_line`, `ui_data`, `interface` to the window, `tgui_act` to ops), `says(PROC)`, `wait(PROC)`, `req_built()`,
`graph_place()`, `cap_keys` accessors in the reads analysis, `req_heard()` that really asks the hooks.

## 7. How to verify

```
CARGO_TARGET_DIR=... tools/analyze/target/release/analyze.exe gen          # after every CAPABILITIES edit; commit code/engine/_generated
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
* **Unit-test compiles are stale until `analyze gen` ran.** A fixture that names a renamed constructor compiles against the old `declare.dm`.
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
