# Intended behaviour changes of the phase 2 conversions

A conversion keeps behaviour. Where it could not, or where keeping it would have kept a bug, the change is listed here with its reason, and the
test that pinned the old behaviour was edited in the same commit. (conversion_guide.md section 2.)

## Chargers (cell charger, recharger, wall recharger)

Pinned by `code/modules/unit_tests/dq_p2_chargers_behaviour.dm` (28 tests, written and green on the legacy code first).

* **Examine adds a line when the machine is unpowered or broken** ("It is unpowered.", "It is broken."): `machine_basics()` brings `powered()` and
  `breakable()` with their look layers and examine lines. A broken charger also draws the library's broken layer where the icon has one.
* **A second cell clicked onto an occupied cell charger is refused** and the first cell stays. The old interaction table fell through to the
  ungated "take out" entry when the insert requirement failed, so the click pulled the first cell out. (The recharger already refused; unchanged.)
* **Refusal and wrench texts are generic.** `Remove [charging] first!` became the anchor capability's "Remove what is in it first."; "\A [charging] is
  already charging here." is "Something is already charging here."; the attach/detach lines are the anchor capability's, one text for both chargers.
  What is refused, and when, is unchanged.
* **The wrench ops carry no wait**, as before (`wait(0)` replaces the wrench profile's 2 s). The RPED op is an ordinary item op.
* **A cyborg takes a charging item out with an ordinary touch** (the `take` op, priority 5, ahead of the module-less cyborg's generic swallow); the old
  code reached the same result through the silicon entry. The item still lands on the charger's tile, and an AI still does nothing.
* **The cell charger's shown level follows the cell** (`chargelevel` is written after each frame and when a cell goes in); the old overlay was drawn one
  frame behind. A full cell sets the draw to idle in the frame that fills it, not the frame after.
* **A destroyed cell charger still deletes the cell it holds** (a recharger still drops its item): pinned, not changed.
* **A charger keeps a 2 second timer while it exists.** The machine pipeline parked an idle charger; `every(2 s, when = charging)` skips its handler while
  empty but the timer re-arms (engine contract: a type-level `every()` polls its gate). Cost is one timer per charger.
* The legacy `cap_parts()` library (`code/datums/capabilities/library/parts.dm`) and its two library tests are deleted: the chargers were its last users.
  A machine's part-derived numbers stay in its `RefreshParts()` until the machine track (phase 4).

## Engine and library pieces the chargers added

* `gesture(G)` alone makes an op answer the intents of that gesture (`op_answers()`): a `item(T), gesture(GESTURE_DRAG)` op is matched by a drag and no
  longer clashes with the use op on the same item. Test: `dq_p2_engine/pinned_gesture_answers_its_own_intents`.
* `anchor(tool =, empty =)` (`code/library/machine/anchor.dm`): op `anchor.toggle`, instant, refused while the named var holds something.
* `part_replacement()` (`code/library/machine/parts.dm`): op `part_replacement.replace` for a part replacer; phase 4 replaces it with `components(slots)`.

## Reagent containers: glass (beakers, buckets, kettles, mugs, bottles, vials, paint cans)

Pinned by `code/modules/unit_tests/dq_p2_reagent_behaviour.dm` (written and green on the legacy code first; the converted code passes the same tests, only
its adapter block changed). Rags are not converted yet: they inherit the label and dip handling and keep their own rules.

* **A hostile click on a person with an open container splashes them again.** It had been unreachable on master since the interaction migration: an item
  that does no harm answered its `attack()` with `ITEM_INTERACT_FAILURE`, and `interaction_hit` read that as "the click was used", so the item's
  `afterattack` never ran on an adjacent mob (sprays, splashes, syringes, droppers). Engine fix in `code/_onclick/item_attack.dm` with a test
  (`dq_p2_engine/a_harmless_item_reaches_afterattack_on_a_mob`); spray bottles now spray a person next to the sprayer as they did before the migration.
* **A splash empties the container.** The old splash over a floor or an object sometimes left a random part of the contents behind (the splash spilled a
  random share on the floor and then failed to move the rest); the commit spends exactly what it reserved.
* **An empty label clears the label** (the name goes back to the bare name); the old code left the name as "beaker ()".
* **Examine reads from the capability:** "It contains 37 of 60 units." / "It is empty. It holds 60 units." / "Its lid is closed." instead of "It contains 37 units
  of liquid." / "It is empty." / "Airtight lid seals it completely." Still only within two tiles.
* **One op answers a click.** Dipping a small thing into a container (in a hostile, disarm or grab stance), labelling it with a pen and testing its blood
  with a hot thing are ops, and an op ends the click: the held item's own afterattack no longer also runs after a dip. A held reagent container is poured
  rather than dipped. A hot item tests blood only while the container holds blood (the old test ran for every item and did nothing without blood).
* **The context menu says "Open or close the lid" and "Set transfer amount"** (the old entries were "Toggle lid" and the verb of the same name); a lid is worked
  in hand or from the menu, never by an empty hand (an empty hand on a container picks it up, pinned).
* **Refusal, pour, feed and splash texts are the library's.** What is refused, and when, is unchanged. A refused feeding says why (a mask, a belly, no mouth).
* **A drink goes to the stomach** (the ingested holder, with the taste) as before; the capability's own flow for it is new (`REAGENT_FLOW_INGEST`).
* The old `pickup()` and `dropped()` redraws of the beaker and bottle are gone (the look follows the contents, the lid and the label); a change of colour with
  no change of amount redraws through `on_reagent_change()`.

## Engine and library pieces the glass containers added

* `reagent_container()` settings may be var names (`volume = nameof(volume)`), plus `starts_open`, `transfer_default/min/max`, `starts`, `taps`, `rests_on`,
  `feed`/`feed_wait`, `examine_range`, `settable`, `spray_cooldown`, `shows_contents` (engine_contracts.md, "Reagent containers"). Tests: `dq_lib/reagent_*`.
* A legacy entry interaction answers the input its handler did (`op_legacy_fits()`): a held item is no longer offered the empty-hand touches of its target.
  A turf is reachable as the target of an op (`reach_surface()`). Tests: `dq_p2_engine/legacy_entries_fit_the_input`, `an_op_at_a_turf_is_reached`.
* `req_reagents(units, more =)`, `reagent_transfer_amount()`, `atom/legacy_transfer_amount()`; `atom/is_open_container()` follows the capability's lid.
* `without(CAP_X)` of a bundle drops the capability the bundle brought, and everything that one brought. Test: `dq_p2_engine/without_drops_a_bundles_nested_capability`.
* The old `cap_reagent_container()` library, its test and the `CAP_LID_OPEN` bit are deleted (nothing used them).

## Reagent containers: syringes and droppers

Pinned by `code/modules/unit_tests/dq_p2_reagent_needle_behaviour.dm` (31 tests, written and green on the legacy code first; only the set-amount adapter
changed with the conversion).

* **The waits show no progress bar and the first message is the library's.** An injection (two thirds of the syringe's time, a third for yourself), somebody
  else's blood draw (three seconds) and the dropper's squirt into the eyes (two seconds) are waits of the operation engine: it draws no progress bar, and a
  second injection started in the meantime is not refused by name (the second one finds the target or the syringe changed when its wait ends). Somebody
  injecting you is still seen to ("is trying to inject", "begins hunting for an injection port on the suit"): that is the new `begins()` part.
* **The thick hide of a species turns a needle away after the wait, not before it** (the same roll, for somebody else only). A needle that cannot go in a
  robotic, lifelike or missing limb is refused before the wait, as before. The old check ran the injector's own `can_inject()` twice (once for each
  message); it is one roll now.
