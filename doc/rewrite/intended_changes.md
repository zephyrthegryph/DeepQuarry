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

## hc-struct (structures, code/game/objects/structures)

Pinned by `code/modules/unit_tests/dq_hc_struct_behaviour.dm` (written on the legacy code first, except where noted).

* **Batch 1: hits, emags, windows, in-hand uses.** The hit reactions are hit hooks: a blast, blob or throw that took the hit over (tree, girder, inflatable, black box) is `extend(/datum/act/hit/<entry>, instead(then(...)))` answering TRUE; one that reacts and lets the hit land (alien resin on a throw, the janitorial cart's spill, the black box's lighter blast) answers `HOOK_DECLINE` from the same hook, as the old non-blocking reaction ran before the hit; a flag that survives a blast is torn from `on_notice(/datum/notice/hit/explosion)`.
* **The holoplant and the biowaste tank take the library's `emag()`.** The old effects returned no number, so the sequencer never used a charge up on either; the card now pays its one use like every other emag, and says the library's line. The holoplant is one-shot (a second sequencer is refused, "It is already subverted."); the tank stays repeatable. The holoplant still sets `emagged` (its look reads it).
* **The safe's and the underwear dresser's windows refuse a non-human with a message** ("You can't work the dial." / "You can't use that."); the old `ui_act_allowed()` dropped the button silently. The dresser's window still closes on its own for someone who cannot wear underwear (`CanUseTopic`, unchanged).
* **The dresser's underwear question** is an `open_request()` listing the items by name; it is re-checked when the answer arrives that the dresser stands, the person is next to it and can still wear underwear (the old window-state requirement could not be met by a player-less test, so the legacy answer is not pinned; `undies_wardrobe_change_asks_for_a_choice` was added with the conversion). The `tweak` button still asks through the gear tweak's own question flow (`ask_metadata`, not in this domain).
* **The safe's `retrieve` and the dresser's `tweak` take their ref through `arg("ref")` and `ui_ref()`:** the safe only hands back something it lists (`contents_of(src)`), as the old `UI_ARG_REF(..., "contents", ...)` checked against the data it sent.
* **The janitorial cart's window stows gear only once the cart has equipped something by hand or item once** (the equippable typecache is built on the first `equip_janicart_item()`): a legacy quirk, pinned by neither side and unchanged.
* **Rubber duckies, torn inflatables** are in-hand ops (`in_hand()`), one per duck type; ops run before the parent bike horn's legacy `INTERACT_SELF`, which still answers the plain horn.
* **Batch 2: the questions structures ask** are `open_request()`s (bonfire, grave marker, morgue and crematorium label, reflector angle, fastening a sign, the Tyr keypad, window tint button id, prisms and prism dial, the toilet crystal, trash pile hide / exit, ghost pods, critter holes, lost drone laws, raider mirror, medical stand, canvas, palette, painting admin pick). Each keeps its old re-checks (`ask_flags`, the tool still held, the pod still unused, a client still behind the ghost) as request fields or a `valid` proc; the typed prompt subtypes are deleted.
* **Yes / No buttons read the standard labels.** The custom button texts ("Take it!" / "Leave it.", "Exit" / "Stay", "Hide" / "Stay", "Squeek!" / "Nope!", "Proceed!" / "Cancel") and the "No first" order of the touch confirmation, the raider's Become Vox? question and the critter confirmation are gone: `/datum/prompt/yes_no` has neither.
* **A ghost pod is freed by any end of its question that is not a yes** (a closed window, a timeout, a failed re-check): the activation handler runs with no answer and clears `busy`; the old prompt freed it on a cancel only.
* **The reflector, underwear dresser and canvas-rename questions** no longer ask the tgui window state (`PROMPT_USABLE`: no player-less test could meet it). The reflector's is "the person is next to it and able, and its rotation is unlocked" when the answer arrives; the dresser's is the wardrobe's own `request_usable()` (next to it, can wear underwear); the canvas rename keeps `usable_state = "physical"`.
* **A finished painting refuses every window button with "The painting is finished."** (the old `ui_act_allowed()` dropped them silently). The canvas's `tgui_state()` override is unchanged.
* **The medical stand's two menu verbs are ops** (`toggle_iv_mode`, `set_iv_transfer`): the old "you can't do that" reason for a non-living actor reads "You can't do that." The stand's `DECLARE_INTERACTIONS` (an item handler that declines on anything but a tank or container) stays for the second pass.
* **Gravemarker carving:** the epitaph's carving starts a second tool use while the name's is still running and is refused by it, as before; only the name is carved. Pinned by `gravemarker_name_is_carved`, unchanged.
* **The painting admin pick** (`admin_lateload_painting`): the three `usr` reads are one `var/mob/admin = usr` (an annotated verb-context read); the questions re-check the admin's rights (`rights = R_HOLDER`) when the answer arrives.
* **Interim tests that built a legacy prompt by hand** (`interim_sign_refasten`, `interim_medical_stand_prompt_actor`) open and answer the request instead; the snapshot row of the biowaste tank (`dq_i7_structures_bulk_capture.dm`) no longer lists the legacy emag interaction.

## hc-tgui (datum-hosted windows: tgui modules, panels, programs)

Pinned by `code/modules/unit_tests/dq_hc_tgui_behaviour.dm` (written on the legacy code first).

