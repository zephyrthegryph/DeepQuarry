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


## Food containers: condiments and cooking containers

Pinned by `code/modules/unit_tests/dq_p2_food_behaviour.dm` (written and green on the legacy code first; spot-checked on the legacy code with seven mutations at once: five were caught at once (a count not reset when emptied, a renamed small shaker, a wrong amount added to a food, a missing item on the oven dish's list, an emptying that ignores distance); the two that were not (a room check one step off, a carton level rounded to the wrong step) led to the boundary cases now in the tests, which were not re-run against the mutations). Only the adapter block changed with the conversion.

* **A condiment is a `reagent_container()`** (always open; it is sipped by yourself and fed to others in three seconds in every stance, poured into an open container, filled from a tank with its top shut, and set to a transfer amount from the menu and by alt-click). The feeding texts of the fed are the library's ("You feed ... from ..."); the swallow keeps the old words. A condiment added to a solid food says "You add some of the condiment to ..." (the old line named the units that moved) and a full or empty one says why it cannot.
* **A hot thing held to a condiment bottle with a changeling's blood in it tests the blood**, as it does for a drink or a glass. The bottle's old item entry swallowed every held item before the test was reached.
* **The bottle's name, description and picture follow what is in it from a table** (`looks_for()`); the small shakers, the packets, the spice bottle and the cartons keep their own (`looks_like_contents`). The old sugar entry set no picture and still does not (an empty bottle that is given sugar keeps its picture).
* **A carton's fill is drawn by `draw()`** (a layer by quarters), redrawn when what it holds changes.
* **A cooking container has no "Set transfer amount" entry** (it poured nothing, so the entry did nothing). Putting a thing in is an op (the same list, the same room rule, a gripper puts in what it holds); an alt-click or the menu empties it (one op; the old verb of the Object tab is the menu entry "Empty container"); its examine lines come from declared lines.
* **A thing that is not on a cooking container's list is no longer swallowed by its item entry**: it falls to the held item's own use of it (a beaker pours into it, as before).

## Food: what every food has

* **"Rename food" is a menu entry** (the old verb of the Object tab); a blank answer puts the original name back, and a dead person or one without hands cannot.
* **A micro in a holder is put into a food by an op** (`stuff`); a shut drink and a wrapped or sealed snack refuse with the library's words. The old per-type texts for the stuffer and the stuffed are kept for drinks ("You drop ... into ...") and snacks ("Stuffed ... into ..."). A micro climbing in by its own drag is still the old entry (a drag of a mob is the engine-gaps branch's); it now lives once on the base food.
* **The food's own grid alignment on a table is gone.** It ran in `afterattack`, which a table's put-on op no longer lets run; tables align what is put on them (`auto_align()`, the same grid and the same centre of mass).
* The raw nutrition pile of the vore code had a `standard_feed_mob()` override that nothing called (the pile has no attack of its own): it is gone.

## Solid food (snacks, pizza boxes, custom food) and the end of the old helpers

Pinned by `code/modules/unit_tests/dq_p2_snack_behaviour.dm` (green on the legacy snack code first; one spot check of mutations was not run: the minimal test policy). Only its adapters changed (a question is answered after the click, a crayon and a fruit by type, a finished snack is given a second of time).

* **`edible()` is the library capability for eating** (`code/library/reagents/edible.dm`): eat, feed another (three seconds), swallow whole (the feeder's belly prompt, five seconds), used up. A bite is a RES_REAGENTS transaction like a drink's sip; what a bite leaves behind (`On_Consume`, trash, a swallowed micro, the contract event) runs one tick after it, as for drinks.
* **Refusals say why in the library's words** (wrapped, sealed, mouth covered, no mouth, too full, from a belly, unconscious while a mask is on); what is refused, and when, is unchanged. The fullness lines you read while eating are the old ones.
* **A wrapped snack and a sealed can are opened by ops** (using it in hand); the stuffing of a micro into a wrapped one is refused as before.
* **Slicing, hiding and scooping are ops of the snack.** A hide question is asked as a yes or no with a fixed text (the old one named both things), and answering no says nothing (the old line said you cannot slice here). A held condiment bottle used on a loaf is no longer asked about being hidden: it is added to the food.
* **An egg or a fruit emptied into an open container is an op** (`opens_into`); a full container refuses it, where the old click used the egg up and put nothing in.
* **Recipes that a held thing makes of a food are ops** (rolling pin on dough or a tea leaf, knife on meat or a cutlet, cheese on a burger, a bun with a meatball, a cutlet, a sausage or any food, bread, flat dough, spaghetti and a bowl with a food). A bun used with a meatball no longer also starts an empty custom burger from the deleted meatball.
* **Donuts: the extra nutriment is `nutriment_amt` of the type** (twelve units for a jelly donut, nine for a frosted one, as before) and the meat donut's three protein is a declared reagent (it lost the nutriment taste data the old add gave it).
* **The pizza box has ops** (open or shut, take the pizza with an empty hand, take the top box off a stack held in the other hand, stack, put a pizza in, write the tag, 30 characters) and declared ownership of its pizza. Its look stays the legacy appearance proc.
* **A micro dragging itself onto a food is the engine's mob drag op** on the base food (`climb_in`).
* **The old `standard_*` feeding, pouring, splashing and refill helpers, the Set transfer amount entries and verb (and `transfer_amount_verb`), `cap_edible()` and `cap_drinkable()` and their tests are deleted**; the interim tests that called the helpers directly are deleted with them (the pour, splash and feed behaviour is pinned by the container tests).

## Seating and beds (beds, chairs, sofas, stools, roller beds and their rack, wheelchairs, the electric chair, the dirty mattress)

Pinned by `code/modules/unit_tests/dq_p2_seating_behaviour.dm` (written and green on the legacy code first; mutation-checked on the legacy code: a wrong padding amount, padding with any material, no sheet back from the cutters, no sheet from a dismantled bed, a wrong buckle wait, a wrong double-bed raise, a roller bed that is not dense, a folded bed that is not used up, a disk not set at the pillow, a wrong mattress wrench time, a stool that gives no sheet and an electric chair that does not turn back are each caught by a test). The tests that pinned old bugs were edited in the same commit as the fix, and say so.

* **Beds, chairs, sofas, the dirty mattress and wheelchairs declare the library `buckle()`** (`code/library/structures/buckle.dm`): the drag of a person onto the seat, the grab, and the empty hand are its ops. The library's refusal reasons replace the old chat lines (it no longer says "You can not buckle while grabbed"; it says who holds them).
* **`buckle()` gained settings and behaviour the furniture needed:** `smallest` / `largest` (a number or the name of a var of the holder; the wheelchairs read `min_mob_buckle_size` / `max_mob_buckle_size` as before, and the old `can_buckle_check` override is gone); a predator who sits on a full seat swallows an occupant they can stumble-vore (`can_stumble_vore`, same rule as `user_buckle_mob`); a seat that was pulling the one who sits (a wheelchair) lets go of them (the old `buckle_mob` override); a grab that buckled its person is let go of (the old code tried to buckle while the grab was held, and a grabbed person cannot be buckled).
* **The kinds that were meant to refuse padding refuse it.** The roller bed, office chair, wooden chair, wheelchair and alien bed each had an `interaction_item()` that swallowed a stack, but the old entry named the bed's own proc by path, so the override never ran and a sheet of cloth padded all of them. They now carry `can_pad = FALSE` (and `can_unpad`, `can_dismantle` where their wrench or cutters overrides said so) and swallow the stack.
* **A shock kit makes an electric chair** (the chair's override of the same dead proc is now the chair's op: a secured kit on an unpadded chair; an unsecured one, or a padded chair, is refused with a reason).
* **The roller bed rack collapses an empty roller bed and frees the person on an occupied one** (the bed's override never ran before).
* **Padding, taking the padding off and taking a seat apart are ops** with the library's refusal texts; the holographic chair and bed, the wheelchair, the roller and alien beds and the nest-like kinds say they cannot be dismantled (as their wrench overrides did).
* **The nest and the pillow piles take none of the bed's ops** (`bed_hands_off()`), as their own interaction tables never inherited the bed's.
* **A secured dirty mattress is bolted with the shared `anchor()`** (wait two seconds as before); its "not secured" notice is an op.
* **`cap_buckle()`, its test and its files are deleted** (nothing but its own test called it).
* **Kept on the old forms, noted:** the legacy `user_buckle_mob` / `hand_gate` / default-drag buckling in `code/game/objects/buckling.dm` (about 40 other types still set `can_buckle`: mechs, pipes, operating tables, nests, cryo and the like, each its own conversion), the roller bed's and wheelchair's own `MouseDrop` fold, the nest's own buckling and struggling, the chair's telekinetic rotation (`INTERACT_TK`, no replacement on master), the electric chair's toggle verb, `make_rotatable()`, `post_buckle_mob()` and the look. `/datum/om/relation/buckled_to` stays: mobs, `buckle_mob()` and the library all use it. There is no `riding_datum` or `deferred_buckle` in this tree to convert.

## Climbing structures (tables, railings, cliffs, fences, machines) on `climb()`

Pinned by `code/modules/unit_tests/dq_climb_conversion_tests.dm` (written and green on the legacy `make_climbable()` behaviour first; only its adapters changed with the conversion: the climb is started by the mob's own drag, and a shake is `climb_shake_off()`). 81 `make_climbable()` sites became `climb()` entries on their types' `CAPABILITIES` blocks (`/datum/om/behaviour/climbable`, `make_climbable()`, `unmake_climbable()`, the `climbers` relation, the `climb_start` and `climb_shake` events and the old `cap_climb()` are deleted). The library's `climb()` gained `landing`, `delay_by`, `gate` and `climbed`: the table's flipped landing, the cliff's half time and climbing-shoes rule, the fence's hole rule and the unanchored railing that breaks are each one holder proc named in the type's own entry.

* **A climber on a flipped table now climbs out the side the table faces** (when it can go there). The old table rule returned that tile and nothing moved the climber, so a climb from a flipped table's own tile did nothing at all.
* **Everyone shaken off falls, not only the first.** The old shake stopped the loop at the first climber who was not hurt in the 25% fall; each climber is now knocked down, and each has the 25% chance to land hard.
* **A shake ends the climb by cancelling it** (the climb op is cancelled and the climber is knocked down) instead of removing the climber from a `climbers` list and letting the finished task fail its checks. A structure that moves under a climber (a crate pushed, a solar panel) does the same through the op's interrupt, for any move that breaks the wait; the old code skipped forced moves (up a staircase), the interrupt cannot tell them apart.
* **The "Climb structure" verb is gone**: a climb is the mob's own drag onto the structure, or "Climb" in the context menu. A climb that is refused says why in the capability's words (the legacy code was silent in some cases) and a mob that is not allowed to act (restrained, buckled, down, paralysed) is told it needs its hands and legs free.
* **A fence is climbable by its hole, not by when it was cut.** A medium hole is climbed through (including the premade cut fences, which the old code never made climbable, only a fence cut at run time); an intact fence and a large hole (walked through) refuse the climb. An intact fence is still not climbable.
* **A structure that is not climbable carries no climbable trait** where the old unmake left it (huge scrubbers, the old reactor crate: `without(CAP_CLIMB)`).
* **The default drag (buckle) entry applies only to what can be buckled to.** It used to apply to anything climbable and emit the climb; the climb is now the capability's op. A closed crate, a low wall and a trolley tank no longer climb through their own drag entries.
* The climb delay of an instance is the type's declaration: a per-instance `climbable_delay` edit on a map no longer exists (none did).
## Closets, lockers, secure closets, crates and secure crates (the family under `code/game/objects/structures/crates_lockers/`)

Pinned by `code/modules/unit_tests/dq_p2_closet_behaviour.dm` (108 tests: the closet, lockers, crates, secure crates, the personal and mind lockers, the emergency locker, coffins and graves, statues, eggs, body bags and stasis bags, wrapping). The file was written against the legacy forms first; the tests that failed there for a reason of their own (a person standing out of reach, a capacity worked out wrong, a fixture left on the tile, an EMP loop that opened the thing it was waiting on) were corrected in the same pass and are named in the commit.

* **A closet is a door over an interior, declared with `CAPABILITIES(/obj/structure/closet)`.** The hand and the "Toggle Open" menu entry are one op (`door`), the bolts are the library's `anchor()` (two seconds, only while the door is open), the seal is the library's `weld_shut()` (two seconds, only while it is shut) and a lit welder cuts an open one apart (`cut_apart`). The mechanism (`open()`, `close()`, the swing, what it takes in and spills) is still the closet's own procs, as the doors keep theirs.
* **`weld_shut()` took a `tool` parameter** (default the welder): a coffin is screwed shut (`configure(weld_shut(tool = TOOL_SCREWDRIVER))`), with no flame and no fuel. A grave and a statue have nothing to seal (`sealable = FALSE`); a filled grave is "welded" from the code that fills it, so it holds like a sealed closet, and examining it says so.
* **`sealed`, `seal_tool` and `breakout` are gone.** The sealed state is the weld key (`is_welded()`, `set_welded()`), the tool that seals a type is the `weld_shut()` parameter and the break-out mutex is the engine's own "an actor has one wait at a time". `locked` stays a var only as what a map says a locker starts as (`locked = 0` in a map still works); the lock is the library `lock()` key, read with `lock_locked()` and written with `force_lock()`. `broken`, `opened` and a crate's `rigged` are tracked (`set_broken()`, `set_opened()`, `set_rigged()`).
* **Breaking out is a wait.** Resisting inside a sealed (or locked) closet starts the `break_out` op: one wait of `breakout_time` minutes that ends if the person is knocked out, dies or the closet is destroyed, or opened by someone else. The old five-second shoves each shook the closet and played the sound; now it shakes and sounds once, when the door gives, and the opening line no longer says how many minutes it takes. A second Resist while the wait is under way does nothing. Every other thing the person does (clicking something) ends the wait, as with any wait.
* **A locker or secure crate has the library lock**: a card or a PDA in the hand (the card in hand is the credential), an alt-click, the "Toggle Lock" menu entry (the old verb), and a hand of somebody whose own ID has the access. The hand opens an unlocked locker and works the lock of a locked one; an alt-click now also works the lock of a secure crate (it did not, only its verb did). The lock refuses while the door is open ("Close the locker first."), when it is broken, and from inside. Any other item in the hand of somebody whose own ID has the access still works the lock of a shut one (`lock_with_item`), as before; a locker's old "Access Denied" for everybody else is the library's. The lock is out of the reach of the one shut in with it.
* **An emag, an energy blade and an EMP**: the emag is the library's `emag()` (repeatable); one that finds the lock already broken is refused with "It is already subverted." and spends nothing, as the old second emag did; a secure crate's blade is the cardless emag. EMPs are `on_notice(/datum/notice/hit/emp)` for the locker and the crate (the same odds).
* **The personal locker's swipe is an op** (`swipe`: the master access, an unowned locker or the owner's own card, and the first card claims it; a card with no name is refused with a reason, a broken lock too) and its "Reset Lock" is a menu op (no longer limited to humans). The mind locker works its lock only for its mind (`allowed()` is kept, and the lock's own requirement asks it).
* **The crate**: grabs are refused with a reason ("You can't stuff anyone into that.", it swallowed them without a word); a cable rigs a shut one and an electropack goes in beside it (`rig`, `attach_pack`), wirecutters cut the rigging (`cut_rigging`) or, on a crate that is not rigged, work it as a hand does (`cutters_touch`); a mob that drags itself onto a shut crate climbs it (the library `climb()`, replacing `make_climbable()`).
* **Package wrap now wraps a shut closet or crate.** The old closet item entry answered "handled" to a wrap, so the wrap's own use never ran and nothing could be wrapped. A shut closet has no op for it now, so the click goes on to the wrap.
* **A closed closet no longer swallows every held item.** The old entry answered every click that was not a tool for it; a click with nothing for the closet to do now goes on to the legacy chain (an item in combat mode hits it, as it does any object).
* **Laundry baskets, grabs and things set down** are ops of an open closet (`empty_basket`, `stuff_grab`, `set_down`, and `stuff` for a drag): the same rules (a cyborg lets go of nothing, only what is carried is set down, a grab only where the locker is large enough) with a reason where there was silence. A locker "too small" (`large = 0`) refuses a grab with the old words.
* **The hidden vore verb is the menu entry "Devour Occupants"** (`devour`): it asks which of the devourable ones shut in with you, and refuses with the old words when there are none. Somebody outside is not offered it.
* **The emergency locker takes supplies with a hand** (`take_supplies`); it has no door, no "Toggle Open" and takes nothing in (the old `toggle()` handed supplies out through the verb). **A statue** has no door, takes nothing and any held thing strikes it (`strike`); it can no longer be welded shut (it had no seal to show). **An egg** is cut open by a welder lit or not (`cut_open`) and has no bolts. **A grave** has no door, climbed into with a hand (five seconds), filled in with a shovel (open), unearthed or, in combat mode, smoothed over with one (shut).
* **Cult rune "free the cultist"** now sees a welded closet and a locked locker (it read a var called `welded` that nothing had).
* **The abandoned crate, the safes' code locks (numberlock, devillock) and the lock-breaking tools**: the code lock is an op (`enter_code`, a hand or any held thing asks for the code; `analyse` is a multitool), the emag opens a locked one, and a hack tool and the brig timer use `force_lock()`. Their shared code (made once, a type table for the alphabet) lives on the safe base; none of the three has an ID lock, as before.
* **Deleted:** the closet's `declare_interactions()` and its `entry_*` interactions, `interaction_item/hand/drag`, `wrench_act`, `welder_act` and their `*_tool_done` procs, `togglelock()` and `set_locked()` of the secure ones (the three code locks' `togglelock()` was the prompt, now the op), `secure_verb_togglelock_effect`, `verb_toggleopen_effect`, `can_use_by_hand`, the break-out push procs and the closet's `DAMAGE_REACTION`s for the EMP.
* **Body bags** (the folded bag, the bag, the mass-grave bag, the stasis bag and the synthmorph bag) declare their ops: a folded bag used in hand unfolds (`unfold`: it must be let go of by where it is carried, and a stasis bag's injector goes with it), a pen labels a bag (`label`: the question is the new typed prompt, and an empty answer leaves the name as it was), wirecutters cut the tag off, and a person who drags a shut, empty bag onto themselves folds it (`fold`, a human only; the drag is the dragged bag's own op, replacing its `MouseDrop()`). A shut stasis bag is scanned by a health analyzer through its skin (`scan`), takes a syringe (`insert_injector`) and gives it back to a screwdriver until somebody is zipped in (`remove_injector`, with the old words for a used bag); opening a used one asks first (`door_used`, one `confirms()`); the synthmorph bag reads a cyborg analyzer (`scan_robot`), swaps its tag for a held badge (`swap_tag`) and gives it back to an alt-click (`remove_tag`). The injector and the tag are declared relations (`owns_one`). A shut body bag no longer swallows every held thing (an open one takes things set down on it like any closet).
* **Kept on the old forms, noted:** `relaymove()` (a move key inside), the `closet_closed` event the bluespace behaviour listens to, `vehiclecage`, `largecrate`'s crowbar (the wooden large crates are not closets), the mimic crate's `DAMAGE_REACTION` and `open()` override, the closet's look (`APPEARANCE_*`) and the door animation, and the ledger slot (`/datum/om/relation/slot/closet_interior`).


## The one transfer verb: `move_into(holder, slot_id, item, actor =)`

Pinned by `code/modules/unit_tests/dq_ownership_transfer_tests.dm` (the old `own_set(..., user =, into =)` tests, moved onto the verb, plus tests for the record and log, the refusal reason, the undeclared var, adoption by shape and the insert hooks). `/atom/movable/proc/move_into(holder, slot_id, actor)` and the transfer arguments of `own_set` / `own_add` / `own_put` were one job done two ways; the verb in `code/engine/declare/transfer.dm` does both: a `slot_id` naming a declared owned var of the holder is the var-slot (checked, released, moved in, adopted through the tracked write of the var's shape, recorded); any other `slot_id` is a ledger slot (checked, released, placed).

* **A transfer asks the holder's `/datum/act/insert` hooks.** `extend(/datum/act/insert, needs(...))` on a holder now refuses a `move_into` too (it used to apply only through ops and `slot_transfer`); the insert's notice goes out when the item lands; the actor is the hook's actor. `force = TRUE` skips the checks and the hooks, as before. The part engine's `put_in` no longer starts the insert itself: the verb does.
* **A refusal is a reason.** The verb returns FALSE (it returned the value or null), leaves the reason in `GLOB.act_last_reason` and the outcome in `GLOB.act_last_outcome`, tells the actor, and writes a `MOVE_INTO:` line to the world log; `move_into_refusal()` is the same check without the move.
* **Items in a mob's hand or equipment now leave through the mob's own release** (HUD, slot redraw, `dropped()`) when a legacy `thing.move_into(holder, ...)` call moves them. It used to be a bare ledger commit that skipped them, so the caller had to unequip first (the equip code still does). An item already inside the holder only changes ledger slot.
* **A NODROP item in a hand is refused by `move_into`**; the old ledger-only call moved it. Use `force`.
* **No first-write learning.** A var the type never declared `owns_one` / `owns_many` is refused and reported (`OWN: move_into: T.v is not declared owns_one/owns_many`); the old accessor learned an `OWN_DELETE` entry on the first write. 48 declarations were added for the converted sites (chemical dispensers' `cartridges` among them).
* `move_into` always moves the item in (off a turf too) unless it is already inside the holder. A var that adopts something that stays where it is is `rel_set` / `rel_add`: the 24 `into = FALSE` sites are those.

### own_set / own_add / own_put retire (transfers wave, part 2)

* **`own_put(h, v, k, x)` is `rel_add(h, v, x, k)`** at 186 production sites (72 files; the unit tests too). `own_set` / `own_add` / `own_put` keep only the in-place arguments (`into = FALSE`, which `own_transfer` / `own_move` use); their `user`, `slot`, `force` and `log` are gone, since only `move_into` moves a thing for a person. They are the engine's own accessors now: callers outside `code/engine/`, `code/datums/ownership/` and the accessor unit tests are the two decl-baselined `own_put` calls in `gun.dm` (firemodes) and `armmounted.dm` (integrated tools), which build their children by hand in `Initialize` and need `starts` declarations before they can take `rel_add`.
* **First-write learning of owned vars is gone.** `rel_set` / `rel_add` / `move_into` need the var declared (`owns_one` / `owns_many`), and an owned var written without one is reported (`own_entry_of_kind`). The starting occupants of `DECLARE_DEFAULT_CHILD` (274 sites, 219 types) became `owns_one` / `owns_many` entries with `starts =` in the type's CAPABILITIES list (`tools/dx/codemods/default_children.py`; a CONTAINED part keeps the legacy `owns(policy = OWN_CONTAINED, starts =)` in `ownership()` until it becomes a slot), `DECLARE_GAS` vars and the containment `ledger` are declared, and `own_adopt_start()` is deleted. Learning of implicit relation views (`rel_set` / `rel_add` on an undeclared var) remains.
* **Legacy `owns(..., is_list = TRUE)` on 14 list vars** (`holdingitems`, `washing`, `victims`, `rockets`, `grenades`, `darts`, ...): the old `own_add` worked on any entry, `move_into` reads the declared shape, so the flag was missing.
* **The declaration tables exist during global init.** `table_of()`'s caches (`type_table_cache()`, `type_blocks_cache()`, the link and keyed-target caches) are statics, not GLOB lists, so the first lookup builds a type's table whenever it comes, even inside a global datum's `New()`. `/datum/lore/loremaster`, `/datum/perk_tree` and `/datum/station_faction_relations` declare `owns_many` in their CAPABILITIES lists again. The audit of the ~750 `rel_add` / `rel_set` calls from global-init datums used the runtime record of every first-written undeclared var (a relation write to a var no list declares is learned as a view): the vars it listed (construction graph `wildcard_edges`, event container `available_events`, `parent` / `graph` / `holder` back references) are views; nothing there needed an owned declaration.
* **`supplied_laws` is untyped owns_many** (it holds the empty-string padding between laws).

## Computer consoles (code/game/machinery/computer), hand conversion

Pinned by `code/modules/unit_tests/dq_hc_computers_*.dm` (written against the legacy forms first). Every window action keeps its name.

* **A window button's guard is a requirement or an early effect.** The old `ui_act_allowed()` overrides moved into `extend(TAG_UI, ...)`: a pure requirement where it refused (the robotics console's authentication, "Access denied."), an early `then()` where it had a side effect (the timeclock's fingerprints, the patient monitor's `set_machine`, the AI restorer's key click and its "stop restoring when empty").
* **Batch 1.** Atmospheric alert, prisoner management, AI restorer, patient monitor, timeclock, robotics control. The `ref` arguments of the windows (alarm, implant, cyborg) are bare arguments resolved in the handler with `ui_ref()`; a ref that is none of those does nothing, as before.
* **Prisoner management "warn"** asks its text with `asks(/datum/prompt/text)`; the fingerprints are left when the effect runs (after the answer), not when the button is pressed.
* **Robotics "hackbot"** asks "Really hack this cyborg?" with `asks(/datum/prompt/yes_no)` after the requirement (the console shows the cyborg, the operator may hack) holds; the cyborg's name is no longer in the question (a field cannot read the op's argument), and a console the operator may not hack with now says "You cannot hack that." where it did nothing. The hack is re-checked when the answer arrives.
* **TimeClock window: the on-duty payload keys are `rank` and `assignment`** (they were `switch-to-onduty-rank` and `switch-to-onduty-assignment`): the TypeScript generator does not quote a hyphenated argument name. `TimeClock.tsx` is changed to send them; the PDA timeclock app (a separate host) is unchanged.
* **Batch 2.** The ID card console and the guest pass terminal. A custom assignment is its own window action, **`assign_custom`** (the "Custom" button of `IdentificationComputer.tsx` sends it; `assign` with the target "Custom" is gone): an `asks()` step cannot be conditional on an argument, and the console now refuses it up front ("needs an authenticated operator and a card") where the old prompt was only never opened. The typed text is the assignment, and the card's name is refreshed after it (it was not after a custom assignment).
* **Guest pass terminal questions** (name, reason, duration) are `asks()` steps; the fingerprints are left when the answer arrives. A typed prompt that the old code could not be answered in a unit test (its re-check read a player's tgui state) is now answered in the tests that were added with the conversion.
* **Deactivating a guest pass** (a hostile use in hand) asks with `open_request(/datum/prompt/yes_no)` and re-checks that the pass is still carried and the person can act when the answer arrives (the old `ASK_CARRIED | ASK_CAPABLE`).
* **Selecting an access on a terminal with no ID** no longer errors (it read the missing card's access).

## Hand-converted items (code/game/objects/items)

Pinned by `code/modules/unit_tests/dq_hc_items_behaviour.dm` (written and green on the legacy code first, except where a line below says otherwise). Gun boxes also by `interim_gunbox_lifecycle.dm`, whose prompt step now goes through the click and the answer.

* **Gun boxes are one op.** The base box's `open` op asks for the kit with a choice prompt; the five variants no longer replace the op, they override `kit_options()`, `kit_question()`, `kit_title()` and `kit_greeting()`. The `variant_gunbox` var and the `/datum/om/prompt/choice/gunbox` kind are gone. A cancelled question keeps the box (as before).
* **Geiger counter.** The alt-click reset on a counter that is off is refused with the reason "It must be on to reset its radiation level." (the old text, now a message). The wall counter's empty-hand and silicon toggles are one `inputs(hand(), remote())` op. `scanning` and `last_perceived_radiation_danger` are tracked and the look is a `draw()`: the icon follows them after the next frame rather than inside the call that changed them.
* **Latex balloon.** The blast and projectile reactions are hooks on `/datum/act/hit/explosion` and `/datum/act/hit/projectile` (a blast bursts it and still lands, a round bursts it and is taken over); a pointed held thing bursts it through an op that passes the click on to the ordinary attack.
* **Petrifier.** The refusal "the device beeps but does nothing" is a message of the op's requirement.
* **Shooting target.** Taking a pinned target off its stake is an op of an empty hand, only a candidate while a stake near it holds it pinned (so a free target is picked up like any item). Written after the conversion: `target_pinned_is_taken_off_stake` was not run on the legacy code; it follows the legacy handler line by line.
* `can_puncture()` and `get_ultimate_mob()` carry `READS_FROM` so a condition may call them.

## Mobs (code/modules/mob/living), hand conversion

Pinned by `code/modules/unit_tests/dq_hc_mobs_behaviour.dm` and `dq_hc_bots_behaviour.dm` (written and green on the legacy forms first). Each worker's area adds its own section below.

* **A mob's damage reaction runs after the hit, not before it.** The 40 `DAMAGE_REACTION` / `DAMAGE_REACTION_AFTER` rows are `on_notice(/datum/notice/hit/<entry>)` for the ones that only react (EMP effects, projectile sounds, antlings, blinking, cloak breaks: they used to run just ahead of the sink) and `extend(/datum/act/hit/<entry>, instead(...))` for the ones that stop a blast (cockroach, illusion, rabbit, puffer, dark purple slime, oil slime, AI core, weaver silk, mimic crate, floor mimic, swarm pulse). A reaction that did not block therefore sees the mob after the hit landed and only when the hit was committed. The mob's own family ladder (human species, simple mob injuries) still runs after the reaction exactly as before.
* **A thrown thing is the generic hit.** The simple mob's reaction sound and the demon's laugh on a thrown thing listen to `/datum/notice/hit` and check the entry (`DAMAGE_ENTRY_THROWN`) themselves: there is no thrown notice.
* **`break_cloak` has a handler for the hit** (`/mob/proc/hit_breaks_cloak(datum/act/A)`); `break_cloak()` stays the call everything else uses.
* **Service bots: the controls open on a hand click through the window's own op** (floorbot, cleanbot, secbot): the old "Open controls" entry took any hand; the op needs an actor who can act (not stunned, not restrained). Farmbot keeps its help-intent touch (it pets first and opens the controls when that did nothing) as its own op, medbot and mulebot keep their legacy hand entries (tip over, right, controls) and the window's open op answers the menu and a remote user only.
* **A button press leaves the presser's fingerprints** through one `extend(TAG_UI, then(ui_fingerprint))` on the bot base (floorbot used to fingerprint the bot itself).
* **Mulebot beacon questions** (set home, set destination) are requests: the answer is re-resolved to its beacon when it arrives (a beacon that was removed meanwhile ends the question without effect instead of reading a deleted one), and the "can still work its window" check is the default tgui state's.
* **`EVENT_HANDLER` is `SHOULD_NOT_SLEEP(TRUE)`** on the 28 mob handlers that carried it (the macro expanded to exactly that).
* `answerer_holds()` (code/library/prompts/answer_checks.dm) is the one `valid()` helper for the old `ask_flags`.
* **Batch 3: medical, security and employment records consoles.** The records window's per-button guard (drop a record the data core no longer holds; the employment console also leaves fingerprints) is an early `then()` on `TAG_UI`. The modal buttons of the window (`modal_open`, `modal_answer`, `modal_close`, the virus and field editors) are not window ops: they stay on the legacy named dispatch, and they no longer drop a stale record first (only the buttons do).
* **The notes editor** (`edit_notes`) is an op: a multi-line text question (`asks()`), refused with "You must log in first." for somebody not logged in (the old handler refused silently, after nothing), and an empty answer asks "Are you sure you want to delete the current record's notes?" with `open_request(/datum/prompt/yes_no/record_notes_delete)` that re-checks the operator is still next to the console. The old "Delete" button text is the standard Yes / No. `/datum/om/prompt/text/record_notes` and `.../confirm/record_notes_delete` are deleted; the editor on a console with no record open is refused instead of runtime.

### Hand-converted items, batch 2 (candles, contraband package, telecrystal, implant pad)

Pinned by `dq_hc_items_behaviour.dm` (green on the legacy code first) and the interim candle and contraband tests, which now drive the click instead of calling the old handlers.

* **Candles.** `wax` is tracked (`set_wax()`), the look is a `draw()` (`look_state()` per type: the candelabra overrides it) and no longer an `APPEARANCE_TEMPLATE`/`APPEARANCE_WATCH`. A lit lighter, match or candle clicked on a candle lights it through an op that passes the click on, as before.
* **Implant pad.** The window answers only a conscious actor (a requirement on every UI op, with the reason "You can't do that right now."); the `ui_act_allowed()` override is gone. An empty hand takes the case out of a pad that is carried anywhere on the actor (`carried()`), where the old check was a hand; a pad lying or inside another's bag is picked up as any item.
* **Contraband package, telecrystal.** Plain ops; a package whose release is refused stays whole (pinned).
* **Residue of this batch:** `code/game/objects/items/weapons/wiki_manuals.dm` (its parent `/obj/item/book` in code/modules/library declares a UI of its own), the stack family (`stacks/*`: `/obj/item/stack` is a hub for dozens of types and its `INTERACT_SELF` entry, UI and state convert as one step), and every `OM_FIELD` that feeds a `DECLARE_PERIODIC_WHILE` (the periodic declaration resolves its fields from the `OM_FIELD` registry, so the field and the periodic form convert together).
* **Batch 4: messaging monitor and cloning console.** The monitor's questions (find a server among several, the key and its replacement, a filter token) are asked from the handlers with `open_request()`, after the handler's own guards (authenticated, server up), as before: an `asks()` step runs before the effect, so it would have asked first. They are re-checked when the answer arrives with `request_usable()` (the console stands, the person is next to it or a silicon), which replaces `PROMPT_USABLE` (a window state that no player-less test could ever satisfy). The server pick lists the servers by name (a repeated name gets a number). A log or PDA reference from the window is looked up in the server's own list.
* **The window's text arguments** (`UI_ARG_TEXT`) are `schema_text(4096)`, not sanitised on the way in; the handlers that sanitise (`set_sender` and the other fake-message setters) sanitise once, not twice.
* **Cloning console:** the window's `view_rec` and `del_rec` modals are named by literal ids. `autoprocess` stays an `OM_FIELD`: `DECLARE_PERIODIC_WHILE` reads field declarations, so it moves with the periodic (`TRACKED` + `every()`), not before.

## hc-mobs silicon

Pinned by `code/modules/unit_tests/dq_hc_silicon_behaviour.dm` (written on the legacy code first, except where noted).

* **"Are you sure?" confirmations show Yes first.** The store-core and pAI wipe confirmations used `no_first = TRUE` (No on the left); `/datum/prompt/yes_no` has no button order, so Yes is first. The answer is unchanged.
* **A hud-less pAI can finish a download.** `refresh_software_status()` read `hud_used.other` and crashed for a pAI with no HUD (nobody playing it); it now skips the buttons.
* **Batch 5: arcade, mass driver and prison shuttle consoles, shuttle control, AI core.** The battle game's moves (`attack`, `heal`, `charge`) are ops: on the legacy forms they lived in the window guard (`ui_act_allowed()`), which only ran for a button that had a `UI_ACT` row, and none of the three had one, so the moves could never run. They work now (blocked while a move is under way, refused when the game is over). The claw machine window refreshes on its own through `ui_opening()` (`UI_AUTOUPDATE`); its PIN question is `open_request(/datum/prompt/number/claw_pin)`. The `OM_FIELD`s of the mass driver (`timing`), the prison shuttle (`in_flight`) and the AI restorer (`restoring`) stay: each is the field of a `DECLARE_PERIODIC_*`/`DECLARE_REPEAT` (a boot error when it is not an `OM_FIELD`), so it converts with its periodic.
* **Shuttle control and the AI core's questions** are `open_request()`s (the shuttle's authorization choice and emag launch, re-checked when the answer arrives that the card is still in the hands of whoever was asked, who can still act; the latejoin confirm of a new empty core; the admin's "which core" pick, re-checked for the admin rights). The core's `DECLARE_INTERACTIONS` (item use that passes the click on, `INTERACTION_HANDLED_PASS`) stays: the `passes()` part has no converter yet. The emag launch's buttons read the standard Yes / No instead of "Launch" / "Cancel".