* **A syringe switching mode redraws.** A full syringe that is drawing, or an empty one that is injecting, is set to the other mode when it is clicked on
  something (as before) and the look follows at once (the mode mark on the held syringe used to lag one redraw).
* **The messages are the library's** ("It is full.", "You cannot directly fill this object."); what is refused and when is the same. The lethal injection
  syringe still refuses blood and the stab, each with its own message.
* **A harm click on a person with a capped syringe still stabs** (the cap was never a guard): pinned, not changed.
* **A dropper's contents are told as "It contains 3 of 5 units."** (within two tiles) instead of "It contains 3 units of liquid."
* **Dead code is gone:** the syringe's `drawing` flag, its OM timed tasks and the `SYRINGE_*` defines (now `NEEDLE_*` in `code/__defines/reagents.dm`).

## Reagent containers: pills and patches

Pinned by `code/modules/unit_tests/dq_p2_reagent_pill_behaviour.dm` (13 tests, written and green on the legacy code first, and green unchanged after the
conversion).

* **A pill or patch is not wasted on a full container or an empty hand-me-down.** A pill dissolved in a container with no room left used to be used up and
  its contents lost; it is refused and kept now. A container with room for only part of it takes what fits and the pill is used up, as before (pinned). An
  empty patch (they start empty) used to be put on for nothing and used up; it is refused with "It is empty." and kept.