* **A module's window is its type's `interface()`; the NTOS skin is added by `/datum/tgui_module/ui_interface()`** (`ntos = TRUE` gives `Ntos<Window>`), where `New()` used to rewrite `tgui_id`. A subtype that only changes the window's state keeps its `DECLARE_UI_STATE` row (the ratchet `tgui_state_override` wants it; `interface(null, state =)` would drop the window name).
* **A ref argument is resolved at the boundary.** `schema_ref()` now accepts the text a window sends (`locate(text)`, null when it names nothing) when the value comes from a player, so `arg("valve", schema_ref(/obj/...))` hands the handler the entity. The old `UI_ARG_REF(name, SOURCE, type)` searched SOURCE; where SOURCE was a whole registry of the type (fuel injectors, fusion cores, gyrotrons, cameras, mobs, shutoff valves) the type check is the same set, so the source procs are gone; where it was narrower (a console's own alarms, an AI's own laws) the handler still checks membership.
* **`ui_shape()` is a macro** (`code/__defines/engine/declare.dm`): the proc taking `...` rejected the documented `ui_shape(field = schema)` form at run time ("bad arg name"). A data-only window declares `ui_shape(...)`, since `analyze gen ui_types` refuses an `interface()` with neither a shape nor an op.
* **The NTOS header buttons** (`PC_exit`, `PC_shutdown`, `PC_minimize`) are three ops of `/datum/tgui_module` (one handler read `action` before).
* **A question a module button asks is an `open_request()`** whose answer is dropped unless the asker's window on the module is still open and interactive (`request_usable()`), as the old re-run dropped it; the `tgui_status(user, state) == STATUS_INTERACTIVE` re-checks inside handlers went with it. A text field's default is read when the question is asked.
* **`ui_act_allowed()` guards** of a module become requirements on its ops: `alarm_monitor` (an AI only, silent), `crew_monitor` (station levels, with the old refusal text; the typing sound plays on every accepted button, not on refused ones).
* **`crew_monitor` and `atmos_control` autoupdate** through `ui_opening()` (`UI_AUTOUPDATE` had no equivalent); `setZLevel` finds the viewer's window with `SStgui.get_open_ui()`.
* **A number prompt with `round_entry = FALSE`** is `step = 0.01` (the new kind rounds to whole numbers unless it has a step).
* **Batch 2: agent card, law manager, camera console, late join, admin shuttle controller.** The agent card's, law manager's and shuttle controller's questions are `open_request()`s answered through `request_usable()`; the law editor's text question is an `asks()` step on the `edit_law` op (its default is the law's text, and the op needs `ui_malf`, silently, as the old `if(is_malf())` did). Law and law-set refs are `arg()` plus `ui_ref(..., source, type)`: only the owner's own laws, or the listed law sets, resolve.
* **The shuttle controller's destination questions** also re-check `rights = R_ADMIN | R_EVENT | R_DEBUG` when the answer arrives (the old re-run only checked the window); the shuttle being moved is held in a declared view (`moving`) between the question and the answer, and the "Launching shuttle" line comes once an answer launched it.
* **The camera console's typing sound** is an early `then` on every window op (`ui_typed`), as the `ui_act_allowed()` guard played it; the lobby window's joining is gated silently on being a new player.
* **A window answer that is "no" to a confirmation** is a false answer to a `/datum/prompt/yes_no` (a legacy alert answered the text "No").
## hc-struct machinery (batches M1 to M3)

Pinned by `code/modules/unit_tests/dq_hc_machinery_behaviour.dm` (written on the legacy code first; `machinery_window_shapes` pins the keys of every machine window's data, captured from the legacy forms and still asserted for the windows not yet converted).

* **Windows.** A machine window is `interface()` plus one `op(ui_act())` per old `UI_ACT`, the data proc is `ui_data(datum/act/eval/A)`; the action names and the data keys are the old ones (TSX unchanged). A handler argument that the old body also read as a machine var of the same name is passed as `raw_<name>` (the converted procs never shadow a var). `UI_ARG_TEXT` is `schema_text(4096)`, not sanitised on the way in; `UI_ARG_NUM` stays `num()` (a window that sent text there already got null).
* **Guards of the old `ui_act_allowed()`** are requirements on every button (`extend(TAG_UI, needs(...))`) with a reason, where the old override dropped the press silently: the turrets' and the turret panel's lock (`lock_refusal()`, a pure read: "Controls locked." / the firewall line / "It can only be controlled using its assigned turret controller."), the fabricator being busy, the nuclear bomb's reach and the pressing person's state, the pipe dispenser's bolts, reach and state, the party button's power, the slipper's lock, the cryo cell's own occupant, the safe-like windows' human-only rule. The fingerprints the guards left are an early `then()` on every button.
* **Hits.** The EMP and projectile reactions of the fire alarm, the portable pump and scrubber, the turrets and the turret panel run before the hit lands and let it go on (`instead()` answering `HOOK_DECLINE`), as the old before-reactions did; the industrial turret's cut of an animal's blow is the same hook with an entry check.
* **Emags.** The turrets, the turret panel and the suit cycler take the library's `emag()`. The old gate read the legacy `emagged` bit (still set), the library's reads its own state: a turret that an EMP emagged can still take a sequencer, and the suit cycler's "The cycler has already been subverted." is the library's "It is already subverted.".
* **Questions** (floor layer, canister, turret frame name, requests console messages and department, machine frequency and text-var prompts) are `open_request()`s. `PROMPT_USABLE` is `answerer_holds(ANSWER_NEAR_SUBJECT | ANSWER_CAPABLE)` (canister) or the console's `request_usable()` (requests console: next to it, or a silicon); the floor layer's choices are the same lists as before (tile stacks by object, work modes by name).
* **Left on the legacy forms, and why.** The read-only windows (doppler array, chemical analyzer): `interface()` with no op and no `ui_shape()` fails `analyze gen --check` ("declares no ui_shape() and no ui_act() op"), the framework has to decide how a data-only window is declared. The air alarm (its window state is the air alarm's remote state: `controls_usable()` reads the `state` argument), the sleeper and its console (`UI_ACT_FORWARD`), petrification's questions (a chain of `/datum/om/flow`s), and every `INTERACT_*` entry that declines at run time (oxygen pump, cryo cell, body scanner, ...).
* **The shared "Tank" window.** `Tank.d.ts` now describes the oxygen pump's window only (the gas tank item still declares its own legacy table for the same window name, which the generator no longer merges); no TSX imports it.
* **Batch 3: communications console, overmap displays, NTOS card/email/UAV programs, player notes.** The communications window's login button works: the old `ui_act_allowed()` handled the `auth` action in its guard but no `UI_ACT` row named it, so the window's own dispatcher never reached it (pinned by `comms_login_button`, new with the op). The console's guards are requirements: near the station (`ui_in_contact`), then logged in on every button but `auth`, captain-only for announcements and the Central Command message, emagged captain for the Syndicate one, with the old refusal texts; the cooldown refusals are requirements too, so they are also re-checked when an answer arrives.
* **The communications questions are `asks()` steps:** announce, the Central Command and Syndicate messages (text), call and recall (yes or no), delete message (yes or no, the message is picked before it asks by an early `then` on the key), the two status lines. A cancelled question changes nothing and costs no cooldown. The Central Command and recall refusals no longer reset the menu to the main screen (they refuse before the op runs).
* **The email client's questions** (`edit_body`, the three password questions as steps `old`/`new1`/`new2`, the export file name, the attachment choice) are `asks()`; the two that need a working hard drive skip their question when it has none (`when = drive_ok`) and the handler says so as before. Every button press still checks for new mail (an early `then`). The card program's `Custom` assignment is a step that is skipped for the listed jobs. The overmap console's add/coordinate/limit questions are steps with `when`s (`add` asks a name, then x and y only for `new`).
* **A window guard that only looked at the viewer and host** (`cardmod`, the navigation display) is one silent requirement on every op of the type (`ui_gate`).

## hc-struct machinery (batches M4 and M5)

* **M4: hits, emags and event handlers of machines and tanks.** The EMP, blast, blob and projectile reactions of the operating table, atm retrieval field, bluespace denier, camera, cloning pod, deployable barrier, flasher, floor light, holoposter, igniter, mass driver, status display, suit storage, VR console, thermoregulator, portable atmospherics and fuel/cooking-oil tanks are hit hooks (`instead(then(...))`, answering `HOOK_DECLINE` where the old before-reaction let the hit go on). The cloning pod, deployable barrier (two stages) and gear dispenser take the library `emag()`; the gear dispenser's `custom` subtype declines. The old emag effects returned no number so a card never wore down; the library always pays one use.
* **M5: windows and questions.** Point defence control, pandemic, parts lathe, autolathe and bomb tester windows are `interface()` plus ops; the old `ui_act_allowed()` guards are requirements with reasons, and the parts lathe's fingerprint is an early `then`. The pandemic release reason and signature are `/datum/prompt` subtypes carrying the strain and the reason. The point defence retag is an `open_request()`. The bomb tester's modes are `BOMB_TESTER_MODE_*` in `code/__defines/machinery.dm` (the generated declaration file is compiled before the machine's own file); a tank to remove is looked up only among the two loaded tanks.
* **Snapshot rows.** The emag card is no longer an interaction row of the deployable barrier and gear dispenser.
* **Batch 4: admin windows (player effects, modify robot, edit player, newscaster).** Every window keeps its admin state as `interface(rights = ...)`. The player effects' per-action guard (`check_rights_for(R_SPAWN)` in `ui_act_allowed()`) is `req_rights(R_SPAWN)` on every button, so a refusal now tells the admin "you can't do that" where the old guard was silent (the guard no longer logs a refused press: each accepted effect is logged once by an early `then`, with the op key where the old line used the action name). The panels whose guard was "has a holder and a target" are one silent requirement; the guard relations (`holder`, `target`) are declared `ref_one()` views, which they already were by use.
* **Player effects' multi-question smites are `asks()` steps** (organs, chemicals, spin, teleport, AI mob, quest, NIF, wet floors, ...): each question that depended on an earlier answer has a `when` or a `computed` text. Two orderings differ: the lleill energy smite sets both values after both answers (the old one set the maximum before asking for the current value), and a smite whose target is not a human is refused before its first question. The item transformation's typepath question is a text step plus a choice step for several matches (`om_prompt_typepaths()`, now marked as reading nothing): the library has no typepath prompt yet. The shadekin kinds are a `GLOBAL_LIST_INIT`; terror writes `fear` through `set_fear()`.
* **Modify robot's confirm/rename upgrade questions and the law edit** are `open_request()`s answered through `request_usable()`, the shuttle-style chain, because their questions depend on the button's own argument (`pending_upgrade`, the `editing_law` view). `UI_ARG_PATH` is `schema_path()`; like `schema_ref()` it reads the text a window sends (`text2path`) at the boundary.
* **`window_request_usable(host, R)`** (`code/datums/sys/ui.dm`) is the shared `valid` check for a window host: the answerer's window on it is still open and interactive.

## hc-struct machinery (batch M6)

* **Read-only windows need no analyze change.** A data-only window is `interface("W")` plus `ui_shape(field = schema, ...)` (code/__defines/engine/declare.dm); the generator types it from that. The doppler array, chemical analyzer and cryopod console are converted that way. The doppler array's static data is now ordinary `ui_data` (`SStgui.update_uis(src)` replaces `update_static_data_for_all_viewers()`), so the window-shape test sees its `explosions` key.
* **Jukebox, colour painter, newscaster, suit storage unit.** Windows as in M1 to M5; the jukebox's tracks to play or remove are looked up only in its own track list; the suit storage unit's old `ui_act_allowed` is one silent requirement (`req(silent = TRUE)`). The jukebox emag takes the library `emag()` (the card is no longer an interaction row). The jukebox admin track-add flow (an `om_flow` of four questions) is a chain of `open_request()`s whose answers so far ride on the prompt subtype. The newscaster's five questions and the colour painter's colour question are requests re-checked with `answerer_holds()`; the newscaster's confirmations are plain Yes/No (the old buttons read Confirm/Cancel).
* **`DECLARE_UI_STATE` of converted windows** is `interface(state = nameof(GLOB.x))` (canister, portable pump, pandemic, space heater, suit cycler, suit storage unit, tank dispenser).
* **Hand-decline handlers.** The three types `interact_declare.py` accepts (atmospheric retention field, medical stand hand and item, fuel tank hand and item) are ops; their falsy returns are `OP_DECLINE`.

## hc-struct machinery (batch M7)

* **Atmospherics control consoles** (`atmo_control.dm`): the console family (general, large tank, supermatter core, fuel injection) converts as one unit: `interface()` on the parent, each subtype adds its own ops and extends `ui_data` with `data = ..()`. The six tank-command buttons share one handler that reads the op's key (`A.key`). The multitool menus are `open_request()`s with the multitool kept on the question (`ref_one`); the gas sensor's menu re-checks `can_see(answerer, sensor, 5)` as before. The generated `GeneralAtmoControl.d.ts` describes only the parent's shape (the window's TSX does not import it).
* **Telecommunications.** The multitool window of every node is `interface()` plus ops on the base type (the base's one `CAPABILITIES` block), with the relay, bus, broadcaster and receiver ops in their own blocks. The old `ui_act_allowed` (a fingerprint) is an early `then`. The four node questions re-check `canAccess()` on the answer; the bus's frequency question treats a cancel as "turn frequency changing off", as `cancelled()` did. The log browser, machine monitor and traffic console take the library `emag()`.
* **Questions.** About 30 `om_ask`s across `code/game/machinery` (cable layer, thermoregulator, meter, bioprinter, mob spawner button, cryopod consent, cutout painting, doorbell, Christmas sack, food replicator, gear dispenser, holopad, holoposter, magnet controller, mass driver, medical kiosk, pipe layer, protean reconstitutor, syndicate beacon, teleporter, transport pod, frames, wish granter, distillery, VR pods, camera assembly, circuit board) are `open_request()`s. `PROMPT_ADJACENT` is `ASK_ADJACENT | ASK_CAPABLE`, `PROMPT_USABLE` is `ASK_CAPABLE`, `inside_target` is `ASK_INSIDE`. A confirmation with custom button text (the bioprinter's "Print Limbs", the spawner's "Normal"/"Neutral", the beacon's offer) is a `buttons = TRUE` choice so the labels stay; a plain `Yes`/`No` confirmation loses its custom labels (the newscaster's "Confirm"/"Cancel").
* **VR pods and the camera assembly.** The avatar choice (location, creature) and the camera assembly's name and direction chains keep their answers so far on the prompt subtype.
* **Area atmos console** is an `interface()` window; its data proc still prunes lost scrubbers as it did.
* **Left on the legacy forms, and why.** `UI_ACT_FALLBACK` (the embedded controller base and every docking controller below it), `UI_ACT_OVERRIDE` (the telecrystal storage), `UI_ACT_FORWARD` (the sleeper), `rerun_ask`/`verb_ask` (the injector maker, cartridge spawn, reagent tank), the tgui modal system (`act_ask`: chem master, synthesizer, dispenser2, atmos filters), the air alarm and petrification (above), and the `REQ_*`-gated `INTERACT_*` entries that `interact_declare.py` rejects (`requires`, `body_uses`, `interaction_forms`, `interaction_kind` residue, 33 types).

## hc-struct (batch M8: new forms)

* **Codemods run over the domain.** `periodic_while.py` converted the bonfire and the fireplace (an `every(2 SECONDS, ..., when = nameof(burning))` with `burning` TRACKED); `appearance_draw.py` converted the cryopod console's look to `draw(look)`; `verb_decl.py` found nothing to do. The rest is residue the codemods name: 34 `MACHINE_PIPELINE` periodics (the machine track's, not `every()`), 83 appearance procs (side effects or writes to state in the proc), and the repeat/derived cases.
* **Oxygen pump.** The ungated hand (with its "no tank" requirement as a reasoned `req()`), the item handler and the "Show Tank Settings" menu entry are ops. The requirement reads whether the actor is incorporeal; `/mob/is_incorporeal()` carries the `ALLOW(reads)`.
* **Not convertible with what is on master**, so left on `DECLARE_INTERACTIONS`/`EXTEND_INTERACTIONS`: the cryo cell and the body scanner (`INTERACT_DRAG`: no drag input), the reagent dispensers (`INTERACT_ALT`), chairs (`INTERACT_TK`), bedsheets and the inflatables (`INTERACT_SELF`), the canvas (`INTERACT_ITEM_AS`, a stance), the palette (`INTERACTION_HANDLED_PASS`), the pillow family and the water cooler (an `EXTEND_INTERACTIONS` under a `DECLARE_INTERACTIONS` of its parent). Each needs its input form (`drag()`, alt-click, self-use, telekinesis, a stance binding) before the codemod or a hand conversion can express it.
* **Batch 5: pAI software and chassis windows, the robot windows.** The pAI mob's software window (`pAIInterface`) and its program windows convert together: the mob's `software` button opens the program's window with the mob's open window as `parent_ui` (`SStgui.get_open_ui()`), and the programs' window state stays the base type's `DECLARE_UI_STATE`. "Only a pAI works a program" was four copies of a `ui_act_allowed()`; it is one silent requirement on the `/datum/pai_software` base. The robot decal window's "a robot with a sprite" guard is a silent requirement. A pAI program's `software` argument is `software_id` in its handler (the parameter would hide the pAI's `software` list).
* **Batch 6: programs of a modular computer (`code/modules/modular_computers/file_system`).** Each program's window is its type's `interface("Ntos...")` (the `tgui_id` var is gone from the programs and the base); the base `/datum/computer_file/program` has the three NTOS header buttons as ops and one `request_usable()`. The word processor's and file manager's open file, and the word processor's unsaved flag, are `TRACKED` (a question's `when` reads them). The questions are `asks()` steps (new file, save as, edit, open with unsaved changes, the file manager's new file and edit with its "edit anyway" step, the news browser's save, the email administration's password and account steps, the network monitor's shutdown and NID questions, the digital warrant's four questions); the warrant's "ID with security access" check is one requirement (with its old text) on those four buttons, kept inside the handlers too. The file transfer's password question is an `open_request()` (the server's password decides whether to ask).
* **A question that the old handler refused before asking** is a requirement or a `when` (an unavailable network, a program with no account); the news browser's "nothing to save" check is in the handler now, so it asks for a file name first when there is no article (the button is not shown then).

## hc-items2: the stack family (`/obj/item/stack`, its subtypes, the sheets, rods, cable coils)

Pinned by `code/modules/unit_tests/dq_hc_items2_stacks.dm` (written on the legacy forms first).

* **`amount` is tracked.** The one writer is `set_amount()` (with `no_limits = TRUE` where the old code wrote the var directly: `use()`, `add()`, a built stack, a planted flag, a kiosk's one pack, the mint, the RMS); a subtype that derived something from the amount in its appearance proc (sandbag slowdown, cable name, processed-alloy export value) now does it in an override of `set_amount()`.
* **The look of a pile is `look_state()`** (`/obj/item/stack/draw()` reads it); subtypes override that proc instead of declaring an appearance proc. The in-hand sprite name of a stack with variants (`item_state`) is set once at creation instead of on every redraw (it never changed).
* **The recipe window opens through `interface("MaterialStack", input = in_hand())`**; the types that never opened it (`custom_handling = TRUE`: marker beacons, empty sandbags, telecrystals, flags, trail lights, sheets, maintenance panels, a cyborg's cable coil) say `without("ui_open")`, which replaces the `custom_handling` var.
* **Combining and splitting** are ops: a stack held against another pours into it (the old handler; `passes()`), a gripper consolidates, an empty hand on a stack held in the other hand asks how many to split off (declines to the pickup otherwise). A stack clicked with itself in the hand is the in-hand use, not a combine. The split question is `step = 0.01`, as every `round_entry = FALSE` question is.
* **Marker beacons:** "Place" refuses with the old two reasons as message types; the colour questions are `open_request()`s over a plain list of the colour names plus "Random" (a placed beacon turns "Random" into a colour at once, where it used to pick one at its next redraw). A placed beacon with no colour picks one when it enters the world. The alt-click needs the actor capable (the hand binding's own rule) in place of the old `dq_marker_beacon_can_recolor()`.
* **Supermatter:** its split is the stack's `split_asked()` plus the scorch; the pick-up stays a legacy entry.
* **Not converted here:** the timed actions of the family (`om_task_*`: recipe builds, wound treatment, flag and trail light planting, log cutting, hide scraping) stay as they are; they are the jobs track.
* **Batch 7: the appearance changer.** The half-second "too fast" guard is a requirement (with its text) plus an early `then` that starts the cooldown; a button refused that way no longer re-arms it. The colour questions are `open_request()`s of `/datum/prompt/color/appearance` (a colour kind that carries which field, channel and marking it answers); the answer is re-checked through `request_usable()` and refreshes the window when it changed something. The questions that depend on the button's argument (the custom species name, the flavor text) are `open_request()`s too, the flavor key held in `pending_flavor_key`. The body designer's save to disk asks the permission question through a request, then writes (`write_record`); loading a save slot asks the body's owner, as before. A number question without rounding (`weight`) is `step = 0.01`.
* **Every continuation proc that ends with a window refresh and returns early is split** (`X` applies and refreshes; `X_apply` is the old body), so the refresh no longer sits after a `return` (the codemod's template put it there in batches 3 to 7).
* **`interim_appearance_callback_actor` now calls `apply_color()` and the `gender_id` op** (the handlers it called by their old signatures are ops).

## hc-items2 group B (weapons, tools, lighters, flashlights, melee, shields, grenades, defibs, bags, small items)

Pinned by `code/modules/unit_tests/dq_hc_items2_B.dm` (written on the legacy forms first; the periodic steps were called directly there, since the legacy lane is not driven by the test clock, and the converted tests add the same checks through the clock).

### Batch 1: matches, lighters, smokables, e-cigs, candles, chewables, ashtrays

* **One handler per use, overridden by the kind.** The self-use of a lighter (`toggled`), the item applied to a smokable (`item_applied`), the e-cig and chewable uses are one op on the base type whose handler the subtypes override (the old interaction chain kept only the most specific entry, so the ancestors' entries were reached through explicit calls). A use that fell through to the clothing's own self-use (`return FALSE`) answers `OP_DECLINE`.
* **`hand()` ops say `when(req_empty_hand())`.** The binding itself also matches a click with something held; the old `INTERACT_HAND` fitted only an empty hand (the e-cig's "Eject cartridge").
* **Stances.** The four `INTERACT_SELF_AS` rows of the cigarette and the pipe are two ops: the calm stances put the lit smokable out, the hurt stance (`stance(I_HURT)`, attack tier) treads it out or empties it.
* **Flames burn through one `every(2 SECONDS, ..., when = nameof(lit))`** on `/obj/item/flame`; each kind overrides `flame_step`. The supermatter lighters' own steps were copies of the lighter's and are gone. An everburning candle no longer leaves the lane (an `every()` cannot end its own work): its step does nothing, so it costs one idle timer while lit. The detonator zippo burns only outside detonator mode, as a step that returns early.
* **A smokable's look is a `draw()`** (`state_suffix()`: `_on` while lit, `_burnt` once partly smoked unless a pipe). `lit`, `smoketime` and `max_smoketime` are tracked; the in-hand and worn state (`item_state`, which a look cannot write) follows `lit` and `smoketime` in their setters. An emptied smokable that leaves no butt (a joint) now shows its `_burnt` state as soon as it is emptied; it kept the new-looking state until the next redraw.
* **The e-cig's look** draws its own on, off and empty states and its light; its `item_state` follows `active` and the cartridge (`on_change`).
* **Ashtray:** the look reads a tracked `butts` count (`sync_butts()` after anything puts butts in or takes them out, including the disposal unit that empties it) and a tracked dish overlay made once at creation; the "full" and "half-filled" descriptions are written when the count changes instead of on every redraw. The ashtray's item op answers before the material's repair op (`priority(above())`) and ends the click, as its old handler did (it never called its parent).
* **Chewables:** `wrapped` is tracked and the wrapper overlay is a `draw()`.

## APC: the last legacy forms (outages, notices, night shift, area link) and the final emp_disable()

Pinned by `code/modules/unit_tests/dq_p2_apc_behaviour.dm` (the outage, overload, signaller, silicon and night-shift tests were added and run green on the
legacy tree first) and `code/modules/unit_tests/dq_emp_disable_behaviour.dm` (three users of the legacy `emp_disable()`, also green on the legacy tree).

* **An outage is a hold on operability.** A pulse (`emp_disable()`, source `SRC_EMP`) and an event's power failure (`energy_fail()`, the electrical fault
  and the supermatter shutdown, source `SRC_POWER_FAILURE`) hold `STAT_OPERABLE` off for their time; the `power_failed` stat is gone. While it lasts the
  ID lock, the emag and opening the window are refused like on a broken APC ("It isn't working."). On master the area went dark during an outage, which set
  the APC's NOPOWER bit and refused the same things in any area that needs power; the difference shows only in an area that needs none.
* **The APC's own area going dark no longer makes it inoperable.** It is the area's supply: its `stat_bits_allow()` reads only BROKEN (its unfinished
  frame is the build graph's, its outages are holds). On master the breaker off darkened the area, set NOPOWER on the APC and refused the ID lock until
  the breaker was on again.
* **A broken APC keeps its area dark** even if a silicon turns its breaker back on (the area reads `supplying`, which a broken APC is not). On master the
  breaker alone decided once the APC was broken.
* **The night shift reaches every APC on "automatic" at once and keeps reaching it.** The system sets one tracked flag; an APC built, or switched back to
  automatic, during the night dims its area straight away (on master it waited for the next dusk or dawn walk). The night-shift step no longer walks the
  APCs across ticks.
* **The station power-failure event, its restore and the supermatter cascade set the APC cells for real** (`set_cell_charge()`: the cell and Rust's charge
  together). On master they wrote the cell and the next power poll put Rust's charge back.
* **emp_disable() users** (PDA multicaster, exonet node, telecomms, research server, port generator, atmospheric field generator, GPS, vehicles): the outage
  is the same length and a pulse while down still does not lengthen it; it now runs on the holder's own clock instead of the world clock, so a holder
  whose clock is slowed recovers on its own time. The EMPED bit is no longer set by it (a vehicle still sets its own); the legacy `operable()` reader sees
  the hold. A GPS and a vehicle declare `operable` beside their types.
* **The fault lights of the APC's examine text** are an `examine_line()`, so they come after the capabilities' lines instead of before them.

## Physical paths: spaces and doors (APC, airlock, lockers, vending, every hatch)

Pinned by `code/modules/unit_tests/dq_paths_behaviour.dm` (16.1a cases 1 to 5, the APC hatch's reasons, the airlock's wires behind its panel, a
locker's door; written and green on the old gates first) and the existing APC, door, closet and vending behaviour suites.

* **A click behind a closed door that nothing else answers is refused with the door's reason** instead of doing nothing. The old gates were
  `when(PANEL_OPEN)` / `when(nameof(panel_open))` / `when(nameof(opened))` (silent: the click fell through to nothing). Examples: a multitool or
  wirecutters on an airlock or vending machine with its panel shut says "The maintenance panel is closed."; cable, wirecutters, a welder, a coil
  or a multitool on an SMES with its access hatch shut says "You need to open the access hatch first." (its weld already said so); an empty hand on a filled
  grave says "It is closed.". Where another op answers the click (an empty hand on a closed APC opens its window) the blocked op stays silent, as
  before, and a catch-all behind a closed door (`item(/obj/item)`: a locker's "put down", an SMES's swallow) stays silent too, so a held thing
  still does what it does by itself (package wrap on a shut locker). Menus leave out ops behind a closed door, as the old `when()` did.
* **The panel latch replaces a two-way rule.** `panel_needs_cover_closed` was an `extend("panel.open", needs(cover closed))` that also kept an open
  panel from being closed while the cover was open. As a latch it only keeps a shut panel shut; an open panel can always be closed.
* **Generated slot refusals.** A device cell on an APC says "That is too small to fit." (was "That power cell is too small to work here."), a
  too-large one "That is too large to fit."; a new cover on a broken APC with its cell in says "Remove the <cell name> first." (was "Remove the
  power cell first."). What is refused, and when, is unchanged.
* **A new APC cover on an APC that isn't broken is silent** (the replace step is offered only on a broken cover) instead of "It isn't broken.";
  the frame in hand falls through to whatever else it means.
* **Library defaults for locks and emags.** `lock()` now needs a working (`req_operable()`), unsubverted (`req_not_subverted()`) holder and
  `emag()` a working one, unless configured off. New for: secure closets and lockboxes (an unsubverted check only: they have no power), and an
  emag on an unpowered or broken machine that had no such gate (portable turrets, turret controls, jukeboxes, gear dispensers, suit cyclers,
  cloning pods, deployable barriers, telecomms consoles, vending machines, door controls, light replacers): it is refused with "It isn't working."
  A one-shot emag is refused on a holder subverted any other way too (an AI hack: `is_subverted()`), not only on one already emagged.
* **Menus leave out every op behind a closed door**, as they left out the `when()`-gated ones: the APC's welder dismantle step no longer shows,
  greyed, in the menu of a closed APC (`dx_menu_order_golden.dm` updated for that one scenario).


## Wires: the wires library replaces /datum/wires

Pinned by `code/modules/unit_tests/dq_wires_behaviour.dm` (written and green on the legacy code first; only its adapter block changed in the
conversion), with the holder tests that already drove wires (dq_p2_apc, dq_p2_door, dq_p2_vending, dq_p2_smes, interim_*_wire_*).

* **A signaler on a wire works again.** `/obj/item/assembly/signaler` read the atom's `wires` var (the holder's legacy wire datum, null on a signaler)
  where it meant its own `wires_type` flags, so an attached signaler never pulsed its wire, and no signaler took a radio signal at all
  (`receive_signal()` refused every one). Both read `wires_type` now. Fixed on the legacy code first, so the tests pin the working behaviour.
* **An electropack no longer reads a wires flag before signalling its master.** `receive_signal()` tested `wires & 1`, the radio's legacy wire
  datum ANDed with a number: a runtime whenever a master was set, so the master never heard it. The dead branch is gone with the datum.


## Wires composed from capabilities (no wire sets)

Pinned by the same tests (`dq_wires_behaviour.dm`, `dq_wires_tests.dm`, dq_p2_apc, dq_p2_door, dq_p2_vending, dq_p2_smes, interim_*_wire_*), unchanged
but for the fixtures that declared a `/datum/wire_set` (the unit-test holder and the p2 box now declare `wires(name =, count =)` and the
capabilities that bring their two wires) and the p2 library assertion that named the set type (it reads the wiring's name now). Two tests are new:
`dq_wires_capability_brings_its_wire` and `dq_wires_shared_wire_shares_its_effect`. Every holder keeps its wire count, its set of working wires and
its randomize behaviour; the round's shared colour layout is keyed by the wiring's name (one per former set, the names did not collide).

* **A pulse is a keyed timed hold; a cut wire outlives it.** The AI control, power, hack, disable and shock pulses hold a stat from the wire's own
  pulse source for the pulse's length. A second pulse refreshes the one hold (it used to stack unkeyed timers, or be ignored while the first ran),
  and a pulse running out no longer undoes a cut made meanwhile. Fixed: the airlock's AI-control pulse (an unkeyed one-second timer that restored
  control even with the wire cut), the air alarm's ten-second AI pulse (the same), the autolathe's three five-second pulses (unkeyed timers; a
  second pulse inside five seconds flipped the state back), the APC's short and AI-disable pulses (ignored while one ran, now refreshed).
* **A pulse sets, it no longer flips, where it is timed.** The autolathe's and the protolathe's hack, disable and shock pulses flipped the state for
  five seconds; they hold it on for five seconds. The R&D machines' untimed pulses still flip.
* **Mending releases the pulse too.** Mending a wire releases what that wire's pulse held (a pulse then a cut then a mend leaves the stat at rest),
  as each holder's mend already did by writing the resting value.
* **APC power wires.** Mending a power wire shocks the hand only when the APC's power comes back (both wires whole), as before; a pulse on one wire
  after mending the other is its own hold, so mending wire 1 does not end wire 2's pulse.
* **The airlock's AI-control states are a stat.** `aiControlDisabled` is a boolean stat (the AI locked out); the unreachable -1/2 "AI bypassed
  the lock" states are gone (nothing set them). The hostile runtime and electrified-door events hold it from `SRC_ROUND_EVENT`.
* **The airlock's ID scanner and safeties are stats.** `aiDisabledIdScanner` (ANY) and `safe` (ALL): the AI's toggles hold and release from
  `SRC_AI_CONTROL` (turning the safeties back on also ends a wire pulse's hold, as setting the var did), the turbolift's fire mode holds the
  safeties off from the lift and lets go after, and the door-crush airlock failure holds them off for good (`SRC_ROUND_EVENT`).
* **Wire-held state is a stat.** `aidisabled` and `shorted` (APC, air alarm), `ai_control_disabled` and `input_cut` (shield generator), `scan_id`
  and `shoot_inventory` (vendor, smartfridge), `safeties` (suit cycler), `hacked`, `disabled` (autolathe, R&D machines) and `shocked`
  (autolathe). The brand intelligence event's `set_shoot_inventory()` holds the vendor's throw from `SRC_ROUND_EVENT`; the suit cycler's emag
  holds its safeties off for good. Electrification countdowns (`seconds_electrified`, the suit cycler's `electrified`) stay countdowns the
  machine runs down a frame at a time, set by `shock_wire(counter =)`.
* **A mapped hacked autolathe.** The 17 map edits `hacked = 1` on autolathes (and the ammolathe's own default) are `hacked_at_start = 1`: the hack
  wire starts cut and holds `hacked`, so mending it unhacks the lathe as before. A protolathe or circuit imprinter no longer reads a starting
  `hacked` (nothing set it).
* **The blueprints' wire legend** is keyed by the wiring's name, not a set type; its links are URL-encoded.


## fw-gaps3 (input kinds)

* **Telekinesis is a provider, and it does any hand op in sight.** `/mob` declares `telekinetic_reach()`: `provides(AFF_MANIPULATE | AFF_TELEKINESIS, reach = TK_RANGE, line_of_sight = TRUE)` while the mob is `tk_ready()` (a TK mutation or powered kinesis gloves,
  not through a remote view). The old reach was the types that declared an `INTERACT_TK` (structures refused a plain grab); under the design a telekinetic actor presses a button or opens a door it sees within 15 tiles through any `hand()` op, compartments and requirements
  still applying. An `INTERACT_TK` entry becomes a `tk()` op: the hand touch for a target no hand reaches, one tier above the hand ops, so at range it is what a telekinetic actor does. Unconverted legacy types keep the telekinesis adapter's own click (`tk_grab`).
* **An alt-click op is `hand()` + `gesture(GESTURE_ALT)` + `ungated()`**: the actor half of the hand gate (unconscious or stunned actors are refused) is new for `INTERACT_ALT`, which had `REQ_INTERACTION_REACH` only; the machine half is not applied, as before.
* **A dragged-onto op needs the actor to have an `AFF_MANIPULATE` provider** (`item(T)` does): the old `INTERACT_DRAG` asked for reach only, so a handless mob could drag a body into a cryo cell; it cannot now (design section 8: a hand op needs a hand).
* **`INTERACTION_HANDLED_PASS` is `OP_PASS`**, per return; behaviour is the same (the op commits, the next candidate or the mob's own click handling follows).

### fw-gaps3 content: cryo cell, body scanner, reagent tanks, bedsheets, linen bin, inflatables

Pinned by `code/modules/unit_tests/dq_fwg3_inputs.dm` (run on the legacy interactions first, through the player's own drag and click paths).

* **`item(T)` no longer answers an item used on itself.** The binding matched a self-use (held == target), so an item with both an `in_hand()` and an `item(/obj/item)` op could run the item op on itself: a pillow used in the hand
  built a pillow pile out of itself. A self-use reaches only `in_hand()` ops, as the old `attackby` never ran on itself.
* **Cryo cell.** The hand, item, drag ("Put inside") and the two menu entries are ops. With the panel open the hand is refused with "Close the maintenance panel first." (it said "Use: close the maintenance panel first.").
* **Body scanner.** The grab and the drag are ops whose refusals are requirements (`insert_allowed`/`drag_allowed`, the old `can_insert_grabbed`/`can_drag_inside`); the reasons are sentences ("It's already occupied.") where they were fragments after the interaction's name.
  A drag only matches a human (`item(/mob/living/carbon/human)`): another mob dragged onto it goes on to the legacy drag handling, which ignored it before as well. Whether it is occupied is read through `occupant_in()`, which follows `OCCUPANT_KEY`
  (every occupant slot publishes it when someone gets in or out). The console keeps its legacy entries (its observer view has no op form here).
* **Reagent tanks.** Alt-click is the alt-click op (an unconscious or stunned actor no longer toggles the input). "Set transfer amount" is a menu op with an `asks()` step: an answer that is not one of the amounts asks again, and the entry is
  hidden (`when()`) on a tank with no amounts. The tank's pass-through item use is the type's default (`OP_PRIORITY_DEFAULT`), so a kind's own item op (the fuel tank's rigging, the water tank's) answers first; the water cooler's item use replaces it.
* **Bedsheets.** Laying a sheet out is the `lay_out` op; a pillow re-declares `lay_out` and `use_item`, so the sheet's own layering never runs for a pillow (it did through the `special_handling` chain, which is gone). The exercise mat's item use passes, as before.
* **Linen bin.** The hand, item and telekinesis ("Take sheet") are ops; a telekinetic actor pulls a sheet out onto the bin's tile from range.
* **Inflatables.** Inflating is the `inflate` op (a torn one re-declares it). The wall's hand, item and "Deflate" are ops; ctrl-click and the menu share `deflate_by()`. The door re-declares the hand and drops the item use (`without("use_item")`), as its old list did; its silicon "Open" stays a legacy entry until silicon entry points are ops.
### fw-gaps3 content: window routing (embedded controllers, telecrystal storage, sleeper, air alarm, atmospherics filters)

Pinned by `code/modules/unit_tests/dq_fwg3_windows.dm` (buttons through `hc_ui()`, run on the legacy declarations first; the questions of the air alarm, the sleeper and the omni filter could not be answered through the legacy harness, so they are pinned on the converted forms only).

* **Embedded controllers (airlocks, docking ports, escape pods).** The program's commands are the window's fallback, `op("program_command", ui_act("*"), needs(req(command_listed, silent)))`: a listed command reaches the program, any other does nothing, as before. **Fix:** an airlock controller's commands (cycle, force, abort, override) work with its maintenance panel shut again. The declared-UI migration had moved the panel check of the old `tgui_act()` into `ui_act_allowed()`, which gated every action; the panel now guards only the tag and frequency settings (`at(SPACE_PANEL)`, a declared space whose door is `panel_open`), which refuse with the panel's reason instead of silently. The tag question is an `asks()` step (its default the current tag).
* **Telecrystal storage and every smart fridge.** "Release" is one op: with no amount it asks how many (`asks(..., when =)`), then vends. A secure fridge that does not work ignores the buttons (a silent requirement). The telecrystal storage's override runs the fridge's own release first and releases crystals only when that refuses, as before; its own number question is gone (the op's question is asked once).
* **Sleeper and console.** The console's window forwards every button to its sleeper (`interface(..., forwards = nameof(sleeper))`) and shows the sleeper's data. An open panel refuses the sleeper's buttons with "Close the maintenance panel first." (a requirement, `req_closed(SPACE_PANEL)`); an occupant without inside controls is ignored silently. The stasis question is an `asks()` step. **Fix:** the "chemical" button takes the reagent id as text (`UI_ARG_NUM("chemid")` refused every id the window sends).
* **Air alarm.** Every lockable control is behind a silent requirement (`controls_usable_by()`, which reads the actor's open window's state so a remote console still bypasses the lock); `aidisabled` is tracked. The thermostat and threshold questions are unchanged `open_request()`s.
* **Atmospherics filters.** The omni filter's flow-rate and filter questions are `asks()` steps behind a silent requirement (configuring, with the filter off); `configuring` is tracked. The trinary filter's three buttons are ops.
* **Rubber duckies.** Each duck's squeeze re-declares the horn's `honk` op (the two in-hand ops clashed at boot since the horn was converted).

### fw-gaps3 content: modals as in-window questions (chem master, chemical synthesizer, chemical dispenser)

Pinned by `code/modules/unit_tests/dq_fwg3_modals.dm` (modals opened and answered as the client does, run on the legacy `ui_modal_opened()` /
`ui_modal_answered()` first; the two flows whose legacy answer re-ran `tgui_act()` through an open window, the buffer's custom amounts and the chained
"make several" modals, could not be driven there and are pinned on the converted form).

* **Chem master.** Every modal is an op bound to `"modal:<id>"` whose question is asked inline; the guards that kept a modal from opening (no beaker, an
  empty buffer, a condiment master asked for pills) are silent requirements. "Make several" (pills, patches, bottles) is one op with two steps, the
  count then the name (shown under the single-item modal's id); a count below one asks again instead of closing (it was dropped silently). The style
  modals answer the picked sprite, whose index is the style. The custom buffer amounts reach the add and remove buttons' own handlers directly (they
  re-entered `tgui_act()`, which needs the open window). A cyborg standing next to it now gets an ejected beaker or pill bottle put in its gripper,
  if it can hold it (`!issilicon()` became "not through a remote link"); the AI never does.
* **Chemical synthesizer.** The three style modals are inline steps; the clear-queue, stall and remove-recipe confirmations are `asks()` steps (stall
  asks only while running, remove only while idle).
* **Chemical dispenser.** Its buttons are ops behind a silent "not broken" requirement; clearing the recipes asks first, and saving a recording asks
  for its name and then, only when that name is taken, whether to overwrite (the old window-interactive check between the two is the op's recheck).
* **Medical, security and employment records consoles.** The field edit modal is one op with two `asks()` steps, a pick when the field has choices and
  a text otherwise (`when =` the field's kind); a field the console does not edit opens nothing. The comment modal is a text step. Pinned on the converted
  form (`dq_hc_computers/fwg3_record_modals`).
* **Cloning console.** Deleting a record asks in the window ("Delete" / "Cancel"); only "Delete" deletes (the old boolean modal reached the delete
  handler on either answer, which then needed the ID in hand). The ID check is unchanged.
* **Yes/no labels.** The trash-eating PDA confirmation ("Definitely" / "Cancel") is an `open_request()` of `/datum/prompt/yes_no` with its labels.

### fw-gaps3 content: questions that re-asked themselves (bookcase, ladder, chameleon stamp, alien coil, paper bin, trolley tank, gas pumps, ATM, artifact harvester, shield generator)

The types the asks() codemod left because the question was not first in its handler (it stood after a guard, or inside an `if` or a `switch` case).
Pinned by `code/modules/unit_tests/dq_fwg3_asks.dm` (the item and hand questions, run on the legacy re-run first) and `dq_fwg3_windows.dm` (the
window questions, on the converted form: a legacy `act_ask` re-run needs the open window).

* **A question asked only in one case is an `asks()` step with `when =`**: the bookcase asks which book only when it has some, the paper bin which paper
  only with no custom paper on top, a gas pump the value only for "set", the ATM the PIN only when lowering the level without the account's card in, the
  artifact harvester only for a charged battery, the shield generator its range and input cap only while the modes are unlocked and its shutdowns only
  while it runs. The guard the old handler ran before the question still runs in the handler, after the answer.
* **Held-kind branches are ops of their own**: a book on a bookcase and a pen on it are two ops (`item(/obj/item/book)`, `item(/obj/item/pen)`); a
  trolley tank's beaker, multitool and pen likewise. **Fix:** the trolley tank's multitool repaint works again (the vehicle's generic item use, an op,
  answered the multitool first and hit the tank since the vehicles were converted); its three uses sit one tier above it.
* **Paper bin:** an unusable hand is a requirement with the old message. **Alien coil:** its touch re-declares the stack's `split` and asks with a
  request, as the stack does. **Chameleon stamp:** the disguise question lists "EXIT" first, as before.
* Not converted here (their `rerun_ask`/`act_ask` sites are held back by other residue, `codemod_rules.md`): the book (its in-hand ops on six
  subtypes would need re-keying together), the craftable collar (its parent collar is legacy), the camera bug, and the client and admin datums
  (preferences, songs, tickets, the event kit's mob spawner).

## Silicon entry points (phase A): remote() ops, the interface provider, the gripper as a provider

Pinned by `code/modules/unit_tests/dq_silicon_entry_tests.dm` (16 tests, green on the legacy hooks first; the converted code passes the same tests, one
of them strengthened as noted below). The shared hooks (`silicon_inspect`/`_pull`/`_alternate`/`_swap_hands`/`_quick`, `is_ai_remote_interface`,
`remote_interface_blocked`, the gripper's `handle_afterattack_special`, the airlock's `silicon_or_ghost`) are gone; the `silicon_entry` lint bans them.

* **A silicon's shift-, ctrl-, alt- and middle-click on a machine is an op** with a `remote()` binding pinned to that gesture (airlock `remote_open`,
  `remote_bolts`, `remote_shock`, `remote_lights`; APC `remote_breaker`; turret control `remote_power`, `remote_lethal`; intercom `remote_microphone`,
  `remote_channel`; appliance `remote_power`; light `remote_flicker`). A player's shift-, ctrl- and middle-click now go through the op resolver first
  (`op_gesture_of_params()`); a gesture no op pins falls through to the legacy click exactly as before. Ctrl and middle have no intent of their own: only
  an op that pins them answers them.
* **The gesture ops ask the same requirements as the window's buttons.** An AI with the airlock's AI-control wire cut can no longer alt-click it
  electrified or middle-click its bolt lights (only bolting and opening were refused before). The APC's ctrl-click asks the window's rules (its AI-control
  wire, the hacker), and the turret control's asks its firewall; neither did before.
* **The link is a provider that comes and goes** (`remote_interface()`, library/mob/silicon.dm): an AI that is not conscious or whose wireless is off, a
  cyborg that cannot act, has a working restraining bolt or looks through a camera has no interface, so no remote() op is a candidate. Before, the bolt
  blocked only the airlock, APC and turret control hooks, and an AI with wireless off still reached remote() ops through the op path. A bolted cyborg's
  shift-click on an airlock now examines it (it did nothing).
* **Whose link a machine lets in is `remote_link_allowed()`** (input over AUTH_REMOTE_ACCESS; an AI is trusted, a cyborg shows its ID card). It replaces
  `siliconaccess()` in the APC's lock and overload, the lock library's exemption and the airlock's window. **A pAI is no longer counted as a silicon by
  these** (it has no interface; it reaches doors through its cable). The APC's "remote user" branch and the turret control's firewall read the input's
  authority, not the mob type.
* **A cyborg's selected gripper is a provider and is preferred over its chassis manipulators** (`held_carrier()`): what it takes goes into the
  gripper (`op_deliver()`, `carry()`), and what it carries is A.held. The cell charger and the recharger
  lose their `isrobot()` branch: a cyborg's gripper takes the charging item into a pocket, and a cyborg without one sets it down on its own tile (both were set down on the charger's tile); the chargers' pins
  give their cyborg a gripper.
* **The gripper carries a cell in and out of an APC through the APC's own ops** (`cell_bay.cell.take`/`.insert`). On master the APC's take op had
  already overtaken the gripper's special case and dropped the cell on the cyborg's tile; the pin now asserts the gripper holds it and puts it back.
* **A cyborg's cell comes out through an op** (`take_power_part` on the cyborg: a person's hand or another cyborg's gripper), replacing the hand
  interaction's cell branch and the gripper's cyborg case. A gripper that cannot hold the cell lets it drop instead of refusing.
* **The airlock's remote-control window opens only through remote()** (it had a hand binding hidden by a silicon-or-ghost condition).

## Construction slots and the wall frames

Pinned by `code/modules/unit_tests/dq_wall_frame_behaviour.dm` (green on the legacy try_build() first), the APC ladder tests of
`dq_p2_apc_behaviour.dm` and the e0 door assembly proof.

* **An APC frame held to a wall builds the APC on the wall.** `try_build()` called `replace_with()` on the frame while it was still in the
  builder's hand, and `replace_with()` hands the successor the original's slot: the new APC frame went into the builder's hand. The frame is
  dropped first now (fixed on the legacy code with the tests).
* **The APC's board goes into the build graph's own slot.** The `apc_construction` slot relation is gone: the ledger makes a slot from the
  graph's `put_in(SLOT_CONSTRUCTION)` (one board, in the graph's space SPACE_HATCH, so the board sits behind the cover like the rest of the
  ladder). A `slot(SLOT_X, capacity =, at =, accepts =)` entry declares any other such slot (the e0 door assembly's).
* **Mounting a frame is the frame's op, `frame.mount`** (`at_target()` a wall or an anchored window): the wall's and the window's item use no
  longer call the frame. Its refusals are requirements with the old texts (the generic frame says "It cannot be placed on this spot." /
  "...in this area." where it named itself), a diagonal or distant builder is refused silently as before, and an APC frame cuts a loose
  terminal under it as part of the mount. `try_build()` is gone.

## SMES, the RCON console and the power-failure event (rewrite/machines-full)

Pinned by `code/modules/unit_tests/dq_p2_smes_behaviour.dm` and the review findings in `code/modules/unit_tests/dq_mf_smes_behaviour.dm` (written and
green on the legacy code first; only adapters changed, except the findings below, each edited in the commit that changes it).

* **The unit shows what really flows.** Rust now reports each SMES's per-step flows (`Smes.output_used`, `input_used`, `input_available`, zeroed by
  the new `SmesFlowReset` law), and `power_poll()` reads them: the input lamp and the window's `inputting` are 0 off, 1 trying with nothing to
  take, 2 charging; `outputting` is 0 off, 1 offering with nothing drawn, 2 feeding a load; `inputAvailable` and `outputUsed` are the readings
  (they were a hardcoded 0, and `inputting`/`outputting` never reached 2, so the hum and the `smes-oc` overlays never showed).
* **The hum follows the output lamp** (`on_change(outputting)`): a unit that feeds a load hums; it was silent whatever flowed.
* **Building a terminal no longer repairs a broken unit.** The legacy `set_stat(0)` after the cable went in cleared every stat bit (BROKEN, EMPED,
  NOPOWER). A unit placed with no input terminal is now *unwired* (a tracked fact that holds STAT_OPERABLE down and darkens the overlays), not
  broken: it has no "It is broken." examine line, and a terminal built for it wires it.
* **The grid checker reaches the SMES.** Its failure calls `do_grid_check()` on the units upstream, which had no override, so a grid check never
  suspended a SMES; it now sets `grid_check` until the checker ends the failure.
* **A coil is counted once it is in** (the counter went up before the move into the parts, so a refused move left one coil too many). A full
  unit refuses a coil with "You can't insert more coils" as a refusal, before anything happens.
* **Refusals are requirements, asked again after a wait:** a whole casing refuses the welder before the weld (it waited the weld out first); a
  terminal site taken during the five seconds refuses at the re-check. The welder is the library's `lit_welder()` (a lit tool; the weld still
  spends no fuel).
* **The RCON tag prompt refuses a tag another unit carries and asks again** (the prompt kind's refusal); an empty answer changes nothing.
* **A failing unit's refusal is a requirement** with the overload message (it was a message from an effect).
* **The wires window opens beside the unit's own for someone at the unit** (physical authority); it was "anyone but the AI".
* **The RCON console reads its units and breakers live** (`known_smes()`, `known_breakers()`); its window data is pure (it rewrote its device
  lists in every refresh) and no destroyed unit or breaker box makes every console rescan. A breaker toggled too recently refuses with a reason
  (it was a message from the effect).
* **The containment failure destroys the unit through the damage model** (`atom_destruction()`) if the blast left it standing; it was `qdel`.
* **The power-failure event keeps what it took out of each unit on the unit** (`held_through_outage`: charge and both switches) and
  `power_restore()` puts back only what it took; the three `last_*` vars are gone.
* **Settings reach Rust once per frame by themselves**: no setter or bind calls `push_to_rust()` by hand. `power_registered()` asks for a resync
  (`native_resync()`, new), the generated reads now include `working` (a stat: operable and no grid check).
* A mapped buildable unit still starts with `cur_coils` standard coils, a frame-built one with the frame's parts; a unit spawned bare keeps its
  type's numbers until parts arrive (pinned).

## Engine and library pieces the SMES added

* `SmesFlowReset` and the `Smes` flow fields (verdigris/domains/power), with a Rust test of the readings.
* `native_resync(E)` (code/datums/native/system.dm): a (re)bound entity's push runs at the frame's refresh.
* `om_field_written()` (code/datums/capabilities/refresh.dm): the legacy field setters (`OM_FIELD`, `OM_FLAG_FIELD`: a machine's `stat` bits,
  `on`, `locked`) now tell the stat layer, so a contribution that reads them (STAT_OPERABLE's `stat_bits_allow()`, `powered()`) recomputes before
  the writer's next line. Before, a converted machine's STAT_OPERABLE did not follow `atom_break()` or a power loss until something else wrote a
  tracked input.
* `lit_welder(fuel =)` and `req_welder_lit()` (code/library/items/welder.dm).
* The reads analysis treats the Verdigris bindings (`code/__defines/verdigris/`) as opaque: a condition that asks a Rust-owned value (a SMES's
  charge) is re-asked when a requirement is checked or a gate polled, never subscribed.

## Medical pods: occupant_pod(), paired_console(), beaker_bay() (sleeper, cryo cell, body scanner, their consoles, the transport pod)

Pinned by `code/modules/unit_tests/dq_medical_pods_behaviour.dm` (28 tests, written and green on the legacy code first; every pin that changed below
was marked LEGACY there and edited in the commit that changed it). The library pieces are tested by `dq_medpod_library_tests.dm` and
`dx_cap_b2_library_tests.dm`.

### What every pod does now (occupant_pod())

* **The menu labels are "Move Inside" and "Eject"** on every pod ("Eject occupant", "Eject Body Scanner", "Enter Pod" and "Eject Pod" are gone).
* **A refused entry says why** ("It is already occupied.", "It is not designed for that organism.", "They are not next to it.", "The subject cannot
  have abiotic items on.", "Close the maintenance panel first."); several old paths declined silently.
* **A screwdriver or a crowbar on an occupied pod is refused** ("Someone is inside it."). The old sleeper and body scanner blocked the tools in
  `screwdriver_act()`/`crowbar_act()` overrides that the maintenance interactions never reached, so an occupied pod's panel opened and it could be
  pried apart with someone inside.
* **A grab used to put someone in is used up** when they go in (the body scanner already did; the sleeper left a dangling grab). A grab used on an
  occupied pod is refused and stays in hand: the cryo cell consumed the grab before it found the cell occupied, losing it.
* **The occupant moving gets out when they can act** (a `while_slotted()` hook on their `relay_movement` action replaces three `relaymove()`
  overrides). An unconscious or restrained occupant stays in, as before.
* **The way in is asked again when its wait ends**: a sleeper that lost power during the two-second wait, or a person moved away from it, takes
  nobody (the old timed task's completion rechecked neither).
* **An occupant leaves onto the pod's exit tile only when nothing blocks it**, else onto the pod's own tile: the cryo cell put its occupant (and its
  beaker) into the wall south of it.
* **Unrelated items clicked on a sleeper or a cryo cell are no longer swallowed** (both machines ended their `attackby` without calling its parent).
  They do what any item does to a machine.

### Body scanner and console

* **The window's eject button works**: it called the menu handler with the actor where the handler expected the action context, so it ran into a
  runtime and nobody came out.
* **The console's screen shows a critical occupant red, not blue** (blue is an empty scanner now, and only that); a hurt but living occupant shows red
  instead of the dead screen; the dead show the dead screen. The old switch over the health ratio sent 0 (critical) to the empty case and any partial
  ratio to "dead".
* **The console pairs when the map load is complete** (`paired_console()`'s `after_init(0)`), not half a second later through a timer, and never
  searches again on a click.
* **A ghost no longer gets the console's view entry** (the legacy observer interaction). The window's own state still decides what a ghost sees.
* **Clicking the scanner opens its window hosted on the scanner** (the `tgui_host()` override that moved it to the console is gone).

### Sleeper and console

* **Stasis needs a working sleeper.** The stasis setting is a `while_slotted()` contribution to the occupant's `STAT_CLOCK_RATE_BIO`, gated on
  `STAT_OPERABLE`: an unpowered or broken sleeper lets its occupant's biology run at full speed, and holds them again when it works. The old
  `machine_step()` wrote the stasis every frame and only ran while the sleeper was operable, so a sleeper that lost power kept its occupant in stasis.
  The stasis setting is now a rate (`stasis_rate`, 0.01 to 1); the window's five choices and their names are unchanged.
* **The two-minute "struggle through the haze" eject of an unconscious occupant is gone**: an unconscious actor cannot act, so it was unreachable.
  A conscious occupant's eject is at once, as before.
* **Dialysis and the stomach pump turn off when the beaker is taken out or the occupant leaves**, through the setters (the old `toggle_filter()` and
  `toggle_pump()` calls meant "turn off" there). Turning either on needs an occupant and a beaker, refused with a reason ("There is no beaker to drain
  into.") where the old button silently set it off.
* **Dialysis moves the same amounts in one transfer** (3 units per chemical present, in proportion, and that many plus one of blood) instead of one
  transfer per chemical in a loop over the list it was emptying.
* **The injectors refuse a dead or too far gone occupant as requirements** (the same texts, as refusals); an unlisted chemical is still refused and
  told to the admins.
* **The sleeper's window opens for a silicon (remote) and, with controls inside, for its occupant ("Controls")**; a hand on the sleeper from outside
  opens nothing, as before. The console opens the window with any item as with an empty hand (the old item-as-touch entry).
* **The console's dark sprite is drawn from its power** (`draw()`), not written by `power_change()`.
* **An EMP is a notice** (`on_notice(/datum/notice/hit/emp)`), not a damage reaction: dialysis and the pump stop, and a working sleeper throws its
  occupant out, as before.
* **A part replacer is refused while someone is inside** ("Someone is inside it."); the old item catch-all ignored it silently.
* **The starting beaker is still deleted with the sleeper**; the survival pod's cover overlay is drawn by its `draw()`.

### Cryo cell

* **An unpowered cell treats, cools and sedates nobody.** Its frame is `every(when = cond_all(on, STAT_OPERABLE, occupied))`; the old periodic
  condition was `on && node` without power, so a cell kept treating with no power.
* **The occupant is held asleep by a status** (`holds_status(EFFECT_SLEEPING)` in a `while_slotted()` gated on the cell being on and working) instead
  of `set_stat(UNCONSCIOUS)` and a direction write every tick; they face south once, on entry. The hold is there whatever the gas in the cell
  (the old write skipped a cell with under 10 moles).
* **Any carbon can be dragged in** (a diona nymph): the menu's "Move Inside" already took any carbon, the drag took only humans.
* **The cell trades heat with its occupant through the gas domain** (`gas_body_heat_exchange()`, code/domains/atmos/gas.dm) instead of
  writing the gas temperature itself; it still settles its pipe network when the gas moved by more than a kelvin.
* **The release sequence is an op wait** (two minutes, ending if the occupant dies or the cell goes) instead of a free-running timer that ejected
  whoever was inside when it fired.
* **The window opens unpowered** (as before) and **its buttons leave fingerprints**; slimes and pAIs are refused the eject button by a requirement.
* **The tube is drawn by `draw()`**: the old shared fluid image had its colour mutated on every redraw.
## Atmospherics machines: the vent pump and the scrubber

Pinned by `code/modules/unit_tests/dq_atmos_machines_behaviour.dm` (green on the legacy code first) and the existing `dq_atmos_tests.dm` flow tests.

* **The area names its air devices, numbered per kind and never reused** (`area_air_device()`): a vent placed after another one went no longer takes
  a number still in use ("#len+1" made two "Vent Pump #2"s).
* **A device's tag goes through one setter, and the area follows it**: a tag set with the multitool (or by an airlock controller's mapping helper)
  moves the device's name and status to the new tag; the old one used to stay registered and the new one stayed unknown to the alarms. The
  blueprints' rename no longer gives the room's vents and scrubbers new tags (it renamed and re-keyed them; now it renames their entries).
* **A scrubber told `panic_siphon = 0` stops siphoning** (the value was tested for truth, so the air alarm window's panic switch could not turn it off).
* **A radio command runs when its key carries a value**; a bare key (no value) is ignored, except "status". The air alarm sends its pressure resets
  with a value now (they were the only bare keys on the air).
* **The vent's internal check is part of its flow law**: the atmospherics siphon (internal check only, 2000 kPa) stops filling its pipe at the
  ceiling (it siphoned the room without bound), and a vent with both checks never drains its pipe below the internal bound. The internal bound is
  pushed to Rust when it changes.
* **A welded vent cannot be unwrenched** (the scrubber already refused; the vent did not). The wrench, the weld and the multitool are ops: the
  wrench waits four seconds, the weld the welder profile's three (two before).
* **The multitool settings are the library's** (`multitool_settings()`): the first question also offers "None", and a frequency or a tag is asked
  with the library's question text.
* **The vent's flow stays volume-limited** (its pipe volume times fifty litres a second, as since the flow law moved to Rust): `power_rating` is what
  it draws, not its limit. A power-limited flow would change every station's ventilation rate; this is recorded rather than changed.
## Vending machines (rewrite/machines-full)

- **One vend op.** Buying is `op("vend")` with its refusals as requirements (stock, power, the product's access, a NIF's readiness for the
  NIFSoft shop), the PIN as `asks()` and the price as `costs(RES_CREDITS, vend_price)`: the credits are reserved after the last answer and
  taken after the effects, so a vend refused or cancelled half way never charges. A refused vend says why (the notice's `refusal`).
- **Coins.** The coin button is `req_on_authority(AUTH_PHYSICAL)`: anyone standing at the vendor, a cyborg included, takes the coin out;
  a silicon over its link does not (before, a cyborg at the vendor was refused).
- **Logs** need the logs to exist and the log access (`check_logs` is gated, no longer a no-op button).
- **Rotation** is the library `rotatable()` capability (`rotatable.clockwise` / `rotatable.counterclockwise`), replacing the vendor's own verbs.
- **Slogans and timed work** run on `every(..., when = STAT_OPERABLE + wanted)`: an unpowered or broken vendor no longer polls; slogans start
  after init and the slogan delay is a time define (10 minutes, unchanged).
- The cigarette machine's Mauser lives in its product table instead of an `Initialize()` override.
- Library: `credits_resource.dm` (the RES_CREDITS adapter: the payer is the actor's credits source), `rotatable()`, `toggles(key, when =)`.
## Airlock and APC, full conversion (rewrite/doors-full)

Pinned by `code/modules/unit_tests/dq_doors_full_behaviour.dm` (written and green on the code before it, commit "Pin airlock and APC behaviour before
the full conversion"), alongside the `dq_p2_door/*` and `dq_p2_apc/*` suites. Each row below edited the assertion that pinned the old behaviour.

### APC

* **A reboot forgets the power alarm it raised.** `reboot()` cleared the alarm on the alarm handler but left `power_alarm_raised` set, so the next poll
  "cleared" it a second time and counted a power event. (bug; `reboot_clears_the_power_alarm`)
* **The channel modes reach the power domain through `push_to_rust()` only.** `set_channel_mode()` and `reboot()` wrote `NATIVE_APC_CHANNELS` by hand;
  the push now carries the three channels with the rest of the settings, once per frame after any of them changed. Same values, one path.
* **One breaker path.** The window's `breaker` op also answers a silicon's ctrl-click (`extend("breaker", binds(remote()), gesture(GESTURE_CTRL))`);
  `remote_breaker`, `set_breaker()` and `toggle_breaker()` are gone, and the area follows the breaker through `on_change(nameof(operating))` whoever
  writes it (the AI restoring its own power, a break). The ctrl-click is under the window's rules: a cyborg without access works an *unlocked* APC's
  breaker by ctrl-click as it already could through the window (it used to also need `remote_link_allowed()` for the ctrl-click alone).
* **Window access is the library's** (`req_window_usable()`, `req_silicon_or_admin()`, `code/library/access/window_access.dm`): the refusal texts are
  the library's ("You can't use that right now.", "Only a silicon can do that."), the rules are unchanged; the APC keeps only its own remote rule
  (`remote_control_allowed()`: the AI-control wire, the hacker and its cyborgs).
* The window data loses `normallyLocked` (always equal to `locked`) and `totalCharging` (always 0); the TSX shows the total load alone.
* Dead state is gone: `debug`, `chargecount`, `longtermpower` (Rust keeps its own), `report()`, the `area()` accessor (the `area` var is read directly).

### Airlock

* **The AI-control wire pulsed and then cut keeps silicons out.** The pulse's one-second timer was unkeyed and set the control back on whatever
  the wire said, so a pulse followed by a cut gave the AI its control back, and pulses stacked timers. Now the cut and the pulse are separate holds on
  `STAT_AI_LOCKED_OUT` (`SRC_AI_WIRE`, `SRC_AI_WIRE_PULSE` for a second). (bug 1; `ai_wire_pulse_then_cut_keeps_the_ai_out`)
* **An emagged door shows its 'AI control allowed' light off, and its open-door wire does nothing.** Both checks read an `emagged` var the door's emag
  never set; they read `emag_emagged()`. (bug 2; `emagged_door_shows_ai_control_off`, `emagged_door_ignores_the_open_wire`)
* **The speed and the autoclose are tracked** (`TRACKED(/obj/machinery/door, normalspeed)`, `autoclose`): the window's speed and the timing wire's
  writes reach whatever reads them. (bug 3; `speed_toggle_is_tracked_and_refused_with_the_wire_cut`)
* **Paired airlocks close each other both ways.** The pairing was a scan of every machine at init that linked only the airlock placed second to the
  first; it is a keyed relation (`ref_many(nameof(close_others), /obj/machinery/door/airlock, by = nameof(closeOtherId))`). (bug 4;
  `paired_airlocks_close_each_other`)
* **The prison break leaves the cell door bolted open.** `prison_open()` dropped the bolts while the door swung, which the bolts refuse, so the door
  stayed unbolted; it drops them forced. (bug found by the pinning test `prison_open_opens_and_rebolts`)
* **Bolts and current are sourced holds** (`STAT_BOLTED` on every door, `STAT_ELECTRIFIED` on the airlock; final_api 16.2). An AI's bolt button and its
  shock buttons hold with the AI as the source, so one AI's unbolt or "restore" releases only its own hold: a second AI's bolts, a wire's pulse, a
  button's lockdown run on. A deleted AI's holds go with it. The door's own motor (a wire, a button, a radio command, a map start) is `SRC_DOOR_BOLTS`,
  and its mechanical raise (`set_bolted(door, FALSE)`, the bolt wire's pulse) still lifts every hold. (`second_ai_and_the_bolts`,
  `ai_restore_after_a_wire_pulse`)
* **Mending the electrify wire releases only the wire's current** (it used to end every electrification).
* **Main and backup power are stats** (`STAT_MAIN_POWER_OUT`, `STAT_BACKUP_POWER_OUT`): a cut cable holds until mended, a tripped breaker for a minute,
  the backup's switchover for ten seconds. The window shows the same numbers. The disrupt buttons, and every other window button, refuse through
  `needs()` with the old text instead of a message in the effect.
* **Touching a live door is one takeover of every click op** (`extend(/datum/act/op, instead(when(STAT_ELECTRIFIED, req_on_origin(ORIGIN_CLICK)), ...))`)
  instead of an early effect on seventeen named ops. Ops that were not on the list now shock too (clearing ice, the ctrl-click's hammer and bell);
  window buttons and a silicon's link never did and still do not. A shocked touch ends `ACT_REPLACED` (it ended refused, so a shut door's denial
  flash no longer follows the shock).
* **The ctrl-click is three ops** (`hammer`, `hold_open`, `doorbell`, all `gesture(GESTURE_CTRL)` and not for silicons); a silicon's ctrl-click is the
  bolt button over its link (`extend("bolt_toggle", binds(remote()), gesture(GESTURE_CTRL))`), and its shift-click the open button. No `click_ctrl()`
  override loops over op keys any more.
* **A thrown metal thing striking a live door sparks** (the sparks were a side effect of `CanPass()`, for any metal item that tried to pass a shut live door).
* **The swing's sound reaches the clients that hear the door** (`hearers()`, `play_motion_sound()`), not every player's mob within twice the view; an AI
  listening through its hologram no longer hears it.
* **An EMP pops open the doors that declare it** (the airlock and the windoor hook `door_emp()`); the base door no longer asks `istype()` of its subtypes.
* **A blob reaching a door** is a takeover of the blob hit (`extend(/datum/act/hit/blob, ...)`): an open door is untouched, a broken shut one opens, a
  sound shut one takes the hit as before.
* Gone as dead: `aiControlDisabled` (its bypass states 2 and -1 had no writer), `hackProof`, `aiHacking`, `canAIHack()`, `lockdownbyai`,
  `next_weather_check`, the `wire_cut()` wrapper, the three hand-keyed power and shock timers and `electrify()`'s thirty-line state machine
  (`electrify(duration, source, user)` is now a hold), `lock()`/`unlock()` (the bolts library's `drop_bolts`/`raise_bolts`, through `set_bolted()`).
* Moved, behaviour intact: the SCP door to `airlock_subtypes.dm`, the cyborg's water reserve and refill verb to `robot.dm`, the cyborg-use rows to
  `atmos_control.dm`, `computer/robot.dm`, `turret_control.dm` and `portable_turret.dm` (its cyborg `isLocked()` branch folded into the turret's own).
=======

## Atmospherics machines: the air alarm and the remote atmospherics console

Pinned by `code/modules/unit_tests/dq_atmos_machines_behaviour.dm` (green on the legacy code first), `dq_atmos_tests.dm` and `dq_fwg3_windows.dm`.

* **The Sif wilderness alarm reads its own oxygen band** (16/17 kPa): it was written under "oxygen", a key no reading used, so the station's band
  (16/19) judged Sif's air.
* **Each alarm keeps its own thresholds** (its type's `default_TLV()`, copied when it initializes). A threshold edit copies the whole edited band (kept
  in order) to every alarm of the area; it used to copy only the edited value to the others, and could leak into the type's shared table and so into
  alarms elsewhere.
* **The thermostat is a gas-domain heater** (`/datum/gas_heater`): the same 1000 J per service interval, the same quarter-of-the-gap cap, the same
  cooling coefficient and start/stop gaps. It works the room's air through one read and one write instead of taking a quarter of the air out and
  merging it back.
* **The scan wakes on the room's own gas watch** (`gas_watch()`, the named observation fields): a main alarm scans once when the air crosses one of its
  bands, keeps scanning while the thermostat works, and parks otherwise. The machine pipeline stage, the OM value watch and its `MACHINE_WAKE` are gone.
* **The lock is the lock library's**: an ID (or PDA) swipe, or an alt-click with the access worn, toggles it while the alarm works and its ID scan wire
  is intact. Pulsing the ID scan wire opens the lock for 30 seconds (it toggled it); cutting it still locks it. Any other item used on the alarm does
  nothing (every item ran the old swipe interaction).
* **The panel, the wires and the cut-out are ops**: the screwdriver waits the tool's two seconds; an empty hand at the open panel opens the wire window
  (it opened the window and the wires together); the wirecutters at the open panel cut the alarm out as before.
* **A refused button says why** (a shorted alarm, a cut AI control, a remote console that does not let the user in, a person's lock button) instead of
  doing nothing in silence. Rcon and the thermostat stay outside the lock; a cut AI control now refuses them to a cyborg too (the AI already had no
  window).
* **The remote console works an alarm through its own panel** (`/datum/air_alarm_remote`, a window forwarding to the alarm's buttons): it vouches for
  whoever the console lets in (`window_vouches()`, read by the lock library), so the custom tgui state, its `qdel(src)` inside `can_use_topic()` and its
  `isAI()` test are gone. A silicon is let in by its link (`remote_link_allowed()`), as everywhere else. The console itself opens by hand or link and
  takes the emag through the emag library.
* **Map edits**: the alarms a map left unlocked (`locked = 0`) say `lock_at_start = 0`.

## Portable turrets, the turret control panel and the turret frame (rewrite/machines-full)

- **Lock and window.** The turret and the panel use the library `lock()`; their window buttons need `req_window_usable()` with the firewall
  (`ailock`) as the remote condition, so a silicon over its link is kept out by the firewall and an admin ghost works a locked machine.
- **Pulses.** `emp_disable()` replaces the hand-written switch-off and re-enable: a pulse holds STAT_OPERABLE down (6-60 s over severity) and
  the turret's / panel's on switch is left as it was (before, the pulse flipped `enabled` off and a timer flipped it back on). A knocked-out
  or unpowered panel tells its turrets to stand down and they follow it again when it comes back.
- **Armed.** `STAT armed` = switched on and operable; the target scan is `every(..., when = STAT_ARMED)`, so an idle or unpowered turret
  does no periodic work (the old mob-chunk sleep tokens and its test are gone). Power that comes back before the turret "noticed" leaves it
  powered (the old delayed power-off landed after power returned).
- **Emag.** `emag(disables_for = 6 SECONDS)`: the turret is subverted, locked away from its panels and switched on, held inoperable for the
  six-second grace.
- **Panel settings.** The panel hands its turrets every setting it shows, `check_down` included (before, the down setting never reached them),
  and no longer overwrites a turret's own firewall. The panel's area is a link (`/area::turret_controls`); mappers name it with
  `control_area_name` (the four map edits were rewritten).
- **The pop-up cover** is the library `popup_cover()`.
- **The frame** is a `construction()` graph: the proximity sensor goes in with a click (before, no click reached it) and stays in the frame's
  construction slot; each step undoes by its tool; a loose frame pries apart into one stack of five sheets (`spawns()` of a stack now makes
  one pile of n). Renaming is `asks()` a text prompt.
## Atmospherics machines: the canister and the portable machines

Pinned by `code/modules/unit_tests/dq_atmos_machines_behaviour.dm` (green on the legacy code first) and the canister tests of `dq_atmos_tests.dm`.

* **The chilled oxygen canister holds one load of oxygen**, chilled to 80 K: it was filled twice (its own fill on top of the oxygen canister's).
* **The presets are a `starts_with` table** (gas -> share of a 45-atmosphere load; the engine set-up canisters' share is 2). The room filler is a
  preset that empties itself into its room.
* **A ruptured canister's gas goes into the room** (`gas_dump()`): it went nowhere (the machine's own destruction let go of the mixture first).
* **The valve's release is `gas_release()`** (the same exact solve and the same release-flow cap per service interval; the turf is woken by the API),
  and a cyborg's jetpack refill too (an exact solve at the mixing temperature, where it used the canister's temperature).
* **A canister can be relabelled while it is empty**, read when asked (it was a stored flag the machine pipeline overwrote each frame, so the type's
  `can_label` never held past the first frame anyway).
* **The release log keeps its newest 50 lines** as a list (it was an unbounded HTML string).
* **The canister's work is an `every()` gated by `working`**, woken by its own gas watch; a closed connected canister's gas change moves only its
  gauge. The machine pipeline stage, its OM value watch, `MACHINE_WAKE` and `om_settled` are gone.
* **The tank bay, the port wrench, the liner, the welder, the strike and the cell slot of the powered ones are ops** (`tank_bay()` beside
  `cell_bay()`); refusals say why ("It is wrecked.", "Nothing happens.", the drain and liner reasons). A liner takes its two sheets as the op's cost.
* **The canister's eject drops the tank on the floor and closes an open valve, as before; the label's colour is a tracked var drawn by `draw()`.**
## Missing forms: the bump action

Pinned by `code/modules/unit_tests/dq_mfo_doors_behaviour.dm` (green on the legacy `Bumped()` first) and the bump tests of `dq_p2_door_behaviour.dm`.

* **Walking into something is the bump action**: `/atom/movable/proc/bump_into()` is its one emitter (the movement path's `Bump()` and a mech's push
  call it), published on the bumped atom with `bumper`, `bumped` and `direction`. A type answers with `on_notice(/datum/notice/bumped, ...)` or takes it
  over with `extend(/datum/act/bump, instead(...))`; an unconverted `Bumped()` still runs after the notice. A refused or taken-over bump skips it.
* **The airlock's bump shock is a takeover**: a live door's shock (or a hallucinating mob's phantom one) replaces the bump; a shock that finds no power
  lets the bump go on to the door as before. A mob shocked this way is stamped for the once-a-second bump limit (it was stamped before the shock).
* **A mech's bump reaches doors through the same emitter**: a mech pushing an anchored object used to call its `Bumped()` directly.
* Converted: the door base, airlock, blast door, firedoor, windoor, unpowered door, transport pod, and the bump answers of the shadekin portals,
  recharge station, teleporter hub, bluespace/flux/gravity anomalies, bump teleporter, grille, cliff, fence, medical holosign, simple door, portals,
  transit tubes, telecube, redgate, autogibber, station map and infrared beam. The rest are held by the `bump_ratchet_on_bumped_overrides` ceiling.

## Missing forms: the generic hit

Pinned by the smash tests of `code/modules/unit_tests/dq_mfo_doors_behaviour.dm` (green on `attack_generic()` first) and the animal tests of
`dq_p2_door_behaviour.dm`, `dq_p2_closet_behaviour.dm`, `dq_p2_lights_behaviour.dm` and the other callers' tests (now driven through `generic_hit()`).

* **A generic attack is the hit/generic action**: `generic_hit(target, user, damage, attack_verb)` is its one emitter (simple mobs' attacks, xeno
  bites, bots, a hulk's or a shredder's smash). A target takes it over with `extend(/datum/act/hit/generic, instead(...))`; otherwise the default
  `attack_generic()` lands with the act's final damage.
* **A taken-over hit is not a landed one for the attacker**: `apply_attack()` returns FALSE for it, so a simple mob's melee effects (poison and the
  like) do not follow a hit a door or a fixture answered itself. A camera's smash used to return TRUE here.
* Converted: the door base, airlock, blast door, firedoor, puzzle door, lift panel, drop pod door, cult pylon, light fixture, camera, expedition demo
  target, ladder and trash pile. The rest are held by the `generic_hit_ratchet_on_attack_generic_overrides` ceiling.
## Electrification as timed holds (vending, smartfridge, seed storage, suit cycler; rewrite/machines-full)

- `shock_wire()` has no counter mode any more. Every user declares `STAT(T, electrified, TOP, base = 0)` (as the airlock does) and
  `shock_wire(stat = STAT_ELECTRIFIED)`: a pulse is a timed hold of exactly 30 seconds (before: 30 "frames" of a per-tick countdown, whose
  real length followed the machine's step rate), a cut wire an untimed hold until mended, and mending releases both.
- Sources do not overwrite each other: an event's or an admin's hold sits beside the wire's, and the strongest (TOP) wins; mending the wire
  leaves another source's hold in place (before, any writer set the one counter).
- The shock counts only while the machine is operable (`shock_live()`): an unpowered or broken machine shocks nobody, and is live again when
  it comes back. A timed hold's clock keeps running while the machine is down, so a pulse can run out during an outage (before, the countdown
  paused). The suit cycler no longer clears its shock when it loses power.
- The `seconds_electrified` counter, its -1 sentinel and the countdown in the machines' periodic work are gone: an idle electrified vendor,
  fridge or seed storage does no periodic work for its shock.

## Atmospherics: the cryo cell's pipe and on-state

* The cryo cell's on-state is its own tracked `cooling` (`set_cooling()`), not the machine core's `on`; its pipe check is the unary device's
  `piped()` (shared with every unary device), not a read of `node` of its own.
* `gas_body_heat_exchange()` wakes the pipe network that owns the gas (`gas_touched(air)`) whenever the gas's temperature moves; the cell no
  longer marks the network by hand. Before, it marked it only when the gas moved by more than 1 K in a tick, so a slow exchange now records
  every change (a revision bump, no extra pipenet pass). A body already at the gas's temperature changes nothing (no rounding drift).

## Missing forms: an explosion's contents

Pinned by `code/modules/unit_tests/dq_mfo_blast_contents.dm` (green on the overrides first), `dq_explosion_batch_tests.dm` and `dq_c8a_occupant_slot_tests.dm`.

* **How hard a blast reaches a holder's contents is declared**: `blast_contents()` or `blast_contents(shield = 1)` in the holder's CAPABILITIES; the
  explosion service reads it (`explosion_contents_severity_of()`). Every `explosion_contents_severity()` override is gone (body scanner, clone pod,
  DNA scanner, pAI card, closet, statue, morgue, transit tube pod, bookcase, APC, atmospherics machinery) and the name is a hard ban.
* No change in numbers: the DNA scanner declared two overrides, and the later one (the full blast) is what ran.