* **The one who puts a patch on somebody else is seen to attempt it** without the limb's name ("attempts to place the patch onto Jane"), and the one who forces
  a pill is told "You attempt to force Jane to swallow the pill". The waits (three seconds) draw no progress bar.
* **The thick hide of a species is rolled when the patch goes on,** after the wait for somebody else (the same roll; a thick material is refused before
  the wait).
* **The messages are the library's** (the limb is missing, it won't work on a robotic limb, it can't be applied through thick material); what is refused
  and when is the same.

## Reagent containers: hyposprays and blood packs

Pinned by `code/modules/unit_tests/dq_p2_reagent_hypo_behaviour.dm` (the hypospray, autoinjector, vial and blood pack tests green on the legacy code first
and unchanged after the conversion; the vial test was red on master before this step, see below).

* **A vial can be loaded into a vial hypospray again.** The glass container conversion (step 1) made a click with an open vial on the hypospray (an open
  holder) a pour, and a pour into a hypospray with no volume refused, so the old load entry was never reached. The `load` op now sits above the pour.
* **A spent autoinjector is shut by its lid state, not the old flag** (`open_at_start`, `REAGENT_CONTAINER_LID_OPEN`): unidentified injectors start shut
  the same way. Nothing a player does differs.
* **The thick hide of a species turns a hypospray away after the wait** (the same roll; before it, for an injection that waits). The injector's three
  seconds and the one who begins an injection being seen to are the op engine's `begins()`; no progress bar.
* **Blood packs:** the label question is the library's text prompt, and the label rules (fifty characters at most, ten shown in the name) are unchanged.

## Reagent containers: cartridges, powder, rolling paper, e-cigarette cartridges

Pinned by `code/modules/unit_tests/dq_p2_reagent_misc_behaviour.dm` (11 tests, green on the legacy code first and unchanged after the conversion). The chemical
canister is not converted: it refills the matching cartridge inside a dispenser machine (a machine-side rule) and is left as it was.

* **A dispenser cartridge's cap is the lid:** "Open or close the lid" in hand or from the menu, "Set transfer amount" (50 to 500), and the label is a menu
  entry (the text prompt is the library's). It examines as "It contains 500 of 500 units." / "Its lid is closed." A cartridge fills only from a tank whose
  top is shut, and pours into an open tank (the old code filled from any tank).
* **A powder is snorted by a straw or a rolling paper** as before; somebody who is not flesh is told so and the click ends (it used to fall through).
* **A rolling paper takes a dried plant as before;** the old "nothing in it" requirement on rolling an empty paper never applied, and still does not (pinned).

## Reagent containers: the cyborg hypospray and drink synthesizer

Pinned by the `borghypo_*`, `drink_synthesizer_*` tests of `dq_p2_reagent_hypo_behaviour.dm` (green on the legacy code first, unchanged after).

* **A click is the same; the window and the recharge are not converted** (`DECLARE_UI`/`UI_ACT`, `periodic_step()` and the old set-amount entry stay: the tgui
  window needs its own wave). The drink synthesizer clicked on a person now refuses silently (it used to fall through to nothing).

## Reagent containers: drinks

Pinned by `code/modules/unit_tests/dq_p2_reagent_drink_behaviour.dm` (cartons, cans, cups, the golden cup; green on the legacy code first, unchanged after).
Condiments, the cooking containers and solid food (`snacks`) are not converted; bottles keep their own smash, rag and spin rules and their `bottle_self` entry.

* **A glass in combat mode splashes a person or a thing, not an open container** (a hostile click on an open container pours, as for a beaker; the old glass
  splashed over the container). A drink that does no harm feeds in any stance as before; a drink with force (the golden cup) hits.
* **A drink says it is being fed to someone** ("is trying to feed ... from the carton") when the three seconds begin, and the ones who finish are told one tick
  after the sip (`On_Consume` follows the transfer); a drink finished by the sip still leaves its trash.
* **"Open or close the lid" is gone from drinks** (a lid that is only a state): a can is opened by using it, a closed one is told it is shut.
* **A cap on a tank the cup is filled from:** a drink fills only from a tank whose top is shut (the old drink filled from any tank).
## Reagent containers: the rag

Pinned by `code/modules/unit_tests/dq_p2_reagent_rag_behaviour.dm` (10 tests, green on the legacy code first, unchanged after the conversion).

* **Using an empty rag in hand says it is dry** (it used to do nothing); wringing out is still five deciseconds a unit and wipes still take three seconds, now
  as waits of the operation engine.
* **Only a flame lights a rag by a click** (the old catch-all item entry ended the click for every other item; a bottle with a rag still lights it, through
  `light_with()`).

## SMES and power terminals (power storage unit, buildable, hybrid, the input terminal)

Pinned by `code/modules/unit_tests/dq_p2_smes_behaviour.dm` (56 tests, written and green on the legacy code first; only its adapters changed).

* **The unit and its input terminals are linked.** The terminal's `master` relation was declared for an APC only, so the old SMES's attempt to link a
  terminal was refused at every build and at every map load (a stack trace once per type). A terminal now answers `master()` with its unit
  (`terminal.unit`, the pair end of the unit's `terminals`): destroying a terminal tells the unit, an overload reaches it, and the wirecutters find
  the terminal they are cutting.
* **Wirecutters and a welder with the hatch open work.** The "any other item" entry used to take them, so `wirecutter_act()` (take the terminal down,
  5 s, a 50 percent shock, ten lengths of cable back) and `welder_act()` (repair every point of damage, a decisecond per point) could be reached only
  by a direct call. They are ops now (`cut_terminal`, `weld`); the waits and costs are the ones the old code stated (no fuel is used).
* **The buildable unit's crowbar guards are gone with their dead code.** `crowbar_act()` (the charge, switch and terminal guards, a wait of ten seconds a
  coil) was shadowed by the machine core's deconstruct entry and never ran from a click. Deconstruction is the core's, as it was in play.
* **No click-spam guard on building a terminal** (`building_terminal`): a build is an op with a wait, and the cable is reserved while it runs. Two
  people building at once both finish; the second one is refused when a terminal already stands where it would go.
* **A hybrid unit makes charge from the moment it exists** (it used to sleep on its pipeline stage until some settings change woke it); its
  unreachable "alien technology" refusals are dropped, and a wirecutter click on it is swallowed with the hatch open as before.
* **The settings are tracked.** Every write of a unit's switches and levels goes through its setter (the power failure event, the supermatter setup,
  the debug verb, the grid checker, the planet SMES and the wires), so Rust hears each of them in the frame it happens; before, a direct write
  stayed unsent until the next wake.
* **An AI needs the remote wire; a cyborg at the unit does not.** Silicon use of the window is the remote binding gated by RCON; an adjacent cyborg
  touches the unit like a hand and opens its window (with the wires beside it when the hatch is open). The old silicon entry refused a cyborg with
  the remote wire cut.
* **The status overlays are drawn from tracked state** (`outputting`, `inputting`, the input switch, `last_disp`); the old code asked Rust each
  redraw. `power_poll()` no longer raises the machine pipeline's CHANGE_MACHINE_CHARGE channel (nothing waits on it).
* **The battery rack keeps its legacy forms** (its own window, interactions and pipeline stage; it was the SMES stage's other user): the stage is
  retargeted to the rack, it draws its own cells (not the SMES overlays) and sends its own window data.

## Battery rack (power cell rack PSU)

Pinned by `code/modules/unit_tests/dq_p2_batteryrack_behaviour.dm` (34 tests, written and green on the legacy forms first; mutation-checked: a wrong cell limit, the
least/most charged cell swapped, a wrong input mode, a wrong clamp, no capacity change on eject, no SMES unit conversion, a wrong slot flag, no transfer cap, a wrong
overlay mark and a dismantle that deletes its cells are each caught by a test). Only the adapter block of the file changed with the conversion.

* **The rack's window takes only its own buttons.** The converted SMES brought its window buttons (toggle input, toggle output, set input, set output) in its
  inherited table, so a rack's window could be sent them (the rack's own `inputting()`/`outputting()` swallowed the toggles, but the level setters worked).
  The rack drops them (`without(...)`); what it keeps is what its window shows: mode, equalise, eject. An EMP, a wire or an admin still reaches the rack's
  `inputting()` and `outputting()`, which still do nothing.
* **The look follows the cells and the charge.** The old rack redrew every tenth frame (twenty seconds) and when a cell went in or out; it now redraws
  in the frame its overlay set changes (a cell filling up, emptying, or the gauge stepping a level), and a cell going in or out is as immediate as before.
  Cost is the overlay set computed each frame (the frame already walks the cells).
* **A cell is taken in by an op.** A cell clicked on a rack ends the click there (the old entry also fell through to the part replacer and the base
  attack, which did nothing for a cell). A full rack refuses with "It has no empty slot for that." (the old text named the rack and the cell).
* **The frame is a timer, not a pipeline stage.** `every(MACHINE_SERVICE_INTERVAL, ...)` runs the same work at the same cadence the machine pipeline had
  (the rack never idled there either); the SMES stage and the pipeline's entry for the rack are gone.
* **Cells are an owned list** (`owns_many`): a rack destroyed or deleted deletes its cells, as before (only `dismantle()` drops them). Tests pin both.
* The premade `input_and_output_on` rack still sets mode three but not its input and output attempts (the rack's `inputting()`/`outputting()` do nothing): pinned as
  it was, not fixed.

## Engine pieces the battery rack added

* A subtype's own `interface()` replaces the window it inherits (`present_interface()` answers the most specific declaration; the subtype says
  `without("ui_open")` so the inherited open op does not clash with its own). Test: `dq_p2_engine/a_subtype_window_replaces_the_inherited_one`.
## Storage items (backpacks, bags, boxes, belts, pill bottles, toolboxes, lockboxes and the kits and cases around them)

Pinned by `code/modules/unit_tests/dq_p2_storage_behaviour.dm` (written and green on the legacy code first; only its adapters changed, and the tests added with the bot assemblies and the looks were checked against the commit before the conversion).

* **A crayon the box will not take says the general refusal.** The mime and rainbow crayons are `refuses` of the crayon box now (they are separate types), so they get "won't go in: it doesn't take that" instead of "too sad / too powerful to be contained in this box". The same check on the marker box was dead code (no mime or rainbow marker exists) and is gone.
* **An ID without the access, on an unlocked lockbox, is refused ("Access denied") and not put in.** The old entry said "Access Denied" and then put the card in. A broken lock, a locked box and an energy blade behave as before (the blade still slices the lock and then goes in, now through `passes()`).
* **The lockbox's lock is `lock()`.** `locked` is the capability's state `LOCK_LOCKED` (`lock_locked(box)`), `broken` stays a tracked var; an emag is `emag()` and its card pays a use and says the library's line besides the old "faint electrical spark" message. A PDA does not work a lockbox (`id_types` is the card only), and an alt-click on one opens it as before.
* **Parachute packing says nothing at the start and nothing when it is given up.** The waits are the old ones (five seconds to pack, two and a half to unpack); the "You start to pack" and "You give up" messages went with `om_task_timed` (an op's wait has no start message and says one thing when it is cancelled). The finish messages are the old ones.
* **A secure safe's service panel, memory reset and emag are ops.** The screwdriver and the multitool wait what the old tasks did (2 s and 10 s); the `om_busy` guard went with the task. The keypad is the same window (`SecureSafe`) and its `type` action is an op; the sparks, the shorted lock and the open light are drawn from tracked state.
* **A pill bottle's label prompt asks "Enter a label for it:"** (the old prompt named the bottle). The rules for the text are the old ones.
* **A box folds without checking that its user is within one tile** (it can only be used in hand, which is within reach).
* **The belt sprite of a worn storage follows the slot changes**, not every `update_icon()`: `on_slot_changed()` tells the wearer.
* **The 85 percent tray slip, the hand labeler's silence and the light replacer's refill are the same behaviours in new places** (`storage_balks()` of the tray, the labeler in the storage's `quiet` list, an op of the storage type).
* **The bot assemblies (a toolbox with ten floor tiles, a first aid kit with a robot arm) are ops of their storage types** in `floorbot.dm` and `medbot.dm`: on an empty toolbox the tiles start the kit and on one with tools they go in like any item; a robot arm on a kit with things in it says to empty it first.
* The old `cap_storage()` library, its tests and the `HOLDS_*` bits are deleted (nothing used them); the slot's hold constraint and `restrict_hold()` of a storage are the capability's.

## Tables (tables, benches, racks and the shelves)

Pinned by `code/modules/unit_tests/dq_p2_table_behaviour.dm` (written and green on the legacy code first; mutation-checked on the legacy code: a wrong plating time, a wrong strength, no flipped check on reinforcing, the carpet no longer blocking the wrench, no carpet dropped, a wrong unreinforcing time, a wrong dismantle sheet, a wrong repair amount, a flip that takes tables of any material, a movement check that ignores the side, no carpet in a full break, no brittle multiplier, a slam that does no harm, no one-table-per-tile rule, a frame that takes items, a drag that pushes the wrong sizes, a second carpet, a flip that does not shake climbers off, a look without the reinforcement layer and a description without the reinforcement's name are each caught by a test). Only the adapter block of the file changed with the conversion (the menu and drag adapters, and two tests that wrote the old layer vars now call `set_layers()`).

* **A tool with no job on a table is put on it, like any item.** The old tool handlers answered every tool (a crowbar on an uncarpeted table, a wrench on a reinforced or carpeted one, a screwdriver on a table with no reinforcement, a welder on an undamaged table) by swallowing the click: the tool stayed in the hand and nothing was said. A tool that has no job here is an item, and an item clicked on a table is put on it.
* **A reinforcing drag may come from either hand.** The old drag handler asked for the stack in the active hand; the drop asks that the stack is carried by the person dragging it (the reach gate still wants them beside the table).
* **Refusals say what they did not before.** A wrench on a carpeted table says to take the carpet off first, on a reinforced one it is the item click above; a flip refused for busy hands or a won't-budge row, a put back refused for something in the way, a grab that is too loose and a table that cannot be reinforced all name their reason (the old code was silent or said it in its own words). The words are the library's; what is refused, and when, is unchanged.
* **Taking the plating off gives back the sheet the plating was made of.** The old code gave a sheet of the material's stack type; a built table now gives back the stack that went on (the same type, with the runtime material a processed alloy carries), and a preset table gives one sheet of its material's stack type, as before. A material with no stack type still cannot be unbolted.
* **Two people plating at once spend one sheet between them.** The old timed job claimed the table; now both waits run and the second finds the table already plated when its own ends, so it spends nothing (pinned: the sheet count).
* **A preset's material is a var.** `plating_id` and `reinforcement_id` (a material id) replace the forty `Initialize()` overrides; `set_layers(plating, reinforcement)` is the one writer (a spell, a theme, a cultified table), and it builds the layers into the graph with a ledger of one sheet each, so the same refund applies. The dead `material_static`/`reinforced_static` vars are gone.
* **Dead code is gone:** the old interaction table, `common_material_add/remove`, the table task types and tool job, `cap_flip()` and its test (tables were its only user).

## Engine pieces tables added

* **The click's parameters reach the ops it runs** (`op_resolve_click_with_params()`, `code/engine/parts/inputs.dm`): `dq_interaction_click_params(actor)` answers inside an effect, so an item put on a table is aligned to where it was clicked. Test: `dq_p2_engine/a_players_click_carries_its_parameters`.
* **A player's drag of an item onto something with ops reaches the op that answers a drag** (`/datum/input_adapter/proc/drag`, `code/modules/keybindings/adapters.dm`): until now only a driver-built drag did; the real mouse drag went to the old `MouseDrop_T`. When no op takes it, `MouseDrop_T` runs as before. Tests: `dq_p2_engine/a_players_drag_reaches_an_op`, `a_drag_onto_a_thing_without_ops_is_left_to_it`. (A drag of a mob is the engine-gaps branch's.)
* `built_material()` is annotated `READS_FROM(E)` like `built()`, so a condition may read it.

