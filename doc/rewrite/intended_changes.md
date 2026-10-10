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

## Missing forms: door looks

Pinned by the look tests of `code/modules/unit_tests/dq_mfo_doors_behaviour.dm` (green on the templates first).

* **Every door draws through draw(look)**: the base door (`door1`/`door0`), the blast door (its type's open and closed states) and the windoor (its base
  state, `open` after it) replace their `APPEARANCE_TEMPLATE`s; the airlock's and firedoor's `update_icon()` -> `changed()` bridges and their
  `APPEARANCE_NONE` lines are gone. A swing, a weld, a hatch and damage redraw through their tracked vars; the firedoor's alert lights and the angled
  bay airlock's built icon (no tracked vars) mark the door changed by hand. No look changes.
## Heat network (rewrite/thermal-domain)

Heat moves only through Rust's conserved transfer primitive and declared edges (`heat_link()`, `heat_pump()`, `heat_engine()`; `heat_move()` and its
wrappers for one-off events). Pins: `code/modules/unit_tests/dq_heat_machines_behaviour.dm` (before/after values logged by each test).

* **Machine heat goes to a booked 20 °C reservoir (approved).** A heat pump with nothing physical to reject into (space heater, thermoregulator)
  pumps against `HEAT_AMBIENT`, an infinite 20 °C reservoir whose flows are booked in the heat ledger as leaving or entering the station. The old
  code deleted or created that heat with no record. The floor tile was rejected as the sink: 150 kW into a solid cell heats it thousands of kelvin.
* **Space heater.** Heating is resistive, one joule of air heat per joule of cell (before: 301.87 K after 20 s from 283 K, air +39 251 J for 39 256 J
  of cell; unchanged in kind). After: 303 K (it reaches its thermostat; it runs on the world step), air +82 615 J for 90 383 J of cell, the
  rest in the room's walls through the solid–air coupling. Cooling now pays for its work: before, the cell gave **0 J** while the air lost 39 251 J (a bug: cooling was free and
  the heat vanished); now the cell pays `Q / COP` with a Carnot-bounded COP and the heat goes to the ambient reservoir (after: 293.05 K from 313 K in 20 s, air
  −82 189 J, cell 3 227 J).
* **Thermoregulator.** Heating gave 5× the drawn power as heat (B10); it is now a heat pump against the 20 °C reservoir at a Carnot-bounded COP, and
  the grid is billed the pump's measured work. Its overload surge heats the room 1:1 with the energy drawn (was 5×).
* **Gas cooling and heating systems.** The freezer is a Carnot-bounded pump from its pipe port into the room (was `2.5·T/T_heatsink`, with coolant
  multiplying the heat moved for free); parts and coolant now raise its Carnot fraction (capped at 1). The heater is resistive at its power rating.
  Both run in Rust on the world step, so they no longer depend on how often the machine steps. Before: freezer loop 243.15 K after 20 s from
  293.15 K toward 200 K, room +20 000 J; heater loop 313.15 K after 20 s toward 400 K. After: freezer loop reaches 200 K, room +79 423 J;
  heater loop reaches 400 K (the 50-mol test loop is small: the old per-step caps made it slower than its rating).
* **Bodies exchange heat with their surroundings only outside their comfort range (approved).** With energy conserved, a 280 kJ/K body at
  game-rate conductance would heat every occupied room, so its links carry the old convection rate only while the old Life code would have run
  convection (body outside its comfort band or air more than 20 K away); inside it they conduct nothing ("Body heat against the room").
* **One-off writes are booked.** Every gas temperature or energy write outside the gas and heat domains became `heat_set()` (an authority write:
  spawn temperatures, admin, events, tests) or `heat_add()` with a `HEAT_SOURCE_*` (fire, reactions, spells, devices, materials). Values are
  unchanged; `heat_books()` now accounts for them. The radiance spell and the supermatter keep their 10 000 K clamp as an authority write.
* **Cryo cell.** The occupant and the cell's gas share one declared `heat_link` (`HUMAN_HEAT_CAPACITY / 2` W/K, about a full settle per
  service interval) while the cell is on, works and holds them; the old explicit settle per interval (`gas_body_heat_exchange`) is gone.
  Pins unchanged (`dq_medpod/cryo_*`, `dq_cryo_cell_cools_mob`).
* **Air alarm thermostat.** `/datum/gas_heater` is deleted; the thermostat is a `heat_pump` on the room's air (500 W, i.e. its old 1000 J per
  service interval, resistive heating and cooling at no better than 1:1) while `regulating_temperature` says it works. Its start/stop
  hysteresis (2 K / 0.5 K, no work below 1 kPa or on an unsafe target) is unchanged. It now works continuously between scans instead of in
  one 1000 J lump per scan; `alarm_thermostat_heats_and_cools` still reads 3000 J over three intervals.
* **Heat exchangers** are one `heat_link` (5000 W/K, scaled by an engineered material's conductance as before) between the pair's pipelines,
  declared by the first of the pair; they no longer step in DM. Before: full mix per SSair tick; after: the loops meet within about a second.
* **HE pipes in space** radiate through a `heat_link` to a 130 K sky (the temperature at which the old solar gain balanced the radiation),
  emissivity 1 over their surface; the old scaling of radiation by the gas's density is dropped (radiation leaves the shell, not the gas).
  A body buckled to one meets the pipe's gas through `heat_equalize` (it was a DM average with a fixed body capacity).
* **Thermoelectric generator.** `heat_engine_once()` per step: the same equalizing transfer, with `thermal_efficiency` now capped at Carnot
  (`1 − T_cold/T_hot`); with stock efficiency 0.65 the cap matters only for loops within a factor of ~2.9 of each other.
* **Gas turbine.** Its adiabatic temperature drop is a booked device write (`heat_set`), unchanged in value.
* **Exosuit cabin.** A 1000 W resistive `heat_pump` toward 20 °C against the outside air, paid from the cell, while temperature control runs
  (was 25 % of the gap, capped at 10 K, per 2 s with no energy). Before: 305.85 K after four regulations from 333.15 K.
* **Mob bodies.** `bodytemperature` is only the starting value; `body_temperature()` reads the mob's Rust heat body (`HUMAN_HEAT_CAPACITY`).
  Thermoregulation, passive heat and prosthetic heating are the body's metabolic power (the old per-run kelvin steps as watts over one Life
  frame). How the body meets the room is "Body heat against the room" below.
* **Test clock.** `test_time()` advances the heat network's edges with it (`vg_heat_net_advance`), so heat-flow pins use the kernel clock.
* **Material science heat** moved onto Rust heat stores and links ("Material science heat" below).

## Body heat against the room (rewrite/heat-followups)

Pins: `code/modules/unit_tests/dq_body_heat_behaviour.dm` (a human in a sealed 9×9 room whose air, floor and walls start at the room's
temperature; Life's environment and thermoregulation stages once per 6 s frame, the native world stepping 6 s of world time between frames). "Before" is the
pre-heat code (f24504821c: the body relaxed toward a mixture that never warmed); "regressed" is the conserved heat domain as it first landed
(43dce9c2bb), where the body met only its tile's ~2 kJ/K of air.

| Case | Before (f24504821c) | Regressed (43dce9c2bb) | After |
|---|---|---|---|
| Unsuited, −50 °C room: body after 1 / 5 / 10 / 20 frames | 304.6 / 287.2 / 273.7 / 262.1 K (holds ~262.7 K) | 306.2 / 301.7 / 300.7 / 299.6 K | 299.9 / 277.8 / 271.2 / 266.0 K (room air 223 → 240 K) |
| Unsuited, 400 K room: after 10 / 20 frames | 347.8 / 357.7 K | 320.5 / 321.5 K | 350.7 / 354.6 K |
| Unsuited, 1000 K room: after 5 frames | 444 K (past 360 K at frame 2) | 422.3 K | 589.5 K, burned |
| Suited, in space: after 100 frames | 310.15 K | 309.6 K | 310.2 K |
| Ten people in a 20 °C room for 50 frames | air unchanged (bodies never heated air) | bodies inert | bodies linked at 0 W/K, 0 W of metabolism, temperature unchanged |

* **A body is linked to its surroundings, not to one tile of air.** Life's environment stage sets three couplings through clothing
  (`set_surroundings()`, `code/modules/heat/heat_mobs.dm`): convection at the old rate (`C·(1−protection)·density / (15 · 6 s)`, about
  3.1 kW/K bare) shared between its tile's air (coupling slot 0) and heat links to the air of the tiles open to it (the plume it stirs);
  contact with the floor solid it stands on (`BODY_FLOOR_CONDUCTANCE`, 4 kW/K bare) and with each wall beside it (30 % of that); and, in
  space or below a tenth of a standard cell's moles, a radiative link to the 2.7 K sky over `HUMAN_EXPOSED_SURFACE_AREA × (1 − cold
  protection)`. Before the fix the body could give a −50 °C room only what one tile of air held, so the tile warmed to the body's temperature
  in seconds and the comfort gate shut.
* **Floors hold heat.** A floor turf's solid is `FLOOR_HEAT_CAPACITY` = 80 kJ/K (a 2 cm steel deck plate of 1 m²; it was 10 kJ/K). The floor
  is what takes a chilled body's heat: a body losing 50 K gives up 14 MJ, which would warm a 9×9 room's air by 80 K but its floor by about 2 K.
  Walls keep their material capacity (312.5 kJ/K for steel) and conductance.
* **The Life frame is 6 s.** The body's conductances and metabolic power were scaled to a 2 s run; they are now scaled to the real Life frame
  (`LIFE_CYCLE_SECONDS`), the cadence the old per-run steps were applied at, so a body chills and recovers at the old real-time rate.
* **The comfort gate stays.** Inside its comfort range (air within 20 K of the body, body between its cold and heat damage levels, pressure
  safe) a body is linked at zero conductance. Game-rate exchange (kW/K, a hundred times a real body's) would otherwise make every occupied
  room a heater. The gate now reads the plume's mean air temperature, not the one tile the body warms.
* **Space radiation scales with protection.** It was the bare 5.2 m² whatever the body wore (and, before the heat domain, a 2.7 kJ step per
  frame, about 450 W); now a space suit's cold protection removes it and a bare body radiates about 2.7 kW, which thermoregulation holds
  within 2 K.
* **`dq_extreme_cold_damages_human` is a plain cold room again**: a sealed room of 50 K nitrogen (air, floor and walls), no stand-in cold
  mass.

## Material science heat (rewrite/heat-followups)

Pins: `code/modules/unit_tests/dq_material_heat_behaviour.dm` (green on the DM model first) and the existing `dq_material_*` tests. An
assembly's material service and a processed batch hold their heat in a Rust heat store (`code/domains/heat/heat_store.dm`: a heat body kept by
handle, with the thermal stock's phase plateau) and move it through heat links Rust integrates every world step. The DM exchange maths
(`exchange_with_gas()`, the ambient exchange in `advance()`, `convert_transferred_heat()`, the stock's 8 % step) is deleted.

| Case | Before (DM model) | After (heat store and links) |
|---|---|---|
| A cell's assembly at 400 K in a sealed room, 30 s | 382.4 K; lost 63 454 J, air +56 213 J | 381.7 K; lost 65 905 J, air +52 180 J (the rest in the floor) |
| A thermoelectric cell from 500 K, 30 s | charge 49.9, 465.4 K | charge 50.3, 464.0 K |
| A batch given 100 K of heat | +100 K | +100 K |
| Hot stock (900 K steel) cooling, 2 s steps: steps 1 / 10 / 30; stops glowing | 851.5 / 556.8 / 342.9 K; after 58 steps | 900 / 580.1 / 348.9 K (its link is made at the first step); after 59 steps |
| A canister (600 K nitrogen inside), 30 s | shell and contents unchanged: the service retired after its first sample | shell 293 → 372 K, contents 600 → 516 K; energy conserved |

* **The service's heat** is its store: `temperature()` and `buffer_energy()` read it, `add_heat(joules, source)` books into it. It is linked to
  its turf's air through its exterior (`construction_thermal_conductance(0.1, 0.004, T)`) and to the gas it holds through its wall (the
  pipelines a pipe machine's ports are in, a vessel's mixture), each sample bringing the conductances to its temperature. An exothermic stock is
  the store's power. A thermoelectric cell's exterior is a heat engine (capped at Carnot); its work is paid into the cell each sample, and what a
  full cell cannot take goes back into the assembly as heat. A retiring service gives what it holds over its air's temperature to the air first.
* **A canister's shell now meets its contents.** Before, a service woken only by hot contents found nothing to do on its first sample (no time
  had passed) and retired, so the shell never warmed; a link moves the heat whether or not the sample runs.
* **Batches** hold a store only while they differ from their surroundings (`temperature()`, `set_temperature()`, `add_batch_heat(joules,
  source)`); at rest they read their rest temperature. Copies carry their share; merging two portions meets them at their common temperature
  (`heat_equalize`) before the merged batch takes both capacities. A material's batch template holds no heat (it is a definition).
* **Process steps book their heat.** Casting (to 20 °C + 80 K) and quenching (to 20 °C) give the heat to the mould and the bath, booked as
  leaving under `HEAT_SOURCE_MATERIAL`; electric heating is `HEAT_SOURCE_DEVICE`, emitter shots `HEAT_SOURCE_WEAPON`.
* **The furnace's hot chamber no longer heats a charge for free.** It brought the charge to the chamber's temperature with no energy taken from
  the chamber; now the two meet at their common temperature and the furnace's electric heating supplies the rest (it draws more power).
* **A pressure wall without a service** (`process_material_environment()`) conducts through `heat_conduct()`, the exact pair solution in Rust.
* **Precision.** The heat crosses to DM as f32: the conservation pins compare to a millionth of the assembly's energy and a buffer to a tenth
  of a millikelvin's worth, not to 0.01 J.

## Gas reaction energy in Rust (rewrite/heat-followups)

Pins: `code/modules/unit_tests/dq_gas_reaction_energy_behaviour.dm` (every reaction once on a test mixture; golden temperatures and moles
measured on the DM maths, green before and after) and the existing fire tests.

* **A reaction's heat is Rust's.** DM's reaction procs keep their rates and stoichiometry and call `gas_react(air, GAS_REACTION_*, extent,
  deltas, aux)`; `vg_gas::reaction_energy::react` applies the mole changes and settles the energy (thermal energy before + enthalpy × extent,
  over the new heat capacity, floored at TCMB, left alone below `MINIMUM_HEAT_CAPACITY`) in one step, booked under `HEAT_SOURCE_REACTION`.
  The enthalpies (`FIRE_PLASMA_ENERGY_RELEASED`, `N2O_DECOMPOSITION_ENERGY`, ...) and freon formation's temperature curve live in
  `verdigris/domains/gas/src/reaction_energy.rs` and reach DM as generated defines. Outcomes unchanged (to 0.05 %).
* **Dry heat sterilization** was an authority write of `T + 0.002 K per mole`; it is now the energy that rise takes, booked as a reaction.

## Missing forms: the DNA modifier console's window

Pinned by `code/modules/unit_tests/dq_mfo_dna_console.dm` (green on DECLARE_UI/UI_ACT and the tgui modals first).

* **The window is interface("DNAModifier") with ops**: every button keeps its action name; the buffer label and the block injector's block are
  `asks()` steps of the `bufferOption` op, shown as the window's modal (`changeBufferLabel`, `createInjectorBlock`), so `ui_modal_answered()` is gone.
* **The block answer must be one of the offered blocks**: the legacy modal took any text with a number before a colon.
* **A refused button says why** (no scanner connected, the console irradiating, the user not standing at it) instead of doing nothing; opening the
  window from inside the scanner is refused with a reason. A silicon works the buttons over its link (it was refused for not standing on a tile).

## Missing forms: priced requests (the malfunctioning AI)

Pinned by `code/modules/unit_tests/dq_mfo_malf_costs.dm` (green on the custom malf prompt kinds first).

* **A malf ability's price is a cost of its request**: `open_request(..., costs = list("[RES_CPU]" = price))` with the plain prompt kinds (yes_no,
  choice, text). The CPU is checked when the AI is asked, set aside when it says yes (or picks), and spent once the ability went through. The
  `/datum/om/prompt/{confirm,choice,text}/malf` kinds and `ability_pay()` are gone (`ability_pay` is hard-banned); abilities that ask nothing spend
  with `res_spend(user, RES_CPU, price)`.
* **The answer re-checks the AI** (`malf_able()`: still malfunctioning, not hacking, not on backup power), as the old prompts' `valid()` did.
* **An AI that cannot pay is told why when the question would open**, and one whose CPU ran short by the answer is told and pays nothing (the old
  answer was dropped silently).
* **Unlocking a cyborg is checked against its 125 CPU when asked** (the old confirmation carried no price and only failed at payment).
* **A camera hack that changes nothing costs nothing** (as before); the AI's hardware pick, the core and station self-destructs and the hack
  confirmations of cyborgs and AIs are plain requests.

## Missing forms: the frame's wrench refund

Pinned by `wrench_refunds_a_loose_frame` and `wrench_refunds_a_held_frame` in `code/modules/unit_tests/dq_wall_frame_behaviour.dm` (no behaviour to pin
first: no click reached the legacy `wrench_act()`).

* **A wrench takes a loose wall or machine frame apart again** (op `frame.refund`, a `tool(TOOL_WRENCH)` op on the frame item): the frame becomes its
  `refund_amt` of `refund_type` (five sheets of steel by default). It was broken in play.
## Consoles: the console base, the ID console and the communications console (rewrite/machines-full)

- **Console base.** A console joins `REGISTRY_COMPUTERS`; an APC's overload finds the consoles of its area there (`area_consoles()`), so the
  legacy `powered_by(POWERED_BY_AREA)` capability, `caps_area_changed()` and `area_members()` are gone. It draws through `draw(look)`: the
  joined desk, the keyboard (off without power), and the screen as a glowing part that lights the room while powered (the light now comes
  from the look, not from a `power_change()` override). The terminal sounds follow STAT_OPERABLE. A pulse (`on_notice(hit/emp)`) breaks it
  one time in five over severity and a blob hit is `instead()` a medium blast, as before. The screwdriver is op `disconnect` (2 s; a broken
  one drops its glass), a gripper holding something is op `use_gripper`, and any other item is op `use_item` (the hand's use), at the
  default tier so a type's own item ops come first. `decode()` and `Initialize()` are gone. The message monitor's "too hot" and the AI
  restorer's stuck screws are `extend("disconnect", needs(...))`; the message monitor's hack screen is `screen_state()` (no longer written
  from the appearance proc); the atmospheric alert console sets its screen and plays its alert sounds when the alarms change, not when it is
  drawn (and its repeat sound is one keyed timer).
- **ID console.** An ID card used on it is op `insert_id` (then the window opens); "Eject ID Card" is op `eject` (operator's card first). Every
  change to the loaded card (access, assignment, name, account, dismissal, custom title) needs an authenticated operator and a card: pressing
  one with no card loaded is refused instead of a runtime. An unknown job and an invalid name are refusals. The access report no longer
  runtimes without an operator card ("Prepared By: Unknown"), the card's name is rebuilt by `update_name()` after every button, and the
  printer is a tracked state (no `SStgui.update_uis`).
- **Communications.** A login is the person's own (`logins`, per actor): someone else at the same console is not logged in by it. The
  announcement's signature is taken from the announcer's ID when they announce. Deleting a message deletes the message whose button was
  pressed (by its id), not whichever message is open when the confirmation is answered; a console's station-wide list cannot be deleted
  from (refused up front). The status display takes one of its presets (an enum; the dead "alert" branch is gone). The emag is the console's
  `emag()`; the module reads it (`routing_scrambled()`), and "Restore Backup" clears it, so the console and its window can no longer disagree.
  The shuttle-call grace periods are measured from the round's start (`ELAPSED(SSticker, round_start_time)`), not from server start, and are
  named (10 and 90 minutes; the old comment said 30).

## Telecommunications (rewrite/machines-full)

- **Running.** A node runs while switched on (`toggled`, tracked) and working: `STAT running` replaces the `on` var the machine step kept in
  sync (`update_power()` and the step are gone). Running, it hums (its sound loop is a declared starting occupant), heats its room with its
  traffic and lets its traffic decay every thermal step (`every(thermal_interval, when = STAT_RUNNING)`): a stopped node does no periodic
  work at all, and its look (`draw()`: the `_off` state) and hum follow `on_change(STAT_RUNNING)`. Traffic decays by its net speed once per
  step (the legacy step multiplied by the frames that had passed since the last one). A node's `STAT_OPERABLE` reads the machine's
  condition bits like any machine's.
- **The multitool window.** It opens with a multitool (the interface's input) and every button needs one (`req_tcomms_multitool()`; the
  legacy window closed itself through a `tgui_status()` override but its buttons still answered). The id, network, filter and the bus's
  frequency are `asks()` (the bus's question now defaults to its current frequency, not the network tag; 0 turns frequency changing off).
  Linking needs a telecommunications machine in the multitool's buffer (a requirement; the legacy link took any buffered machine), and
  unlinking a link index that is not there is refused. The relay's station lock is a requirement (it can lock only from the satellite or back
  from the station). The receiver's and the broadcaster's range is one op on the base (`ranged`), not two copies. The status line is
  `report()` over a tracked `temp`.
- **Repair.** Only nanopaste repairs a node, and only a damaged one (the legacy handler answered every item, doing nothing for most).
- **Servers.** A log entry from a signal with no speaker no longer runtimes (`M?.isMonkey()`). The log's size is its length: deleting an
  entry from the log browser frees its place (the legacy counter was never decremented, so a server whose entries were deleted dropped the
  wrong ones, or none, at its cap). The compiler and the server's radio are declared starting occupants.
- **The consoles.** The network monitor and the log browser share one set of entries (`tcomms_probe_console()`): scan (refused while the
  buffer is full), view, release, the network question, the status line, the emag (whose message lost its "You you"). The log browser's
  delete is a requirement (its access, or emagged) instead of a check inside the effect, and an index with no entry is refused. The traffic
  console keeps its legacy form; its network and status line now live on the console base.
- Magic numbers are named in `code/__defines/radio.dm` (TCOMMS_*).

## Fabrication: the autolathe, the R&D production machines and the exosuit fabricators (rewrite/machines-full)

The autolathe, the protolathe (and the department protolathes), the circuit imprinter and the exosuit and prosthetics fabricators share one
library capability, `fabricator()` (code/library/machine/fabricator.dm): the print button, its refusals, the print run, where prints drop, the
store's sheets button and item intake, and examine. A machine built from a board takes `board_machine()`, a dismantle graph (behind the open
panel a crowbar takes it apart into the frame, its board and its parts), in place of `maintenance_flags`. Behaviour tests:
`dq_mf_fab_behaviour.dm` (written green on the legacy code first).

- **Refusals are requirements, told to the person who pressed.** One run at a time, a design the machine knows (a hacked design only while
  hacked: the legacy protolathe built a hacked design it did not show), a design of its build type, every material slot filled, the store
  not on hold and the materials for the whole run. The legacy lathes said these aloud (`atom_say()`) from inside the effect and returned;
  nothing about the materials is spent either way.
- **The print run** is a keyed timer chain on the machine (`fabricator.print`) owning its run record, not an OM task (autolathe) or a
  DECLARE_REPEAT over loose vars (protolathe). It stops, and says why aloud as before, when the machine stops working (any reason: the
  protolathe used to keep printing while EMPed or broken), the power draw fails, the store goes on hold or the materials run out.
- **Where prints drop.** A drag of the machine onto a tile (by someone standing next to it, never while it prints) points it there; alt-click
  forgets it (the protolathe's examine always promised this; only the autolathe had it). One rule for every lathe: a blocked tile, wall or
  not, sends the print onto the machine's own tile (the protolathe dropped onto any dense floor that was not a wall). The exosuit fabricator
  keeps its own rule (a blocked exit holds the part) and has no reset.
- **The panel.** `panel()` with the wires behind it: a hand, wirecutters or a multitool at the open panel reach the wires (the autolathe's
  cutters and multitool did not, the legacy tool overrides never ran under the router), and the screwdriver that opens the panel shows the
  wires as before. The autolathe's panel does not open while it prints. The R&D machines' wrench (2 seconds, the panel shut) is `anchor()`.
- **The exosuit and prosthetics fabricators now have a panel and come apart with a crowbar** into their frame and board (they had a board and
  a panel sprite but no maintenance at all).
- **The store.** An item used on a shut machine goes through the store's own use gate (sheets in, a sheet snatcher, a multitool on a silo
  link), as the legacy attackby fall-through did; the panel's tools are not fed to it. The autolathe now takes sheets while it prints (the
  protolathe always did).
- **The exosuit fabricator's queue** runs on a part timer (`exofab_part`) instead of a polling machine step on `world.time`: the queue starts
  when it is started. Stopping the queue mid-part lets that part finish and drop (the legacy step stopped looking at a part once the queue
  was stopped, so it hung until the queue was started again). A part held for a blocked exit makes the queue wait for it (the legacy queue
  went on and a second held part replaced the first). Better parts rescale the part under way, as before.
- **The prosthetics fabricator's** species and manufacturer questions are `asks()` of their ops (the setting was applied only when the legacy
  window was still interactive). Its limb and species disks are timed ops whose corrupted-disk refusal is a requirement.
- **The window.** The autolathe and the fabricator declare their data's shape (`ui_shape()`, typed for TypeScript); the window shuts while
  the disable wire holds (as the legacy `tgui_status()` did) and its buttons are refused. A touch on a shut autolathe whose shock wire is
  live shocks (half the time) instead of opening the window, as before.
- Examine lines come from the capability (material cost, drop direction) and are shown at any range; the autolathe no longer says its panel
  is closed.

## Pipe devices: pumps, the regulator and the valves (rewrite/pipenet-full)

Pinned by `dq_atmos_m/pipes/*` in `code/modules/unit_tests/dq_atmos_pipes_behaviour.dm`. The shared controls are `pipe_device_window()`,
`pipe_device_switch()`, `pipe_device_max()` and `pipe_device_unwrench()` (`code/domains/atmos/pipe_device.dm`).

- **The window no longer swallows tools.** A wrench or a multitool on a pressure or volumetric pump opened its window (the window's hand op
  answered first, so the legacy `wrench_act()`/`multitool_act()` were never reached): the wrench now takes a stopped pump off (4 s) and the
  multitool lifts and restores the volumetric pump's limiter.
- **Pump windows** open for someone the pump's access lets in while it works; the ctrl-click switch and the alt-click "max output" are ops with
  the same access check (they were legacy click handlers). The switch says what it did.
- **The regulator** (passive gate) asks its target pressure and flow limit with typed prompts on its ops (the `atmos_scalar` prompts and their
  window callback are gone); its wrench is refused while its valve is open, as before.
- **Digital valves** (straight and three-way) turned for anyone: they inherited the manual valve's ungated wheel beside their own
  access-checked one. Now only someone their access lets in turns them, and only while they have power (the area's power, the NOPOWER bit).
- **Automatic shutoff valve.** Its wake is `wake_automatic_shutoff_valves(network)` calling each bordering valve's keyed `leak_check` timer
  (every valve for new construction), not an OM sleeper behaviour watching CHANGE_PIPE_LEAKS. `close_on_leaks` is tracked. A hand switches the
  circuit; an alt-click turns it by hand only while the circuit is off (refused with a reason otherwise, where it used to say so and do nothing).
- **Wrenches** of every converted device are ops with the 4 s wait (the three-way valve's and the manual valve's were 4 s through `use_tool`).

## Filters and mixers: trinary and omni (rewrite/pipenet-full)

Pinned by `dq_atmos_m/pipes/trinary_*` and `dq_atmos_m/pipes/omni_*`.

- **The wrench reaches them.** As with the pumps, the window's open op answered a wrench before the legacy `wrench_act()`: a filter or a mixer
  (trinary or omni) can now be taken off (4 s), running or not, as the legacy wrench allowed.
- **Windows and switches.** The trinary mixer's and omni mixer's windows are `interface()` + `ui_data()` + ops (no `DECLARE_UI`/`UI_ACT`); every
  filter and mixer window now opens for someone the device's access lets in (the mixers' did not check; an unlocked device lets everyone in, as
  before). The ctrl-click switch is the shared `pipe_device_switch()` op; on an omni device it still ends configuring.
- **The omni mixer's share prompt** is an `asks()` number on the `switch_con` op (the `atmos_config_review` request and its callback are gone for
  the mixer); it is not asked when no other input is free to take the rest (it used to do nothing).

## The pipe network core: gas_touched(), the connector (rewrite/pipenet-full)

- **`gas_touched(air)` is the one way to say a mixture changed in place.** `/datum/pipe_network/proc/mark_dirty()` is gone; its fifteen callers
  (the algae farm, the circulator, the injector, the pipeline's leak face, the network's external reservoirs, the machine service's pump commit,
  the generated station's utility fill, the gas thruster, the portables) name the mixture they changed. The network's `revision` still moves.
- **The engineered-material follow-up runs again.** A pipeline whose engineered pipes still had exposure work re-armed a five-second timer that
  only bumped the revision, so the follow-up pass never ran; it now marks the network for its engineered-material pass (`mark_topology_dirty()`).
- **The connector has no work of its own.** Its periodic step, its gas watch on the attached device and its MACHINE_WAKE/MACHINE_SLEEP from the
  portables are gone: the attached device's gas is a port in the network's Rust region, so nothing in DM needs to hear it change. Its wrench is
  `pipe_device_unwrench()`, refused while a device is attached or any portable stands on it (the latter used to fail silently).

## The outlet injector (rewrite/pipenet-full)

- **Its flow is a Rust device edge** (`push_to_rust()`, like the vent): `volume_rate` litres a second of its pipe's gas forced into its turf while
  it is piped, powered and on. Its DM machine step, its pump queue and the unary gas wake are gone; power_rating is what it draws, not a cap.
- **Controls are ops**: the hand toggle, the ctrl-click rate reset (only on a running injector away from its default), the multitool through
  `multitool_settings()` (tag, frequency, buffer; the `atmos_config_review` prompt chain is deleted), the wrench (`pipe_device_unwrench()`).
  A radio "inject" runs at once instead of in a `spawn`.

## Heater and freezer; the unary base's wake machinery is gone (rewrite/pipenet-full)

- **Heater and freezer work on `every(when = heating/cooling)`**, armed by their gas watch (`gas_watch()` on `air_contents`), their switch, their
  thermostat (`set_temperature` is tracked) and power changes (`reconsider()`); nothing polls and nothing calls MACHINE_WAKE. The heat itself is
  the thermal domain's `heat_pump` entry, as before. Their RPED is `part_replacement()`; the window opened by a hand is `interface()` alone (the
  legacy ungated `open_ui` interaction is gone).
- **The unary base** loses `register_gas_dependencies()`/`gas_wake_condition()`/`wake_from_gas()`/`invalidate_gas_dependencies()`, its
  `set_use_power`/`Moved` overrides, `step_has_work()`/`arm_wakes()` and the OM_FIELD_VIEW on `node` (now a plain `ref_one` relation);
  `piped()` is its one reader. No unary device is DM-stepped any more.
- `dq_hc_struct/cryo_cell_is_switched_through_the_window` read the cryo cell's old `on` var; it reads `cooling` (the cryo migration's state).

## Dual-port vent and heat exchanger (rewrite/pipenet-full)

- The dual-port vent's settings are plain `TRACKED` (no CHANGE_MACHINE_SETTINGS bridge: nothing DM-steps it), its look is `draw(look)` (it now
  reads `operable()` for "off" where it read the area's `powered()`), and its gauge is an `examine_line()`.
- The heat exchanger's wrench is `pipe_device_unwrench()` with its floor check as a requirement (4 s, as before).

## UI sweep: legacy windows to interface() and ops (rewrite/ui-sweep)

Converted by `tools/dx/codemods/ui_declare.py` (families of types together, parents first); hand fixes listed below. Pinned by the
focused tests of the touched windows (the tests that called a handler with its old signature press the button through `op_ui_act()`).

* **A button's guard runs in its handler.** A `ui_act_allowed()` override became `ui_gate(A)`, asked first by every handler of the type's
  family (`if(!ui_gate(A)) return FALSE`); a family with a guard on one subtype has a root `ui_gate()` that answers TRUE. A press the guard
  refuses is an op that did nothing, as before (no message unless the guard spoke).
* **Typed args through the schemas.** `UI_ARG_BOOL` is `bool()` (text "true"/"false" is refused, JSON booleans pass), `UI_ARG_PATH` is
  `schema_path()`, `UI_ARG_REF` is `schema_ref()` plus a check at the head of the handler that the ref is in its source (`contents` reads
  `contents_of()`); a ref the handler never null-checks is required (a button without it does nothing; before, the handler ran with null).
  `UI_ARG_CHOICE`/`UI_ARG_LIST` pass the raw value, checked in the handler (a choice no longer converts between number and text).
* **No new way to open a window.** An atom's converted window says `without("ui_open")`: it still opens from the type's own
  interactions (with their access, power and hand checks), not from a fallback click or a silicon's remote open. Pinned by the conversion
  pins (`code/modules/unit_tests/snapshots/pins/`, recorded before the conversion; only `keys:` changed).
* **The power sensor's data** is `monitor_data(user)`, the power monitor's focus (the sensor has no window), not an output of the sensor.
* **State rows.** A subtype's `DECLARE_UI_STATE` declares the inherited window again with `state =`; a parent's state goes to every window
  below it; `tgui_state()` falls back to the interface's state. The security console's state row was never read (its window is its camera
  module's, through `ui_redirect()`) and is gone.
* **Messages.** The ice cream vat's flavour and cone messages are `act_message()` (the actor reads "You ...").
* **The holodeck's AI override** is asked by how the press came (`A.authority & AUTH_REMOTE_ACCESS`), not `issilicon()`.
* **Ship consoles (helm, engines, sensors, disperser).** Their questions (navigation entry, coordinates, autopilot and thrust limits,
  sensor range, disperser settings) are `asks()` steps of the button's op instead of requests owned by the window; a window button's op
  stops when its window closes or stops being interactive (`/datum/pending_op/recheck_reason()`). A silicon toggles the sensors' overmap
  view over its link from anywhere it works the console (the distance check is a hand's).
* **Copier, fax, ore console, exosuit console, paper.** Their window questions are `asks()` steps: the AI's photo pick, the fax title,
  department and the "default title" check on an admin fax (asked before sending, as before), the ore setting, a beacon's message, the
  admin paper's send confirmation. The ore console's named setting is a number (`int(0, 3)`): the legacy text arg stored "1" instead of
  1. A text arg at the window boundary takes a number as its text (`schema_check()`), as the legacy parse did.
* **Plushie editor, shock collar tag, account terminal funds, shadekin flicker colour, particle editor type, filter editor colour,
  ColorMate colour.** Asked with `asks()` on the button's op; the filter editor's icon questions run as their own flow from the handler.
  The account terminal asks the amount only of a central command card, as before.
* **Communicator and instrument editor.** The communicator's name, ringtone, message and note, and the song editor's import and lines,
  are `asks()` steps. Cancelling the note question now leaves the note (it cleared it); a message is asked before the exonet check (the
  check still refuses to send). Answering "Yes" to keep editing an oversized song import ends it: the player presses import again (it
  reopened the paste box).
* **Library computers, mob spawner, feedback form, event manager, character directory.** Their questions are `asks()` steps of the button's
  op (the event manager's from the old `act_ask()` calls). The library upload confirmation is asked even with nothing scanned (the
  handler then does nothing); a feedback submission that is empty or too long is not confirmed (the handler says why). A guard in a
  handler that stood above its question now runs after the answer.
* **interface() takes the legacy window options**: `window_var = nameof(x)` (a window named by a var each subtype sets: the appliances,
  the inventory panel, a rig, the entity narrator), `autoupdate`, `pinned` (the lobby, the tooltip, the media player) and
  `preinitialized`. `ui_types` leaves a var-named window untyped.
## Pipes and the atmospherics base (rewrite/pipenet-full)

- A pipe's wrench and welder are ops: `unwrench` (1 s; refused under intact floor and while its gas pushes back; the "gush of air" warning as it
  begins and the throw past two atmospheres when it is done, as before) and `seal` (4 s, only on a fatigue crack). The `pipe_unwrench` tool job
  is deleted.
- A stable leak sleeps on two native gas watches (its pipe's gas and the room's) instead of an OM condition watch; Rust's change report wakes it
  and the same equalization test decides.
- The base type's engineered-material fitting and pipe-painter swallow are ops (`fit_material`, `painter`); a tank swallows any other item with
  an op (an engineered-material stack, the narrower binding, is now fitted where the tank used to swallow it too).

## The meter (rewrite/pipenet-full)

- **No machine step.** A gas watch on the mixture it reads (`watched_air`, which follows its pipe to a rebuilt network's mixture) moves its
  tracked `needle`; it draws with `draw(look)`; a radio meter sends when the rounded kPa changes. It left the machine pipeline's roster.
- Its tools are ops: the wrench (4 s, back to its item), the screwdriver (the panel, tracked `open`), the multitool (an open panel asks its tag
  with `asks()`, re-checked when answered; a shut one moves it to the next pipe on its tile). A hand or an AI reads the gauge (it was a `Click()`
  override); the gauge is an `examine_line()` (an AI reads it through its eye). The turf meter takes no tool (`without()`).
- Known unrelated flake while testing: `REFRESH DRIFT: /obj/machinery/computer/station_alert/all` (not atmos; left to its owner).

## Pipe construction: fittings, the dispenser, the pipe layer (rewrite/pipenet-full)

Pinned by the generated pins `snapshots/pins/obj.item.pipe*.txt`, `obj.machinery.pipedispenser.txt`, `obj.machinery.pipelayer.txt` and
`dq_atmos_m/pipes/fitting_fastens`.

- A fitting's use-in-hand (rotate), its "Flip Pipe" verb (now a menu op), its material liner and its wrench are ops; the wrench's tile check is
  a requirement with the old refusal texts (the shared init-direction cache is filled when the fitting is made, so the check only reads it). The
  meter and gas-sensor items fasten with wrench ops. `fasten()` is the one way a fitting becomes its device (the pipe layer calls it instead of
  faking a wrench `attackby()`).
- The dispenser's "put back" (a fitting or a meter item), its wrench (2 s to bolt, 4 s to unbolt, tracked `unwrenched`) and the disposal
  dispenser's drag-in are ops.
- The pipe layer's hand switch (empty hand only), its metal eject (asks yes/no with `asks()`), pipe recycling, steel loading, pipe-type choice
  (wrench), auto-dismantle and dismantle (crowbar) are ops; its RPED is `part_replacement()` and its status is an `examine_line()`.

## Portable pumps and scrubbers, the area air console, the stasis clamp (rewrite/pipenet-full)

Generated pins: `snapshots/pins/obj.machinery.portable_atmospherics.powered.*`, `obj.machinery.computer.area_atmos.txt`, `obj.machinery.clamp.txt`.

- **Portable pump and scrubber** work on `every(MACHINE_SERVICE_INTERVAL, when = on)` (the machine pipeline's portable stages are deleted);
  their looks are `draw(look)`; the window is `interface()` alone (the legacy ungated open-UI interaction is gone, and with it the ghost's
  "View" menu entry, as on the canister). EMPs and the power button no longer raise the machine channel by hand.
- **Huge pumps and scrubbers** (`huge_portable_controls()`): an empty hand says to use the console (it used to open the portable's window
  through the inherited `interface()`, a master bug); cells and tanks are swallowed; the wrench bolts it while off (the stationary one refuses:
  its bolts are too tight); the inherited window, cell, tank-bay and port ops are dropped. Their step is `every(when = on)`.
- **Area air console**: no MACHINE_WAKE when it switches the scrubbers (their `every()` follows `on`).
- **Stasis clamp**: its hand toggle (only while on a pipe), its drag-onto-yourself removal (3 s, refused while active) and the clamp item's
  attach (3 s, refused where a clamp already is) are ops; the OM timed tasks are gone. `open` is tracked.

## Phase C init and lifecycle codemods (rewrite/lifecycle)

The codemods are `tools/codemods/init_overrides.py`, `qdel_src.py` and `review.py` (the hand-review dump and decisions). Most of the change is
`ALLOW(init/CODE)` and `ALLOW(lifecycle)` reasons on overrides and self-deletes that stay as they are; those change nothing. The conversions that do:

* **Constant lights are light vars.** An `Initialize()` that only called `set_light(range, power, color)` with constants (12 spell, effect and snack
  types) is now `light_range`, `light_power`, `light_color` and `light_on = TRUE` on the type. A static light is lit when the thing materializes
  (`/atom/movable/on_materialize()`), not during `Initialize()`, so a latent instance carries no light source until it is materialized. A range
  between 0 and 1.4 is written as 1.4, the value `set_light()` raised it to. Turfs are not converted: a turf does not light itself from its vars.
* **Loaded exosuits list their equipment in `mecha_starting_equipment`** (Odysseus loaded, combat and shuttle pods, the death Ripley, the gorilla,
  the Scree phazon). The base `/obj/mecha` init attaches table equipment before it adds its radio, cabin, air tank and cell, where the overrides
  attached it after; no equipment's `attach()` reads those. Test: `dq_init_codemod/mecha_equipment`.
* **Storage boxes whose `Initialize()` only made their contents use `starts_with`** (the forensics boxes, dice, botany disks, NIFsoft boxes, two pill
  bottles, body record disks, the backup kit). The contents are latent until the box is used (C5) and `calibrate_size()` counts them; the old
  contents were made after it ran. A box mapped with `empty = TRUE` now starts empty, as the var says; the overrides filled it anyway.
  Test: `dq_init_codemod/storage_contents`.
* **A repainted cardboard cutout is `replace_with()`d** by the cutout type picked: made where the old one stands, as before, and handles that named
  the old cutout now resolve to the new one.
* **Mech equipment destroyed with its exosuit goes with `expire(0)`** instead of a bare `spawn` before `qdel()`: the delete is a timer owned by the
  equipment, run after the current call returns, as the spawn did.
* **qdel(src) is banned** (`qdel_src` lint, hard ban): every self-delete is a verb or carries an `ALLOW(lifecycle)` reason. Converted to
  `replace_with()`: a cut-apart closet (steel), the singularity generator (its singularity, or the particle smasher once installed), a box
  crumpled into its trash (then put in the user's hands, as before).
* **Bare `spawn` is counted by the scheduler lint.** The shuttle turf's breaklight refresh is `after(src, 0)` (a turf changed meanwhile drops
  the timer, which replaces the type check), a suffocating carbon gasps at once (the other gasp branch never spawned), and a toxin-loaded
  human vomits on `after(self, 0)`.
## Items, structures and effects: tool procs, interactions and hits to ops (rewrite/items-structures)

Codemods `tools/codemods/` (tool_act, interaction_datums, damage_reaction; `run_items_wave.sh`) and `tools/dx/codemods/interact_declare.py`
(now translating `REQ_*` clauses to `needs()`), over code/game/objects and code/game/turfs. Pins: `snapshots/pins/obj.*` recorded first.
- **Tool procs are ops** (`op("use_<q>", tool(TOOL_Q), wait(0), then(PROC_REF(<q>_used)))`): instant as before, the welder spends no profile fuel.
  They now appear in the menu and screentip as "Use screwdriver" etc. (the legacy procs were invisible there). A legacy
  `ITEM_INTERACT_BLOCKING` (used up, nothing done) is a committed op with no effect (`OP_OK`): the actor sees the same thing, the op is logged
  and published as done. `SKIP_TO_ATTACK` and falling off the end decline, so the click still goes on to the attack.
- **A tool or held item now reaches the type before its window**: where a window's open op (`ui_open`) used to answer every held thing first
  (the janitorial cart, the tank dispenser), the converted item/tool op answers, as the old attackby did; its decline falls back to the window.
- **Menus follow the op engine**: an item op is listed only while its item is held (no greyed "needs a ..." rows), a self-use only while the
  thing is in hand, a drag only on a drag; screentips name the op instead of "nothing". Labels keep the legacy wording ("Use", "Alternate use",
  "Insert a ...").
- **EMP reactions that never blocked run after the hit** (`on_notice(/datum/notice/hit/emp)`), as the consoles' did; blocking ones are
  `extend(/datum/act/hit/<x>, instead(then()))`.
- Types left for a hand conversion, and why, are listed in `tools/codemods/exclusions.txt`.
## Body migration, slice 1: wounds, bleeding and blood on the body clock (rewrite/body-full)

Pinned by `code/modules/unit_tests/dq_body_rate_pins.dm` (green on the old code first; numbers below are old -> new over the pin's span).
Wound healing, bleeding, arterial tears and blood refill are rates integrated over the time that passed (`code/modules/body/body_clock.dm`),
run by one `every(LIFE_CYCLE)` per human gated by `body_clock_active`; the Life stage `blood` and the limb's `update_wounds()` are gone.

* **No per-tick rounding.** Autoheal was rounded to a tenth per update ("prettier on scanners") and the whole-body external bleed to a tenth per
  cycle: a lone dressed wound now heals 0.25 a cycle (was 0.3 rounded; the old pipeline ran it a little more often still: a dressed 8-point cut was
  4.0 after ten cycles, now 4.75); a 20-point arm cut bleeds 20/35.01 = 0.571 a cycle (was 0.6). Pins: external bleed over five cycles 2.106 -> 1.991,
  arterial tear 2.100 -> 1.725 (tear 20.5 -> 20.4), refill over ten cycles 1.0 -> 0.9.
* **The first step comes one cycle after the clock starts** (the every() arms one interval after it is raised), so the first cycle of a fresh wound or
  draw is integrated at the second step; totals over a span are one cycle behind, never ahead. A 5-point cut bleeds one cycle longer in the pin.
* **A healed wound fades ten minutes after it was made**, by a timer. Before, a wound healed to 0 on a limb with nothing else to process was never
  removed (the limb stopped being processed); the pin records it gone after 11 minutes.
* A salved wound's per-cycle 2% disinfection chance is 2% per cycle of elapsed time (same rate).

## Body migration, slice 2: stance, grip and damaged limbs (rewrite/body-full)

Pinned by `dq_body_rate_pins.dm` (`lost_leg_collapses`, `broken_arm_drops`, `splinted_arm_holds`, `trauma_fractures`; green on the old code first).
`bad_external_organs`, `recheck_bad_external_organs()`, `need_process()` and both `last_dam` vars are gone; `H.damaged_limbs()` is a query.
The stance is derived when a limb changes (`code/modules/body/limb_state.dm`); the periodic limb checks run in one `every(LIFE_CYCLE)` gated by
`limb_trouble`.

* **The stance follows an amputation at once.** Before, the organs stage idled once no limb needed processing, so a clean amputation left
  `stance_damage` 0 (no slowdown, no collapse) until something else woke the stage; the pin now reads >= 4 straight away.
* **A splinted fracture is not broken** for grip and stance. `is_broken()` rolled `prob(30)` on every read of a splinted fracture (so a splinted leg
  still counted as broken about a third of the time, and a splinted arm could still drop what it held); now a splint in place holds.
* The broken-bone jolt while moving stops at the first limb that jolts in a cycle (was: every broken limb rolled its 10%).
* Open wounds getting dirtier while you move ran per organs cycle for processed limbs; it is now part of the body clock (same 1 germ per cycle).
## The algae farm (rewrite/pipenet-full)

Pinned by `dq_atmos_m/pipes/algae_farm_converts` and the generated pin.

- It works on `every(when = working)`; `working` (tracked) is reconsidered when its switch, its power, its stores (loading, ejecting) or its
  input's gas change (a gas watch on `air1`, composition). The OM derived field, the periodic declaration, the OM watch and MACHINE_WAKE are gone.
- Its RPED is `part_replacement()`, loading materials an op. The "you cannot insert this item" catch-all is gone: an op answering any held item
  would take the screwdriver and the crowbar from the machine core's panel and deconstruction (ops answer before the legacy interactions), so
  another item is now what the machine core does with it.

## Thermoelectric generator and circulators (rewrite/pipenet-full)

- **The TEG works on `every(when = generating)`.** `generating` (tracked) is reconsidered when its bolts, its circulators, its power or its loops
  change; asleep, it holds native gas watches on its circulators' four mixtures (pressure) and wakes when either loop has a head worth turning.
  The periodic declaration, the OM watch, MACHINE_WAKE and `SSmachines.hibernate_generator()` are gone; it left the machine pipeline roster.
- Its window is `interface()` with a requirement (bolted down and working), so a hand on a loose or dead TEG is refused with a reason instead of
  doing nothing; it no longer reconnects its circulators when the window opens (the wrenches and the map load do). Its look is `draw(look)` from
  a tracked `lastgenlev`; the circulators' hot/cold overlays are set when the level changes, not from inside the TEG's appearance proc.
- The circulator's and the TEG's wrenches are ops; the circulator's "running" display times out on a keyed `after()` (was `om_after_replace`),
  and its look is `draw(look)` from a tracked `run_state` and `temperature_overlay`. The TEG joins `REGISTRY_TURBINES` with `membership()`.



## Power plants: the supermatter (rewrite/power-plants)

Pinned by `code/modules/unit_tests/dq_power_plants_behaviour.dm` (`dq_pp/sm_*`), green on the legacy code first.

- **No machine step.** The crystal's reaction is `every(MACHINE_SERVICE_INTERVAL, then(PROC_REF(sm_step)))` (2 s, as the pipeline frame was);
  it left the machine pipeline's roster. Off a turf it skips the step (it used to stop stepping for good on a null loc; a crystal with a null
  loc never comes back, so nothing changes in play). Cadence pin: 5 steps in 10 s, before and after.
- **The exhaust is a gas reaction in Rust** (`GAS_REACTION_SUPERMATTER`, `SUPERMATTER_THERMAL_RELEASE` = 10000 J per unit of device energy,
  `verdigris/domains/gas/src/reaction_energy.rs`). Before, DM added the phoron and oxygen with `adjust_gas()` (the new moles arrived at the
  mixture's temperature, so they brought their own heat) and then `heat_add()`ed the release. Now the reaction keeps the mixture's energy over
  its new heat capacity and adds the release, so the exhaust carries no free heat: at power 500 in 500 K oxygen the step adds 5.50 MJ, where
  it added 5.54 MJ (the 0.37 mol of phoron and 0.05 mol of oxygen at 500 K were the 37 kJ, 0.7%). Power, damage and the gas amounts are
  unchanged (pins: `sm_energy_curve_*`, `sm_damage_*`, `sm_gas_release`). The 10000 K cap stays a `heat_set()`.
- **Touch, item touch and bump are ops and a notice** (`touch`, `touch_item`, `on_notice(/datum/notice/bumped)`); the legacy interaction table,
  the cyborg "Use" interaction and the `Bumped()` override are gone. What a player sees: a plain click with an empty hand or anything held
  touches the crystal (the pin's "click: nothing" became "Click: Touch"; that is what the legacy click did in play, the pin harness did not
  run the legacy click); a cyborg beside it touches it with its empty hand (as the legacy "Use" did when adjacent); a silicon at range and the
  AI open the monitor window through `interface(..., input = remote())` (was the robot interaction's `tgui_interact()` and `silicon_use`).

## Power plants: the singularity, its containment, emitters, collectors and the particle accelerator (rewrite/power-plants)

Pinned by `dq_pp/sing_*`, `fg_*`, `containment_field_*`, `emitter_*`, `collector_*`, `particle_*`, `pa_*`; green on the legacy code first, every
number unchanged (size thresholds, dissipation 1 per 11 steps at stage one, field draw 2750 W alone and 8500 W linked with 3 fields, the 250 kJ
store cap, 64 kJ per emitter shot in bursts of four, collector output moles x strength x 20 W).

- **No machine pipeline, no PERIODIC lanes.** The singularity (and Nar-Sie, the cascade rift and the energy ball) steps on its `every(2 s)`
  (`singularity_frame()`), field generators and emitters on `every(MACHINE_SERVICE_INTERVAL, when = ...)`, the control box emits on
  `every(..., when = active)`, particles fly on `every(0.1 s)`. The singularity generator collapses at the drain after a particle brings it to
  200 (`on_change(nameof(energy))`), not on the next 2 s frame.
- **Containment-failure alert fixed.** `cleanup()` looked for singularities in `REGISTRY_MACHINES`, where none ever were, so the admin
  "SINGUL/TESLOOSE!" alert never fired; it now reads `REGISTRY_SINGULARITIES`. A field generator next to the map edge no longer runtimes
  raising its fields (it stops at the edge).
- **Field generator warm-up** is a keyed `after()` chain (two 5 s stages, the fields at 10 s, as before); switching off cancels it and the
  warm-up overlay goes with it (it used to stay on the dead generator).
- **The bolt-and-weld ladder is a library capability** (`floor_weld()`, `code/library/machine/floor_weld.dm`) for emitters and field
  generators: wrench instant, welder 2 s, refused while running; same messages.
- **Locks are `lock()`** (emitter, collector; no alt-click): the ID swipe toggles `LOCK_LOCKED`, an emag shorts it open for good (`emag()`),
  the collector locks only while active. `activate()` and the remote emitter button read `lock_locked()`.
- **The particle accelerator parts and control box are on a construction graph** (loose, bolted, wired, closed; `pa_stage()` is the old
  number). Opening a closed control box's panel now also powers it off (it stayed idle before). Parts and boxes rotate through the
  `rotatable()` menu instead of granted verbs.
- **The singularity generator** anchors with `anchor()`, opens with `panel()`; the screwdriver's two flavour waits (3 s then 8 s) became an
  examine line while the panel is open; installing the super I/O coil is a 30 s op.
- Pins: clicks the legacy harness showed as "nothing" (field touch, collector toggle) now name their op; the emitter, collector and parts lost
  the "Repair/Load/Wire (refused: needs ...)" rows for items not held (the menu offers an item op only when that item is held).
- Mecha UI: the window helpers' tgui parameters are renamed so the body's `state` reads the mech's maintenance state again (before this, the parameter shadowed it).
- Lobby "Observe": the confirmation is now an `asks()` step on the observe op and opens only once the round has finished setting up. The handler still checks login holds and the round state when the answer comes back.
- **Emags on items are the emag library** (`emag(then(PROC_REF(on_emag)), repeatable =, powered = FALSE)`): a sequencer that
  works now also says the library's "You subvert X with Y" line, and pays one use (the legacy handlers' counts were 0 or 1).
  A handler that did nothing declines: the card goes on to its other uses. The defib kit works its paddles' emag by key.
- **Timed tool uses are op waits**: the vehicle cage (wrench 6 s, cutters 7 s) and salvageable wrecks (crowbar 17 s) say a
  begin line to the user as well as onlookers, and the wait scales by the tool's speed as every tool op does.
- **The window tint button's cutters**: with the panel shut they go on to the legacy tool handling instead of being swallowed.
- **The portable sign asks its direction as an op step** (`asks()`), so the question is the op's and the answer is re-checked.

## Lifecycle forms (rolls, params, registries, adjacency, endings, input)

The nine forms of `code/engine/lifeforms/` (final_api.html section 6 "Lifecycle forms"; tests `dq_lifeform_*_tests.dm`) and the codemods that moved
`Initialize()`, `qdel(src)` and `usr` sites onto them.

* **Random per-instance values are seeded.** A `rand()`/`pick()`/`prob()` an `Initialize()` drew from the world RNG is a `rolls()` entry drawing from
  the instance's own stream (the round seed with its map position, or its creator's stream). The distributions are the same (`range_of(a, b)` is
  `rand(a, b)`, `pick_one()` is `pick()`, `pick_weighted()` is `pickweight()`, `chance(p)` is `prob(p)`, `PIXEL_JITTER(n)` is each pixel offset in
  `rand(-n, n)`); the realisation differs: the same round seed rolls the same map, and the world RNG no longer advances for them.
* **A rolled value is suppressed by a map edit or a given param.** The old overrides re-rolled a var even where the map set it (a mapped `icon_state`
  of a random rock was overwritten); a roll now leaves a value that differs from the compiled default alone.
* **Rolls run before the type's own init code.** An override that rolled after `..()` rolled after the capabilities initialized; a capability whose
  `on_holder_init()` read a rolled var now sees the rolled value instead of the default.
* **Constructor arguments are set before init.** A `param(pos = N)` writes the positional argument in `/atom/New()`, before the root of `Initialize()`,
  where the override wrote it after `..()`: init code between sees the value instead of the default.
* **Contents made by `contains()` are created in nullspace** and moved in with the capabilities' init, as `starts =` already did: a content's own
  `Initialize()` sees no loc.
* **Every ending publishes `/datum/notice/ended` with a cause** (when something listens), and the endings the verbs make record it: `expire()`
  is `END_EXPIRED`, `replace_with()` `END_REPLACED`, `consume()` `END_CONSUMED`. Nothing listened to an ending before, so no behaviour changes.
* **A `lives_while()` scope ends its holder when the scope ends** instead of the host's `on_destroy()` deleting it: the order changes (the holder
  ends in the host's first destroy step, before the host's links are cleared) and the holder's ended notice says `END_OWNER`.
* **Input handlers take their actor from the input.** A converted `Click()`/`MouseDrop()`/`MouseEntered()` override read `usr`; the generated native
  override reads it once and hands the handler `A.actor`. An admin or callback path that set `usr` by hand runs under `with_actor()`, which restores
  the previous `usr` even when the callback throws (the hand-written swaps left it set).
- Laptop vendor: the legacy handlers' tgui `state` parameter shadowed the vendor's order state, so "pick device" always refused and the hardware buttons were open in every state. The handlers now read the vendor's own order state.
- Ticket windows: the data helpers no longer shadow the ticket's `state` (the panel shows open/resolved/closed again). "New ticket" asks its questions (ckey, text, level, and duplicate only when the player already has a ticket) as `asks()` steps before the handler runs, so an offline ckey is reported after all the answers instead of after the first. "List tickets" is an `asks()` step.
- Circuit export window: its data reads the assembly's data through `tgui_data(user)`.
## The gas turbine and its motor (rewrite/pipenet-full)

Pinned by `dq_atmos_m/pipes/turbine_spins` and the generated pins.

- The turbine works on `every(when = spinning)` (bolted, whole, and spinning or with a head across it); asleep it watches its two sides with
  `gas_watch_many()` (the shared multi-mixture watch, also used now by the TEG and a pipe's sleeping leak). The motor works on
  `every(when = converting)`, which the turbine's step reconsiders instead of MACHINE_WAKE. OM derived fields, the periodic declarations, the OM
  watch and the `ownership()` table proc are gone; both left the machine pipeline roster. Their wrenches are ops; the turbine's look is
  `draw(look)` from tracked `driven` and `speed_band`.
- **Bug fixed:** after a stroke the turbine handed its input side `remove(volume_ratio)` (0.2 moles) instead of `remove_ratio(volume_ratio)` (its
  share by volume), so nearly all the gas was dumped to the output and the head flipped. Its two sides now settle at one pressure.

## The thermoregulator (rewrite/pipenet-full)

- It works on `every(when = regulating)`: on, bolted, on the grid and its room a degree or more off its target. A gas watch on its room's air
  (temperature), its switch, its target (tracked `target_temp`) and moving it reconsider; the OM watch, the periodic declaration and MACHINE_WAKE
  are gone, and it left the machine pipeline roster. The heat itself stays the thermal domain's `heat_pump`.
- Its hand switch (empty hand), wrench and multitool target (an `asks()` number in degrees C) are ops; a hand on an unbolted one is refused with a
  reason (it did nothing). The Southern Cross and Cryogaia regulators keep their own step and wrench (the Cryogaia one's message is the shared
  one). Its look is `draw(look)`; its display is an `examine_line()`.

## Heat-exchanging pipes (rewrite/pipenet-full)

- An HE pipe's DM work is only what Rust does not do: a body lying on it (heat equalize and the burn) and its glow. It works on
  `every(when = tending)` (a body on it, or its glow more than 10 K behind its gas above 500 K); asleep, it watches its pipeline's gas with
  `gas_watch_many()`. Its pipeline joining, a buckle, a move and a disconnect reconsider. The OM watch, the machine step and its roster entry are
  gone; the dead leak branch in the step is gone (HE pipes cannot leak). The exchange itself stays the shell's heat body and the sky link.
- Its watch is on every change of the gas, not temperature alone: a heat-domain write to a pipe region (`heat_set`) does not report a
  temperature-only change to a gas dependency watch (reported to the thermal owner).

## Air system debug panel and the network core leftovers (rewrite/pipenet-full)

- The air system's debug panel (`SSair`, "Debug Atmospherics") is `interface("AtmosControlPanel", rights = R_DEBUG)` + `ui_data()` + ops; the
  `DECLARE_UI`, `UI_DATA_REPLACE` and `UI_ACT` rows are gone. "move-to-target" takes the turf's ref and locates it in the op.
- The base `/obj/machinery/atmospherics/machine_step()` is deleted (no atmospherics device is stepped by the machine pipeline any more), the
  pipeline's MACHINE_WAKE of each pipe on joining is gone (HE pipes reconsider on their `parent`), and the engineered-material follow-up timer is
  checked with `after_left()` instead of `om_timer_slot_pending()`.
- **Object verbs keep their legacy base requirements** (reach and an actor who can act: `needs(req_adjacent(), req_capable())`
  on a converted `INTERACT_VERB` that is not `carried()`); a ghost now sees them greyed out instead of not at all.
- **`interaction_pass` specs are ops with `passes()`** (the flesh and transit turfs, solid rock, the skipjack wall): the click is
  handled and goes on, as before.
- `interface(pressed = PROC_REF(x))`: a holder reacts to every button pressed in its window, its own ops' and the forwarded ones. The PDA's click, fingerprint and clown honk use it; before this they ran in its `ui_act_allowed()`.
- PDA power app: forwards to its power monitor through `interface(null, forwards = nameof(power_monitor))`.
- PDA status display, notekeeper, contracts; borg hypo recipe save; wiki donation; secrets menu: their questions are `asks()` steps. The status lines, the red-contract opt-in, the vetting question, the recipe-overwrite question and the shuttle-jump transition questions open only when they apply (`when =`). The wiki pin question now opens for any human's donation while the terminal works, and the handler uses the pin only for a card that needs one. The secrets menu's questions are now asked of the pressing admin's mob instead of their client.
- Spellbook: `choose_spell()` no longer takes the unused params/window.
- Wiki crash prank: the fake ads go to a silicon's remote press (`AUTH_REMOTE_ACCESS`) instead of checking `issilicon()`.
- Fishing program: dropped a dead UI_DATA_REPLACE row whose helper did not exist.

## Lifecycle forms, second pass (rewrite/lifecycle-forms-2)

- The endings codemod's heuristic picked a wrong cause for about 330 sites; `tools/codemods/ending_fix.py` re-caused them from a reviewed
  list. Only the ended notice's `cause`, `by` and `detail` change: no content reacts to the cause yet, so drops, logs and messages are as
  before. The reviewed state is `tools/ci/ending_causes_snapshot.txt` (`ending_sites.py --update/--check`).
- Three verbs join spent/consumed/destroyed/dissolved: `lapsed(thing, by)` (END_EXPIRED now: a status effect's duration, a capped history,
  an animation or flash), `replaced_by(thing, successor)` (END_REPLACED for a transformation whose successor the caller already made: mob
  transforms, evolutions, soulstone constructs, organ and limb swaps, a turf change) and `ended_with(thing, owner)` (END_OWNER for an
  owner's teardown: `on_destroy()` loops, a container's leftovers, windows and huds whose host is gone).
- Digestion, stomach acid, cleaning reagents and acid melting are `dissolved`; eating, feeding, grinding, recipes and machines that take an
  item in are `consumed` with the taker as `by`; explosions, burning and crushing are `destroyed` with a detail (`"explosion"`, `BURN`,
  `BRUTE`, `"emp"`, `"rcd"`, `"deconstructed"`). `create_*`, `*treat*` and `*feature*` procs were "consumed" by a substring match of "eat";
  they are `spent` (a discarded temporary) or `replaced_by`.
- Rolled at creation (`rolls()`, seeded; the distributions are unchanged): the hallucination decoy's report, tabloids, target paper, cig
  butts, the advanced gift's chaos roll, random umbrellas and towels (`R.hex_colour()`), tilted duffle bags, first-aid kit looks, prybars,
  junk mail, bar signs, the animal crates' contents, trash piles, hawaiian shirts, extraction points, kittens, eclectus parrots, kururak
  instinct, the rare frog (a new `rare` var), gelatinous cubes (`R.saturated_colour()`), autocloners, crystals and greytide gear.
- A generic arcade cabinet rolls its board before init and becomes that machine right after its init (`after_init()` + `replace_with()`),
  instead of deleting itself from inside Initialize(); an adventure box that rolls `discarded` is spent right after its init.
- Native input with an actor: the HUD's screen objects, alerts, radial slices, ability and spell buttons, the rig/mech air toggles, the
  click catcher, the SDQL2 stat buttons, the changeling ID card, movable screen objects and action buttons (`drag_onto()`, new
  `drag_over()`), IV drips, feeders, roller beds, hoist hooks, observer ghosts, overmap ships, mob holders (`drag_onto()`) and the palette
  and environmental message tooltips (`tooltip()`) read their actor from the input. A drop handler that went on to the native parent now
  runs before the parent's MouseDrop instead of after it. A handler that falls through (INPUT_FALLTHROUGH) no longer runs a second time
  when the fall reaches a parent type's generated override (`input_falling`, `input_fell()`).
- A null positional constructor argument no longer overwrites a param's var (the old overrides' `arg || default`).
- Smoothing is adjacency(): walls, low walls, tables, catwalks, windows, bay grilles, sandbag barricades and retention fields share
  ADJ_KIND_SMOOTH, each joining what its connects proc accepts (walls take walls of a blending material and the low walls they join;
  structures the anchored structures they connect to). The index tells every member whose neighbours changed, so a removed table,
  catwalk or wall now redraws its neighbours (before, they kept joining the gone piece, pinned by dq_smoothing_pins), placing and anchoring
  reach them too, and the hand propagation (update_connections(1) in Initialize/on_destroy, the low walls' and bay grilles' after-init
  connect, windows refreshing nearby tables) is gone. A map load recomputes each member once when the batch closes
  (BATCH_WORK_ADJACENCY replaces the wall smoothing batch). The look of a placed layout is unchanged (the pin's placed rows).
- More native input reads its actor from the input: the vitals monitor, the backpack-style packs (defib, shield generator, bluespace
  radio, proton pack, medigun), the cup on a cooler, a mob dragged onto its dragger (`drag_onto()`), the mob nametag tooltip (`hover()`),
  the debug and ticket stat buttons and the rig stat buttons (`click_on()`). Admin rights checks with an actor in scope read its client
  (`admin_require(client, rights, entry)`) instead of the deprecated usr-reading `check_rights()` (28 sites).
- Constructor arguments are params (`param(pos =)`); the work an argument drove runs through the param's setter (`apply =`) at the root of
  init, where the old override ran it after `..()`: before its parents' code after `..()` rather than after it. A value only built from is
  `keep = FALSE` (a mob a holder takes in, the victim of a grab, the construct a bin is built from, a mob's predecessor). A construction the
  setter refuses (a grab with no victim in reach, a shield wall between inactive generators, a field by a diffuser) is spent at init instead
  of returning INITIALIZE_HINT_QDEL. Converted: mob holders, farmbots, protean buttons and rigs, overmap mob markers, jellyfish, spores,
  commlinks, bluespace rifts, engine exhaust, pointers, magnetic bores, dominated brains and prey, grabs, NIFs, AR souls, ship landmarks
  (a visiting landmark now lives_while() its master), paper and paper planes (their offsets rolled), graffiti (its scrawl rolled), magazines,
  broken guns, projectile guns, blobs and their cores, chunks and overminds, samples, fake attackers, produce, slices, seeds, vines, vine
  soil, circuit cameras, emissive blockers, stacks, alloys, shovels, resonance fields, battery modules, hoists, drop pod doors, conveyors,
  disposal parts and bins (the construct is consumed), debris and dust, infomorphs, shields, boats and oars, quad bikes, digestion remains,
  finds (rolled when not given) and strange rocks; silicons, AIs, humans, teppis, mice and slimes take their arguments as params and keep
  an Initialize() for the rest.

## Atmospherics looks (rewrite/pipenet-full)

- Every `APPEARANCE_TEMPLATE`, `DECLARE_APPEARANCE` and `DECLARE_APPEARANCE_PROC` in the pipe network and its devices is a `draw(look)` with
  `drawn_from()` reads: valves (`open` is tracked), three-way and shutoff valves, trinary and omni filters and mixers, the heater and freezer,
  the heat exchanger, the injector, the pumps (the overclock overlay drawn from its icon), the regulator (`flowing` is tracked), the algae farm,
  the tanks (a `tank_state` per gas), simple, manifold, four-way and universal pipes and the pipe vent. The looks read `operable()` / the NOPOWER
  bit where they read the area's `powered()`.
- A look has no underlays: manifolds and universal adapters build their pipe stubs in `update_underlays()` (also when a floor tile over them
  changes, through `hide()`), and the omni devices set theirs when their port icons change. No appearance proc writes `icon_state`, `dir` or
  `underlays` as a side effect any more.
## Body migration, slice 3: internal organs on the organ clock (rewrite/body-full)

Pinned by `dq_body_rate_pins.dm` (`liver_toxin_overload`, `kidneys_clear_toxin`, `healthy_organs_idle`; green on the old code first).
Every organ's `periodic_step()` is `organ_tick(cycles)`, run by one `every(LIFE_CYCLE)` per human gated by `STAT_ORGANS_ACTIVE` (held while an
organ has work); the Life `organs` stage, `process_organs()` and `PROCESS_ACCURACY` are gone. Loose organs keep one cycle per periodic step.

* **Burst work became per-cycle rates with the same mean.** The liver's every-tenth-cycle strain (x10) runs every cycle (x1); the spleen's
  every-20-cycles work fires with chance cycles/20 per step; horror organs' `life_tick % N && prob(p)` events are `prob(p * cycles / N)`; the
  horror heart's 1u spaceacillin every 60 cycles is 1/60 u a cycle. Kidneys, spleen and Unathi organs that applied x10 every cycle keep it
  (`ORGAN_LEGACY_BURST`).
* **Liver strain under heavy toxin load is 0.2 a cycle** (was 2.0 every tenth cycle): the pin's twenty cycles cost about 4 (old run 5.65, the
  bursts landing with other random liver harm).
* **Kidney clearance is a rate:** load x 0.02 a cycle under a tenth of endurance (was prob(load) of 1-3, the same mean). Pin: 8 toxin load
  falls to below 8 within thirty cycles (old run 8 -> 6.6).
* "Force an update so we start processing the internal bleeding" calls are gone: adding a wound raises the body clock itself.

## Body migration, slice 4: germs as rates; pain messages on the body (rewrite/body-full)

Pinned by `dq_body_rate_pins.dm` (`antibiotics_clear_germs`, `necrosis_kills_limb`, `hurt_limb_pain`; green on the old code first).
Germ procs take `cycles` (`handle_germ_effects`, `handle_antibiotics`, `handle_rejection`, `update_germs`, `handle_germ_sync`); the Life `pain` stage
is `pain_step()` on an `every(LIFE_CYCLE)` gated by `STAT_PAIN_FELT` (held while the body carries afflictions).

* **Germ growth is exponential by rate**: germ_level / 600 a cycle above half of level one without antibiotics (was prob(germ_level / 6) of +1,
  the same mean); level-three growth 7.5 a cycle (was rand(5, 10)); antibiotic clearance and every spread step scale by the elapsed cycles.
* **Transplant rejection** grows `rejecting` by elapsed cycles and spreads its every-tenth-cycle germ and toxin bursts over each cycle at the same mean.
* **Chemical traces** on limbs fade 0.1 a cycle (was 1 every tenth Life tick).
* **The clocks integrate at most one step**: a body clock that was parked and starts again does not integrate the time it slept (fixes a
  first-step overshoot found while pinning).
* `life_om/derive_and_present` and `life_om/npc_vision_follows_inputs` fail on master before this branch's first body change; not touched here.
- Board games: UI_SUBACT rows are plain procs; each game routes its "game_action"/"setup_action" message with a `game_subaction()`/`setup_subaction()` dispatcher whose arguments go through schemas (`payload_args()` in code/engine/parts/inputs.dm). "Invite player" is an `asks()` step whose choices are the players the inviter sees. Pinned by interim_board_game_subactions.
- Schemas: at the input boundary, `num()`/`int()` read numeric text ("3") as a number, as the legacy UI_ARG_NUM did. NaN is refused.
- Preferences: the window is `interface(... forwards = nameof(middleware))`. Each preference editor routes its own actions with a `handle_action()` override whose arguments go through schemas (`payload_args()`), replacing the UI_ACT/UI_ACT_PREF_PROC table. "Reset slot" asks its two questions as `asks()` steps (the second only after a "Yes"). The colour pickers ("set_color_preference", the setup's "dq_pick_color") are `asks()` steps whose answer the handler writes. A preference the client may not write still refuses after the picker answers. The middleware's window data reads its window with `SStgui.get_open_ui()`. Pinned by interim_preference_editor_actions and the loadout tests.
- **Silicon uses are `remote()` ops** (`INTERACT_SILICON`; `INTERACT_ROBOT` adds `when(req(/mob/living/silicon/robot, of = ON_ACTOR))`).
  The curtain, the simple doors and the mirror: a cyborg beside it uses it (`needs(req_adjacent())`); the AI is not offered what it could
  not do. The fire axe cabinet asks the actor's kind in its ops' `when()`, not in its handlers. The resin door replaces the base door's
  hand and item with `without()`; its tear (combat mode) and its pull have disjoint stances.
- The i7 interaction snapshots of the converted types are re-blessed (their legacy ids are ops now).

## Mob Life on the kernel's Life sequence (rewrite/om-life, L1)

Pinned by `code/modules/unit_tests/dq_life_om_tests.dm` (ported from the pipeline to the sequence in the same commit) and the medical, body,
form, robot and vore tests that run Life frames.

* **A wake wakes the steps that read it, not the whole mob.** The pipeline's unpark woke every stage of a parked mob; the sequence clears the sleep
  bits of the steps whose reads the change names (CHANGE_MOB_STAT, CHANGE_MOB_CLIENT and CHANGE_EXPLICIT still wake every step, LIFE_WAKE_ALL).
  The rest stay asleep until their own reads or rewakes. Fewer steps run after a wake; none that has work is missed (the audit still runs).
* **A woken step asks should_run() before it runs** (a rewake does not). The pipeline ran a woken stage once and then asked idle(). Steps whose
  rule was "nothing to do until woken" (voice, fall, visible name, pulse, simple mob vitals, AFK, ambience, germs) are declared `once = TRUE`: a
  wake by one of their reads runs them once, as before.
* **Trait steps attached before the mob materialized now run.** `om_stage_add()` returned early for a mob whose Life pipeline was not attached yet,
  so a trait state attached during Initialize never ticked; the mob's `on_materialize()` now adds every attached state's steps.
* **The step profile is per step, not per mob type.** The mob service's two-minute report logs `MOB_STEP_PROFILE` lines (sampled cost per Life
  step) and `MOB_PARK_SUMMARY`; the per-type `MOB_PROFILE` lines are gone (the sequence samples per step).
* Stasis still slows biology, not the frame: the sequence runs on world time and `begin()` advances the body's stasis counter, as the pipeline did.
  Moving Life onto `CLOCK_BIO` (AFK, ambience and grabs slowing in stasis too) is left for the Life state slice.
- Vore panel: the belly settings are sub-actions routed by `vore_nested()` (refused without a selected belly; the belly reschedules after), replacing UI_ACT_NESTED/UI_SUBACT. Each attribute's value goes through its schema, and a sub-action that asks in the window gets the window as `extra`. "Pick from inside/outside" keep their `rerun_ask()` questions in plain procs called by the ops. "Reload/load preferences" confirm with `asks()` steps. Pinned by interim_vore_panel_attributes.





## Power plants: the tesla coils and grounding rods (rewrite/power-plants)

- Pinned by `dq_pp/tesla_coil_curves` (loss, multipliers, relay 0.9, amplifier 1.075, prism split, ranges, cooldown); unchanged.
- The energy ball steps on the singularity's `every(2 s)` (`singularity_frame()`), and bumps into it dust through the bumped notice.
- The coil's multitool conversion and the coil board's reconfiguration are ops with `asks()`; part replacement is `part_replacement()`;
  the looks are `draw()`. An empty hand on a coil or rod buckles whoever the actor is pulling (the legacy interaction asked for the grab
  stance, which no longer exists as a mob state). Any held item no longer "touches" a coil for a fingerprint (that swallowed every tool click).

## Power plants: fusion (rewrite/power-plants)

Pinned by `dq_pp/fusion_*` (field size by strength, 1..1000 clamp at 5 W a unit, 100 energy per K, the 1% heat loss a step, instability
tick * size / 10000, the reaction table, 30 fuel a step, the trap above 10000 K); unchanged.

- **No machine pipeline.** The core steps its field on `every(MACHINE_SERVICE_INTERVAL, when = owned_field)` (`core_step()`, then the field's
  `field_react()` a decisecond later), the injector on `every(..., when = injecting)` (`injecting` is a tracked var), the hydromagnetic trap on
  `every()` while bolted (it used to sleep until a new field woke it; it now finds a field raised anywhere in its 7 tiles on its next step).
- The trap no longer keeps its 7-tile scan in a var (the scan held the trap itself: a deleted trap leaked).
- The core's unused `str` topic action is gone (nothing sent it; the console sets the strength through `set_strength()`).
- Ops for every interaction: the cradle, part replacement and ident tag only with the field down; the injector's rod, its blitz confirmation
  (`confirms()`), its ident tag; the three consoles' window and tag; the compressor's sheets, containers, dragged supermatter and its
  "Eject Supermatter Sheet" menu entry. Hand ops answer an empty hand only, as the legacy hand interactions did.
- Calm steps never bled a field's instability: `rand(0.01, 0.03)` rounds to 0 (pinned as it is; a balance change for later).

## Power plants: portable generators and RTGs (rewrite/power-plants)

Pinned by `dq_pp/pacman_*` and `rtg_output` (fuel per step, the supply, running dry, the heat band and overheating, cooling, the emag limit,
RTG output per rating); unchanged.

- **No machine pipeline.** A generator steps on `every(MACHINE_SERVICE_INTERVAL, when = has_work)`: while on, or while it still has heat to
  lose (it used to sleep after cooling until a toggle woke it; the same condition now parks it). RTGs step while bolted down.
- PACMAN ops: fuel sheets, the window (a hand on a bolted generator; a broken one refuses it), the wrench (`anchor()`, not while running,
  joining and leaving its network), part replacement (not while running) and a repeatable `emag()` that lifts the output limit to 2.5x
  (`is_emagged()`). The base generator's empty "Use" interaction (it did nothing) is gone.
- The altevian reactor's fuel, toggle (a silicon's remote touch through `binds(remote())`) and fuel gauge (`draw()`); the void core's cell
  (`owns_one(..., starts = starting_cell)` replaces the built subtypes' ownership tables); hits are `extend(/datum/act/hit/...)`.
- Every look is `draw()`; the reactor's glow is `look.light()`.

## Power plants: the gravity generator (rewrite/power-plants)

Pinned by `dq_pp/gravgen_*` (2 charge a step, gravity at 100 and off at 0, the breaker's spin-up and spin-down); unchanged.

- Its spin is `every(MACHINE_SERVICE_INTERVAL, when = spinning)` (`charging_state` and `broken_state` are tracked vars; the spin constants are
  `GRAVGEN_IDLE/UP/DOWN` in `code/__defines/power.dm`).
- The repair ladder (screwdriver, welder, 10 plasteel, wrench) is four ops on every part of the generator; a part's empty hand opens the
  generator's window (`perform_op(..., "ui_open")`) instead of re-running the main part's legacy attack procs. The window opens to an empty hand
  (the legacy "Use"); held tools no longer show a "Use" entry that did nothing.
- The middle part draws the charge overlay from its main part (`draw()`); no raw overlays. Hits are `extend(/datum/act/hit/...)`.

## Power plants: solars (rewrite/power-plants)

Pinned by `dq_pp/solar_output` (cos^2 exposure, nothing past 90 degrees, obscured or off the controller's network); unchanged.

- **The controller steps for real.** Its legacy `machine_step()` returned PROCESS_KILL after one run and nothing woke it again, so a manual
  rotation rate never advanced the target angle and an unlinked tracker or a panel moved to another network kept its link. It now steps on
  `every(MACHINE_SERVICE_INTERVAL, when = operable)`: manual tracking turns a degree every 36000 / rate deciseconds, as the window says, and
  stale links drop (its panel check clears once done, where the flag used to stay set).
- Ops: the panel's and tracker's crowbar (2 s and 5 s), a hostile swing at a panel, the controller's screwdriver (2 s) and its window (an
  empty hand; it was a legacy "Use"); the assembly's wrench, glass (two sheets of either glass), tracker electronics and crowbar. Looks are
  `draw()` (the panel's facing is `look.set_dir()`, not a write from the appearance proc). Relations are declared (`ref_one`/`ref_many`).

## Power plants: the power monitoring console (rewrite/power-plants, b266f960a0)

- Its legacy "Use" hand interaction (`power_monitor_use`) is the `use` op: an empty hand on an operable console opens its monitor window, as
  before (the i7 interaction snapshot lost the legacy row; recorded here after the fact). It checks its sensors on `every(MACHINE_SERVICE_INTERVAL)`
  instead of sleeping on their grid keys.

## Power plants: the gas turbine (rewrite/power-plants)

Pinned by `dq_pp/turbine_output_curve` and `compressor_spin_up` (((rpm / 100000) ^ 0.8) * 100000 * productivity W; a tenth of the way to the
target a step less rpm^2 / (500000 * efficiency)); unchanged.

- The compressor and the turbine step on `every(MACHINE_SERVICE_INTERVAL, when = running)` (the compressor's `starter` is tracked; the turbine
  no longer needs the compressor to wake it). Their overlays are `draw()` from tracked stages (no raw overlays).
- Ops: part replacement, the compressor's and the computer's ident tags (`asks()`); the turbine's window is an empty hand on a working turbine
  (the legacy `ui_prepare()` check); the "touch for a fingerprint" interactions on any item are gone (they swallowed every tool's click).
- The declared UI model is deleted: code/__defines/sys_ui.dm (DECLARE_UI, UI_ACT, UI_DATA, UI_SUBACT, UI_ACT_PREF_PROC and the rest), its runtime tables and dispatch in code/datums/sys/ui.dm (ui_decl_of, ui_dispatch, ui_parse_args, ui_declared_data, ui_act_allowed, ...), `act_ask`/`om_act_ask`, the `-DUI_TYPES_DUMP` boot with the `ui-types` build target (`analyze gen ui_types` writes the interface types), and dq_sys_ui_tests. Their names are hard-banned in `[lint.legacy_forms.lists] banned`. `tgui_act()` keeps "change_ui_state" (the layout toggle) as the one action every window answers.
- EFTPOS: settings answers resume again. Since the EFTPOS window moved to ops, `eftpos_settings_resume()` looked for a legacy row that no longer existed and dropped every answer.
- Email administration: its buttons need the network access again (`needs(req(PROC_REF(network_admin_access), silent = TRUE))`). The old `ui_act_allowed()` guard had stopped running when the window moved to ops.
- Shuttle consoles: the button guard is `console_gate(mob/user)`, asked by the ops (`ui_gate()`) and by the answers to the codes/destination questions (which used to call `ui_act_allowed()`). The resleeving and vore-save prompts recheck only that the window is still open and interactive.
- tgui modals: the dead `ui_modal_opened()`/`ui_modal_answered()` hooks (no host overrode them; modals are ops bound to "modal:<id>") are deleted and hard-banned.

## Statuses, immunities and godmode on the stat layer (rewrite/om-life, L3)

Pinned by `dq_life_om_tests.dm` (statuses, immunity, godmode, voluntary sleep) and every focused test that applies a status.

* **Statuses run on the mob's biology clock.** A status is a status stat (`code/library/mob/statuses.dm`) whose dose is a hold on
  `HOLD_CLOCK_BIO`: stasis and suspension pause it (the OM statuses ran on the mob's timer clock). A stun taken into a stasis bed lasts until
  the mob's biology has lived it out.
* **An immunity zeroes a status instead of ending it.** Gaining the immunity (godmode, a mutation, a type's `immune_to()`) makes `has_status()`
  FALSE at once, as before; if the immunity ends while the dose still has time left, the status is back for the rest of it (the OM ended the
  dose when the immunity arrived).
* **Type immunities are declarations.** The OM decls (`self_effects`) became `immune_to()` / `immune_to_incapacitation()` in each type's
  CAPABILITIES block; godmode's implied immunities are `immune_to(..., when = STAT_GODMODE)` on /mob.
* **`holds_status()` holds under the activation's source.** The OM keyed each activation's hold; the stat layer keeps one hold per source and
  stat, so two activations with the same source share one hold (none exist today).
* `EFFECT_CAN_MOVE` and `EFFECT_CAN_ACT`, OM composites nothing outside tests read, are gone. Feeding `STAT_CAN_ACT` from the statuses ("one stun
  path") is a separate step: it changes what ops refuse.
* Life frames run under the kernel test clock again (`test_time()` drives the Life sweep, as the OM test scheduler ran the pipeline).
/^## Body migration, slice 5: surgery steps are ops (rewrite/body-full)

Pinned by `dq_body_pin_surgery_incision` (a scalpel click on a lying patient on an operating table runs the incision to an outcome; green on the old
code first) and the existing `dq_surgery_*` tests. Each `/datum/surgical_step` is an op `surgery_<step>` on the human (`code/modules/surgery/surgery_ops.dm`):
the step's state checks are its `when()`, steadiness its `needs()`, the organ choice and the drastic-step confirmation `asks()`, `claims()`, `wait()`, and
the roll in `then()`. `do_surgery()`, the focus and step om tasks, `choose_surgical_step_for()`, `surgery_ask()`, `surgery_zones_in_progress` and the
steps' `choose_target()`/`confirm()` are gone (steps declare `target_choices()` and `confirm_text()`).

* **One click runs the best step.** With a tool several steps take, the click performs the highest-priority step (then declaration order); the others
  are the patient's menu entries. The old click asked which step every time.
* **One surgery per surgeon, one claim per patient.** The per-zone lock is the op's claim: while a step waits on a patient, a second claiming op on them
  is refused (two surgeons could work two zones at once before).
* **The surgeon must stay conscious and adjacent with the tool in hand** (the op's keeps): an interruption abandons the step, as before.
* **Self-surgery's three seconds of focus are part of the step's wait** (was a separate focus task before choosing).
* Scanners and stethoscopes keep their patient use through `use_on_patient()` (was an override of `do_surgery()`).
* Boot fix found on the way: atoms created during global init (a GLOBAL_DATUM_INIT statclick) no longer index the lifecycle tables before they exist.

## Body migration, slice 6: loose organs (rewrite/body-full)

Pinned by `dq_body_pin/loose_organ_ticks`. A part out of a body ticks every 2 s on an `every()` gated by `STAT_TICKS_LOOSE`, which the organ holds
from `left_body()` and drops when it joins a body, dies or is ruined; `OM_FIELD left_body_loose`, `OM_DERIVE_FIELD organ_ticks_loose` and the
`DECLARE_PERIODIC_WHILE` are gone. A dead prosthetic repaired on the bench no longer resumes ticking (it had nothing to tick for).


## The machines still on machine_step(): started work (rewrite/power-plants)

Every machine outside atmospherics that still had a `machine_step()` (90 types: medical, kitchen, mining, shields, xenoarchaeology, cargo,
recycling, overmap consoles, the singularity beacon, ...) runs its step on `started_work()` (`code/library/machine/started_work.dm`): an
`every(MACHINE_SERVICE_INTERVAL)` that runs while its STARTED_WORK_ACTIVE key holds. The step's PROCESS_KILL stops it; `MACHINE_WAKE()` /
`MACHINE_SLEEP()` and `sleep_until_powered()` route to `work_start()` / `work_stop()` / `work_wait_for_power()`; a `DECLARE_PERIODIC_WHILE`
gate became the work's `when` (tracked vars) or `gate` (computed procs, asked before each step), with `wakes_on` the vars the gate read; a
`step_start_condition()` became `starts =`. The machines left the machine pipeline roster. Conversion pins were recorded for every type
before the change (`code/modules/unit_tests/snapshots/pins/`) and are unchanged: no interaction moved.

- **Work no longer sleeps on change keys.** The disposal unit, the point defense turret and the shield capacitor slept on watched keys
  (`sleep_until_keys()`) and were woken by the pipeline: the disposal unit now stops (PROCESS_KILL) and is started by what changes it (an
  insertion, a flush, its gas watch, as before); the turret looks for meteors every step while it is active; the capacitor asks its grid
  again every step while it is short of charge. Their `om_sleep_violation()` audits and the key-sleep tests are gone.
- A machine whose gate is a computed proc (an occupied pod, a cooker keeping its heat, a powered drying rack) no longer parks while the gate
  is false: its started work skips the step instead, so the gate is asked every 2 s. The cooker's and the drying rack's gates are virtual
  (`needs_step()`, `step_gate()`) so the subtype's rule replaces its parent's.
- `..()` calls into the base `machine_step()` (which only answered PROCESS_KILL) are gone; the nuclear bomb's step answers PROCESS_KILL itself.
- The legacy tests that read the pipeline (`machine_stepping()`, `sys_periodic_allows()`) read the work (`test_work_allowed()`,
  `test_machine_idle()`, `test_step_machine()` in `dq_sys_periodic_tests.dm`); `dq_started_work_waits_for_power` tests the library.
- **Carried-only verbs refuse with the engine's wording**: `carried()` says "You can't do that." where the legacy clause said "you need
  to be carrying it". A verb effect the type also calls itself (the shield generator's toggles, the jetpack's) stays a plain proc; its op
  runs it through a thin `<verb>_op(A)` effect.

## Mob repeats on every() (rewrite/om-life)

The mob DECLARE_REPEATs (dizzy and jittery shakes, dreaming, autofire, AI follow-camera, pAI door hack, robot transform
sounds, the eclipse's volleys, the macrophage's deathwatch, the jellyfish's chained attacks) are type-level every()
entries gated on a tracked var; the drift and stagger helpers are after() steps.

- **Shakes end on death at the next shake.** The dizzy and jittery statuses ended on the OM death event; the shake now
  ends its status when it finds its mob dead, within a decisecond. A status started on a dead mob ends the same way.
- **Follow camera with no eye cancels tracking.** The AI's tracking loop used to stop silently and leave `cameraFollow`
  set; it now cancels tracking ("Follow camera mode terminated"), so the next track starts clean.
- **Polled gates for relation views.** The AI's and pAI's repeats are gated on relation views (`cameraFollow`,
  `hackdoor`), which do not publish like tracked vars, so their every() polls (once a second) instead of parking.
- **Registries are `registry()`** (the lifecycle form): radiation collectors and singularities (an energy ball's miniballs stay out through
  the registry's `when`, where `skips_registry()` kept them out before), and the fusion cores, fuel injectors and gyrotrons filed under their
  ident tag (`key = nameof(id_tag)`, now tracked): their consoles read `registry_all(REGISTRY_X, tag)` instead of scanning every member.
  Pinned by `dq_pp/plant_registries`.
- **Trait disabilities are granted capabilities.** Coughing, epilepsy, coprolalia, tourettes, nervousness, pollen, rotting
  and gibbing were OM behaviours fed by the Life disabilities step's event; each is now a capability its trait grants
  (source: the trait) with an `every(LIFE_CYCLE)` on the mob's own clock. They no longer wait on the Life frame's gates
  (placed, status ok), so a mob in nullspace still ticks; each disability's own checks (conscious, not in a belly, not
  transforming) are unchanged.


## Leftovers: organ internals (rewrite/leftovers)

Pinned by `dq_leftovers/*` (organ butchery, peridaxon revival, robotic limb patches, stumps, gibbed limbs) and the organ conversion pins.

- **Organ state is tracked**: `status`, `damage`, `max_damage` and `robotic` are plain vars with `TRACKED` setters (were `OM_FIELD`s); the setters
  keep their names. They no longer raise `CHANGE_EXPLICIT` or `om_field_written()`.
- **Organ interactions are ops**: bite (help stance, aiming at the mouth, flesh only), butcher (a sharp edge, or a screwdriver on a robotic
  organ: ten seconds by the tool's speed, `begins()`/`on_interrupt()` messages as before), revive (five units of peridaxon). A limb pulls out what
  is stuck in it before it can be bitten, in any stance; the bench surgery on a loose limb is one op per tool and stage, and the hemostat's
  "What would you like to remove?" is the op's question (`asks()`), offered only when the limb holds something. The context menu no longer lists the
  legacy catch-all entries ("Use", "Organ self", a "Bite" refused while not in hand); it lists the ops that apply.
- **Timed work is ops with `wait()`**: butchery (was `/datum/om/task/timed/organ_butcher`), a robotic limb patch (`robo_repair()` starts the key-only
  op `robo_repair`, one second, was `/datum/om/task/timed/external_robo_repair`; walking away still abandons it, now checked when the second is up),
  the anomalock heart's core install and removal (three seconds each; the refusals "core already in!", "no core!", "can't remove core!" are the
  ops' requirements). The gibber still butchers at once.
- **Tool procs are ops**: an arm-mounted augment's screwdriver swap is `swap_mount` (instant, `wait(0)`); the mimetic potato's knife and cable, and
  the piñata and money tumours' puncture, are their own ops (each ahead of butchery, as their old item handler was).
- **Starting contents**: the health scanner implant's analyzer and the multitool augment's matter synthesizers are `starts =` of their `owns_one` /
  `owns_many` (were made in `Initialize()`). The species and robotize organ layouts stay runtime creation (they depend on the body, not the type).
- **Endings say why**: a limb burnt away or blown off is `destroyed(limb, null, BURN | BRUTE)` (was `spent()`); a stump lives while it is attached
  (`lives_while()` on its owner, once joined) instead of deleting itself in `removed()`; an MMI holder taken out is `replaced_by()` its MMI; a
  diona limb that splits into a nymph, a brain swapped for another, and organs dropped by a robotize are `replaced_by()`; a slime limb that
  splatters and limbs melted to regrow are `dissolved()`.


## Leftovers: space heater, portable pumps and scrubbers, atmospherics sensors and consoles (rewrite/leftovers)

- **The space heater's work is started work** (`started_work(step = work_step, starts = TRUE, when = nameof(state))`, was `DECLARE_PERIODIC_WHILE`
  on the machine pipeline and `machine_step()`); switching it on starts it, a cell running dry stops it, power returning restarts it. Its cell
  insert, part replacement, hand use and screwdriver hatch are ops (were datum interactions and `screwdriver_act`); its cell is the `owns_one`'s
  `starts = nameof(cell_type)` (was the legacy `ownership()`). The screwdriver opens and closes the hatch instantly, as before (`wait(0)`).
- **Portable pumps and scrubbers start with their cell through `starts =`** (a `starting_cell()` the pump and scrubber answer; made without one
  when `skip_cell`), not in `Initialize()`.
- **The gas sensor listens to its air through a `gas_watch()`** instead of the machine pipeline and an `om_watch_arm_value()` sleep: it broadcasts
  once after it is placed and then whenever the rounded readings it sends differ from the last broadcast (the same rule as before), and again when
  it moves or its outputs are toggled. Its wrench and multitool are ops; the multitool's two questions (which output, then the ID tag when
  saving to the buffer) are the op's `asks()`, so the second is asked only after "-SAVE TO BUFFER-".
- **The atmospherics control consoles' multitool menu is an op** whose first question is `asks()` (a console with ports adds Inlet and Outlet to
  the choices); the later questions (ports, sensors, frequency) are unchanged requests. Their redundant legacy "open UI" hand interaction is gone:
  `interface()` brings it.
- **The fuel injection console's automation is started work** while `automation` (now `TRACKED`, was an `OM_FIELD`) holds; switching it on
  restarts work a missing radio stopped. Both left the machine pipeline roster and their pipeline stages.
## Reagents: holders, reaction and metabolism maths (rewrite/reagents)

Pinned by `dq_reagents_start_snapshot` (the starting reagents of every type under each declaring root, recorded on the legacy code),
`dq_chem_reaction_progress_pin` and `dq_chem_metabolism_pin` (recorded on the DM maths), `dq_forms_reagents` and `dq_decl_reagents`.
Design: `reagents.md`.

* **Starting reagents: no change.** 698 `DECLARE_REAGENTS*` lines and the reagent tanks' legacy `capabilities()` entries became `reagents()`
  entries; every pinned row matched. The holder is made in the capability's preinit hook, at the same point of `Initialize()` as before.
  The reagent tanks' holder (the legacy capability's) is now made there too, before the other capabilities' init rather than after it.
* **A holder declared with more reagents than its volume** still warns (`WARNING`), now from the capability.
* **Metabolism is planned per cycle.** Each holder works out every reagent's uptake rate at the start of a Life cycle (the body's share once,
  then each reagent's), and the dose and overdose for all of them in one Rust call; each reagent's effects then run in the old order. Before,
  each reagent's rate read the heart, stomach and filtering organs after the previous reagent's effects had run, so an effect that changed the
  pulse or an organ in the same cycle moved the next reagent's rate one cycle earlier than now. The `prob()` rolls of filtering organs
  (toxins) now come before the cycle's effects instead of between them: the same odds, a different draw order.
* **An overdose() override that changes the reagent before calling `..()`** gets the base injury the cycle computed from the volume at the
  cycle's start. Every override in the tree calls `..()` first or unchanged.
* **A reaction with yield below 1 and no product amount** no longer divides by zero (it skips the yield limit); none exists in the tree.

## Reagent machines: interactions are ops (rewrite/reagents)

The chem master, grinder, chemical dispenser, synthesizer, distillery, bunsen burner, alembic, injector maker, fluid pump and chem analyzer
lost their `/datum/interaction/machine_*` datums for `op()` entries; their `ownership()` procs, `APPEARANCE_TEMPLATE` / `DECLARE_APPEARANCE_PROC`
looks (except the pump's, the distillery's, the synthesizer's and the syringe's, which read untracked state), `OM_FIELD`s, `OM_EMIT`s, `om_busy`/`om_hold_busy` and `own_take*` calls went too.
Pinned by `dq_reagent_machines_behaviour.dm` (written on master first; the analyzer test fails there on the bug below) and the generated
conversion pins (`snapshots/pins/`, re-blessed after review).

* **The generated pins record clicks now.** A click with an item on a converted machine reads `Click: Use` / `Click: Place container` where
  the legacy datum rows said `click: nothing` (the pin harness never resolved legacy datums as clicks); the click itself did the same thing.
  The rows for held items "the legacy interactions ask for" are gone because no legacy interaction asks any more.
* **Duplicate "Use" menu entries are gone** on the chem master, dispenser, synthesizer and analyzer: each had a legacy touch that opened the same
  window as the interface's own `ui_open` op (which already answered the click); the window still opens on a touch, gated as `ui_open` is
  (the dispenser's and the master's not-broken checks are `extend(TAG_UI, ...)` / the machine hand gate).
* **The grinder's "operating" state is a stat** (`STAT_GRINDING`, a 6 s hold from `grind()`), not the OM busy flag. Same window, same refusals.
* **The chem analyzer's scan is an op** with a 2 s wait that claims the analyzer (`claims()`, drawn from `op_claimed()`); a broken wait says
  "Sample moved outside of scan range". It used to runtime on its first scan (`found_reagents.Cut()` on a list nothing had made): fixed.
* **The chem master's "You add the beaker" line** had a literal tab where `	he` was meant; fixed.
* **The injector maker offers "Add plastic" for any material stack** and declines a non-plastic one, which goes on to the silent swallow as before
  (the old datum hid the entry for other materials; the reads lint forbids the material lookup in a condition).
* **Injector maker refusals** say "Storage is full." / "You cannot put a filled injector into the machine." (the old text added the capacity).
* **The distillery's heating and mixing menu entries** need a living, capable actor as the old verb gate did (`req_capable()`).
* **The grinder's and the distillery's radials, the distillery's slot choice and its thermostat** are the ops' own questions (`asks()`), not
  requests opened from the effect; the buttons, their order and their effects are the same. An AI's grinder menu is refused while unpowered by
  the input's remote authority rather than by `isAI()`.
* **Contained beakers, bottles, the synthesizer's catalyst, the hypospray's vial and the fuel tank's rig** are `owns_one()` with the default
  teardown (deleted with the holder), as `OWN_CONTAINED` resolved them through the holder's contents.
* Still legacy, waiting for their replacements: the dispenser's and synthesizer's ghost view (`INTERACT_OBSERVER`: `by(AFF_OBSERVE)` has no
  provider yet), their screwdriver cartridge removal (`rerun_ask` in `screwdriver_act`), the machines' `*_act` tool procs, the syringe's pick-up
  (`EXTEND_INTERACTIONS` over the item base's) and look, the synthesizer's underlay look, the blood pack's look (it writes `item_state`).

- **Questions are op steps** (`asks()`): the flag's rip asks yes/no, the food cart asks which food, the bar sign asks its face. The
  answer is re-checked by the op's requirements. The food cart offers "Grab food" only while it holds food; the bar sign takes an ID or
  PDA granting its `req_access` (ACCESS_BAR) in hand, or the actor's own access, as every credential requirement does. The flag burns
  with a lighter or any welder (lit or not, as before) after 2 s.
- **The girder's hulk smash**: its offered_when asked a girder proc of the actor, which never answered, so it was never offered; the
  girder stays legacy (it reads mob mutations) and keeps that.


## Leftovers: hydroponics trays, destructive analyzer, particle smasher, power cells (rewrite/leftovers)

Pinned by `dq_leftovers/*` (tray growth and freezing, cell self-charge and gradual charge) and the conversion pins of the tray, the soil plot, the
analyzer, the smasher and the cell.

- **A tray's growth is started work** (`started_work(step = work_step, starts = has_seed, gate = not_frozen, wakes_on = frozen)`, was
  `DECLARE_PERIODIC_WHILE` on the machine pipeline over an `OM_DERIVE_FIELD`); `frozen` is `TRACKED` (was an `OM_FIELD`). The growth timer is a
  keyed `after()` read with `after_pending()` / `cancel_after()` (was `om_timer_slot_*`). **An empty tray no longer runs a frame when it is placed
  and no longer re-arms a growth timer while nothing grows**: planting, a reagent or the freezer starts it.
- **The tray's interactions are ops**: the item use (one effect, as before: only an injecting syringe over a plant goes on to what else the click
  means), the hand's harvest, telekinetic harvest, the alt-click lid, the three verbs (offered to the living only; the light level is the op's
  question), the wirecutters' sample, the wrench's bolting of a tray with no port under it, the multitool's freezer (its refusals are requirements).
  **A ghost's harvest stays a legacy observer interaction** (`INTERACT_OBSERVER` in a one-line `declare_interactions()`): ops have no observer binding.
- **The soil plot**: a tank does nothing (the tank bay is `without()`), a shovel in combat mode fills it in (a three-second `wait()`, was
  `om_task_timed`), otherwise digs it up after "Do you want to destroy the growplot?" (a confirming question, then a five-second `wait()`; it ends
  `dissolved()`, was `om_qdel_self`). Digging is refused with "There is something growing here." while a plant grows.
- **The destructive analyzer's load and recycle are ops**: loading through the closed hatch while idle (not a cyborg's module item: a
  `when()` on the actor, was an `isrobot()` in the effect), recycling by dragging a part replacer onto it.
- **The particle smasher's item uses are ops** (analyzer swallowed, fill target, attach beaker, swipe ID, store, the eject verb, the wrench).
- **A power cell's self-charge is an `every(2 SECONDS)`** while `self_recharge` and `recharging` hold (both `TRACKED`; `recharging` drops when a
  step finds the cell full and rises on a discharge, was `DECLARE_PERIODIC_WHILE` plus `om_task_periodic()`), and its gradual charge an
  `every(1 SECOND)` while steps are left (was `DECLARE_REPEAT`). The spike cell's arcing is its own `every(2 SECONDS)`.
## Relevance is a stat (rewrite/om-life)

`EFFECT_RELEVANCE` on the OM contribution store is `STAT_RELEVANCE` (MAX, on `/datum`): `om_observe`/`om_unobserve`/`om_relevance`
are `hold()`/`release()`/`stat_value()`. Same levels, same sources (a datum source deleted drops its hold, as before); the OM
cadences still follow it through `relevance_changed()` until the framework goes. No behaviour change intended.
- **Suspension is a stat too.** `EFFECT_SUSPENDED` is `STAT_SUSPENDED` (ANY, on `/datum`): `om_suspend`/`om_unsuspend` are
  `hold(E, STAT_SUSPENDED, TRUE, source)`/`release()`. Life's admit guard, the OM timers and cadences read the stat;
  `suspended_changed()` resumes them. No behaviour change intended. `life_sweep` after both: h512 149.8 ms/s for 3413
  frames, mix 33.4 ms/s.
- **The bio clock is the `clock_rate_bio` stat.** `EFFECT_CLOCK_BIO_INHIBIT`/`_MULT` are gone: stasis holds
  `STAT_CLOCK_RATE_BIO` at `1 - depth` (MIN, so the deepest stasis wins, as before), and CLOCK_BIO time runs at that rate
  (`clock_now(E, CLOCK_BIO)`, which replaces `om_clock_now`). A biological clock can no longer run faster than world time;
  nothing outside the OM tests did. The unused `stasis_occupant` relation is deleted.
- **Mob alpha and push blocking are stats.** `alpha_mult` (PRODUCT, base 1, a source re-holding replaces its value) and
  `unpushable` (ANY) on `/mob/living`, held under `SRC_ALPHA_*` / `SRC_PUSH_*` source ids (or a datum). The unused OM
  effect rows (slowed, armour, insulation, move speed, power draw, vitals HUD) and the vitals HUD behaviour are deleted.
  No behaviour change intended.
- **Grave markers ask, then carve at once**: the screwdriver asks the name and then the epitaph as op steps and carves both together
  (the legacy carving took the material's hardness per line, after the questions; a tool op's wait always comes before its questions,
  so the wait is gone rather than put in front of them). The item marker no longer also strikes after asking (its proc returned NONE).
- **The personal shield generator's screwdriver** asks before destroying a built-in cell (an op step, re-checked) and takes any other cell
  out; its multitool asks the shield colour as an op step. **The Tyr keypad's multitool** asks its code as an op step, above the puzzle
  door's catch-all for held items.

## Chemical dispenser refill and closets made in play (rewrite/watch-fixes)

- **A chemical canister refills the dispenser's matching cartridge through the dispenser's `refill_cartridge` op.** It was the canister's
  `afterattack()`, which the dispenser's ops (486461023f) now answer first, so the click set nothing; the pin gains the `refill_cartridge` key.
- **A body bag unfolded in play leaves what lies on the floor alone** (`collects_in_play = FALSE`); every other closet made closed still takes
  in the loose items on its turf, and a mapped bag still holds what was mapped into it.
- **The toilet's conversion pin is recorded with a fixed random seed per type**, so its random lid (and its Flush row) no longer flips between
  recordings; the pin's human is kept awake (godmode) for the same reason.

- **DECLARE_EMAG is gone from code/game/objects and code/game/turfs** (ceiling 0). The sleevemate's sequencer asks what to make of it as
  an op step and spends a card use only when a hack is picked (the legacy one spent it when it asked). Pinned by `dq_items_emag_ops`.
- **The extinguisher cabinet** is ops: a cyborg's module and gripper are not offered its uses (they did nothing); the wrench opens or
  shuts a full cabinet and unwrenches an empty one after 1.5 s. **The holoplant** goes out when its anchoring changes (`on_change`),
  where its wrench proc switched it off after the machine's anchor.

## Items and structures, second pass: interactions are ops (rewrite/items-structures-2)

- **A ghost's click is `observer()`** (the old `INTERACT_OBSERVER`): an op binding that needs `AFF_OBSERVE`, which only `/mob/observer/dead`
  provides (`provides(AFF_OBSERVE)`), reach `REACH_ANY`. A living actor never reaches such an op (the reach gate now checks the provider of a
  `REACH_ANY` op whose binding names an affordance). Trash piles (become a mouse) and ghost pods (inhabit) use it; their refusals are
  requirements with the old texts, and the yes/no that followed is the op's `asks()` step (a ghost keeps only `TARGET_PRESENT`).
- **A manual ghost pod no longer goes busy while a ghost is asked**: several ghosts may be asked at once; the first yes takes it and the
  rest are told another spirit got there first (re-checked on the answer).
- **Every movable's default drag buckle is the op `drag_buckle`** on `/atom/movable` (default tier, offered while `can_buckle` and
  `drag_buckle`, both `TRACKED` now). The legacy entry showed as a greyed "Buckle" in the menu of everything; a drag is no menu entry. A
  type whose old interactions replaced every inherited one (the nest, the pillow piles) says `without("drag_buckle")`.
- **A stance op is picked from the menu whatever the stance** (the engine's rule for `stance()`): the snowman's Crush, the alien resin's
  and nest's Melt, the railing's Slam, the toilet's Yank no longer show "combat mode is off" in the menu.
- **The prism's and the dial's rotation are op steps**: yes/no, then the bearing or the compass point (and the dial's last yes); the
  prop's message no longer shows before the question. A locked or externally controlled prism refuses with its reason.
- **The puzzle door answers only to its locks**: its own touch and item use replace the blast door's open, close, pry and swallow (a
  click with an item now runs the old attackby: pry against the locks, a plastique turns to ash).
- **The cutout's painting takes a paint can or a floor painter** (its own ops); anything else is the barricade's repair or hit, as the
  decline used to fall through to.
- **Toilets roll their lid at init** (`rolls(nameof(open), range_of(0, 1))`, was `rand` in `Initialize()`). Taking the teleplumbing crystal
  is the hand op's question step, asked only when the cistern is open, empty and the actor is a person. A cyborg's module never goes in a
  cistern (a cyborg's own item op). The shower's temperature valve asks as an op step and the alt-click still goes on (`passes()`).
- **The sink**: a silicon is not offered the wash (it did nothing); emptying a container is a drag of a reagent container (an empty one
  says so instead of greying the entry out).
- **The low wall**: a cyborg is not offered placing or dragging things onto it (it did nothing), and so no longer hoists windows up.
- **The potted plant** refuses with the slot's size message ("That is too large to fit.") instead of naming the item.
- **The window tint button's multitool** asks for an id as an op step when it has none and stores it otherwise (the button's `id` is
  `TRACKED`). **The crematorium button** needs crematorium access through `req_access()`.
- **`req_mutation(M, of = ON_ACTOR)`**: an engine requirement on the actor's mutations (reads `MOB_KEY_CONDITIONS`); the girder's hulk
  smash is `when(req_mutation(HULK))`.
- **Devices**: the emergency beacon's pick-up refusal and wrench appear only once it is active (an inactive beacon is picked up as any
  item); the flashlight takes only a cell (`item(/obj/item/cell)`, only while it uses power); the transfer valve takes only a tank or an
  assembly; the intercom no longer has a catch-all item op that only fingerprinted it; the plant analyzer drops the gas scan it never ran.
  The uplink multitool opens its uplink through its own in-hand op. The pAI's radio inherits the ordinary item ops it once replaced (it
  lives inside the card, out of reach).
- **A ghost joining a simple mob** is the observer op `ghost_join` with a yes/no step (re-checked on the answer); `ghostjoin` is `TRACKED`.
- **More devices**: the vac attachment's settings and sprite choice, the translocator's beacon radial and new-beacon name, the beacon's
  eat-into-a-belly and first pick-up warning, and the pAI card's part removal, multitool check and ID access are `asks()` steps. The
  translocator's OOC alert now shows after the beacon is chosen, and the magic tome is the translocator with its words and page type as
  vars (no copy of the menu). The tape recorder's print cooldown is told when printing (the menu entry is no longer greyed during it).
  A ghost that may never respawn still only gets the warning before loading into a pAI card, as before. A cyborg is refused its own
  flash by a separate op on the robot head. `idaccessible` (pAI), `panel_open` and the critical parts (pAI card), `emagged`/`playing`
  (tape recorder), `ruined` (tape), `buildstep` (TV assembly) and `beacons_left` (translocator) are `TRACKED`.

## Leftovers: the machinery sweep (rewrite/leftovers)

Every machine still on datum interactions or tool procs was pinned first (`code/modules/unit_tests/snapshots/pins/`, recorded on the legacy
code), then converted by the codemods: `tools/codemods/tool_act.py` (tool procs to `tool(Q)` ops with `wait(0)`), `tools/codemods/interaction_datums.py`
(now also lowers the machinery bases `machine_hand`/`machine_item`/`machine_alt`/`machine_drag`/`machine_verb` and the shared `open_ui` and
`part_replacement` datums) and `tools/dx/codemods/interact_declare.py` (compact specs to ops; the shared effects are the shared op handlers
`op_open_ui`, `op_swallow`, `op_part_replacement`, ... in `code/datums/interactions/shared_effects.dm`). All three take `--prefix /type` now.

- **A converted op answers after the ops the type already had** (`priority(OP_PRIORITY_DEFAULT - 1)`): the legacy interaction or tool proc it
  replaces ran only when no op answered, so a click an existing op took (the window's `ui_open`, a library panel or wire op) still goes there.
  Where no op answered, the click now resolves to the converted op by label instead of reaching the legacy attack chain ("nothing" in the old
  pins); the effect is the same proc.
- **The master R&D server's "no doing anything to it" op takes every item**, its library tool ops included (the legacy handler's comment was
  the intent; the pin showed the library ops answering first).
- **The pandemic's screwdriver ejection is gone**: the computer's own screwdriver op (disconnect) always answered first, so it was unreachable.
- **The DNA scanner's and the suit storage unit's "climb in" checks run in the op's effect**, with their legacy refusal text: they read the
  occupant slot, which the generated reads cannot follow.
- **Left on the legacy forms** (residue of the codemods, not converted here): 58 types with `declare_interactions()`, 93 compact
  `EXTEND_INTERACTIONS` sites (the lowered form the op codemod could not finish: silicon and observer specs, questions opened from the handler,
  shared handlers, key clashes), 55 tool procs (handlers that open a request, call `..()` or return an expression), and the ten machines whose
  conversion would have opened a request from an op effect (cable layer, floor layer, holoposter, mass driver, point defence, protean
  reconstitutor, requests console, fax machine, conveyor and its switch).
## Life's OM events are actions (rewrite/om-life)

- The status increase events (stun, weaken, paralyze, sleep, blind) were refusable OM events no handler ever refused;
  they are FIXED actions whose notices keep their names (remote view ends on them). The never-used veto
  (`COMPONENT_NO_STUN`) is gone. The vision and darksight events are `PUBLISH`es; the mutations veto, which nothing
  listened to, is deleted (`COMPONENT_BLOCK_LIVING_MUTATIONS`).

## The machine and chem clock domains are gone (rewrite/om-life)

- `CLOCK_MACHINE` and `CLOCK_CHEM` had no effect held on them anywhere, so they always ran at world speed. They are
  deleted: a machine's timers run on its own clock (suspension still pauses them), and the reflector lane measures its
  dt on world time. The final API's clocks are CLOCK_WORLD, CLOCK_OWN and CLOCK_BIO. No behaviour change intended.

- **More structures and toys are ops**: the catwalk (welder slice by stance, plating), window (bang/knock/item/tk, the weld repair op
  with its 4 s wait and 1 fuel, the polarized window's multitool id as an op step), micro tunnel (one hand op asks enter-or-reach,
  one from inside asks the action, then where to or whom; a simple mob's click runs the same op), bonfire (rods ask stake or grill),
  tank dispenser, weightlifter (a person on the machine; the refusals are the old texts), gargoyle statue (a cyborg's module only hits it),
  underwear dresser (the window's open needs a species that wears underwear), canvas and palette (fills and colours are op steps),
  toy and energy swords (alt-click recolour as two op steps), plushies (the squeezes by stance; naming is the menu op with a question;
  the dragon's own squeeze replaces them), balloons, the acorn staff.
- **A weld repair waits before it mends**: the window's repair is a 4 s wait, then the repair (the legacy tool step did both at once in
  the test's fast tool path).
- **The energy sword's cell insert answers the click** once the cell is in (the legacy handler let the hit follow).
- **A menu entry with no name of its own is named after its op** ("Take cell", "Baton item") where the legacy entry derived "Use".
- **Items with their own uses are ops**: the sharpening kit, snowball (compact or smash by stance), armour plates and inserts, the
  butterfly knife grip (an ingredient that cannot be let go says why, from the handler), smoke bomb (a multitool asks the colour), chem
  grenade (its self-use replaces the grenade's prime), stun baton (the cattleprod keeps its own item use), police tape (lift or break by
  stance), teleportation scroll (uses, then the area, as op steps; `uses` is tracked), hand teleporter, ore satchel (`current_capacity` and
  `max_storage_space` tracked), service fabricator (a radial step), barbed wire, the electric welder's cell. The material subtypes' own
  item uses come before the material's repair, as their EXTEND did.

## The OM framework retired (rewrite/om-retire-2)

Pinned by `code/modules/unit_tests/dq_retired_behaviour_pins.dm` and the existing AI, tether, burning, vore and property tests.

- **The AI brain loops run on the mob's own clock** (CLOCK_OWN), as final_api.html section 14 specifies: suspension pauses them,
  stasis (CLOCK_BIO) no longer does. Out of relevance (RELEVANCE_NONE) or outside RUNLEVEL_GAME/POSTGAME a loop's timer still fires and
  skips its run; the OM ring parked it instead. A calm brain still hibernates on its chunk watches.
- **The material service and a belly's digestion cycle are keyed `after()` timers** on their own clock, not OM deadlines on the
  background lane. The cadence and the per-entity cancel are unchanged.
- **The turf_prepare_step_sound veto is gone**: nothing handled it, so a footstep on a turf without a footstep sound stays silent as before.
- **The dqai_target_changed / dqai_target_lost events are gone**: nothing listened to them.
- **The before/catch_throw and before/dice_roll events are direct calls** (`omen_blocks_catch()`, `omen_roll_override()`): the omen was
  their only handler.
- **attack_self is an action** (`ACTION(attack_self, ...)`): the tether host takes it over with an `instead()`; everything else that used
  the OM veto event is gone with it.

## Machinery, round 2: the residue onto ops (rewrite/machinery-2)

`tools/codemods/machine_ops.py` converts what the first sweep left on machine types in one step: a `declare_interactions()` override listing
machine datum interactions or compact specs, or an `EXTEND_INTERACTIONS` row, becomes ops of the type's `CAPABILITIES` block (the same table as
`interact_declare.py`, plus the datum fields `held_type`, `requires`, `also_requires`, `offered_when`, `stance` and `consumes_input`). Converted
ops answer after the ops the type already had (`priority(OP_PRIORITY_DEFAULT - 1)`, as in the first sweep); a second op of the type on the same
input takes the next tier down, so the legacy declaration order still decides.

- **A type whose legacy override dropped `..()` (a replacement) gets `without()`** for each parent op it never had: the ghost jukebox takes no
  touch or item, the refinery's furnace, grinder, mixer, pipe, splitter, vat and waste drop the parent's transfer-amount verb (`into -=`).
- **A held list of item types is one op with `inputs(item(A), item(B))`** (`held_type = list(...)`): the menu lists it only for those items.
- **The alien VR pod's own scan answers before the VR pod's** (`vr_sleeper_scan` is a tier lower), and the microwave's grab-stance pAI eject
  before its plain touch, as the legacy order had them.
- **Verbs (`menu()`) need `req_adjacent()` and `req_capable()`** in place of the per-type `dq_actor_can_act` wrappers: a living actor who is
  not incapacitated, beside the machine.
- **Requirements read tracked state**: the claw machine's `gamepaid`, the item bank's `busy_bank`, the emergency shield generator's
  `is_open` and `malfunction`, the shield wall generator's `power` and the storefront's `department_id` are `TRACKED`; the records console's
  ID slot is `req_empty(nameof(scan))`; the DNA analyzer's sample is a `ref_one()` relation and its slot `req_empty(nameof(bloodsamp))`, its
  busy check `req_is(nameof(scanning), FALSE)`; the holomap's watcher check is `req_is(nameof(watching_mob), FALSE)` (a watcher touching it
  again is told someone is watching, where it did nothing) and "stand in front" is the new library `req_on_holder_turf()`; the refinery drain
  is `req_reagents(0, more = TRUE)`; the cryopod's occupied checks read `slot_occupant()`, which follows `OCCUPANT_KEY`.
- **A held item that can't be let go** (a sticky trait, a slot that refuses) is refused by the new library `req_held_releasable()` with the
  release refusal as the reason: the DNA analyzer refuses a stuck swab, used or not (an unused stuck swab was taken and then rejected).
- **The centrifuge's trolley drop** checks its silent guard (the actor can reach both, is free and able) in the effect and declines, as the
  old `MouseDrop_T` did, instead of a cached condition on the actor's position.
- **The security camera console's cyborg use** declines for an AI shell (it interfaces as the AI) from the op instead of asking `isrobot()`;
  the robotics console's cyborg use declines when the cyborg has access (the window answers), as before.
- **Conversion pins probe each item an op binds** (`item(T)`), not only the items legacy interactions named, so a converted type keeps the
  rows its legacy interactions had; pins of types converted earlier gained those rows.
- **Second pass (30 more machines).** Legacy requirement forms translate: `REQ_FIELD`/`REQ_FIELD_NOT` are `req_is(nameof(v), ...)` with the
  legacy text, `REQ_ANCHORED` and `REQ_PANEL` read `anchored`/`panel_open`, `REQ_TYPE(PRED_ACTOR, T)` is `req(T, of = ON_ACTOR)`.
  `REQ_ON(PRED_ACTOR, /machine/proc/x)` asked a machine proc of the actor, which never has it, so it always refused (the specops shuttle
  console's access check, the paper shredder's "empty bin"): it is asked of the machine, as meant.
- **The reads analysis knows legacy `ownership()` declarations**: a var listed with `owns(nameof(v))` is written only through the ownership
  accessors, whose `own_field_changed()` publishes the var's name, so a requirement may read it (the grinder's held items, the cable
  layer's reel). A `var/const` is a constant. Sixteen `ALLOW(reads)` annotations that this made unnecessary are gone; the windoor's claw
  check is the library's `req_can_shred(15)`.
- **Requirements on tracked state**: the beehive's `closed`, the honey extractor's `processing` and `honey`, the material furnace's
  `firing`, the paper shredder's `paperamount`, a honey frame's `honey` and a bee pack's `full` are `TRACKED`; the beehive's frames
  (`ref_many`) and the furnace's output (`ref_one`) are declared relations. The shredder's "empty bin" needs `req_capable()` and paper in
  the bin; its separate posture check (lying, restrained) is gone.
- **Arcade tickets are a `stack()` binding** that takes the two tickets itself; a short stack is refused with the binding's "You don't have
  enough for that." (was "you need 2 tickets to claim a prize").
- **The waste processor's drops** check their silent guard in the effect and decline, like the centrifuge; **the resleever's drag** is
  offered to humans and cyborgs only (a `when()` on the actor) and needs the machine panel shut (`maintenance_panel_shut()`); **a
  cyborg's item click on a conveyor** is its own op that takes the click and does nothing (the module never drops), ahead of the drop.

## The draw sweep: legacy appearance declarations become draw(look) (rewrite/draw-sweep)

Pinned by the look tree pins (`code/modules/unit_tests/snapshots/look_trees/`, `dq_look_tree_pin`): icon, icon_state, dir, colour, overlays and
underlays of every creatable subtype of each converted chain, recorded from the legacy code and compared after the conversion.

* **A converted type is drawn as it is created, from its state at the end of its init.** A legacy template or layer was applied inside the
  root `Initialize()` (before the subtype's own init ran) and a provider (`DECLARE_APPEARANCE_PROC`) only on the first `update_icon()`; the draw runs at
  the first refresh, after the whole init. So a type whose init changes what it shows now shows it at once: the armed bear trap
  (`/obj/item/beartrap/start_active`) is armed, the suit dispenser and the shutoff monitor show their light and panel overlays, and a robot's flash lying loose shows burnt (it has no robot to
  draw power from; in a robot it reads the robot's cell, as before).
* **A subtype's declared look wins over the parent's init.** The mouse hole (`/obj/structure/mob_spawner/mouse_nest/mousehole`) declared
  `tunnel_hole`, but the nest's init wrote its state after the declaration had drawn, so it showed a trash pile; it shows its hole now.
* **Three providers named one subtype's sprite for the whole chain**, which a redraw showed (now at creation): shock paddles drew
  `defibpaddles` for jumper cables too, the multitool's idle state was `multitool` for every disguised hacktool, and a casing mapped spent
  became `-spent-spent`. Each draws from its own type's `initial(icon_state)` now.
* **`look.held_state()` and `look.identity()`** (code/datums/capabilities/look.dm): a draw sets the inhand state, the name and the description
  through the look, and the slot holding or wearing an item (a hand, the belt, the back...) redraws when its sprite or inhand state changes
  (`look_redraw_worn()`; providers called `update_held_icon()` or a slot's `update_inv_*()` by hand). The press camera drone's look follows a
  tracked `streaming` that mirrors its camera when it is toggled.
  A draw that does not set them leaves them as they are, so a rename or a reskin stays.
* **The used autoinjector keeps its spent sprite** through a draw of its own; its init wrote the state by hand, which a draw would redraw over.
* **A generic emissive blocker follows the sprite a look draws** (`look_resync_emissive_blocker()`, `code/datums/capabilities/look.dm`). The blocker
  is a copy of the sprite taken in `/atom/movable/Initialize()`; a legacy declaration had drawn by then, a draw had not, so the copy kept the type's
  initial state. Every `draw()` type now swaps it when its icon or state changes (before, any later state change also left it stale).
* **The suit dispenser's frame overlay is drawn once**: its init added `special_frame` by hand beside the draw that adds it.
* **Chains whose look reads another object's state stay on their legacy declarations** (35 draws: reagent machines reading a beaker,
  guns reading a magazine's rounds, vehicles reading a tank...), and so do 13 that built layers by writing an image's members or redrew
  their holder's hands: a `draw()` reads only tracked state and writes nothing (`sys/dx_reactive`, which now also checks `look_parts()`).
  Their looks are unchanged; `look_sweep` reports them as residue (hop_read).
* **Rotation is the library's `rotatable()`** on the floodlight, the infrared emitter, the drill brace, the shield capacitor and the suspension
  field generator (their `Initialize()` called `make_rotatable()`): the turn ops are in the interaction menu instead of the verb panel, and the
  actor gate stands in for the old incapacitation and tiny-pest checks; a ghost's menu lists them, as on every `rotatable()` type.
* **A redraw that was immediate is at the end of the frame.** `update_icon()` re-applied a declaration on the spot; its replacement is the tracked
  write itself (the redraw is generated) or, where the draw reads state nothing publishes, `changed(src)` at the old call site. Code that read
  `icon_state` or `overlays` right after `update_icon()` would see the old look until the frame ends; none of the converted callers does.

- **The ten prompt machines ask on the op** (`asks()` steps; the question opens before any effect, and the hand and place are kept while it
  is open): the cable layer's wirecutters (cut length), the floor layer's wrench (work mode), crowbar (tiles to remove) and screwdriver
  (tile type), the holoposter's multitool (poster), the mass driver's, conveyor's, conveyor switch's and fax machine's multitools (id or
  department, behind an open panel: with the panel shut the click is taken and nothing happens, as before), both point defence multitools
  (ident tag), the protean reconstitutor's wrench (component), and the requests console's multitool (department) and its window's write
  and announcement buttons (the write question opens only for a department name that reads as text). Their prompt subtypes lose the tool
  they kept (the op keeps the hand). The holoposter's fingerprint and click sound come with the answer, not before the question. A floor
  layer with nothing in it opens no tile question (it said "is empty").
- **The conveyor switch's tools are ops**: the welder takes the switch apart behind an open panel after 2 s (a lit welder, no fuel), the
  wrench flips one-way operation, the wirecutters change speed behind an open panel.
- **The fax machine's staff request form is one op**, the window's button and the menu's verb, with four questions (confirm, job, reason,
  confirm) as `asks()` steps whose later steps read the earlier answers (`step_value()`); a "No" or a closed question ends it with
  nothing sent. It needs a human or silicon actor, beside the fax from the menu. A silicon's touch logs it in by its own op.
- **Machine maintenance is ops** (the `maintenance` section of `CAPABILITIES(/obj/machinery)`): the panel (an open and a close op), deconstruct
  behind the open panel, secure and unsecure with the panel shut (the machine's wrench time, begin and end messages) and the lit welder's
  repair, each offered by the type's `maintenance_flags`. They answer after a type's own tool ops (moved to `OP_PRIORITY_DEFAULT`, as a
  subtype's `*_act` ran before its `..()`) and ahead of its catch-alls for any item (same tier, the tool binding is the more specific),
  which is the legacy order: the first sweep's catch-alls had come to answer screwdrivers and crowbars before the panel (a grill, a
  station map, a grinder, a firework launcher...); they no longer do. The legacy datums survive only as the interaction engine's own test
  fixture (`/obj/dq_maint_probe`); the machine behaviour is pinned by `dq_machine_maintenance/*`.
- **Every machine tool proc is an op.** Guards that swallowed the tool are needs on the base ops (`extend("machine_panel", needs(...))`:
  the airlock controller that isn't deconstructable, an occupied recharge station, a busy washing machine or protean reconstitutor, a hot
  or running shield generator); reactions after the base op are appended handlers (`extend("machine_anchor", then(...))`: power machines
  join or leave the network, turbines and compressors find each other, a bunsen burner drops its container, a quantum pad re-finds its
  power region, the grid checker's flag, the firework launcher's redraw, the anomaly harvester lets go). The six wall displays share
  `display_disconnect_op()` (2 s, needs a board). The chemical dispenser's and synthesizer's cartridge removal ask on the op. The drill's
  label op asks instead of opening its prompt from the effect.

## Integration 2026-10-06 (om-retire-2, draw-sweep, items-structures-2)

* **Conversion pins re-recorded (147 files).** A converted item op (`menu()`, `item(T)`, `stack(T)`) is probed with what it binds, so the
  pins of the targets those items act on gained rows: the held ID card's "Read ID Card" and the paper's "Create Area" (a carried-only verb
  refuses with the engine's wording, as above), the new held-item rows of the converted items (tape recorder, pAI card, UAV, translocator,
  robot head and suit, mail, camera bug, area editor, TV assembly, glass jar, toy mecha, drone circuit), and the turn ops of the five
  `rotatable()` machines. The implant chair's grab op is "Put in chair" with a grab only; its two verbs are ops. A bare `/obj/item/holder`
  is not a probe (it is made around a mob).
* **A deferred `dx_*` callback finds its owner again**: the wrapper key is the one `rerun_unwrap()` reads (`rerun_h`).
* **Open prompts are pinned, not changed.** An op paused at a prompt was already cancelled on losing its actor, target, held item, reach (adjacent bindings, the window) or what its requirements read, and re-ran its requirements on the answer; `dq_prompt_interrupt/*` now pins it (walk away, drop, delete, power loss, answer after a requirement changed, `keeps = 0`, chains). No behaviour changed.
- **Ambient effects run only while a player is near** (client-proximity relevance, `code/controllers/subsystems/proximity.dm`): map-effect intervals (smoke, sparks and steam emitters, sound emitters, screen shakers) and timed beam points park while no client eye is in their 8-turf cell or the eight around it, and resume when one arrives, instead of polling for a player within 12 turfs. The range is now cell-based (between 8 and 24 turfs), the eye counts wherever it is (an AI camera, an observer) rather than the mob, and AFK players count (the old check ignored them after five minutes). A beam point that is parked with its beams up keeps them up. `always_run` holds the effect relevant everywhere.

## Machines: the machine pipeline is deleted (rewrite/machine-stats)

* **A fire alarm's lockdown countdown ticks as started work.** It is the same count (one service interval a step, the alarm trips at zero), now an
  `every()` that runs only while `timing` and the alarm is operable; nothing in the game starts it on a plain fire alarm. The old stage also
  looked for a hotspot once at spawn; the hotspot check now runs only inside the countdown (a hotspot reaches an alarm through its heat rule).
* **The distillery runs as started work.** It starts when switched on and parks when it has nothing left, and a power or breakage change gives it
  one more step (it used to wake on the same changes through channels). The gas watch it never armed is not replaced.
* **A machine's high gear (`speed_process`) no longer moves its work to a faster lane.** The fast-lane step it ran called the machine's
  `machine_step()`, which no converted machine defines, so the gear already did nothing to the work; the field stays for the mining and
  conveyor interfaces that show it.
* **`MACHINE_WAKE` on a machine with no started work does nothing**, as it already did for every machine that had left the pipeline (hydroponics
  trays woken by chem smoke, for one).

## Machines: started work parks while the machine is not operable (rewrite/machine-stats)

* **A machine's started work runs only while `STAT_OPERABLE` holds.** Unpowered, broken, panel-open (maintenance) and EMP'd machines no longer step;
  their work resumes by itself when they work again. Before, each step ran and refused (or ended its work and waited for power). The 13 machines
  whose step reads power itself (the distillery, exonet node, magnet, ATM, recharge station, cooking appliances and others) declare `unpowered = TRUE`
  and run as before. `STAT_OPERABLE` is now contributed by every machine (the stat bits, `stat_bits_allow()`), not only machine_basics machines.

## The power grid: an area's demand is its machines' contributions (rewrite/power-grid)

Design and migration: `doc/rewrite/power_grid.md`.

* **No tallies.** An area's standing power demand per channel (`demand_equip`, `demand_light`, `demand_environ`) is the sum of what its machines
  contribute (`contributes_to` the machine's `power_area`), settled when a machine's `use_power`, idle or active draw, channel or area changes. The
  `static_equip/light/environ` vars, `power_use_change()`, `use_power_static()`, `retally_power()` and `check_static_power()` are gone (the admin
  "Check Static Power" VV option with them): there is nothing that can drift, so there is nothing to recount.
* **Every machine joins its area.** `area.power_machines` holds every machine standing in the area (it held only the ones that wanted power-change
  calls); `area.lights` is `lights_here()`. A machine moved between areas takes its draw and its power state with it in one step.
* **Rarely, a load shows that the tallies had lost.** A subclass that wrote its draw outside the setters, or a machine moved while it was still
  initialising, used to leave the area's load wrong until someone retallied; the APC now carries exactly what the machines in the area ask.
## Machines: NOPOWER and BROKEN are stats (rewrite/machine-stats)

* `NOPOWER` is the `has_power` stat held false by `SRC_GRID` (set_powered() is the one writer); `BROKEN` is the `intact` stat held false by `SRC_DAMAGE`.
  `has_stat()`, `stat_add()`, `stat_remove()`, `set_stat()` and `stat_bits_now()` are shims over them (and over the `stat` bits POWEROFF, MAINT and EMPED, which
  are still bits), so every existing caller keeps its behaviour. A type's default `stat = BROKEN` or `NOPOWER` moves into the stat layer at Initialize.
* The self-powered turret (`/obj/machinery/porta_turret/rcd`) declares that area power never stops it. Fixed in rewrite/power-grid: its power is its own, BROKEN and EMPED still stop it.

## The power grid: a machine's power is a read of its area (rewrite/power-grid, stage 2)

* **Power is a stat, not a push.** A machine has power while its area's channel for its `power_channel` is energized; there is no per-machine write when a channel
  flips (`doc/rewrite/power_grid.md` section 7). A machine created or moved into a dark area is dark at once; a moved machine takes the new area's reading in the
  same step. A machine with no area has power.
* **Self-powered machines are not darkened by their area**: the APC and the SMES (as before, now declared), and the RCD turret (a fix: it was stopped by area power
  though declared self-powered).
* **A turret's power loss is still a moment late** (its capacitors, 0 to 1.5 s); restoration is immediate. A jukebox that is not bolted down has no power.
* The self-powered turret (`/obj/machinery/porta_turret/rcd`) declares that area power never stops it; it does today (not changed here). Left to the grid work.

## Machines: maintenance, switch and EMP are stats (rewrite/machine-stats)

* **MAINT, POWEROFF and EMPED left the bit field.** Under-maintenance is the `in_maintenance` stat (held by `SRC_MAINTENANCE`; written by the oxygen pump's
  hatch and the pipe dispenser's unwrench), the machine's own switch is `switched_on` (held off by `SRC_SWITCH`; the cookers' on/off), and a pulse is a timed
  `SRC_EMP` hold on `STAT_OPERABLE`. `operable()` is unchanged in meaning: powered, whole, not in maintenance, not pulsed. The switch alone never stopped a
  machine working and still doesn't.
* **Cookers and a wrecked turret start in their state through hooks.** A fryer, grill, oven or mixer starts switched off (`starts_off`), as before; the
  destroyed alien turret starts broken (`starts_broken()`), as before. Both are applied at the end of the machine's Initialize.
* **A camera's EMP outage is a timed hold.** It lasts 90 seconds over the pulse's severity, as before; the hold ends by itself and the camera's own
  timer clears its alarm. A camera that was already pulsed keeps its first deadline (as before).
* **Watchers moved off `stat`.** The machines that woke on any change of the condition bits (pipe turbine, air alarm, chargers, the started-work machines) now
  wake on `STAT_OPERABLE` (cookers also on `STAT_SWITCHED_ON`). A machine whose switch alone changed used to wake those watchers; now only the cookers hear it.
* **`panel_open` is a tracked var.** Same writers (each machine's panel op), same channel; no behaviour change.
* The vehicle's own condition bits (`/obj/vehicle`, `stat` with EMPED) are a separate field and are not machine conditions; they are unchanged.

## SMES hatch tools answer before the window (integration rewrite/integ-4)

* **A SMES's hatch tools take the click before the window does.** The window answers any click of the hand, a held tool included; with the window
  open-able the screwdriver now opens the maintenance panel and the crowbar deconstructs (`machine_panel`, `machine_panel_close`,
  `machine_deconstruct` run one priority step above the window). Pin rows: the buildable SMES's screwdriver and crowbar clicks.
* **An unwired SMES and the battery rack still open their window.** `ui_open` is ungated on both (the hand gate reads `operable()`, which now includes
  "has an input terminal"); the window's buttons were never behind that gate and are unchanged (pinned by `dq_p2_smes/unwired_window_opens_buttons_keep_working`).

## Topic links as ops (rewrite/op-topic)

Pinned by `code/modules/unit_tests/dq_topic_*_tests.dm` and `dq_e2/topic_*` (the behaviour tests were written and green on the `TOPIC_ACTION` rows first;
the converted code passes the same tests). A browser or chat link (an `href`) is the op whose `topic("key", args...)` binding names its key, run through
the input inbox with the requirements and refusals of a click. Every `TOPIC_ACTION` row outside the machinery folder is an op now.

* **A value the schema cannot read refuses the link and tells the clicker** ("That isn't something you can enter."). A `TOPIC_NUM` that was not a number
  reached its handler as null, and a `TOPIC_REF` that named nothing of its type or source was dropped without a word; both now refuse with the message. A
  number past its range is clamped and logged, as for a window button.
* **Text longer than the field's length is refused, not cut.** `TOPIC_TEXT(name, n)` truncated to n characters; `arg(name, schema_text(n))` refuses. The
  links the game writes never exceed their field.
* **A rights refusal on a link reads "You do not have sufficient rights to do that."** (`req_rights` now has its own message; it said "Not while things are
  as they are.", which was the generic forbid). The admins are still told of the attempt (log, `log_href`, `message_admins`); the `ADMIN DENIED` private
  log line now carries the rights the link asked for.
* **A link holder's `topic_allowed()` gate still runs first** and says why itself; it is not yet a `needs()` requirement for the types that use it (an
  exosuit's pilot check, the held-item check of the blueprints and the sleevemate, the admin token check). Their refusal is a silent "You cannot use that
  link right now." beside what the gate itself said.
* **A link that only its own mob may use** (`if(user != src) return`) is `needs(req_self())`, refused silently as before.
* **The client's own hrefs** (private message, mentor message, Discord registration, stat browser reload and preload, the command bar's typing flag, the
  `action=openLink` link) are ops of the client's session. The typing flag is one op resolution per keystroke now instead of one table lookup.
* **The language, flavour text, vore, record-HUD and cyborg alert links of mobs** are declared on `/mob` guarded by the holder's type: their own
  `CAPABILITIES` blocks (`code/library/mob/hands.dm`, `code/modules/combat_ai/integration/mob_living.dm`) are another worker's, and move there when it is free.
  Behaviour is unchanged. A cyborg's and an AI's "show alerts" link is one op.
* **A nested `topic_ask()` answer still re-enters through `topic_dispatch()`**, which tries the holder's op first, so the admin panels' multi-step
  questions work as before until their handlers become `asks()` steps.
* **Links that ask are `asks()` steps of their op** (the exosuit's rename, pressure and passenger questions, the cable reel, the communicator reply, the
  sleevemate's mind steal, the traitor panel's telecrystals, the game mode panel's option and antag-type questions, the feedback viewer's filters, the
  admin newscaster, CentCom and syndicate replies, round mode picks and force speech, and the View Variables questions: rename, stop animations,
  languages, verbs, organs, species, AI brain, mass delete). The old answer-callback procs and the href re-run plumbing of those links are deleted.
  * A second link clicked while a question is open no longer cancels it: an actor has any number of pending ops (see "Several pending ops per actor" below), so two panels' questions are open at once, and the same link clicked again focuses its open window.
  * A question the actor no longer may answer (the rights or reach its prompt class checks) is refused when the answer comes, as before.
  * **A guard that reads state is a requirement, so it runs before the question.** The state it reads is tracked: the `mob_state()` capability keys
    `MOB_STATE_PLAYED` (set in `/mob/Login()` and `/mob/Logout()`, which every key transfer and `ghostize()` runs; a requirement cannot read the builtin
    `client`) and `MOB_STATE_KNOWS_LANGUAGE` (`sync_language_state()` after every write to `languages`) on every mob (capability keys, because the
    `base_vars` ratchet refuses a new var on `/mob`), a mech's `state` (the maintenance graph writes it through `set_state()`), the
    mech cable layer's `cable_length` (`sync_cable_length()`), and the admin caster's `admincaster_channel_ready` / `admincaster_wanted_ready`
    (`admincaster_resync()`, run when the panel refreshes). So a mech's tank valve and passenger links refuse silently while the bolts are hidden (a passenger link still says "There are no passengers to remove." after the question: who is
    in a compartment lives in the slot ledger, which nothing tracks); the cable reel refuses with "There's no more cable on the reel."; "Give AI" on a player's mob
    refuses up front ("This cannot be used on player mobs!") instead of asking three questions; removing a language from a mob that knows none opens no
    question and says "This mob knows no languages." (`dq_topic_guards`, `dq_mob_state_keys`). A mech link's reach is `req_adjacent()`.
  * The communicator reply and the sleevemate's mind steal still ask first and then check what they check (their guards read state nothing tracks yet).
  * **Fix:** the mech's "remove passenger" link looked for the passenger in the pilot slot of the compartment, not its passenger slot, so it never found
    anyone; it reads `OCCUPANT_SLOT_MECHA_PASSENGER` now. (`passenger.dm`'s "compartment occupied" check has the same wrong slot; left as it was.)
  * **Newscaster and Wanted confirmations of a draft that cannot be sent** (no name, a name another channel has, no description) are refused up front with
    the reason as a chat line, and no confirmation opens; they showed the error screen at once. The readiness is re-derived on each panel refresh, so a
    channel another admin creates in between is still caught by the handler's own check.
  * **Round mode picks and CentCom/syndicate replies refuse with a chat line** where they raised a pop-up ("The game has already started.", "The game mode has to
    be secret!", no functional radio / no headset), as requirements; the unban "already lifted" notice is a TGUI alert, as the other admin alerts are.
  * **A VV "Give AI" no longer rebuilds the brain when its questions are cancelled**: the brain is made when the last answer is in.
* **A link whose handler asked through `open_request()` and re-ran itself with `topic_ask()` or a replay token** (the ban panel's questions) still
  re-enters through `topic_dispatch()`; those are the remaining `topic_ask()` sites (admin_topic_bans, admin_topic_mobs, admin_topic_panels, player_notes).

## Several pending ops per actor

* **The one-waiting-op-per-actor rule is gone.** An actor may have any number of pending ops (waits and open questions), up to `OP_PENDING_CAP` (10); one more is refused with "You have too many things going on at once: finish or cancel one first." and nothing is cancelled to make room. Before, any new input stopped the actor's one pending op, a question included (so opening a second panel link, or clicking anything while a window question was open, dropped the first question).
* **What conflicts is `claims(mask)`** (`CLAIM_HANDS`, `CLAIM_BODY`, `CLAIM_TARGET`; `claims()` alone is all three, `claims(0)` none). A timed `wait()` on a physical binding that declares no `claims()` holds hands and body while the wait runs (what the single slot gave it implicitly); a question holds nothing, and neither does a timed wait started from a window button or a topic link. A physical input needs the hands, so it still stops a physical wait ("You stop what you were doing."; an AI's is refused as busy), but it no longer stops a question, and a window button or link no longer stops a wait (it needs no hands). The target claim is unchanged: a second claimant is refused and it lasts the whole pending op.
* **Clicking the same op on the same target while its question is open focuses that window** instead of opening a second (the old rule cancelled the open question and asked again).
* **Each question closes on its own loss.** The subscription was already per pending op; with several open, a lost requirement, target, held item or reach closes only the questions that depended on it, each with its reason.
* **The Resist verb's "already breaking out" check** is unchanged (the break-out op is system-origin and never in the actor's list).

- **A simple mob's melee swing and innate shot are ops** (`mob_attacks()` in `CAPABILITIES(/mob/living/simple_mob)`, `code/library/mob/attacks.dm`): the combat AI's `melee_attack` and `ranged_attack` tactics call `mob_attacks.melee` / `mob_attacks.shoot` with the mob as actor (`ORIGIN_AI`), so they meet the op requirements: capable (not stunned, restrained or dead), the target adjacent (melee) or a projectile to shoot, and off the attack cooldown. A refusal fails the tactic (the brain's one-second fail cooldown applies) instead of attacking anyway, and is traced. The ops are AI-only (`inputs(ai())`): a player's click on a simple mob is unchanged.
- **The AI loops park on `when = STAT_RELEVANCE`** (the strategic and tactical `every()` of the brain's capabilities): no behaviour change (the same z-occupancy relevance as before), the check moved from the handler to the entry. AI mobs deliberately do not use `proximity_tracked`: they change simulation state, so they keep running anywhere a player is on their z-level.
- **AI decisions can be traced**: `datum/ai_brain/traced` (one brain) or `GLOB.ai_trace_all` writes each behaviour start, stop and op outcome to the game log. Off by default.
- **Every AI tactic's action is an AI-only op of `mob_attacks()`** (`step`, `special`, `fire`, `throw`, `pickup`, `alarm`, `slam`, beside `melee` and `shoot`), including the `ports/*` creatures' steps, special attacks and melee. All need a capable, conscious actor; melee, shoot, fire and throw also need the attack cooldown over, so a port that used to attack through its cooldown is now refused and fails its tactic for a second. A charge's slam and a thrown grenade keep their numbers (slam 2.5x melee damage, throw range 6).

## AI packs, states, standings, roles (rewrite/ai-packs)

Spec: `doc/rewrite/ai_packs.md` ("Implementation status" lists what is not in yet). Pinned by `dq_ai_cadence_*`, `dq_ai_pack_*`, `dq_ai_standing_*`, `dq_ai_state_*`, `dq_ai_roles_*`, `dq_ai_port_*` and `dq_ai_cost_*`; the 23 tactic tests and `dq_ai_tactic_shared_ops` pass unchanged.

* **Mobs in a calm area can take up to five seconds to notice something new.** Perception is the pack's and runs on chunk activity, a member hurt or a member heard, coalesced to one pass per window: calm 5 s, alert or fleeing 1 s, engaged 1 s while a player can see the pack and 2 s off screen. A calm brain used to wake on the first mob that moved near it and look within two seconds.
* **Friendlies and neutrals in range are noted without line of sight.** Only hostiles are checked for sight (the old pass saw only what `view()` showed). A friendly behind a wall now counts as a visible ally for call-for-help, healing and rally. Hostile sightings still equal what `view()` shows the spotter (darkness, invisibility, opaque objects), pinned by `dq_ai_pack_perception_parity`.
* **Pack mates share sightings.** One member spots a hostile; the others learn after the faction's alert delay (0.75 s) if they are within 12 tiles. A pack of one behaves as before.
* **Packs spread over their targets.** Members of a pack choose from the hostiles that hold fewer than two members each (SPREAD), so a pack fans out instead of all biting the nearest. FOCUS (follow the leader's target) is available per faction.
* **Wolves, giant spiders and xenomorphs hunt in packs** (join within 5 tiles of a pack leader, leave beyond 9). Wolves have their own faction (`FACTION_WOLF`; they used to be `FACTION_NEUTRAL`, and the station dogs and guard wolves keep that); they still treat neutral-faction animals as allies. Spiders and xenomorphs now regard their own faction as allies (it used to be neutral because the faction had no data). A player taking over a mob takes it out of its pack.
* **Grudges last five minutes** (a hit used to be remembered for thirty seconds) and are held as standing rows, one per subject. `add_personal()` keeps its name; the brain's `personal` list, `personal_entry()` and `expire_personal()` are gone. `NEMESIS` is standing -150, `HOSTILE` -100, `WARY` -50, `NEUTRAL` 0, `FRIENDLY` 50, `ALLY` 100. AI mobs now carry stat holds, so their stat recompute takes the general path. A grudge given a negative duration holds nothing.
* **A running tactic no longer blocks re-selection.** An event (damage, a new target, perception changed) or one second engaged re-picks while a tactic is running; before, a tactic that kept returning CONTINUE was never replaced until it finished. IDLE and BACKGROUND tactics tick three times slower below `RELEVANCE_VISIBLE`.
* **A retreat is the pack's.** One member's `pack_retreat` puts a retreat order on the pack (eight seconds, ends with the issuer); packmates' `pack_retreat` then scores 110. `call_for_help` rallies the whole pack (a grudge for each packmate) and still forwards the attacker to allies seen outside the pack.
* **Followers serve.** `set_leader()`/`set_follow()` on a mob that has a brain makes the follower sworn: it joins the leader's pack, never splits off, takes the leader as an ally and the leader's hostile standings as its own, and is freed when the leader dies. A broodmother is a lord and the broodlings it births are sworn to it (they follow it when calm). The kururak ace is the pack's alpha (+30 authority).
* **A brain's state gates its tactics.** Calm and alert brains run what a brain with no target ran before; engaged brains everything; a fleeing brain only fleeing or interrupting tactics (so a retreating mob keeps retreating); a regrouping one the idle follow and home tactics.
* **A ysbryd hunting a mob nobody controls no longer runtime-errors** (its victim's plane holder is null-safe).
* **Cost.** `dq_ai_cost_packs_of_1_5_20` counts exactly: line-of-sight `view()` builds fall from one per brain per pass to one per pack per pass (engaged x20: 100 builds to 5), and an idle pack builds none. Wall time of a pack pass is within the old per-brain pass for idle packs of 5 and 20 and about twice it for engaged packs (a pack pass also re-targets and re-assesses every member, which the old measured loop did not). A pack of one costs more per pass than the old per-brain loop (the pack machinery) and the same number of `view()` builds.
* **A calm mob parks until its pack perceives something** (it used to wake on any mob moving in its chunks): a mob that wanders never parks, as before. The strategic loop is gone; the one loop runs the slow work every two seconds while a mob is awake.
* **A charging mob's wind-up is an op:** it cannot do anything else while it winds up (other ops are refused as busy), and the charge is cancelled if the target is gone or it dies; it dashes up to six tiles and slams only if it arrived.
* **Control spell and capture crystal followers** hold their ally standing under the spell or crystal as source; carrier swarmlings and glitch-boss illusions follow and serve their parent like broodlings do.
* **Cost (re-run).** Steady-state perception passes: pack of 5 or 20 strictly cheaper than the same mobs alone (engaged x20: 18 ms against 85 ms; idle x20: 15 against 66); idle solo packs at or below the old pass (x20: 51 against 72 ms); engaged solo packs 1.1 to 1.7 times the old pass.
## Sweep: objects, turfs, defines (rewrite/sweeps-objects)

* **Ambient and radiation periodics gate on proximity**: anomalies, nests, mob spawners, green glow, uranium doors, radiation emitters and the POI reactors park while no client is near (`proximity_tracked`, `STAT_RELEVANCE`) where they slept on `mob_near()` before; the scanner spawner stays ungated.
* **Camera bug**: the "no bugged cameras" message is now a refusal of the op; the old in_use guard (which blocked the re-run of its own question) is gone.
* **Poster rip**: a ripped poster no longer offers the question (the op is hidden); the question is the op's `asks()` step.
* **Tanks**: the pressure check runs while the tank is leaking, damaged or `handled` (set in equipped(), cleared in dropped() when no mob holds it) instead of testing `ismob(loc)` each run.
* **Ticker reboot countdown and beam / mini hud ticks** re-arm with `after()` (a plain datum has no type-level every()).
* **Tape recorder**: a recorder whose tape is missing or full when its tick runs now stops recording.
- **Clothing, vore, vehicle and detective-work sweep (sweeps-clothing).** Deliberate differences from the legacy resolver: the void suit's "no modifying while worn" is `req_not_worn(SLOT_ID_SUIT)` (a human who is awake and wearing it; accessories and labelers are excluded by the op's `when()`), and the subtype copies on the response-team and AutoLok suits are gone (they declined and the base op answers); "Eject tank" and "Toggle Helmet" refuse when the suit holds no tank, cooler or helmet even when nobody wears it (the old requirement passed silently and the effect did nothing); the fingerprint card's "take your gloves off" refusal also shows for a used card; the tactical sec-vis glasses ask for the pattern first and toggle after the answer; the friendship bracelet, vehicle paint and smole colour prompts are `asks()` steps; the holster's menu "Holster" verb draws with the helping stance (a menu pick carries no click stance); vehicle engine and kickstand verbs need the actor on the vehicle's own tile (`req_on_holder_turf()`, was `REQ_REACH(0)`); refusal wording is the sentence form of the old fragments. New library requirements: `req_actor_slot_empty()` and `req_worn_by_actor()` (`code/library/items/actor_slot.dm`).
- **Projectiles sweep (rewrite/sweeps-projectiles)**: the gun self-use is one op per stance group (`gun_self`, `gun_self_hurt`; the hurt op tells `gun_operate` the stance through its key) and every gun type's self-use and fit chain is `gun_operate(A, callback)` / `gun_item(A)` with `..()`; a decline answers where the old chain answered falsy. The detective guns' naming refusal ("you don't feel cool enough"), the bottle's "needs to be on the floor to spin" and the disposal bin's "cannot reach the controls from inside" are said by the handler after the question (a requirement may not read `mind`/`loc`: `sem/reads`). The parcel pen label is an ask chain (menu, then title or note) instead of the hand-rolled captured request. The pneumatic gun's pressure prompt, the cyborg blade recolor and the adjustable tracer recolor are `asks()` steps; their captured-item prompt types are gone.
- **Gamemodes sweep (rewrite/sweeps-gamemodes).** A periodic that returned PROCESS_KILL or REPEAT_STOP to end itself now clears its gate var instead: the mecha sleeper (`sustaining`), syringe gun (`synthesizing`, refreshed on attach/detach/selection), the ticker circuit (`is_running`, so a data write with the pin on restarts it), generators/relay/droid (their own flags). The nuclear mecha reactor still irradiates only on the cycle its parent shut down (the old `if(..())` read the kill result; kept as it was). A rune's manifest summoner that is destroyed ends the repeat without dusting the homunculus, as before. Menu entries that were hidden by a predicate (mecha verbs by `*_possible`, passenger bay, airtank, port state; ATM deposit without an account) are now offered and decline in the handler; the pilot check is a requirement (`pilot_only`, reading `pilot_of()`, published as OCCUPANT_KEY). The artifact blade's cooldown refusal is a message from the handler, not a requirement. Hit hooks: coolant tank blast and the mecha tracking beacon's EMP are `instead` hooks; the mecha afflictions-after-blast is an `on_notice`.
## Legacy-form sweep, misc1 (shieldgen, telesci, mining, overmap, multiz, games, casino, awaymissions, samples, pda, modular_computers, media, library, hydroponics, entrepreneur, resleeving, maintenance_panels, turbolift, blob2, generated_station)

* **A question comes before the effect.** Where an effect asked after doing something, the op asks first: the bookcase-style `asks()` steps replace `rerun_ask` in the
  book (pen), the horoscope, the spirit board, the botany disk, the rift and the ladder. The portal's staff flow shows its guidance text in the first question (it was a chat
  line before the question); a cancel creates nothing (the old flow had already made the portals when the later question was cancelled). The resize portal's own question is
  an op that passes the click on to the bind flow, so it is asked first instead of beside it.
* **A ladder with both ends asks which way** whenever it has both ends; an incomplete ladder or an out-of-reach actor is now told after the question (reach and capability
  are the op's requirements, so a far or incapable actor is refused before it).
* **Actors an effect turned away silently are not offered the op**: silicons on the PDA alt-click and verbs, non-humanoids on the hoist, a cyborg on the research sample
  (its own ops pick up and use it unharmed), a ghost on a portal or modular computer it may not use (a swallow op takes the click, as before).
* **Refusal texts**: a silicon on a ship console without AI control is refused with "Access Denied." (a chat line before); the wheel of fortune's ticket check of an
  existing ticket and the SPASM collar ownership check are told by the handler; the survival capsule's VR refusal is a handler line.
* **Datum periodics are every() since rewrite/gaps-j** (framework_gaps.md J1): `/datum/shuttle`, `/datum/turbolift`, `/datum/generated_station_planner`, `/datum/hose`, `/datum/hose_connector`,
  `/datum/artifact_master`, `/datum/changeling` and the meteor mode declare a type-level `every()` in their `CAPABILITIES` block; `lifeform_datum_new()` arms it when the datum is made.

## Legacy-form sweep (DECLARE_INTERACTIONS, DAMAGE_REACTION, DECLARE_EMAG, DECLARE_PERIODIC, DECLARE_REPEAT), integrator notes

The conversion pins (menu pins and hit/emag pins, `doc/rewrite/snapshot_pins.md`) were recorded on the legacy forms and blessed after the sweep; the rows that changed fall into
these classes, each systematic. No row was blessed that is not one of them.

* **A null-named legacy interaction is a menu entry labelled "Use".** `INTERACT_HAND(null, ...)`, `INTERACT_ITEM(null, ...)` and `INTERACT_USE(null, ...)` were invisible in the menu and the
  screentip; the op has a label, so "Use" (or the op's own label) appears, and `click: nothing` becomes `click: Click: Use` for the held probes the op binds. The effect is the same.
* **The legacy `Emag` menu entry and its "(refused: needs a cryptographic sequencer)" rows go.** The library's `emag()` is item-bound: the card's click does the work, the menu does not list it.
  A refusal is the library's "It is already subverted." where the old handler said its own.
* **Refusal wording.** `REQ_IN_INVENTORY` / `REQ_SELF_HELD` rows ("you need to be carrying it", "not in your hand") are the engine's "not in your hand" / "You can't do that.". Rows for the
  base `/obj/item` defaults changed with the move of the item defaults into ops: "Pick up" (empty hand only, lowest tier), "Collect", "Customise", "Move To Top", "Toggle Digestable".
* **Requirements that read untracked state became handler refusals** (`sem/reads` cannot follow `loc`, `client`, `mind`, `held`, untracked vars through `req()`): the check runs first in the
  handler and answers `OP_DECLINE` after saying its text, so the click goes on to the next candidate as the old failed requirement did. The menu no longer greys such an entry out with the
  reason; the zoom verbs of the scoped guns, the hoist, card decks, the laptop fold, the locket, the gas mask hailer, the spellbook, the deadringer and a few more.
* **Op keys are new** (named from the handler, no `gen_*`): the `keys:` rows of every converted type.
* **Hit hooks.** A hook that took the packet over or rescales it (mecha blast, shield thrown hit, shieldgen EMP, projector EMP, grille blob) is `extend(/datum/act/hit/x, instead(...))`;
  hooks that only react are `on_notice(/datum/notice/hit/x)` and run after the hit lands. A hook that used to run twice on a severity-1 blast (the vendor's sparks, the mecha afflictions) runs once.
* **Hand ops answer with a held item** (engine semantics, final_api section 9: a `hand()` touch is the fallback of a click that no `item()` op took): a smoleworld building clicked with a card
  now crumbles. The generic item "Pick up" is gated on an empty hand to keep the old behaviour.
* **The `/obj/item` and `/turf` default ops sit at the lowest tier** (`OP_PRIORITY_DEFAULT - 10`): the old defaults ran after every type's own interaction.
* **Cosmetic and ambient periodics opt into proximity** (`proximity_tracked`, `when = STAT_RELEVANCE`): they stop when no client is near. Simulation periodics keep running everywhere.
* **`analyze gen reads` emits its table in chunks**: BYOND does not compile one list literal of about 760 assoc entries.

## Integration batch 6 (rewrite/integ-6): pins re-blessed after merging the sweeps with master

Each changed pin row is one of these classes; nothing else was blessed. `dq_interaction_domain_snapshot/i7_bulk` is not re-blessed (a stardog left by an earlier test in the same run poisons it, framework_gaps.md J9).

* **Every simple mob's `keys:` row gains `mob_attacks.*`** (alarm, charge, fire, melee, pickup, shoot, slam, special, step, throw): the AI ops of rewrite/ai-packs, which the sweep's pins predate.
* **A rights refusal reads "You do not have sufficient rights to do that."** (`req_rights`'s own message from rewrite/op-topic) on the ghost-only rows of the bluespace rift, modular computers and the event portal.
* **A SMES's crowbar click is "Deconstruct"** (hatch tools answer before the window, integ-4): the sweep's "Ui open" row is gone.
* **The shield projector's regeneration is one `every()` with a tracked `regenerating`** (the master conversion replaced the sweep's periodic): hit rows read `regenerating: 0 -> 1` where the legacy `periodic_pipe` row was.
* **A machine's break and EMP are stat holds, not a write to `stat`** (machine-stats): the `stat: 0 -> 1` rows of four computers and the shield generator are gone. An EMP's timed hold (and a shield's `after()` flash) owns a timer on the machine, so the machine's `om_rec` appears after the hit (seed storage emp, shield emag, projectile and thrown rows).

## Gaps batch J (rewrite/gaps-j): datum periodics, questions asked from handlers, void suits, labels, sector registry

* **Datum periodics (J1).** A type-level `every()` of a plain datum is armed when the datum is made and parks on a tracked `when =` var like an atom's; a relation view as the gate
  (hose connector, artifact master) polls every interval instead. A shuttle's 2 s step is gated on a tracked `working` that only a shuttle `New()` registered can set, so an idle or
  unregistered shuttle holds no timer (an unregistered one is dropped by its creator, and a polling timer would have kept it alive: the ownership audit's "dropped with a rec").
  A hose, a hose connector and a turbolift step on `0.2 SECONDS`, `2 SECONDS` and `1 SECOND` as their cadences did. Supply payroll is checked on the 20 s supply step
  (`next_payroll` passed) instead of a self-timed repeat: it may run up to 20 s after its time. A changeling's drains, the meteor waves and the station planner's poll keep their intervals;
  a drain that finds no owner now skips (it cannot end its own every()) and the camouflage ends itself through its flag.
* **Questions asked from handlers (J2)** are `asks()` steps of ops: the cat naming (pen and penlight), the sticky pad (a pen), the multibelt's radial and the cyborg coil's colour, the
  stardog's fur pick and Emote Beyond, the nanite goop (two chained steps, the second `when =` the first answered On), a pAI's ID swipe, a think-tank's ghost take-over (`observer()`),
  the face of glamour (create, recall, speak) and the glamour ring.
  * Guards the old handler answered with `return FALSE` (fall through to the next candidate) are `when(req(...))`; a `needs(req(..., silent = TRUE))` would end the click instead.
  * The pAI's item interaction is three ops: an ID swipe while it accepts access changes (asks add/remove, the answer checked again when it arrives), an ID swipe while it does not
    (told so), and the hit or bonk at the lowest tier. A pin row `human|<ID> click: Click: Pat` is now `Click: Use`: the legacy item interaction was shadowed by the help-stance Pat in
    the legacy resolver, so an ID swipe patted the pAI; the hand-written pAI tests drove the handler directly and never saw it. Other held items still pat.
  * A think-tank ghost's click is `Click: Take control` (the pin harness never reached the old observer interaction); the nanite goop's rows say `Interface (refused: )` for actors who may
    not use it, and an AI's click is `Click: Interface`.
  * `get_area()`, `locate_in_list()` and `dq_actor_not_ic_muted()` carry `READS_FROM()` so a requirement may call them. The nanite goop's holder links are declared `ref_one()`.
  * Not converted (the form they need does not exist yet): the mecha pry-component step (a legacy construction ladder), the replicator's consent questions (the answerer is the inserted
    mob, not the op's actor: `op_request_fields()` always sets `answerer = A.actor`), the cyborg gripper's radial (a cancel must go on to use the wrapped item, and its `in_radial_menu`
    state is set while the ring is open), and `code/game/machinery` types (Codex's). `item_attack.dm`, `observer.dm`, `interaction.dm`, `items.dm` and `wall_construction.dm` hold no
    `open_request()` at all.
* **Void suits (J3).** The screwdriver on a suit (void, AutoLok, response team) is `voidsuit_remove_component`: `req_not_worn(SLOT_ID_SUIT)` (the ledger read is the library requirement),
  one `asks()` for the component, and per-type `has_removable_component()` / `removable_components()` (the AutoLok and the response suit never offer a helmet). The pin rows for a
  screwdriver gain `Remove component` and its refusal; a screwdriver click on a suit that holds something is `Click: Remove component` where it was `Voidsuit install item`.
  Ripley's ore detection already reads the pilot slot through `pilot_of()` (OCCUPANT_KEY); a fingerprint card's gloves requirement is `req_actor_slot_empty()`; the card's `attack()` that takes a
  print from another person is a melee override with several different refusals and stays.
* **Labels (menu pins).** An unlabelled `op("hand", hand())` showed as `Hand` (from its key); its legacy form was null-named, so it is `Use` (the class above). The fishing rod's item op is
  `Use` (it was `Fishing rod item`). `Help` (the help-stance touch of `INTERACT_HAND_DEFAULT_AS(I_HELP, "Help", ...)` in item_attack.dm) and `Robot nom (refused: you don't have that ability)`
  are rows of the original recorded pins (ff6247c6f1), not changes: every ability picker is offered to an actor without the ability as a refused entry. Left as they are.
* **Sector registry (J9).** `unregister_z_levels()` removed numbers from `GLOB.map_sectors`, which is keyed by the level as text, so a deleted sector (the stardog's ship) stayed
  registered and the next `get_overmap_sector()` handed out a dying one (`rel_set` refused "is being destroyed" in `i7_bulk` after `dq_conversion_pin`). It removes the text keys it owns.
  `i7_bulk` still fails alone and combined on master for another reason (a gravity generator part's break during its own destroy, `hold(...): the holder is deleted`), which is in
  `code/game/machinery`.

## Window outputs (rewrite/ui-outputs)

Pinned by `dq_ui_data_pin` (`snapshots/ui_pins/`, recorded on the code before the conversion; no row changes) and `dq_ui_outputs_*`.

* **Pushes are once per frame.** The OM push throttle (2 ds per window) is gone: a window gets at most one delivery per tick, in phase R, however many requests and tracked writes reached it. `update_uis()` and `request_push()` queue the same delivery.
* **Status class.** A window's status is re-checked when the user's or host's location, the user's stat, status, hands, equipment, conditions, client or can-act stat publish a key. Hands (`MOB_KEY_HANDS`) and a movable host's move (`ATOM_KEY_LOC`) are new keys; nothing else changed what decides a status.
* **Hand `update_uis()` class.** In the converted hosts (agentcard, appearance_changer, vorepanel_set_attribute, notes panels, the admin panels in `ui_push_converted`) a deleted `update_uis(src)` is replaced by the framework: an op handler that returns TRUE refreshes its window (as before), and an answered question (`open_request` handler) now pushes its owner's windows (and, for a handler on a window, that window's host). Handlers that refused to answer no longer push (the old calls ran on a cancelled answer too).
* **Unban and delete-book panels** track their data (`shown_rows`, `books`, `error_msg`).

## Timed actions as ops (rewrite/timed-tasks)

Pinned by `code/modules/unit_tests/dq_timed_pin_behaviour.dm` (written and green on the legacy `task_timed` / `task_start` forms first; 17 of 18 passed, the 18th leaked the teleport's sparks, now cleaned up; the adapters `running()`, `declared_duration()` and `was_cancelled()` read a pending op as well as a task, every other assertion is unchanged). Each class below is one cause, not one site.

* **Class: the same player starts the action a second time.** The task refused the second action on the same target and the first went on. A bare-hand wait derives `CLAIM_BODY` (it keeps the actor in place), so the second click stops the first wait ("You stop what you were doing.") and starts its own; an item or tool wait also holds the hands. One wait is pending afterwards either way. An op that should run beside another says `claims(NONE)`. Pin: `same_actor_twice` (its refused-second-click lines are legacy-only).
* **Class: the refusal only the old handler wrote.** `whetstone` with fewer than five sheets said "You need 5 [whetstone] to refine it ..."; the binding is `stack(/obj/item/stack/material, 5)` now, so a short stack is not a candidate and the click falls through unanswered. Pin: `whetstone_short_of_sheets` keeps "starts nothing" and "spends nothing" and drops the message line.

## Timed actions as ops, W1 additions

* **Class: the grave marker's fingerprint is added when the placement completes, not at the click.** A refused or cancelled placement leaves no print. Its start and finish lines name the item by template (the legacy text had a tab in "place <tab>he"). Pins: `gravemarker_*` (the prints are not asserted).
* A silent refusal (`req(.., silent = TRUE)`) stops the click, as the legacy handler's `OP_OK` did: not a change (permanent beacon, a UAV with no cell, a grave marker off a turf).

## Timed actions as ops, W3 additions

Pinned by `code/modules/unit_tests/dq_timed_pin_w3_behaviour.dm` (written on the legacy forms; the NIF tool pins call `screwdriver_act()` / `multitool_act()` there and `test_click()` after, because the driver's click does not reach a legacy `*_act` override: the assertions are the same). The goo trap pin `gootrap_free` stops before the end on the legacy form: the legacy end raises a runtime (`act_message` is handed the victims' names as its user), so completion is pinned on the converted form only.

* **Class: a click cooldown set at the start is gone.** The implanter console's `setClickCooldown(DEFAULT_QUICK_COOLDOWN)` at the start of the self-implant; an op's wait holds the actor instead. Pin: `backup_implanter_self_implant`.
* **Class: a legacy runtime that the conversion removes.** `backup_implanter_ch/wrench_done` wrapped a ternary in `span_notice()` (`"<span>" + anchoring ? ...`), a runtime at the end of every wrench; the pins record the start and the cancel only, and the converted form finishes. Pins: `backup_implanter_wrench_off`, `backup_implanter_wrench_on`.
## Timed actions as ops, W4 additions

* **Class: the start message of a few ops names the actor and the item by template.** The fuel tank's detach line says "the device" where it named the rigged assembly, and the outcrop's line reads "%U% begins to hack away at %T%." (the legacy text named `[user]` and was sent to the actor only). The start sounds of the survey beacon and the cup dispenser play at the start (`plays(.., at_start = TRUE, volume = 0.6)`). Pins: `fueltank_rig_and_detach`, `outcrop_dig` check the verb phrase only.
## Timed actions as ops, W2 additions

* **Class: a tool wait is scaled by the tool speed.** The railing wrench and screwdriver, the low wall, drop pod and toilet wrenches and the toilet crowbar waited a fixed time; `tool(Q)` scales `wait()` by the held tool's speed. Pins: `railing_wrench`, `railing_screwdriver`, `droppod_wrench`, `toilet_wrench`, `toilet_crowbar` (run at the default speed, so unchanged).
* **Class: a refusal says the claim message.** A second searcher of a loot or trash pile, and a second lifter on a weight machine, used to get "already being searched" / "already in use"; a claimed target says the engine's claimed message. Pins: `loot_pile_search`, `trash_pile_search`, `weightlifter_lift` (they assert the refusal and that something is said, not the text).
* **Class: a direction read at the end.** A pushed desert rock moves the way its pusher faces when the push ends, not when it began (a turn in place is not a move). Pin: `desert_rock_push`.
* **Class: a refusal the old handler left silent now says why, and a fur tree says it has no sticks.** A fur tree used to swallow "search for sticks" without a word; its `sticks` is now false and the tree's refusal says "You don't see any loose sticks...". Pin: `tree_sticks` (the empty-tree refusal).

## Timed actions as ops: the menu and key rows of dq_conversion_pin (rewrite/timed-tasks)

The snapshot pins were re-blessed once, for these classes (one cause each; the rows are `human|<held> menu/click` and `keys:`):

* **Class: `keys:` rows.** Every converted type gains its ops' keys and loses the legacy handler ids (`item`, `hand`, `attackby`...); `reload` is new on every simple mob (the reload op of a ranged mob). Changes by design (doc/rewrite/snapshot_pins.md).
* **Class: a generic "Use" / "Collect" / "Wash" entry is replaced by the op that does the work.** The converted type offers "Refine", "Burn", "Dig", "Pry open", "Scan anomaly", "Free the victim", "Deploy trap" and so on for the held item that fits; the all-items "Use" entry (a handler that checked the item inside) is gone, and an item that does nothing falls through to the next candidate (pick up, collect) as the handler's `OP_PASS` / `OP_DECLINE` did. A bare hand on an undeployed trap or wire is "Pick up". The sink offers "Wash" for an item only when it is gurgled (the entry used to appear for every item and do nothing).
* **Class: an entry whose op is gated by `needs()` is shown greyed, with its refusal.** "Use screwdriver (refused: )" on a mine, a UAV, a railing or a toilet (a silent refusal has no text); "Search (refused: You see nothing...)" on a potted plant; "Refine (refused: You don't have enough for that.)" on a whetstone with a short stack.
* **Class: the legacy blocks are ops.** "Eject pai blocked" (a crowbar on a bot with a closed panel or no pAI), "Multitool blocked" and "Screwdriver blocked" (a NIF in the wrong state) are the refusals `crowbar_act`, `screwdriver_act` and `multitool_act` ended the click with; they show as refused entries and the tool never falls through to a hit.
* **Class: the medbot's help-intent entry.** "Right or open controls" is "Open controls" (righting a tipped bot is its own op, "Right", beside "Tip over").

## Timed actions as ops, X additions

Pinned by `code/modules/unit_tests/dq_timed_pin_w5_behaviour.dm` (written on the legacy forms) and the earlier pins of the same sites (`e_beacon_*`, `low_wall_*`, `railing_welder`, `barricade_repair`, `flora_uproot`, `grille_window`).

* **Class: a welder that is not lit does not weld.** The railing repair and the reflector weld / cut used to take any welding tool (the reflector only asked for fuel); `lit_welder()` refuses an unlit one with "Turn on the welding tool first!", as every other converted welder op does.
* **Class: a short stack falls through.** The low wall's rods (two) and glass (four) and the grille's window sheet are `stack(T, n)` bindings: a stack that is too small is not this op's, and the click goes on to the wall's "place" op (it used to say "You need at least two rods"). Same shape as the whetstone's short stack.
* **Class: the cost of a stack is taken when the work ends.** The low wall's rods and glass, the grille's sheet and the barricade's sheet are reserved at the end of the wait and spent with the effect (the old handler used them in the done proc, or not at all when the stack was gone).
* **Class: a held item that no longer fits is checked when the click is decided.** The reflector's wrench needs a loose reflector ("Unweld the reflector from the floor first!" is its refusal), the UAV's cell needs a drone with no cell, a shovel uproots only a type that can be removed. Nothing changes for a click that worked.
* **Class: the fingerprint of a low wall build is added at the start.** `starts()`; before it was added at the click, as it is now.
* **Class: the sniper rifle's take-down checks the carrier and the chambered round as requirements.** The legacy verb returned silently for a dead user; the op's `carried()` and `rifle_empty` refuse before the wait.
## Timed actions as ops, Y additions

Pinned by `code/modules/unit_tests/dq_timed_pin_w6_behaviour.dm` (40 pins written and green on the legacy `task_timed` forms before the conversion; `candybowl_repeat_asks` is recorded on the converted form only, because the legacy repeat question was opened by a callback the driver cannot answer in the same way). The existing `candybowl_*` pins (dq_timed_pin_w4) cover the first search.

* **Class: a legacy re-entry that never reached the op is gone.** The event kit structure's delay called `attack_hand()` again past the delay, which never reached its op, so a delayed structure stayed off; the item's `attack_self()` re-entry did work. The converted structure turns on (or off) when the wait ends, like the item. Pin: `generic_structure_delayed` asserts the result on the converted form only.
* **Class: a refusal the old handler wrote is the claim message, and a short stack falls through unanswered.** A second searcher of a candy bowl or a box pile is told the engine's claimed message ("Someone is already working on that.") where the bowl said "someone is already looking through"; a fishing rod with less than five lengths of cable is a `stack(coil, 5)` that does not match, so the click falls through without "You do not have enough length". Pins: `candybowl_one_searcher` (asserts that something is said), `boxpile_one_rummager`, `fishing_rod_string_short_of_cable` (starts nothing, spends nothing).
* **Class: a tool wait is scaled by the tool speed.** The hive's screwdriver waits 3 seconds at the default speed (the legacy wait was fixed). Pin: `beehive_dismantle` (default speed). The legacy start sound is `plays(.., at_start = TRUE)`.
* **Class: the wirecutters on a carved book are a refusal that does not fall through.** `book/carve_cutters_blocked` stands for the `wirecutter_act()` that answered `ITEM_INTERACT_BLOCKING` (the menu-row class above).
* **Class: a click cooldown set at the start is gone (logs).** Cutting a log with an edged item set the user's click cooldown to the cutting time; the wait holds the actor instead (the W3 class). The item is judged by `when(req(...))` with `read_once()` (edge, force), the time by `wait(PROC_REF(cut_time))`. Pins: `log_cut_planks`, `log_cut_cancel_on_move`, `log_blunt_item` (dq_timed_pin_w4).
* The decompression needle names itself by template (`%I%`) where its legacy line named the needle as the target; `used` is tracked and written through its setter. Pins: `decompression_needle*`.
* **Class: a mob worker that strays far from its job finishes it.** The ants' build task ended ("You need to stay still to build") when the worker was more than a tile from the turf; the `ai()` op has no range keep (framework_gaps.md K15), as the spiders' ops. One step aside still builds, as before. Pin: `ant_builder_steps_aside`. The ants' and the mouse's idle checks read `is_working()` (their pending op) where they read `task_busy()`; the bear, savik, goose and mining drone idle checks the same.
* **Class: a refusal the old handler left silent now says why (a welder that is off).** The sensors suite and graffiti welds answered `ITEM_INTERACT_BLOCKING` / `OP_OK` with no word for an unlit welder; `lit_welder(fuel = 0)` says "Turn on the welding tool first!". Pins: `sensors_weld_undamaged`, `graffiti_clear_welder_off` (start nothing). The sensors weld waits `max(5, damage / 5)` as before, scaled by the tool speed (the W2 tool-wait class).

The `dq_conversion_pin` rows that changed for the Y conversions (not blessed; the classes of "the menu and key rows" above): `/obj/structure/meteorite` (the all-items "Use" entry is "Use" for a pickaxe only; items that do nothing show "click: nothing"), `/obj/effect/decal/writing` ("Clear graffiti" for a lit welder; the generic "Engrave" row for the welder is gone), `/obj/item/book` ("Carve cutters" and "carve_cutters_blocked" for wirecutters; keys), `/obj/item/material/fishing_rod` and its subtypes (`fishing_rod_string` key).
## Destructive held-item and hand ops need harm intent (rewrite/om-leftovers)

A held-item op answers a click (a generic "Pick up" only with an empty hand), but an op that destroys, crumbles, dismantles
or consumes its target must not fire on a casual click. Gate it individually with `stance(I_HURT)` or an `asks()` confirm.
Changed: smole buildings and smole ruins no longer flatten when clicked with any item on help intent (harm intent still
does; disarm still takes a building apart by hand); remains crumble only on harm intent. Tool-specific ops (a welder cutting
a closet, a knife slicing food) are deliberate and stay ungated. The supermatter wall's "Touch with", smole buildings and smole ruins are gated by one requirement,
`harm_click_only` (code/datums/operations/req.dm): the item op is declared before the bare-hand op so a held item answers first, and a click not on
harm intent is **refused** with "That would destroy it. Use harm intent if you mean it." rather than falling through to the hand touch (on the wall
that touch dusts the player). Empty hand still touches. The gate is click-path only: a menu pick is deliberate and stays ungated. Remains keep their
hand-op `stance(I_HURT)` (there is no item op, so an item click does nothing destructive). Reviewed and left as is: the stardog/tank "swallow" item ops
(they take the item, not the target).

## Machinery final admission and gravity teardown (2026-10-07)

- Camera attack admission, AI upload level admission, robot remote admission, floor-light custody, suit cycler custom-item admission, and Santa actor identity explicitly sample their current input state with `read_once()`. These samples do not claim a subscription. Menus that sample are rebuilt, including enclosing menus, so mutable instantaneous admission never uses an old generation cache. Tracked-only menus retain their cache. Waiting requirements still require real tracked dependencies for mutable conditions.
- Gravity generator part teardown preserves whole-generator destruction but does not run damage reactions on a deleting part or a deleted main. Destroying a main removes its active power-use membership before recalculating gravity. Ordinary damage still breaks the live generator and switches gravity off.
- The ATM return field hand operation now explicitly displays the existing action as “Use”.

- Cell Charge/Drain menus retain visible disabled rows outside the actual active/inactive hands. Immediate requirements sample the real hand interface, including virtual robot hands. They retain the existing not-in-hand refusal and metabolism/charge effects.

- The DX menu-order test now records surviving click candidates after `when()` filtering, matching runtime dispatch; its all-candidates column remains diagnostic. This fixes premature pickup candidates in 14 item fixture families and does not change gameplay pickup admission. Snapshot differences are reviewed separately.

- The domination cancellation regression expects REQUEST_DEFAULT_TIMEOUT, following framework gap E2: omitted/zero request timeout selects the ten-minute default; only REQUEST_NO_TIMEOUT opts out. Production consent and its decline/cancellation behavior are unchanged.
- I7 bulk capture uses native conversion-pin queries after machinery retired its last legacy interaction declaration. Its former query silently captured empty native targets. The new capture records real menu labels/refusals, selected clicks, native keys, wires and held bindings, with per-target cleanup and persistent-cache prewarming. This is a snapshot instrument migration, not authorization for gameplay changes; each affected class is recorded below when its new capture is reviewed.

- Borg-upload selection keeps its menu admission dependent on power and integrity. The production selection request prepares and rechecks the live free-cyborg catalogue before opening and before accepting an answer; an empty catalogue cancels without displaying a window or changing the selected cyborg. Thus Select cyborg is admitted at the menu and the precise availability check belongs to the request, instead of allocating a roster inside a pure requirement.
- Shuttle authorization restores the visible disabled Authorize row for an empty hand, with the existing needs-a-card refusal. The same item operation handles menu selection; emag authorization remains separate and is not duplicated.

### I7 native capture causes by class

Each row replaces the retired interaction-ID availability format with native menu labels/refusals, selected clicks, native keys, held-binding probes and exposed wires. This records the actual public native queries, not an approval to change gameplay. The class source and inherited declarations were reviewed against the old refusal obligations. Suit cycler, recharge station, shuttle and borg-upload semantic deltas are checked separately before acceptance.

| Class | Declared source context / recording cause |
| --- | --- |
| `/obj/machinery` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`. |
| `/obj/machinery/access_button` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/account_database` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/economy/Accounts_DB.dm`. |
| `/obj/machinery/ai_slipper` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/ai_slipper.dm`. |
| `/obj/machinery/ai_status_display` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/airlock_sensor` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/doors/airlock_control.dm`. |
| `/obj/machinery/alarm` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/air_alarm.dm`. |
| `/obj/machinery/alembic` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/anomaly_harvester` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/anomalies/anomaly_harvester.dm`. |
| `/obj/machinery/artifact_analyser` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/xenoarcheaology/tools/artifact_analyser.dm`. |
| `/obj/machinery/artifact_harvester` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/atm` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/economy/ATM.dm`. |
| `/obj/machinery/atmospherics` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/ATMOSPHERICS/rust_pipenets.dm`. |
| `/obj/machinery/atmospherics/binary/algae_farm` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/atmospherics/binary/passive_gate` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/ATMOSPHERICS/rust_pipenets.dm`, `code/ATMOSPHERICS/components/binary_devices/binary_atmos_base.dm`, `code/ATMOSPHERICS/components/binary_devices/passive_gate.dm`. |
| `/obj/machinery/atmospherics/binary/pump` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/atmospherics/binary/volume_pump` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/atmospherics/omni` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/ATMOSPHERICS/rust_pipenets.dm`, `code/ATMOSPHERICS/components/omni_devices/omni_base.dm`. |
| `/obj/machinery/atmospherics/pipe` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/ATMOSPHERICS/rust_pipenets.dm`, `code/ATMOSPHERICS/pipes/pipe_base.dm`. |
| `/obj/machinery/atmospherics/pipe/tank` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/atmospherics/trinary/atmos_filter` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/ATMOSPHERICS/rust_pipenets.dm`, `code/ATMOSPHERICS/components/trinary_devices/trinary_base.dm`, `code/ATMOSPHERICS/components/trinary_devices/filter.dm`. |
| `/obj/machinery/atmospherics/tvalve` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/ATMOSPHERICS/rust_pipenets.dm`, `code/ATMOSPHERICS/components/tvalve.dm`. |
| `/obj/machinery/atmospherics/tvalve/digital` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/atmospherics/unary/outlet_injector` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/ATMOSPHERICS/rust_pipenets.dm`, `code/ATMOSPHERICS/components/unary/unary_base.dm`, `code/ATMOSPHERICS/components/unary/outlet_injector.dm`. |
| `/obj/machinery/atmospherics/valve` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/atmospherics/valve/digital` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/atmospherics/valve/shutoff` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/ATMOSPHERICS/rust_pipenets.dm`, `code/ATMOSPHERICS/components/valve.dm`, `code/ATMOSPHERICS/components/shutoff.dm`. |
| `/obj/machinery/autolathe` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/autolathe.dm`. |
| `/obj/machinery/beehive` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/biogenerator` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/biogenerator.dm`. |
| `/obj/machinery/bomb_tester` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/bomb_tester.dm`. |
| `/obj/machinery/bookbinder` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/botany` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/hydroponics/seed_machines.dm`. |
| `/obj/machinery/bunsen_burner` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/reagents/machinery/bunsen_burner.dm`. |
| `/obj/machinery/button` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/button/crematorium` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/buttons.dm`, `code/game/objects/structures/morgue.dm`. |
| `/obj/machinery/button/doorbell` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/button/flasher` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/button/garbosystem` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/buttons.dm`, `code/modules/recycling/v_garbosystem.dm`. |
| `/obj/machinery/button/holosign` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/button/ignition` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/button/mob_spawner_button` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/buttons.dm`. |
| `/obj/machinery/button/neonsign` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/button/remote` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/button/remote/airlock/survival_pod` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/buttons.dm`, `code/game/machinery/door_control.dm`, `code/modules/mining/shelter_atoms.dm`. |
| `/obj/machinery/button/remote/airlock/survival_pod/bolts` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/buttons.dm`, `code/game/machinery/door_control.dm`, `code/modules/mining/shelter_atoms.dm`. |
| `/obj/machinery/button/remote/driver` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/button/windowtint` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/buttons.dm`, `code/game/objects/structures/window.dm`. |
| `/obj/machinery/cablelayer` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/CableLayer.dm`. |
| `/obj/machinery/camera` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/cash_register` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/economy/cash_register.dm`. |
| `/obj/machinery/casino_prize_dispenser` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/casino/casino_prize_vendor.dm`. |
| `/obj/machinery/casinosentientprize_handler` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/chem_master` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/reagents/machinery/chem_master.dm`. |
| `/obj/machinery/chemical_analyzer` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/reagents/machinery/chemalyzer.dm`. |
| `/obj/machinery/chemical_dispenser` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/chemical_synthesizer` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/reagents/machinery/dispenser/chem_synthesizer.dm`. |
| `/obj/machinery/chipmachine` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/economy/casinocash.dm`. |
| `/obj/machinery/clamp` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/compressor` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/power/turbine.dm`. |
| `/obj/machinery/computer` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/computer/aifixer` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/computer/aiupload` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/computer/computer.dm`, `code/game/machinery/computer/law.dm`. |
| `/obj/machinery/computer/arcade` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/computer/computer.dm`, `code/game/machinery/computer/arcade.dm`. |
| `/obj/machinery/computer/arcade/clawmachine` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/computer/arcade/orion_trail` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/computer/computer.dm`, `code/game/machinery/computer/arcade.dm`, `code/modules/admin/orion_trail_panel.dm`. |
| `/obj/machinery/computer/borgupload` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/computer/card` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/computer/communications` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/computer/computer.dm`, `code/game/machinery/computer/communications.dm`. |
| `/obj/machinery/computer/crew` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/computer/cryopod` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/computer/fusion_core_control` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/computer/computer.dm`, `code/modules/power/fusion/core/core_control.dm`. |
| `/obj/machinery/computer/fusion_fuel_control` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/computer/guestpass` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/computer/gyrotron_control` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/computer/computer.dm`, `code/modules/power/fusion/gyrotron/gyrotron_control.dm`. |
| `/obj/machinery/computer/message_monitor` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/computer/pandemic` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/computer/pod` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/computer/computer.dm`, `code/game/machinery/computer/pod.dm`. |
| `/obj/machinery/computer/pod/old/syndicate` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/computer/computer.dm`, `code/game/machinery/computer/pod.dm`. |
| `/obj/machinery/computer/power_monitor` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/computer/prison_shuttle` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/computer/computer.dm`, `code/game/machinery/computer/prisonshuttle.dm`. |
| `/obj/machinery/computer/rdconsole_tg` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/computer/rdservercontrol` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/computer/robotics` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/computer/computer.dm`, `code/game/machinery/computer/robot.dm`. |
| `/obj/machinery/computer/roguezones` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/computer/secure_data` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/computer/security` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/computer/computer.dm`, `code/game/machinery/computer/camera.dm`. |
| `/obj/machinery/computer/ship` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/computer/computer.dm`, `code/modules/flight_operations/flight_console.dm`. |
| `/obj/machinery/computer/ship/navigation/telescreen/dog_eye` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/computer/shutoff_monitor` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/computer/computer.dm`, `code/game/machinery/computer/shutoff_monitor.dm`. |
| `/obj/machinery/computer/shuttle` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/computer/shuttle_control/emergency` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/computer/shuttle_control/web` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/computer/computer.dm`, `code/modules/shuttles/shuttle_console.dm`, `code/modules/shuttles/shuttles_web.dm`. |
| `/obj/machinery/computer/skills` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/computer/specops_shuttle` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/computer/station_alert` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/computer/computer.dm`, `code/game/machinery/computer/station_alert.dm`. |
| `/obj/machinery/computer/stockexchange` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/computer/supplycomp` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/computer/telecomms/monitor` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/computer/computer.dm`, `code/game/machinery/telecomms/telemonitor.dm`. |
| `/obj/machinery/computer/telecomms/server` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/computer/telecomms/traffic` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/computer/teleporter` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/computer/computer.dm`, `code/game/machinery/teleporter.dm`. |
| `/obj/machinery/computer/telescience` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/computer/timeclock` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/computer/turbine_computer` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/computer/computer.dm`, `code/modules/power/turbine.dm`. |
| `/obj/machinery/containment_field` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/power/singularity/containment_field.dm`. |
| `/obj/machinery/conveyor` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/conveyor_switch` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/recycling/conveyor2.dm`. |
| `/obj/machinery/cryopod` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/cryopod.dm`. |
| `/obj/machinery/department_storefront` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/deployable/barrier` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/deployable.dm`. |
| `/obj/machinery/disposal` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/recycling/disposal_machines.dm`. |
| `/obj/machinery/disposal/deliveryChute` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/dnaforensics` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/detectivework/microscope/dnascanner.dm`. |
| `/obj/machinery/door` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/door/airlock` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/door/airlock/phoron` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/doors/door.dm`, `code/game/machinery/doors/airlock.dm`. |
| `/obj/machinery/door/blast` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/doors/door.dm`, `code/game/machinery/doors/blast_door.dm`. |
| `/obj/machinery/door/blast/puzzle` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/door/firedoor` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/doors/door.dm`, `code/game/machinery/doors/firedoor.dm`. |
| `/obj/machinery/door/unpowered` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/doors/door.dm`, `code/game/machinery/doors/unpowered.dm`. |
| `/obj/machinery/door/window` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/door/window/holowindoor` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/doors/door.dm`, `code/game/machinery/doors/windowdoor.dm`. |
| `/obj/machinery/doorbell_chime` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/doorbell.dm`. |
| `/obj/machinery/doppler_array` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/embedded_controller` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/embedded_controller/embedded_controller_base.dm`. |
| `/obj/machinery/exonet_node` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/exonet_node.dm`. |
| `/obj/machinery/feeder` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/field_generator` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/power/singularity/field_generator.dm`. |
| `/obj/machinery/firealarm` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/fire_alarm.dm`. |
| `/obj/machinery/firework_launcher` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/floodlight` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/floodlight.dm`. |
| `/obj/machinery/floor_light` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/floor_light.dm`. |
| `/obj/machinery/floorlayer` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/food_replicator` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/food_replicator.dm`. |
| `/obj/machinery/fusion_fuel_compressor` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/power/fusion/fuel_assembly/fuel_compressor.dm`. |
| `/obj/machinery/fusion_fuel_injector` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/gear_dispenser` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/gear_dispenser.dm`. |
| `/obj/machinery/gear_dispenser/suit_fancy` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/gear_painter` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/generated_station_department_control` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/generated_station/generated_station_runtime.dm`. |
| `/obj/machinery/generated_station_upload_terminal` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/generated_station/generated_station_objectives.dm`. |
| `/obj/machinery/giga_drill` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/gravity_generator/main` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/power/gravitygenerator.dm`. |
| `/obj/machinery/gravity_generator/part` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/power/gravitygenerator.dm`. |
| `/obj/machinery/hologram/holopad` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/holoplant` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/objects/structures/holoplant.dm`. |
| `/obj/machinery/honey_extractor` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/hydroponics/beekeeping/beehive.dm`. |
| `/obj/machinery/hyperpad` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/hyperpad/centre` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/telesci/hyper_pad.dm`. |
| `/obj/machinery/igniter` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/igniter.dm`. |
| `/obj/machinery/implantchair` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/injector_maker` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/reagents/machinery/injector_maker.dm`. |
| `/obj/machinery/item_bank` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/client/stored_item.dm`. |
| `/obj/machinery/keycard_auth` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/lapvend` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/modular_computers/laptop_vendor.dm`. |
| `/obj/machinery/librarycomp` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/library/lib_machines.dm`. |
| `/obj/machinery/librarypubliccomp` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/libraryscanner` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/library/lib_machines.dm`. |
| `/obj/machinery/librarywikicomp` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/library/wikicomp.dm`. |
| `/obj/machinery/light` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/light/flamp` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/power/lighting.dm`. |
| `/obj/machinery/light/small/torch` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/light_construct` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/light_switch` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/lightswitch.dm`. |
| `/obj/machinery/light_switch/survival_pod` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/magnetic_controller` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/maint_recycler` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/maint_recycler/code/maint_recycler.dm`. |
| `/obj/machinery/maint_vendor` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/maint_recycler/code/maint_vendor.dm`. |
| `/obj/machinery/material_furnace` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/mecha_part_fabricator_tg` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/research/tg/machinery/mech_fabricator.dm`. |
| `/obj/machinery/mecha_part_fabricator_tg/prosthetics` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/media/jukebox` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/message_server` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/research/message_server.dm`. |
| `/obj/machinery/microscope` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/detectivework/microscope/microscope.dm`. |
| `/obj/machinery/mineral/equipment_vendor` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/mineral/mint` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/economy/mint.dm`. |
| `/obj/machinery/mineral/processing_unit_console` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/mining/machinery/machine_processing.dm`. |
| `/obj/machinery/mining/brace` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/mining/drill` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/mining/drilling/drill.dm`. |
| `/obj/machinery/navbeacon` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/navbeacon.dm`. |
| `/obj/machinery/newscaster` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/nuclearbomb` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/nuclear_bomb.dm`. |
| `/obj/machinery/papershredder` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/paperwork/papershredder.dm`. |
| `/obj/machinery/particle_accelerator` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/particle_accelerator/control_box` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/power/singularity/particle_accelerator/particle_accelerator.dm`, `code/modules/power/singularity/particle_accelerator/particle_control.dm`. |
| `/obj/machinery/particle_smasher` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/power/singularity/particle_accelerator/particle_smasher.dm`. |
| `/obj/machinery/partslathe` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/partyalarm` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/fire_alarm.dm`. |
| `/obj/machinery/pda_multicaster` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/pda_multicaster.dm`. |
| `/obj/machinery/photocopier` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/photocopier/faxmachine` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/paperwork/photocopier.dm`, `code/modules/paperwork/faxmachine.dm`. |
| `/obj/machinery/pipedispenser` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/pipe/pipe_dispenser.dm`. |
| `/obj/machinery/pipedispenser/disposal` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/pipelayer` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/pipe/pipelayer.dm`. |
| `/obj/machinery/porta_turret` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/portable_turret.dm`. |
| `/obj/machinery/porta_turret_construct` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/portable_atmospherics` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/atmoalter/portable_atmospherics.dm`. |
| `/obj/machinery/portable_atmospherics/canister` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/portable_atmospherics/hydroponics` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/portable_atmospherics/hydroponics/soil` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/atmoalter/portable_atmospherics.dm`, `code/modules/hydroponics/trays/tray.dm`, `code/modules/hydroponics/trays/tray_soil.dm`. |
| `/obj/machinery/portable_atmospherics/powered` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/portable_atmospherics/powered/pump/huge` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/portable_atmospherics/powered/reagent_distillery` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/atmoalter/portable_atmospherics.dm`, `code/modules/reagents/machinery/distillery.dm`. |
| `/obj/machinery/portable_atmospherics/powered/scrubber/huge` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/atmoalter/portable_atmospherics.dm`, `code/game/machinery/atmoalter/scrubber.dm`. |
| `/obj/machinery/power` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/power/apc` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/power/power.dm`, `code/modules/power/apc.dm`. |
| `/obj/machinery/power/breakerbox` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/power/emitter` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/power/emitter/gyrotron` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/power/power.dm`, `code/modules/power/singularity/emitter.dm`, `code/modules/power/fusion/gyrotron/gyrotron.dm`. |
| `/obj/machinery/power/fusion_core` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/power/generator` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/power/grid_checker` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/power/power.dm`, `code/modules/power/grid_checker.dm`. |
| `/obj/machinery/power/grounding_rod` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/power/port_gen` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/power/port_gen/large_altevian` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/power/power.dm`, `code/modules/power/port_gen.dm`. |
| `/obj/machinery/power/port_gen/pacman` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/power/power.dm`, `code/modules/power/port_gen.dm`. |
| `/obj/machinery/power/quantumpad` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/power/rad_collector` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/power/power.dm`, `code/modules/power/singularity/collector.dm`. |
| `/obj/machinery/power/rtg/abductor` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/power/rtg/reg` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/power/shield_generator` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/power/power.dm`, `code/modules/shieldgen/shield_generator.dm`. |
| `/obj/machinery/power/singularity_beacon` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/power/smes/batteryrack` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/power/solar` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/power/power.dm`, `code/modules/power/solar.dm`. |
| `/obj/machinery/power/supermatter` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/power/supply_beacon` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/power/tesla_coil` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/power/power.dm`, `code/modules/power/tesla/coil.dm`. |
| `/obj/machinery/power/thermoregulator` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/power/turbine` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/processor` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/xenobio/machinery/processor.dm`. |
| `/obj/machinery/pump` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/reagents/machinery/pump.dm`. |
| `/obj/machinery/radiocarbon_spectrometer` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/readybutton` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/holodeck/HolodeckObjects.dm`. |
| `/obj/machinery/reagent_refinery` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/reagent_refinery/filter` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/reagent_refinery/furnace` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/refinery/core/industrial_reagent_machines.dm`, `code/modules/refinery/core/industrial_reagent_furnace.dm`. |
| `/obj/machinery/reagent_refinery/grinder` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/reagent_refinery/mixer` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/reagent_refinery/pump` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/refinery/core/industrial_reagent_machines.dm`, `code/modules/refinery/core/industrial_reagent_pump.dm`. |
| `/obj/machinery/reagent_refinery/vat` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/refinery/core/industrial_reagent_machines.dm`, `code/modules/refinery/core/industrial_reagent_vat.dm`. |
| `/obj/machinery/reagent_refinery/waste_processor` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/reagentgrinder` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/reagents/machinery/grinder.dm`. |
| `/obj/machinery/recharge_station` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/rechargestation.dm`. |
| `/obj/machinery/recycling` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/replicator` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/xenoarcheaology/artifacts/replicator.dm`. |
| `/obj/machinery/requests_console` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/requests_console.dm`. |
| `/obj/machinery/rnd` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/rnd/destructive_analyzer` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/research/tg/rdmachines.dm`, `code/modules/research/tg/machinery/destructive_analyzer.dm`. |
| `/obj/machinery/rnd/server/master` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/robotic_fabricator` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/seed_extractor` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/seed_extractor.dm`. |
| `/obj/machinery/seed_storage` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/hydroponics/seed_storage.dm`. |
| `/obj/machinery/shield` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/shield_capacitor` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/shieldgen/shield_capacitor.dm`. |
| `/obj/machinery/shield_diffuser` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/shieldgen/shield_diffuser.dm`. |
| `/obj/machinery/shield_gen` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/shieldgen` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/shieldgen/emergency_shield.dm`. |
| `/obj/machinery/shieldwall` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/shieldgen/sheldwallgen.dm`. |
| `/obj/machinery/shieldwallgen` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/shower` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/objects/structures/watercloset.dm`. |
| `/obj/machinery/slot_machine` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/casino/slots.dm`. |
| `/obj/machinery/smart_centrifuge` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/space_heater` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/spaceheater.dm`. |
| `/obj/machinery/station_map` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/holomap/station_holomap.dm`. |
| `/obj/machinery/station_slot_machine` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/status_display` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/status_display.dm`. |
| `/obj/machinery/suit_cycler` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/suit_storage/suit_cycler.dm`. |
| `/obj/machinery/suit_storage_unit` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/suspension_gen` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/xenoarcheaology/tools/suspension_generator.dm`. |
| `/obj/machinery/syndicate_beacon` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/syndicatebeacon.dm`. |
| `/obj/machinery/syndicate_beacon/virgo` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/telecomms` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/telecomms/telecomunications.dm`. |
| `/obj/machinery/telepad` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/telesci/telepad.dm`. |
| `/obj/machinery/the_singularitygen` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/transportpod` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/transportpod.dm`. |
| `/obj/machinery/turretid` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/turret_control.dm`. |
| `/obj/machinery/v_garbosystem` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/vr_sleeper` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/virtual_reality/vr_console.dm`. |
| `/obj/machinery/vr_sleeper/alien` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/virtual_reality/vr_console.dm`, `code/game/machinery/virtual_reality/ar_console.dm`. |
| `/obj/machinery/washing_machine` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. |
| `/obj/machinery/wheel_of_fortune` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/modules/casino/casino.dm`. |
| `/obj/machinery/wish_granter` | machinery native ops and inherited machine admission; native labels, refusals, selected clicks and keys replace legacy IDs. Reviewed source: `code/datums/behaviours/burning.dm`, `code/game/machinery/machinery.dm`, `code/game/machinery/wishgranter.dm`. |

- Suit cycler retains the disabled Put in cycler, Fit helmet and Fit voidsuit rows when the required grab/void helmet/voidsuit is absent. Recharge station retains disabled Replace parts and both Put in recharger routes with the original rapid-part-exchanger/grab/mob refusals. Native menu bindings now preserve these legacy rows; physical item/drag bindings, vacancy predicates, rig exclusions and actual insertion effects remain the existing routes.
- Synchronous request opening assigns its declared step name before invoking opening callbacks. A cancellation or synchronous answer owns continuation immediately; the opening caller does not attach an already closed request or overwrite a subsequent question. This corrects request lifecycle bookkeeping, not prompt availability or answer policy.

### Machinery round 2: reviewed DX menu-order capture (2026-10-07)

The complete focused capture changes 332 of 334 dynamic scenarios; the other two dynamic scenarios and all 247 static rows are retained. Every previous menu key remains in its previous relative order. Of the changed scenarios, 282 add menu rows already declared by the merged native item, turf or bot operations. The remaining 50 change only click diagnostics: the capture now applies `op_resolution_matches()` and records the same `when()` survivors used by real dispatch, rather than the unfiltered pass-one candidates. This does not change click dispatch or admission policy.

The all-candidates column is diagnostic only; it also records merged native and inherited declarations. The click column filters inactive robot, claw, door, storage and intent candidates using their existing predicates. No new predicate, priority, refusal or effect is approved by this capture refresh.

| Captured target class | Changed scenarios | Reviewed cause |
|---|---:|---|
| `/obj/machinery/door/airlock` | 14 | Menu keys and order are unchanged. Click diagnostics now exclude inactive candidates through the existing `when()` predicates (including robot remote, claw and closed-door alternatives); actual dispatch already used this filter. |
| `/obj/structure/firedoor_assembly` | 14 | Twelve held-item scenarios gain only the inherited item `move_to_top` and `toggle_digestable` menu rows documented by the object-default sweep. Two empty-hand scenarios keep their menus. Existing click predicates are now reflected in the diagnostic column. |
| `/obj/structure/door_assembly` | 14 | Twelve held-item scenarios gain only the inherited item `move_to_top` and `toggle_digestable` menu rows documented by the object-default sweep. Two empty-hand scenarios keep their menus. Existing click predicates are now reflected in the diagnostic column. |
| `/obj/item/reagent_containers/glass/paint` | 14 | Merged base item defaults add `collect_item`, `move_to_top`, `pick_up_item` and `toggle_digestable` menu keys (object-default sweep documented above; `/obj/item` block in robot/component.dm). Click adds only the applicable collection/pickup bindings; existing storage/reagent `when()` predicates filter inactive candidates. |
| `floor` | 13 | Merged turf item/touch/crawl operations and floor help/disarm/grab/hurt/graffiti operations are now captured (turf.dm and floor_acts.dm, documented turf sweep). Their existing low priorities and stance predicates remain. Held item defaults add Move To Top/Toggle Digestable. |
| `box` | 13 | The storage-box alias gains only inherited item Collect/Move To Top/Toggle Digestable menu rows from the documented object-default sweep. Existing storage menu order remains; inactive storage click alternatives are filtered by their current predicates. |
| `/obj/item/storage/backpack/holding` | 14 | Merged base item defaults add `collect_item`, `move_to_top`, `pick_up_item` and `toggle_digestable` menu keys (object-default sweep documented above; `/obj/item` block in robot/component.dm). Click adds only the applicable collection/pickup bindings; existing storage/reagent `when()` predicates filter inactive candidates. |
| `/obj/item/storage/backpack/holding/duffle` | 14 | Merged base item defaults add `collect_item`, `move_to_top`, `pick_up_item` and `toggle_digestable` menu keys (object-default sweep documented above; `/obj/item` block in robot/component.dm). Click adds only the applicable collection/pickup bindings; existing storage/reagent `when()` predicates filter inactive candidates. |
| `/obj/item/storage/bible` | 14 | Merged base item defaults add `collect_item`, `move_to_top`, `pick_up_item` and `toggle_digestable` menu keys (object-default sweep documented above; `/obj/item` block in robot/component.dm). Click adds only the applicable collection/pickup bindings; existing storage/reagent `when()` predicates filter inactive candidates. |
| `/obj/item/storage/box` | 14 | Merged base item defaults add `collect_item`, `move_to_top`, `pick_up_item` and `toggle_digestable` menu keys (object-default sweep documented above; `/obj/item` block in robot/component.dm). Click adds only the applicable collection/pickup bindings; existing storage/reagent `when()` predicates filter inactive candidates. |
| `/obj/item/storage/box/matches` | 14 | Merged base item defaults add `collect_item`, `move_to_top`, `pick_up_item` and `toggle_digestable` menu keys (object-default sweep documented above; `/obj/item` block in robot/component.dm). Click adds only the applicable collection/pickup bindings; existing storage/reagent `when()` predicates filter inactive candidates. |
| `/obj/item/storage/pill_bottle` | 14 | Merged base item defaults add `collect_item`, `move_to_top`, `pick_up_item` and `toggle_digestable` menu keys (object-default sweep documented above; `/obj/item` block in robot/component.dm). Click adds only the applicable collection/pickup bindings; existing storage/reagent `when()` predicates filter inactive candidates. |
| `/obj/item/storage/lockbox` | 14 | Merged base item defaults add `collect_item`, `move_to_top`, `pick_up_item` and `toggle_digestable` menu keys (object-default sweep documented above; `/obj/item` block in robot/component.dm). Click adds only the applicable collection/pickup bindings; existing storage/reagent `when()` predicates filter inactive candidates. |
| `/obj/item/storage/secure` | 14 | Merged base item defaults add `collect_item`, `move_to_top`, `pick_up_item` and `toggle_digestable` menu keys (object-default sweep documented above; `/obj/item` block in robot/component.dm). Click adds only the applicable collection/pickup bindings; existing storage/reagent `when()` predicates filter inactive candidates. |
| `/obj/item/storage` | 14 | Merged base item defaults add `collect_item`, `move_to_top`, `pick_up_item` and `toggle_digestable` menu keys (object-default sweep documented above; `/obj/item` block in robot/component.dm). Click adds only the applicable collection/pickup bindings; existing storage/reagent `when()` predicates filter inactive candidates. |
| `/obj/item/storage/quickdraw` | 14 | Merged base item defaults add `collect_item`, `move_to_top`, `pick_up_item` and `toggle_digestable` menu keys (object-default sweep documented above; `/obj/item` block in robot/component.dm). Click adds only the applicable collection/pickup bindings; existing storage/reagent `when()` predicates filter inactive candidates. |
| `/obj/item/reagent_containers/glass/beaker` | 14 | Merged base item defaults add `collect_item`, `move_to_top`, `pick_up_item` and `toggle_digestable` menu keys (object-default sweep documented above; `/obj/item` block in robot/component.dm). Click adds only the applicable collection/pickup bindings; existing storage/reagent `when()` predicates filter inactive candidates. |
| `/obj/item/reagent_containers/spray` | 14 | Merged base item defaults add `collect_item`, `move_to_top`, `pick_up_item` and `toggle_digestable` menu keys (object-default sweep documented above; `/obj/item` block in robot/component.dm). Click adds only the applicable collection/pickup bindings; existing storage/reagent `when()` predicates filter inactive candidates. |
| `/obj/structure/bed/chair` | 14 | Twelve held-item scenarios gain only the inherited item `move_to_top` and `toggle_digestable` menu rows documented by the object-default sweep. Two empty-hand scenarios keep their menus. Existing click predicates are now reflected in the diagnostic column. |
| `/obj/machinery/vending` | 14 | Menu keys and order are unchanged. Click diagnostics now exclude inactive candidates through the existing `when()` predicates (including robot remote, claw and closed-door alternatives); actual dispatch already used this filter. |
| `/mob/living/bot/floorbot` | 12 | The merged base bot `bot_item` operation in bot.dm is now captured, plus the held item Move To Top/Toggle Digestable defaults. Existing controls/menu order remains; this records the native wrapper for the existing item interaction. |
| `/mob/living/bot/medbot` | 14 | Merged native `bot_item`, `medbot_item` and four stance-specific hand operations in medbot.dm now appear. These preserve the previously documented medbot help/right/controls and disarm/tip-over behavior. Only the help binding survives the fixture click intent; held item defaults also appear. |
| `/obj/machinery/power/apc` | 14 | Menu keys and order are unchanged. Click diagnostics now exclude inactive candidates through the existing `when()` predicates (including robot remote, claw and closed-door alternatives); actual dispatch already used this filter. |
| `/obj/structure/table` | 14 | Twelve held-item scenarios gain only the inherited item `move_to_top` and `toggle_digestable` menu rows documented by the object-default sweep. Two empty-hand scenarios keep their menus. Existing click predicates are now reflected in the diagnostic column. |

### Upload-console module click restoration (2026-10-07)

For `/obj/machinery/computer/borgupload` and `/obj/machinery/computer/aiupload`, a physically held AI law module selects Install module ahead of the inherited generic computer Use item fallback. The installation bindings use the default tier and their specific AI-module type wins over the generic item binding. The AI console narrows only the physical binding to modules; its existing menu binding, missing-item refusal, contact-level requirement and non-module fallback remain. Native snapshots record this restored click and the corresponding installation menu ordering. Public-click regressions assert the production recipient's exact installed supplied law, not only a selected key.

### Machinery conversion-pin refusal and access parity (2026-10-07)

- `/obj/machinery/camera`: native menu bindings retain disabled Use, Bug camera, Attack and Slash rows and their original missing-item/camera-bug/not-possible refusals. Physical attack/shred predicates still filter inappropriate clicks. Paper/PDA Show to camera remains a multi-item domain offered only with a matching held item. Immediate injury-kind changes update the disabled/enabled Attack row without cache publication.
- `/obj/machinery/doppler_array`: Replace parts retains its disabled needs-a-rapid-part-exchange-device row; the actual held-tool operation is unchanged.
- `/obj/machinery/ai_status_display`: the item-touch Use row retains its missing-item refusal for empty hands; actual item touches continue through the same handler.
- `/obj/machinery/computer/pandemic`: Insert beaker retains its disabled inappropriate-item row and existing occupied-slot refusal. Inappropriate physical item clicks still fall through; real glass and syringe insertions retain their state and custody effects.
- `/obj/machinery/computer/pod/old/syndicate`: generated Ui open now enforces the same syndicate credentials as the existing custom hand operation. This closes a public window bypass; credentialed users still open it. The disabled uncredentialed row records this real access correction, not an instrument-only change. Existing ghost behavior is unchanged.
- `/obj/machinery/computer/prison_shuttle`: generated Ui open now enforces the existing security-or-hacked requirement and prison-route condition, closing the corresponding public window bypass. Public credentialed acceptance and broken-route refusal remain tested. The separate Emag-row removal is the previously documented policy.

- Pandemic compatible-container clicks now choose Insert beaker above the generic computer Use item fallback. Its existing appropriate-container predicate still passes invalid items to the generic route. Beaker and syringe regressions assert actual public-click selection, slot contents, physical location and hand custody; occupied-slot refusals preserve both containers.
## Final native admission and shared-pin review

The AI status-display touch and Pandemic insert-beaker menu bindings explicitly require adjacency and action capability, matching their physical binding gates. Focused regressions use a distant actor and a real STAT_CAN_ACT veto and assert refusal and unchanged hand/slot custody before successful adjacent use. The native capability contract reads that stat; it is not a test-specific handler override.

Camera Attack also corrects a legacy receiver bug: the old PRED_HELD requirement attempted to call the camera's held_is_bashing predicate on the held item. Native admission invokes the camera predicate with the actual actor and held item, so twelve ordinary blunt-item probes that were incorrectly gray now enable. The injury-kind regression checks both rejected and accepted real damage. Show-to-camera remains limited to its actual paper/PDA input domain; unrelated held-item gray rows are intentionally absent.

The 227 conversion-pin files whose types also occur in I7 use the same native producer, actor/item probes, seed, fixture normalization and cleanup. Their refresh uses the reviewed canonical I7 records only. Per-class causes are listed in the 283-class table above and the six specific restoration/access cases above; removal of stale 'material processor in the way' refusals comes from isolated per-target cleanup. The other 735 global conversion-pin files are neither refreshed nor claimed verified by this batch.

## Machinery final pin completion (2026-10-07)

The initial capture used codex/machinery-final-1007 at 5a09c4e569, whose tree is identical to integration merge 8d0de1539c. The subsequent repair changes only the hit-test producer; production behavior is unchanged. These 155 classes account for 2,513 differing conversion rows. The electronic-assembly op clash and anomalock-heart runtime remain unchanged; neither is blessed away.

`robot_remote_blocked` replaces the inherited legacy key `gen_robot_interaction_swallow`. Its physical requirement still checks the robot remote-view context; the menu entry retains its separate refusal. This is an operation-key migration, not removal of the robot remote restriction.

Wish granter **nothing → Touch** and mob spawner button **nothing → Spawn mob** are intended screentip changes. Both labels already existed on origin/master's legacy hand interactions; the native-only screentip query omitted them before conversion. The existing wish sequence/charge handling and spawner choices/effects remain in their handlers. This source review is not an extra execution of those effects.

| Class | Removed / added rows | Cause |
|---|---:|---|
| `/mob/living/simple_mob/vore/overmap/stardog` | 1 / 1 | The same construction/ownership failure remains recorded; only its diagnostic source path moved from code/datums/lifecycle/links.dm to code/engine/refs/lifecycle_links.dm. Do not remove or mask construction fault; only old lifecycle-links file moved into engine/refs. |
| `/obj/item/am_containment` | 53 / 20 | Inherited /obj/item native defaults: pickup is empty-hand-only; Collect and Customise are typed held-item inputs; Move To Top and Toggle Digestable are menu ops, with engine adjacency/capability/carried refusals. These explain changed generic rows independently of this subtype. Its own only capability entry is an explosion interception; no new interactive effect. |
| `/obj/item/camera_assembly` | 62 / 33 | Inherited /obj/item native defaults: pickup is empty-hand-only; Collect and Customise are typed held-item inputs; Move To Top and Toggle Digestable are menu ops, with engine adjacency/capability/carried refusals. These explain changed generic rows independently of this subtype. Native hand/item Use ops now select the existing assembly interaction handlers; held input domain adds /obj/item probe. Typed screentip capture previously omitted legacy handlers. |
| `/obj/item/card/id/guest` | 105 / 20 | Inherited /obj/item native defaults: pickup is empty-hand-only; Collect and Customise are typed held-item inputs; Move To Top and Toggle Digestable are menu ops, with engine adjacency/capability/carried refusals. These explain changed generic rows independently of this subtype. without(show) removes inherited duplicate card display; show_pass uses one in_hand op for help/disarm/grab and deactivate_pass is hurt-stance in_hand plus confirmed deactivation. Not-in-hand and wrong-stance legacy gray alternatives disappear via binding/stance Match, not new acceptance. |
| `/obj/item/cell/device/weapon/gunsword` | 25 / 34 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. The held-cell probes inherit the restored Charge/Drain not-in-hand refusal rows and native cell injection Use route. |
| `/obj/item/cell/device/weapon/recharge/alien` | 90 / 53 | Inherited /obj/item native defaults: pickup is empty-hand-only; Collect and Customise are typed held-item inputs; Move To Top and Toggle Digestable are menu ops, with engine adjacency/capability/carried refusals. These explain changed generic rows independently of this subtype. Subtype self in_hand op is default tier above inherited charge/drain default-minus-one, preserving mode swap. Parent inject_cell adds typed item Use and missing-item menu route; electrovore charge/drain menu routes explicitly retain not-in-hand refusal. |
| `/obj/item/cell` | 25 / 34 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. The held-cell probes inherit the restored Charge/Drain not-in-hand refusal rows and native cell injection Use route. |
| `/obj/item/cell/void` | 90 / 53 | Inherited /obj/item native defaults: pickup is empty-hand-only; Collect and Customise are typed held-item inputs; Move To Top and Toggle Digestable are menu ops, with engine adjacency/capability/carried refusals. These explain changed generic rows independently of this subtype. Subtype self in_hand op is default tier above inherited charge/drain, preserving mode swap; parent cell native routes add injection Use. Parent charge/drain now explicitly retain their disabled not-in-hand menu routes. |
| `/obj/item/deskbell` | 0 / 18 | The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Native menu enumeration now includes the disabled AI/ghost compatibility rows; the effects and refusal gates are unchanged. Only rows added, no removal/effect change; underlying legacy requirement refuses these participants. Compatibility menu producer now exposes real refusal rows. |
| `/obj/item/flashlight/flare` | 0 / 3 | The held-cell probes inherit the restored Charge/Drain not-in-hand refusal rows and native cell injection Use route. |
| `/obj/item/flashlight/glowstick` | 0 / 3 | The held-cell probes inherit the restored Charge/Drain not-in-hand refusal rows and native cell injection Use route. |
| `/obj/item/flashlight` | 0 / 3 | The held-cell probes inherit the restored Charge/Drain not-in-hand refusal rows and native cell injection Use route. |
| `/obj/item/floor_light` | 66 / 20 | Inherited /obj/item native defaults: pickup is empty-hand-only; Collect and Customise are typed held-item inputs; Move To Top and Toggle Digestable are menu ops, with engine adjacency/capability/carried refusals. These explain changed generic rows independently of this subtype. install is in_hand Use, so floor-target probes do not offer legacy out-of-hand self-use. Its actual custody requirement samples real release_refusal and consume rechecks; focused integration proves blocked then accepted installation. |
| `/obj/item/fuel_assembly/blitz/unshielded` | 64 / 45 | Inherited /obj/item native defaults: pickup is empty-hand-only; Collect and Customise are typed held-item inputs; Move To Top and Toggle Digestable are menu ops, with engine adjacency/capability/carried refusals. These explain changed generic rows independently of this subtype. own pick_up hand override remains. Native item operation retains shielding effect but omits label; op_label synthesizes Unshielded lead shell from key unshielded_lead_shell, replacing legacy Use. |
| `/obj/item/implant/integrated_circuit` | 0 / 3 | The held-cell probes inherit the restored Charge/Drain not-in-hand refusal rows and native cell injection Use route. |
| `/obj/item/megaphone` | 0 / 2 | Native menu enumeration now includes the disabled AI/ghost compatibility rows; the effects and refusal gates are unchanged. Only rows added, no removal/effect change; underlying legacy requirement refuses these participants. Compatibility menu producer now exposes real refusal rows. |
| `/obj/item/perfect_tele` | 0 / 3 | The held-cell probes inherit the restored Charge/Drain not-in-hand refusal rows and native cell injection Use route. |
| `/obj/item/radio_jammer` | 0 / 2 | The held-cell probes inherit the restored Charge/Drain not-in-hand refusal rows and native cell injection Use route. |
| `/obj/item/rig/nikki` | 1 / 1 | The same construction/ownership failure remains recorded; only its diagnostic source path moved from code/datums/lifecycle/links.dm to code/engine/refs/lifecycle_links.dm. Do not remove or mask construction fault; only old lifecycle-links file moved into engine/refs. |
| `/obj/item/suit_cooling_unit/emergency` | 0 / 3 | The held-cell probes inherit the restored Charge/Drain not-in-hand refusal rows and native cell injection Use route. |
| `/obj/item/suit_cooling_unit` | 0 / 3 | The held-cell probes inherit the restored Charge/Drain not-in-hand refusal rows and native cell injection Use route. |
| `/obj/item/weldingtool/electric` | 0 / 2 | The held-cell probes inherit the restored Charge/Drain not-in-hand refusal rows and native cell injection Use route. |
| `/obj/machinery/air_sensor` | 1 / 4 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/appliance/cooker/fryer` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/appliance/cooker/grill` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/appliance/cooker/oven` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/appliance/mixer/candy` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/appliance/mixer/cereal` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/appliance/mixer` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/appliance` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/artifact` | 1 / 4 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/artifact_scanpad` | 1 / 4 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/atmospherics/binary/circulator` | 1 / 4 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/atmospherics/pipe/simple/heat_exchanging` | 1 / 4 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/atmospherics/pipeturbine` | 1 / 5 | Per-target cleanup removes prior material-processor/inactive-AI products; Climb is sampled without an unrelated fixture obstruction. Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/atmospheric_field_generator` | 1 / 4 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/auto_cloner` | 1 / 4 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/bluespace_beacon` | 1 / 4 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/bluespace_denier` | 1 / 4 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/clonepod/transhuman` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/clonepod` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/computer/arcade/battle` | 3 / 3 | Library emag(then(on_emag),powered=FALSE) replaces emag_gated. Held sequencer selects library Use and native emag keys instead of generic computer Use item. Legacy Emag menu removal is explicitly documented; robot_remote_blocked replaces old generated robot-swallow key. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/computer/area_atmos` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/computer/atmoscontrol` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/computer/atmos_alert` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/computer/cloning` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/computer/general_air_control/fuel_injection` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/computer/HolodeckControl` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/computer/looking_glass` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/computer/mecha` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/computer/med_data` | 13 / 33 | Native MedicalRecords interface remains; inherited computer climb unchanged. Removed inactive-AI-in-the-way Climb refusal was a prior fixture contamination, eliminated by per-target cleanup, while held item Move To Top/Toggle Digestable additions are inherited defaults. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/computer/operating` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/computer/prisoner` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/computer/rcon` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/computer/scan_consolenew` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/computer/security/telescreen/bodycamera` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/computer/ship/disperser` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/computer/ship/engines` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/computer/ship/helm` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/computer/ship/navigation` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/computer/ship/sensors` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/computer/shuttle_control/explore` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/computer/shuttle_control/multi` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/computer/shuttle_control/specops` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/computer/shuttle_control` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/computer/transhuman/designer` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/computer/transhuman/resleeving` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/disperser` | 1 / 4 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/dna_scannernew` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/door/blast/puzzle/tyrdoor/keypad` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/drone_fabricator` | 1 / 4 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/embedded_controller/radio/airlock/docking_port` | 1 / 6 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/embedded_controller/radio/airlock` | 1 / 6 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/fitness/heavy` | 1 / 6 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/fitness` | 1 / 5 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/flasher/portable` | 1 / 4 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/flasher` | 1 / 4 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/gibber` | 8 / 8 | The native gibber_interaction_item route (DEFAULT - 1) precedes gibber_interaction_hand (DEFAULT - 2): a held item selects its existing feed handler and Use label, rather than the empty-hand Start gibbing action. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/holoposter` | 1 / 4 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/icecream_vat` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/iv_drip` | 1 / 6 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/magnetic_module` | 1 / 4 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/mass_driver` | 1 / 4 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/mech_recharger` | 1 / 4 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/media/jukebox/ghost` | 2 / 8 | Per-target cleanup removes prior material-processor/inactive-AI products; Climb is sampled without an unrelated fixture obstruction. Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. The ghost subtype removes fingerprint/interact and declares observer-bound ghost_use labelled Use; native screentip resolution now reaches that existing observer handler. |
| `/obj/machinery/medical_kiosk` | 9 / 13 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. The explicit medical_kiosk_interaction_item input invokes the existing item handler and exposes its Use label to native screentip resolution; the previous legacy handler was omitted from that query. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/microwave` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/mineral/processing_unit` | 1 / 4 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/mineral/stacking_machine` | 1 / 4 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/mineral/unloading_machine` | 1 / 4 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/ntnet_relay` | 1 / 4 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/optable` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/ore_silo` | 1 / 5 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/organ_printer` | 31 / 48 | Per-target cleanup removes prior material-processor/inactive-AI products; Climb is sampled without an unrelated fixture obstruction. Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Native printer item and control ops expose their selected key-derived labels and disabled beaker/control requirements; the existing printer handler receives the item. The item path precedes generic UI, while fixture cleanup separately removes unrelated Climb obstructions. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/oxygen_pump/mobile/stabilizer` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/oxygen_pump` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/paradoxrift` | 1 / 22 | started_work remains autonomous unpowered loot work. New captured generic /obj/item probe and held-item Move To Top/Toggle Digestable rows originate from inherited machinery/item declarations; generated robot-swallow key retires in favor of robot_remote_blocked. No new player loot operation. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/petrification` | 1 / 5 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/pointdefense` | 1 / 4 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/pointdefense_control` | 1 / 5 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/portable_atmospherics/powered/pump/huge/stationary` | 14 / 20 | Per-target cleanup removes prior material-processor/inactive-AI products; Climb is sampled without an unrelated fixture obstruction. Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. The held-cell probes inherit the restored Charge/Drain not-in-hand refusal rows and native cell injection Use route. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/portable_atmospherics/powered/pump` | 14 / 22 | Per-target cleanup removes prior material-processor/inactive-AI products; Climb is sampled without an unrelated fixture obstruction. Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. The held-cell probes inherit the restored Charge/Drain not-in-hand refusal rows and native cell injection Use route. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/portable_atmospherics/powered/scrubber` | 14 / 22 | Per-target cleanup removes prior material-processor/inactive-AI products; Climb is sampled without an unrelated fixture obstruction. Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. The held-cell probes inherit the restored Charge/Drain not-in-hand refusal rows and native cell injection Use route. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/power/hydromagnetic_trap` | 1 / 4 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/power/port_gen/pacman/mrs` | 1 / 4 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/power/port_gen/pacman/super` | 1 / 4 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/power/rtg` | 1 / 4 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/power/sensor` | 1 / 4 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/power/smes/buildable` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/power/solar_control` | 1 / 4 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/power/supermatter/shard` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/power/tesla_coil/relay` | 1 / 4 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/power/tracker` | 1 / 4 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/power/turbinemotor` | 12 / 16 | Per-target cleanup removes prior material-processor/inactive-AI products; Climb is sampled without an unrelated fixture obstruction. Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/protean_reconstitutor` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/pump_relay` | 1 / 4 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/reagent_refinery/pipe` | 15 / 19 | Per-target cleanup removes prior material-processor/inactive-AI products; Climb is sampled without an unrelated fixture obstruction. Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/reagent_refinery/reactor` | 15 / 20 | Per-target cleanup removes prior material-processor/inactive-AI products; Climb is sampled without an unrelated fixture obstruction. Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/reagent_refinery/splitter` | 15 / 19 | Per-target cleanup removes prior material-processor/inactive-AI products; Climb is sampled without an unrelated fixture obstruction. Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/reagent_refinery/waste` | 1 / 4 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/replicator/vore` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/scale` | 1 / 5 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/shipsensors` | 1 / 4 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/shuttle_sensor` | 1 / 4 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/smartfridge/drying_rack` | 25 / 25 | Per-target cleanup removes prior material-processor/inactive-AI products; Climb is sampled without an unrelated fixture obstruction. The drying rack inherits smartfridge physical item/tool precedence: DEFAULT tool actions and DEFAULT - 1 item use precede ui_open at DEFAULT - 3, preserving stocking, panel and wire handling before window opening. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/smartfridge` | 13 / 13 | Smartfridge ui_open is DEFAULT - 3; stocking item use is DEFAULT - 1 and tool/wire handlers are DEFAULT. Click diagnostics therefore expose the actual physical handler (Use/Wires/tool label), rather than allowing the window op to swallow it. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/sparker` | 1 / 4 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/teleport/hub` | 1 / 4 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/the_singularitygen/tesla` | 1 / 4 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/transhuman/autoresleever` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/transhuman/resleever` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/transhuman/synthprinter` | 1 / 1 |  Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/machinery/vitals_monitor` | 1 / 5 | Inherited native item menu defaults now expose Move To Top and Toggle Digestable on the held-item probes. The native item input domain supplies the real /obj/item probe, so its click and menu rows are now recorded. Inherited gen_robot_interaction_swallow becomes robot_remote_blocked. |
| `/obj/structure/AIcore` | 12 / 32 | ai_core_install item(/obj/item), label Use wraps existing core assembly interaction. Native screentip now records Use and adds broad held probe; empty-hand human/robot Use rows from item-required legacy domain are absent. Held item default menu rows are inherited. |
| `/obj/structure/cable/heavyduty` | 22 / 32 | Inherits cable Use; heavy_coil item(/obj/item/stack/cable_coil) labels Connect cable and checks heavy_coil_holds with needs-heavier refusal. Wrong held-type gray Connect cable rows no longer match; actual appropriate-coil requirement remains. |
| `/obj/structure/cable` | 12 / 32 | item(/obj/item) Use wraps existing cable interaction; typed native screentip records Use and broad held probe. Empty-hand human/robot legacy Use rows disappear because no item is supplied. Held-item defaults are inherited. |
| `/obj/structure/casino_table/board_game` | 12 / 12 | Per-target cleanup removes prior material-processor/inactive-AI products; Climb is sampled without an unrelated fixture obstruction. |
| `/obj/structure/casino_table/roulette_table` | 13 / 13 | Per-target cleanup removes prior material-processor/inactive-AI products; Climb is sampled without an unrelated fixture obstruction. |
| `/obj/structure/easel` | 12 / 12 | Per-target cleanup removes prior material-processor/inactive-AI products; Climb is sampled without an unrelated fixture obstruction. |
| `/obj/structure/event/santa_sack` | 23 / 42 | give_present hand op synthesizes Give present label from key, replacing legacy Use while keeping Santa identity requirement and recipient asks/effect. Bind/unbind sack is native menu with real adjacency/capability refusal; held-item defaults add inherited rows. |
| `/obj/structure/frame` | 23 / 46 | Native item Use keeps existing construction handler and broad probe. climb remains; inactive-AI obstruction was leaked fixture state. Cut-the-frame/wrench disabled rows are actual construction ops now captured rather than legacy-only availability. |
| `/obj/structure/gravemarker` | 11 / 11 | Per-target cleanup removes prior material-processor/inactive-AI products; Climb is sampled without an unrelated fixture obstruction. |
| `/obj/structure/janitorialcart` | 12 / 12 | Per-target cleanup removes prior material-processor/inactive-AI products; Climb is sampled without an unrelated fixture obstruction. |
| `/obj/structure/low_wall` | 15 / 15 | Per-target cleanup removes prior material-processor/inactive-AI products; Climb is sampled without an unrelated fixture obstruction. |
| `/obj/structure/meteorite` | 12 / 12 | Per-target cleanup removes prior material-processor/inactive-AI products; Climb is sampled without an unrelated fixture obstruction. |
| `/obj/structure/mopbucket` | 12 / 12 | Per-target cleanup removes prior material-processor/inactive-AI products; Climb is sampled without an unrelated fixture obstruction. |
| `/obj/structure/ore_box` | 12 / 12 | Per-target cleanup removes prior material-processor/inactive-AI products; Climb is sampled without an unrelated fixture obstruction. |
| `/obj/structure/outcrop` | 12 / 12 | Per-target cleanup removes prior material-processor/inactive-AI products; Climb is sampled without an unrelated fixture obstruction. |
| `/obj/structure/particle_accelerator/fuel_chamber` | 11 / 11 | Per-target cleanup removes prior material-processor/inactive-AI products; Climb is sampled without an unrelated fixture obstruction. |
| `/obj/structure/privacyswitch` | 12 / 30 | toggle_privacy hand ungated Use keeps cooldown requirement; chained choice only when admin confirmation needed. Native screentip exposes previously existing hand action; held item defaults add menu rows. No new privacy authority grant. |
| `/obj/structure/railing` | 12 / 12 | Per-target cleanup removes prior material-processor/inactive-AI products; Climb is sampled without an unrelated fixture obstruction. |
| `/obj/structure/trailblazer` | 11 / 11 | Per-target cleanup removes prior material-processor/inactive-AI products; Climb is sampled without an unrelated fixture obstruction. |
| `/obj/structure/trash_pile` | 12 / 12 | Per-target cleanup removes prior material-processor/inactive-AI products; Climb is sampled without an unrelated fixture obstruction. |
| `/obj/structure/undies_wardrobe` | 11 / 11 | Per-target cleanup removes prior material-processor/inactive-AI products; Climb is sampled without an unrelated fixture obstruction. |
| `/obj/vehicle/train/trolley_tank` | 15 / 15 | Per-target cleanup removes prior material-processor/inactive-AI products; Climb is sampled without an unrelated fixture obstruction. |

### Hit pin producer and class causes

The repaired producer samples public `is_emagged(target)` before and after each real hit. Native subversion is stored in capability keys, not the old raw `emagged` var; replacing that raw observation with a measured public-state row keeps an absent emag effect falsifiable. The final capture contains 26 real `emag / is_emagged: 0 -> 1` witnesses.

`shared_cache_uid` is excluded alongside the existing identity fields: it is assigned from a global monotonic counter and is not a hit effect. Native capability runtime data is keyed by that identity outside target.vars. Nine real chameleon fixtures warm their persistent production choice caches during test New, before the runner measures globals, so lazy initialization is not misreported as a state leak. Production caches and debug tracing remain intact.

The final capture differs in 40 hit classes / 468 rows. All 62 master `emp 1 / refresh_queued` expectations remain byte-identical, including the four reported inherited master failures. No refresh_queued difference is blessed. The electronic-assembly and anomalock-heart pin files remain untouched. Appearance bridges are not edited; removal of raw appearance bookkeeping is not a claim that these hit pins prove visual rendering.

| Class | Removed / added rows | Cause |
|---|---:|---|
| `/obj/effect/blob` | 24 / 0 | Appearance-cache bookkeeping is now in rx_state, which the producer already excludes; these raw bookkeeping transitions no longer appear. Existing physical hit, integrity, product and deletion rows remain recorded. |
| `/obj/effect/energy_field` | 5 / 5 | The scheduler record is engine-owned /datum/scheduler_record instead of /datum/om/rec; the recorded lazy scheduler allocation remains visible under its new type. |
| `/obj/effect/plant` | 2 / 2 | The scheduler record is engine-owned /datum/scheduler_record instead of /datum/om/rec; the recorded lazy scheduler allocation remains visible under its new type. |
| `/obj/item/ammo_casing/a12g/stunshell` | 6 / 0 | Appearance-cache bookkeeping is now in rx_state, which the producer already excludes; these raw bookkeeping transitions no longer appear. Existing physical hit, integrity, product and deletion rows remain recorded. |
| `/obj/item/ammo_magazine/smart` | 0 / 1 | The added public is_emagged 0 -> 1 row directly observes actual subversion; it adds coverage of the existing effect rather than a new gameplay effect. |
| `/obj/item/clothing/accessory/badge/holo` | 0 / 1 | The added public is_emagged 0 -> 1 row directly observes actual subversion; it adds coverage of the existing effect rather than a new gameplay effect. |
| `/obj/item/clothing/gloves/bluespace` | 0 / 1 | The added public is_emagged 0 -> 1 row directly observes actual subversion; it adds coverage of the existing effect rather than a new gameplay effect. |
| `/obj/item/clothing/mask/gas/sechailer` | 0 / 1 | The added public is_emagged 0 -> 1 row directly observes actual subversion; it adds coverage of the existing effect rather than a new gameplay effect. |
| `/obj/item/clothing/suit/lasertag` | 0 / 1 | The added public is_emagged 0 -> 1 row directly observes actual subversion; it adds coverage of the existing effect rather than a new gameplay effect. |
| `/obj/item/kinetic_crusher` | 0 / 1 | The added public is_emagged 0 -> 1 row directly observes actual subversion; it adds coverage of the existing effect rather than a new gameplay effect. |
| `/obj/item/modular_computer` | 0 / 1 | The added public is_emagged 0 -> 1 row directly observes actual subversion; it adds coverage of the existing effect rather than a new gameplay effect. |
| `/obj/item/retail_scanner` | 0 / 1 | The added public is_emagged 0 -> 1 row directly observes actual subversion; it adds coverage of the existing effect rather than a new gameplay effect. |
| `/obj/item/shield_projector` | 7 / 7 | The scheduler record is engine-owned /datum/scheduler_record instead of /datum/om/rec; the recorded lazy scheduler allocation remains visible under its new type. |
| `/obj/item/stack/material/supermatter` | 21 / 0 | Appearance-cache bookkeeping is now in rx_state, which the producer already excludes; these raw bookkeeping transitions no longer appear. Existing physical hit, integrity, product and deletion rows remain recorded. |
| `/obj/item/storage/backpack/chameleon` | 2 / 1 | The scheduler record is engine-owned /datum/scheduler_record instead of /datum/om/rec; the recorded lazy scheduler allocation remains visible under its new type. The migrated hit/emag path no longer produces the previous lazy raw containment-ledger allocation; this is a bookkeeping observation, with the actual tile products, integrity and deletion witnesses retained. |
| `/obj/item/storage/belt/chameleon` | 2 / 1 | The scheduler record is engine-owned /datum/scheduler_record instead of /datum/om/rec; the recorded lazy scheduler allocation remains visible under its new type. The migrated hit/emag path no longer produces the previous lazy raw containment-ledger allocation; this is a bookkeeping observation, with the actual tile products, integrity and deletion witnesses retained. |
| `/obj/machinery/atm` | 2 / 1 | Native capability runtime data is kept in the identity-keyed runtime registry rather than the holder cap_data list; the volatile registry identity is excluded. The former raw emagged transition is replaced by the real public is_emagged 0 -> 1 observation of native subversion. |
| `/obj/machinery/cash_register` | 2 / 1 | Native capability runtime data is kept in the identity-keyed runtime registry rather than the holder cap_data list; the volatile registry identity is excluded. The former raw emagged transition is replaced by the real public is_emagged 0 -> 1 observation of native subversion. |
| `/obj/machinery/computer/HolodeckControl` | 30 / 1 | Appearance-cache bookkeeping is now in rx_state, which the producer already excludes; these raw bookkeeping transitions no longer appear. Existing physical hit, integrity, product and deletion rows remain recorded. Native capability runtime data is kept in the identity-keyed runtime registry rather than the holder cap_data list; the volatile registry identity is excluded. The former raw emagged transition is replaced by the real public is_emagged 0 -> 1 observation of native subversion. |
| `/obj/machinery/computer/looking_glass` | 30 / 1 | Appearance-cache bookkeeping is now in rx_state, which the producer already excludes; these raw bookkeeping transitions no longer appear. Existing physical hit, integrity, product and deletion rows remain recorded. Native capability runtime data is kept in the identity-keyed runtime registry rather than the holder cap_data list; the volatile registry identity is excluded. The former raw emagged transition is replaced by the real public is_emagged 0 -> 1 observation of native subversion. |
| `/obj/machinery/computer/rdservercontrol` | 30 / 1 | Appearance-cache bookkeeping is now in rx_state, which the producer already excludes; these raw bookkeeping transitions no longer appear. Existing physical hit, integrity, product and deletion rows remain recorded. Native capability runtime data is kept in the identity-keyed runtime registry rather than the holder cap_data list; the volatile registry identity is excluded. The former raw emagged transition is replaced by the real public is_emagged 0 -> 1 observation of native subversion. |
| `/obj/machinery/computer/ship` | 29 / 1 | Appearance-cache bookkeeping is now in rx_state, which the producer already excludes; these raw bookkeeping transitions no longer appear. Existing physical hit, integrity, product and deletion rows remain recorded. Native capability runtime data is kept in the identity-keyed runtime registry rather than the holder cap_data list; the volatile registry identity is excluded. The added public is_emagged 0 -> 1 row directly observes actual subversion; it adds coverage of the existing effect rather than a new gameplay effect. |
| `/obj/machinery/computer/shuttle_control` | 32 / 1 | Appearance-cache bookkeeping is now in rx_state, which the producer already excludes; these raw bookkeeping transitions no longer appear. Existing physical hit, integrity, product and deletion rows remain recorded. The added public is_emagged 0 -> 1 row directly observes actual subversion; it adds coverage of the existing effect rather than a new gameplay effect. |
| `/obj/machinery/embedded_controller/radio/simple_docking_controller/escape_pod_berth` | 2 / 1 | Native capability runtime data is kept in the identity-keyed runtime registry rather than the holder cap_data list; the volatile registry identity is excluded. The former raw emagged transition is replaced by the real public is_emagged 0 -> 1 observation of native subversion. |
| `/obj/machinery/gibber` | 30 / 1 | Appearance-cache bookkeeping is now in rx_state, which the producer already excludes; these raw bookkeeping transitions no longer appear. Existing physical hit, integrity, product and deletion rows remain recorded. Native capability runtime data is kept in the identity-keyed runtime registry rather than the holder cap_data list; the volatile registry identity is excluded. The migrated hit/emag path no longer produces the previous lazy raw containment-ledger allocation; this is a bookkeeping observation, with the actual tile products, integrity and deletion witnesses retained. The former raw emagged transition is replaced by the real public is_emagged 0 -> 1 observation of native subversion. |
| `/obj/machinery/librarycomp` | 2 / 1 | Native capability runtime data is kept in the identity-keyed runtime registry rather than the holder cap_data list; the volatile registry identity is excluded. The former raw emagged transition is replaced by the real public is_emagged 0 -> 1 observation of native subversion. |
| `/obj/machinery/mineral/equipment_vendor` | 22 / 0 | Appearance-cache bookkeeping is now in rx_state, which the producer already excludes; these raw bookkeeping transitions no longer appear. Existing physical hit, integrity, product and deletion rows remain recorded. Native capability runtime data is kept in the identity-keyed runtime registry rather than the holder cap_data list; the volatile registry identity is excluded. |
| `/obj/machinery/photocopier` | 1 / 0 | Native capability runtime data is kept in the identity-keyed runtime registry rather than the holder cap_data list; the volatile registry identity is excluded. |
| `/obj/machinery/seed_storage` | 4 / 3 | The scheduler record is engine-owned /datum/scheduler_record instead of /datum/om/rec; the recorded lazy scheduler allocation remains visible under its new type. Native capability runtime data is kept in the identity-keyed runtime registry rather than the holder cap_data list; the volatile registry identity is excluded. The former raw emagged transition is replaced by the real public is_emagged 0 -> 1 observation of native subversion. |
| `/obj/machinery/shield` | 5 / 3 | The scheduler record is engine-owned /datum/scheduler_record instead of /datum/om/rec; the recorded lazy scheduler allocation remains visible under its new type. Native capability runtime data is kept in the identity-keyed runtime registry rather than the holder cap_data list; the volatile registry identity is excluded. |
| `/obj/machinery/shieldgen` | 30 / 1 | Appearance-cache bookkeeping is now in rx_state, which the producer already excludes; these raw bookkeeping transitions no longer appear. Existing physical hit, integrity, product and deletion rows remain recorded. Native capability runtime data is kept in the identity-keyed runtime registry rather than the holder cap_data list; the volatile registry identity is excluded. The migrated hit/emag path no longer produces the previous lazy raw containment-ledger allocation; this is a bookkeeping observation, with the actual tile products, integrity and deletion witnesses retained. The added public is_emagged 0 -> 1 row directly observes actual subversion; it adds coverage of the existing effect rather than a new gameplay effect. |
| `/obj/machinery/shield_capacitor` | 1 / 1 | Native capability runtime data is kept in the identity-keyed runtime registry rather than the holder cap_data list; the volatile registry identity is excluded. The added public is_emagged 0 -> 1 row directly observes actual subversion; it adds coverage of the existing effect rather than a new gameplay effect. |
| `/obj/machinery/shield_gen` | 1 / 1 | Native capability runtime data is kept in the identity-keyed runtime registry rather than the holder cap_data list; the volatile registry identity is excluded. The added public is_emagged 0 -> 1 row directly observes actual subversion; it adds coverage of the existing effect rather than a new gameplay effect. |
| `/obj/machinery/shipsensors` | 22 / 0 | Appearance-cache bookkeeping is now in rx_state, which the producer already excludes; these raw bookkeeping transitions no longer appear. Existing physical hit, integrity, product and deletion rows remain recorded. Native capability runtime data is kept in the identity-keyed runtime registry rather than the holder cap_data list; the volatile registry identity is excluded. |
| `/obj/machinery/smartfridge/secure` | 30 / 1 | Appearance-cache bookkeeping is now in rx_state, which the producer already excludes; these raw bookkeeping transitions no longer appear. Existing physical hit, integrity, product and deletion rows remain recorded. Native capability runtime data is kept in the identity-keyed runtime registry rather than the holder cap_data list; the volatile registry identity is excluded. The former raw emagged transition is replaced by the real public is_emagged 0 -> 1 observation of native subversion. |
| `/obj/machinery/suspension_gen` | 5 / 1 | Native capability runtime data is kept in the identity-keyed runtime registry rather than the holder cap_data list; the volatile registry identity is excluded. The migrated hit/emag path no longer produces the previous lazy raw containment-ledger allocation; this is a bookkeeping observation, with the actual tile products, integrity and deletion witnesses retained. The added public is_emagged 0 -> 1 row directly observes actual subversion; it adds coverage of the existing effect rather than a new gameplay effect. |
| `/obj/machinery/v_garbosystem` | 2 / 1 | Native capability runtime data is kept in the identity-keyed runtime registry rather than the holder cap_data list; the volatile registry identity is excluded. The former raw emagged transition is replaced by the real public is_emagged 0 -> 1 observation of native subversion. |
| `/obj/structure/grille` | 21 / 0 | Appearance-cache bookkeeping is now in rx_state, which the producer already excludes; these raw bookkeeping transitions no longer appear. Existing physical hit, integrity, product and deletion rows remain recorded. |
| `/obj/structure/noticeboard` | 15 / 0 | Appearance-cache bookkeeping is now in rx_state, which the producer already excludes; these raw bookkeeping transitions no longer appear. Existing physical hit, integrity, product and deletion rows remain recorded. |
| `/obj/vehicle` | 2 / 3 | The scheduler record is engine-owned /datum/scheduler_record instead of /datum/om/rec; the recorded lazy scheduler allocation remains visible under its new type. The added public is_emagged 0 -> 1 row directly observes actual subversion; it adds coverage of the existing effect rather than a new gameplay effect. |

## Relations conversion (rewrite/relations)

Pinned by `code/modules/unit_tests/dq_rel_lifecycle_pins.dm` and the `dq_om_relation_*` tests, written green on the legacy relations first.

* **A leash that outlives its pet's step stops on the next slow step** instead of stopping its periodic work in the unlink: `periodic_step()` returns `PROCESS_KILL` when it clears the leash. A leash on nobody does nothing in between.
* **An overmap mob's marker deleting on its own expires the mob** through the marker's `on_destroy` (its `parent`) instead of the relation hook; a marker supplied to a mob without setting its own `parent` no longer takes the mob with it.
* **A throw's `subject` stays set after the throw lands** (until the throw is deleted a tick later); the old edge did the same.

* **Buckle, pull and grab are sparse declared links (KR2).** A rider moved off its seat's tile by a forced move is now let go one tick later (the old range check never fired for a `forceMove`). A pull made on something not within a tile is refused instead of linking and breaking at once.
* **`melee_hit` is the lowest tier.** The closet's blow was tier 20 and now answers after every specific op of the closet; an open closet in combat mode puts a held item down rather than hitting it. A coffin and a statue drop `melee_hit` (was `strike`); pin `keys:` rows change.
* **12 swallow ops are gone.** A held item no longer has its use swallowed by a tank, cable layer, seed extractor, pAI radio, shower, torch, SMES, turbine computer, injector maker, photocopier, stardog console or conveyor (robot): the item's own ops (a spray bottle) answer, else the legacy click runs. Pin rows `... menu: Use` / `click: Use` for those types disappear.
* **Objects without an op can now be hit with a held item in combat.** Every `/obj` has the `melee_hit` op (lowest tier): a crowbar in combat mode on a vending machine, a tank, a shower, a console now takes the blow (`receive_weapon_hit`, the item's force). Specific ops still answer first. Opted out (no hit): items, effects, singularities, bellies, soulgems, spell buttons, the wall torch. Pin rows: `keys:` gains `melee_hit` on every object type and `click:` rows for a held item in combat change from `nothing` to `Hit`.
* **The web and the weeds take a quarter of the force through the damage pipeline** (the weeds used `take_damage` directly before); the solar panel and the canister lose their bespoke messages ("hits it with" wording of the capability).
* **A blast door answers an ID card with the access refusal**, no longer with the silent swallow (its `allowed()` has always been FALSE).
* **Orbits can circle a turf** and keep the orbiter's saved transform on the link; `holds_while` listens to move notices (observe) again.
* **Pin classes of the `melee_hit` bless** (about 500 pin files): `menu: Hit` for a held item on every object type (the new op; refused with the stance reason outside combat), `keys:` gains `melee_hit`, `menu: Move To Top` / `Toggle Digestable` appear on rows whose menu was empty (any listed op brings them), `click:` rows that were `nothing` become `Hit` where combat is the best answer; the web and weeds hit only in combat mode now (it was any stance), so a spiderling or a weed's click label shows its touch (`Stomp`, `Touch weeds`) where `Hit web` / `Hit weeds` was; `Strike` menu rows (closet, canister, solar) are `Hit`; rows of the 12 swallow targets lose `Use`. Moved lines of unchanged text (sorting) are not changes.

## The duplicate emissive blocker (draw framework, KD22)

* The old `add_overlay()` merged the priority overlays into every add, so pins recorded a duplicate emissive blocker after each redraw; one blocker is drawn now.
  `add_overlay()` merges them only when the atom has no overlays left, `cut_overlay()` never takes the blocker with a layer, and `cut_overlays()` keeps it.
  Every pin row that changes is that class: a `blocker x2` becoming the one blocker, or a probe row that only gained and lost the blocker.
* The lightpost is a plain draw over tracked `lit` and `festive`; its light follows the look (`look.light()`, `look.light_off()`).

## Batch 7b merge (fixes-small + links-hit + draw-framework on the machinery master)

Pins were taken from the machinery side on every conflict and regenerated with `--bless` after the last merge; the classes below are every change that bless made.

* **links-hit rows on the machinery pins** (360 `pins/` files): the `melee_hit` classes of the relations section above (`menu: Hit`, `keys:` gains `melee_hit`, `Move To Top` / `Toggle Digestable` / own-op rows on formerly empty menus, `Strike` becomes `Hit`). Where a swallow op is gone, a tool's `click: Click: Use` becomes `Click: Use item`, `Click: Toggle` (another listed op is now the best answer) or `nothing`.
* **`hit_pins/` thermal glasses, sechailer, kinetic crusher**: the `refresh_bits: 2 -> 0` rows are gone. A draw mark no longer stays pending after the hit: the `add_overlay()` single-blocker fix (draw framework) means the emissive redraw these items queued is settled inside the hit. `refresh_queued` rows remain.
* **Line numbers**: two `runtime while making it` rows (stardog, nikki rig) carry the line of `lifecycle_links.dm` in the stack; the link teardown call added two lines.
* **Not blessed**: the `look_trees` row of `electronic_assembly` (it would record the pre-existing `op_clash` runtime in place of its overlay) stays as before.

## Requests and bridges round 3 (2026-10-07)

The effective status sources for stun, weakness/knockdown, paralysis and sleep independently veto `STAT_CAN_ACT`. Consciousness is an additional contribution driven by the existing published `set_stat` setter. Immunity masks the effective status before its contribution is evaluated. Ending one dose does not undo a different source; removing the last effective source restores admission immediately. This fixes previously admitted machine operations during impairment.

The native requests preserve the same action names, prompt types, choice/default values, cancellation behavior and resulting state. Medical/security/skills notes use a conditional deletion confirmation after an empty text answer. Newscaster and message-monitor steps retain captured drafts, record identity and current-key checks. Painter only samples whether an item is inserted when opening its colour request; removing it while the question is open retains the old completion behavior. Jukebox's unused manual request helpers are removed; its native cancel continuation remains.

Atmos-control Add captures the actual buffered device when naming opens; Remove captures the original name/tag map; Set reads the held tool's live buffer when the answer commits. Camera preview/retry and third-party consent remain unchanged pending their recorded framework gaps. Wall/floor frame selection, board configuration and cutout painting keep stale-target checks and actual timed effects. Empty petrification catalogues now refuse at request opening with the existing no-target message rather than entering a message-and-return effect.

Magnetic-controller and traffic-controller configuration questions now use native steps. Their access checks are requirements; successful fingerprint/window effects execute at commit. Pandemic release forms carry the selected strain and reason between steps: answered No prints an unsigned form, while cancellation still prints nothing. Missing archived strains refuse at request opening with the existing error text. Alien wire splitting retains inactive-hand selection and its pickup fallback.

VR transform/logout verbs dispatch native operations guarded by their actual granted verb, sampled with `read_once` so revocation cannot leave cached admission. Logout deliberately remains available while impaired. AI status retains the existing wireless-control verb gate and uses a private native continuation; core latejoin offers start on the newly completed core, and admin core selection runs on the existing admin holder with current owner/rights requirements. These are existing native continuation forms, not renamed request wrappers.

Delayed atmosphere alert sounds use the existing major/minor sound sets (70/50 volume, varying pitch) directly. Delayed pod destruction uses the native `spent` primitive, while delayed singularity motion keeps its legacy callback: BYOND’s builtin step is not a callable /proc path, and no native callback replacement exists. World deferred callbacks and deadline diagnostics call their engine-owned implementations; Doppler's distinct world notice bus is preserved.

No appearance bridges or snapshot pins are re-blessed in this wave.


The frame construction graph now expresses all seventeen former transitions as native stages. It explicitly seeds loose, placed and partly built frames from their actual physical state. Anchor, board, cover, wire, glass and finish effects retain the old FRAME_* mirrors and appearance updates. Reverse edges retain their fixed material refunds; automatic ledger refunds are suppressed to prevent duplicate material return. Completing a machine transfers its actual fitted board and parts before disposing of the frame. This removes the legacy frame interaction keys in favour of native stage op keys without intending to change the construction actions.

The ship helm's Emote Beyond action now uses its existing native capability block, retaining actual seven-tile reach and visibility, capability/mute checks, and all emote/admin tracing. Its old `ship_emote_beyond` interaction identifier becomes the native op key. The six otherwise unused abstract machinery interaction bases are removed after their last concrete consumer is converted.

Record and message-server selections now declare their existing reference slots, matching the relation setters already used for writes. Native guards can follow those slots rather than relying on undeclared raw pointers. Frame glass admission remains material-based: generic stacks whose actual material is plain glass are accepted, preserving the old construction matcher.

The existing consciousness setter now notifies the native stat layer of the actual stat variable key, so unconsciousness/death and recovery settle STAT_CAN_ACT immediately. The original publication remains. Status holds are admitted before immunity is enabled in regression fixtures: immunity rejects new holds and masks already running holds; its policy is unchanged. Native frame tool steps that were instant explicitly use wait(0), while anchor, cable, glass and cutting retain their original real delays.

## Draw sweep 3, worker B (structures)

* **Catwalk: a bare write of `smooth_mask` no longer redraws different connections.** The legacy appearance proc called `update_connections()` while drawing,
  so a look-state pin that wrote `smooth_mask` by hand saw the connection overlays change. The draw only reads `connections`; they are recomputed where the
  adjacency index reports a change (`smooth_changed()`, which also requests the redraw) and at init. The eight `smooth_mask=1/2` rows of
  `look_states/obj.structure.catwalk.txt` are gone for that cause; the made look is unchanged.

## Draw sweep 3, worker A (items and effects)

* **Energy blades, shield and toy sword draw over tracked state.** `/obj/item/melee/energy` (swords, axe, blade, spear), `/obj/item/shield/energy` and `/obj/item/toy/sword` are `draw(look)`
  over `TRACKED` `active`, `lcolor` (and `rainbow` for the blades); their `update_icon()` calls are gone. `/obj/item/shield/energy` draws the lit blade with `look_appearance(icon, ...)`
  and its `held_state()`/`light()`/`light_off()` follow `active`. Pin rows that change:
  * **The blade colour is applied when the thing is made** (look tree rows `color: #rrggbb` on every `/obj/item/melee/energy` subtype that has an `lcolor`): the legacy appearance proc only
    ran on the first `update_icon()`, so a fresh blade sat uncoloured until it was switched on; the first refresh now draws every atom after its init. The look-state rows `+color:` that
    came with a first redraw therefore vanish, and a `rainbow` write now shows `-color` (the rainbow blade draws white).
  * **The altevian cutter's state follows `active`** (look-state rows `active=1/2 +overlay ...altevian-cutter_active`): `active` is tracked now, so writing it redraws the look; the
    legacy pin harness' `update_icon()` after the write was the only thing that redrew it.
* **The RMS meter draws over tracked `stored_charge`.** The charge stage is computed in the draw (`charge_stage` is gone). The look-state `max_charge=0` row reads `runtime: Division by zero`
  without the `refresh of ...` prefix: the same division by zero, now inside the draw.

## Draw sweep 3, codemod roots

* **A write the legacy look ignored now redraws.** Types converted by `look_sweep.py convert` (areas, translocators, gravemarker, suspension generator, refinery machines, chem canister, pump relay, voidcraft wall, dog eye, cyborg baton, sol, pneumatic, consul) draw over the state they read. Look-state rows that appear (`ready`, `recharging`, `status`, `fire`/`eject`/`party`) were absent from the legacy pin because only an explicit `update_icon()` redrew; the calls are now `changed(src)` or deleted.
* **The sol SMG's duplicate charge overlay is gone.** The legacy provider added `smg_*` after the appearance overlays (`x2` rows); the charge overlay is now an effect that runs once.

## The emissive blocker follows a drawn sprite (draw sweep 3 C)

* A look that changes an atom's sprite re-syncs the atom's generic emissive blocker (`look_resync_emissive_blocker()`); the legacy providers wrote `icon_state` and left the blocker
  at the sprite the atom was made with. The look-state pins of the NTNet relay (`enabled`), the shield generator family (`active`) and the fuel port (`opened`) gain, beside each `+state` /
  `-state` row, a `+overlay` / `-overlay` row of the blocker (`icons/...:<state>:8:#000000`): the same sprite change, now shown on the blocker too. No state, colour or other layer row changes.
* The folder, paper plane, blob family, glass roulette ball and disposal bin family keep their look-tree and look-state rows exactly (the disposal bin's `mode` and `flush` rows, the folder and
  plane rows, the blob's tree rows); the disposal bin's broken sprite is the one thing not pinned: the legacy provider left `disposal-broken` on the bin after a repair, the look restores the
  type's own state.

## Draw framework round 2 (medical stand, furnace, wall bin)

* **The medical stand's reagent bag is tinted with `color`, not blended into the icon** (`icon += colour` before): the stand draws `look_overlay_image(..., color =)`. It also redraws when the beaker or tank it holds changes (watched).
* **The refinery furnace's side is a tracked var** (`set_filter_side()`); flipping redraws without `update_icon()`. A turn of the furnace (`set_dir()`) redraws it.
* **A wall disposal bin's offset is `look.offset()`** from its dir; turning a bin through `set_dir()` moves it (the hand `changed()` after `dir =` is gone).
## Batch 7b merge (fixes-small + links-hit + draw-framework on the machinery master)

## Batch 8 merge (requests-and-bridges + om-fields + draw-sweep-3 on the batch 7b master)

* **links-hit rows on the machinery pins** (360 `pins/` files): the `melee_hit` classes of the relations section above (`menu: Hit`, `keys:` gains `melee_hit`, `Move To Top` / `Toggle Digestable` / own-op rows on formerly empty menus, `Strike` becomes `Hit`). Where a swallow op is gone, a tool's `click: Click: Use` becomes `Click: Use item`, `Click: Toggle` (another listed op is now the best answer) or `nothing`.
* **`hit_pins/` thermal glasses, sechailer, kinetic crusher**: the `refresh_bits: 2 -> 0` rows are gone. A draw mark no longer stays pending after the hit: the `add_overlay()` single-blocker fix (draw framework) means the emissive redraw these items queued is settled inside the hit. `refresh_queued` rows remain.
* **Line numbers**: two `runtime while making it` rows (stardog, nikki rig) carry the line of `lifecycle_links.dm` in the stack; the link teardown call added two lines.
* **Not blessed**: the `look_trees` row of `electronic_assembly` (it would record the pre-existing `op_clash` runtime in place of its overlay) stays as before.

## Draw framework round 2b: neighbours, tracked connections, dir as a setter

* **A flipped table's emissive blocker follows its flipped sprite** (`look_states/obj.structure.table.txt`: every `flipped=1` row loses `-overlay: ...:blank:8:#000000` and gains `+overlay: ...:flip0:8:#000000`, 29 table types). The legacy provider wrote `icon_state = "flip0"` and left the generic emissive blocker at the sprite the table was made with (`blank`); a look that changes the sprite re-syncs the blocker (`look_resync_emissive_blocker()`, as for the other converted types). The standing table rows (`look_trees/obj.structure.table.txt`, all 276) are unchanged.
* **The refinery hub's look tree and state pin are unchanged** (`look_trees/obj.machinery.reagent_refinery.hub.txt`; the hub has no numeric var, so its look-state pin is empty). It now redraws when the machine it faces arrives, leaves, turns or is unanchored, and when a filter beside it flips (the legacy hub drew once at init and on `update_neighbours()`).
* **`connections` / `other_connections` on `/obj/structure` are `TRACKED`**: the smoothing code writes them through `set_connections()` / `set_other_connections()`, and the hand `changed(src)` after them (sandbag, `smooth_changed()`) is gone. A smoothing structure whose draw reads them redraws by itself. The two unanchored-window providers (`bay`, `eris`) no longer write all-zero connections themselves: `update_connections()` already answers all zeros for an unanchored structure.
* **A bare `dir` write on an atom is a `tracked` lint error** (`SETTER(/atom, dir)`); 19 sites went through `set_dir()` (look apply, phase-shift animations, smite, toilet crafting, stairs, hydroponics, wall frames, disposal holders, telesci pads, mech prosfab, mob facing in `mob_movement.dm`). `Moved()` publishes a dir BYOND turned natively, only when it changed. Nothing in `code/game/machinery` or `code/modules/power` was touched (the lint found no site there).
* **Not blessed, unchanged from the base:** the `electronic_assembly` look-tree rows, the `baton/arm` and `baton/slime` rows and the `ntnet_relay dos_failure` rows differ on the base commit too.
Pins were regenerated with `--bless` after the last merge; only rows that change are committed (empty look-state files, the baton file's line endings and the `electronic_assembly` look tree were not rewritten: the last would record the pre-existing `op_clash` runtime in place of its tree). The classes:

* **`hit_pins/` shield generator, suspension generator, blob** (draw sweep 3): a type that now draws over tracked state has its first draw queued when it is made, so the hit probe flushes it. The rows `refresh_bits: N -> 0` and `refresh_queued: 131071 -> 0` are that first flush; the old `emp 2 | nothing` row of the shield generator and the blob is replaced by them. The blob draw has no overmind in the probe, so it takes its inert look (`name: 'blob' -> 'inert blob'`, `light_range: 2 -> 0`), exactly as `base_blob.dm` draws a blob with no overmind.
* **`look_states/` NTNet relay** (draw sweep 3 C): a hand write of `dos_failure` now redraws the relay. The rows are the sprite change `ntnet -> ntnet_off` with its emissive blocker overlay following it.
* **`pins/` frame** (requests and bridges, native frame construction): the seventeen legacy frame transitions are native stages, so the menu rows carry the stage labels (`Wrench into place`, `Cut frame apart`), the refusals of the legacy entries are gone, and the held circuit board and material stack show the inherited item menu defaults and the `construction.build:*` keys.
* **`pins/` ship navigation console and its dog-eye screen** (requests and bridges): the helm's Emote Beyond action is native, so a ghost far away is refused with `too far away`.
* **`pins/` claw machine** (requests and bridges): the card PIN request is a native request, so its key `clawmachine_card_pin` is listed.
## Timed actions as ops, B additions

Pinned by `code/modules/unit_tests/dq_timed_pin_w8_behaviour.dm` (nine pins green on the legacy forms; the mop, plastique, ladder weld, maintenance panel weld, hardsuit cable mend and blank-envelope open could not be driven on the legacy form, because the driver's click does not reach a legacy `afterattack()` / `*_act()` override, and were dropped).

* **Class: the target of the task is the real target.** The DNA injector, tape roll and mail used to name the item as the task's target, so a patient who left or was deleted did not stop the work. The op's target is the patient; a lost patient ends the work. Pins: `dna_injector` (no loss line), `tape_*`.
* **Class: a refusal the old handler wrote is a requirement with the same words.** The grip, head, eyes, mouth, worn face cover, the smart magazine's attached cell, and the bag-valve mask's seal; a roll used in the help stance falls through (`stance(I_DISARM, I_GRAB, I_HURT)`) instead of answering a failure.
* **Class: the grip on a taped patient is checked when the work ends too**, as the old done procs did.
* **Class: a latent legacy bug is fixed.** Cable mended a hardsuit module only when `damage != 1`, yet the handler let only `damage == 1` through, so cable never mended anything. Now an almost destroyed module (2) is mended to 1 and 0 and 1 are refused ("no damage" / "crude tools").
* **Class: a refusal that was a balloon alert is a chat line** (someone else's mail; the pins do not assert it).
* A bonfire that is empty (or a permanent one) is taken apart by its own `dismantle` op; the fuel is taken out by `hand`. A blank envelope has `seal` (unsealed) and `open` (sealed) in hand; opening a blank envelope still hands nothing out (`special_handling`), as before.
## Timed actions as ops, A additions

Pinned by `code/modules/unit_tests/dq_timed_pin_w7_behaviour.dm` (107 pins written and green on the legacy `task_timed` / `task_start` forms before the conversion; 19 more were dropped because the legacy form could not be driven or leaked in the test world: modular limb verbs, the pitcher fish-out, the teppi slaughter, the stardog, the space worm, cyborg wrench/extract, the sleeper patient/compactor completion, the tongue drink/dry/food/lick). Each class is one cause.

* **Class: a worker with no retained argument re-derives it at the end.** The strip slot's item, the first accessory, the grab and the airway obstruction, the grabbed limb and the platform's last stored thing are read when the wait ends, not captured at the start (`perform_op` carries no arguments). Pins: `h_strip_slot_remove`, `h_strip_tie`, `h_heimlich`, `h_grab_throat`, `h_grab_inspect`, `r_platform_unload`.
* **Class: the grab-inspect chain hangs off the grab.** The target is the grab item, so a victim who steps away breaks the grab and ends the work. The appendicitis line names the user. Pins: `h_grab_inspect`, `h_grab_inspect_interrupted`.
* **Class: throat and shank use any grab the user holds on the target.** Pins: `h_grab_throat`, `h_grab_shank`.
* **Class: a start or refusal message goes to the op's actor and onlookers.** The NIF disk's "is uploading" line to the target is the others-line; the implanter's self-use no longer prints "is injecting" (a wait of 0 has no start); the Nikki hat user sees no start line; tongue and sleeper refusals are `needs` messages, the tongue's drink line reaches the user (the old line went to the tongue item). Pins: `v_nifsoft_upload_other`, `v_backup_implanter_self`, `v_nikki_hat_equip`, `r_tongue_*`.
* **Class: a second input from the same player replaces the first wait.** A second tongue click (the "already licking" refusal is the actor's single pending op). Pin: `r_tongue_one_lick_at_a_time`.
* **Class: a click the old override ended with a failure falls through to a hit.** The grinder on a living thing that is neither a monkey nor a slime, the implanter on a non-carbon (and the grinder's "cannot process" buzz is gone). No pin.
* **Class: an already-empty dead slime waits one grind step before it is consumed.** Pin: `v_grinder_slime`.
* **Class: repeated resists in a belly start parallel escapes.** The belly escapes are `ORIGIN_SYSTEM` ops (a human prey is not an `ORIGIN_AI` actor) with no claim. Pins: `v_belly_escape_*`.
* **Class: the decompiler fires when the click lands on the drone.** The old code also fired for the turf that held it. Pin: `r_decompile_drone_cancel_on_move`.
* **Class: a weaver is cancelled when it falls unconscious during the wait.** The silk, tile and consciousness are requirements re-checked after the wait; the "state" refusal is the default not-capable text. Pins: `s_weaver_floor`, `s_weaver_cancel_on_move`.
* **Class: the glamour ring's cooldown refusal is told from the completion with no wait.** The wait is `wait(PROC_REF)` returning 0 for a "No" and for a draw inside the cooldown. Pin: `s_glamour_ring_restore`.
* **Class: the xeno build tile, the teppi shear and the dominated brain.** The structure's tile is read when the wait ends; shearing needs wool at offer and again at the end (a dead teppi with wool is not refused at offer time); the dominated brain's resist waits on the brain itself and no longer prints the "already dominated" / "cannot return" refusals (the button is not offered). The Resist Control, Return to Body and Nutrition Heal abilities are always declared menu ops gated by `when` instead of verbs granted and revoked at run time. Pins: `m_xeno_build`, `m_teppi_shear`, `m_dominated_*`, `v_nutrition_heal*`.
* **Class: a player-driven worker is an `ai()` op started by `perform_op`.** The borer and leech infest (a menu() op cannot take the answered target as the wait's target; framework gap below). Pins: `m_borer_infest`, `m_leech_infest`.
* **Class: nutrition heal re-clamps at the end of the wait.** A nutrition drop during the wait heals slightly less. Pins: `v_nutrition_heal*`.

Sites left: species- and trait-granted abilities (lleill, shapeshifter, protean powers, succubus/bloodsuck/shred/cocoon/devour, shadekin interactions, ddraig polymorph, regenerate, lick wounds, dominated-brain review chains) have no master mechanism for a species to grant a `menu()` op; `/mob/living` item-click chains (beacon feed, body writing, eat minerals, vertical nom, butchering) need ops in `CAPABILITIES(/mob/living)`; the spell cast delay and the dormancy repair steps have no op host (a datum / an affliction). Framework gaps: a `menu()` op whose answered target is the wait's target; a repeat-until-done op with a per-iteration cost (`self_repair`, `grab_drain`, `spin`, `lick_step`); an op that carries a computed list (melee swing); `wait(INFINITY)` (apply_pressure).

## Machinery non-harm item clicks (2026-10-08)

The inherited `/obj` melee hit is now offered on machinery only for harm stance,
including in non-harm menus. The restriction is scoped to player click/menu origins;
explicit AI/system attack requests retain their existing behavior. Specific item strikes on doors, portable turrets and
light fixtures use the same harm condition. Deployable barriers previously
labelled an ordinary-use item op "Hit"; it now explicitly answers attack and
requires harm. Help, disarm and grab therefore reach the machine's existing tool,
insertion or Use operation rather than striking it. No substitute no-op Use was
added; machines without a matching interaction still have no interaction. Harm
still uses the existing damage handlers and canister item exclusions remain.

The `i7_bulk` re-record covers these inherited machinery classes and their door,
light, portable-turret and deployable-barrier subtypes. Removed non-harm Hit menu
rows and any Click: Hit -> the machine's real interaction/nothing rows are caused
by these intent corrections, not by removing damageability. The re-record changes
282 files: 261 have only key-list changes and 21 also have behavior rows changed.

Key-list changes record the inherited `melee_hit` introduced on master in
`82357da35c`, and the obsolete no-op `use`/`swallow` keys removed on master in
`f857c445a3`/`82357da35c`. They do not imply a new non-harm attack. Every class
with changed behavior rows is accounted for below; native master pins independently
confirm the cablelayer, shower, turbine and photocopier interactions.

| Snapshot class(es) | Cause |
|---|---|
| `obj.machinery.atmospherics.pipe.tank` | Master `f857c445a3` removed no-op Swallow; unmatched held items now do nothing. |
| `obj.machinery.cablelayer` | Master removed generic no-op Use; actual Toggle now answers held-item clicks. |
| `obj.machinery.computer.turbine_computer` | Master removed generic no-op Use; existing Use item/UI operations remain. |
| `obj.machinery.photocopier` | Master removed generic no-op Use; real toner insertion and other concrete interactions remain. |
| `obj.machinery.seed_extractor` | Master removed generic no-op Use; unmatched items have no interaction. |
| `obj.machinery.shower` | Master removed generic no-op Use; actual shower Toggle answers held-item clicks. |
| `obj.machinery.deployable.barrier` | This fix makes its damaging Hit harm-only; wrench repair, ID swipe and emag retain precedence on non-harm clicks. |
| `obj.machinery.door`, `.unpowered`, `.airlock`, `.airlock.phoron`, `.window`, `.window.holowindoor` | This fix hides Strike from non-harm menus; real door open/close and tool operations remain. |
| `obj.machinery.door.blast` | Harm-only Strike plus master `82357da35c` removing no-op Swallow; forcing/prying and actual denial behavior remain. |
| `obj.machinery.light`, `.flamp` | This fix hides damaging Hit from non-harm menus; bulb/socket interactions remain. |
| `obj.machinery.light.small.torch` | Master removed no-op Swallow; its explicit `without("melee_hit")` remains respected, so this torch stays nonhittable. |
| `obj.machinery.porta_turret` | This fix makes Strike harm-only, preserving concrete controls/maintenance. |
| `obj.machinery.portable_atmospherics.canister`, `obj.machinery.power.solar` | Master replaced their specific Strike with inherited melee hit; this fix hides that hit outside harm. Canister item exclusions remain. |
| `obj.machinery.computer.ship.navigation.telescreen.dog_eye` | Existing master `c624e243d3` native Emote Beyond now exposes its truthful `too far away` ghost refusal; same cause as the already blessed native navigation pins above. |

Verification: `dq_interaction_domain_snapshot/i7_bulk` successfully re-recorded
283 type files (282 changed). The focused `machine_click_intent` regression
passed after its preliminary-candidate assertion was corrected to inspect the
actual winner. It checks real Use execution, harm integrity loss and an explicit
AI attack without harm click stance, with clean boot and no state leak. Final
compilation had 0 errors; DreamChecker had 0 diagnostics; lint and ratchets passed.
No full suite ran, and no baseline, ceiling or ALLOW annotation was changed.

## Batch 9 merge pins (rewrite/integ-9)

Merging machinery-click-intent with ui-outputs and timed-tasks changed these pins; the rows were reviewed and blessed by class.

* **`pins/` machinery files (334 files, 3629 removed `menu: Hit` rows, 8 `click:` rows `Click: Hit` -> `nothing`).** The class of "Machinery non-harm item clicks" above: the same intent correction applies to the `dq_conversion_pin` copies of the machinery types, not only to `i7_bulk`. Only removals of `menu: Hit` and the `Click: Hit` -> `nothing` change; no other row moved.
* **`look_states/obj.item.melee.robotic.baton.txt` (20 rows).** The sampled variable set for the arm and slime batons shifted (`gurgled` is sampled, `randpixel` no longer is) because the merged branches changed the variable list the look-state sampler walks on `/obj/item`; the arm and slime looks themselves (`electrified arm`/`shock`, `slimebaton`/`slimebaton_active`) are unchanged.
* **Stale interim tests.** `interim_confetti_cleanup` and `interim_snow_shovel_cleanup` asserted the old handler/commit shape; the ops are now `wait()` ops (timed-tasks), so they assert the actor has a pending op.

## Grants, timers and the c4 boundary tests (rewrite/om-leftovers)

- Grants are capabilities and keyed stats, not a grant store: abilities are `granted_ability(id)` activations, verbs and hides are `granted_verb()` activations
  (the verb store reads the live activations), conditions are `held_condition(path)`, traits are holds on `STAT_TRAIT_HOLDS` and cadences holds on
  `STAT_CADENCE_HOLDS`. The step cadence hears its holds through an on_change reaction, delivered at the next drain point rather than inline.
  The OM `self_grants`, `grants_target` and `grants_occupant` rows, the legacy verb-path form of `grant()` and `hidden_verb()` are gone.
- A keyed timer whose datum argument is deleted drops the call and clears its key (`after_pending()` is false afterwards); `keeps_dead = TRUE` still runs it
  with the argument null. The fulton chain, the cryptdrake landing and the transit-tube station completions opt in, because their tail must run.
- The smole building and ruins "Smash" ops answer harm intent as well as use, so a harm-intent click with a held item smashes rather than landing a melee hit.

## Batch 10 merge pins (rewrite/integ-10)

Merging om-leftovers into master changed these pins; the rows were reviewed and blessed by class.

* **`hit_pins/` machinery, computers and shield generators (`refresh_bits: 9 -> 0` becomes `1 -> 0`, `73 -> 0` becomes `65 -> 0`, `8 -> 0` row gone).** Bit 8 is `CHANGE_EFFECTS`: the OM effect store marked a machine's first draw with it when the machine's self-effect hold was made at init. The effect store is deleted, so only the explicit bit stays. Same cause as the draw-sweep class above.
* **`hit_pins/obj.structure.reagent_dispensers.coolanttank` (four `om_rec: null -> /datum/scheduler_record` rows).** The tank no longer gets a scheduler record from an init-time effect hold; the record is created lazily by the first explosion or projectile hit that needs one.
* **`hit_pins/obj.structure.smoleruins` (`emag`: deleted and two bricks -> nothing).** An emag swipe is a non-harm item click; the smole "Smash" op is gated by `harm_click_only` (see the destructive held-item class above).
* **`pins/mob.living.simple_mob.vore.overmap.stardog` (`Nutrition heal` menu rows, keys `nutrition_heal` and `reload`).** The branch re-recorded this file before master's timed-tasks gave every simple mob the `nutrition_heal` op; the merge needs both.

## Topic gates as requirements (rewrite/om-leftovers-2)

- **Sleevemate:** its scan links spend the click cooldown (`DEFAULT_ATTACK_COOLDOWN`) only after the gate passes (the held-in-active-hand check). The old gate spent it first, so a link clicked while the sleevemate was not held also paid the cooldown. Now a refused link costs nothing.
- **Topic refusals say `You cannot use that link right now.`** (`MSG(op/topic_gate)`) where the old gates returned silently; the Access Denied line of an obj the clicker's ID cannot use is unchanged, printed once per check.
- **VV namespaced ops (`topic_in`) carry no `TAG_TOPIC`**, so the per-type topic requirements never reach them; the VV dispatch keeps its own gate.


## Draw framework round 2c: cards, floors, look pins for turfs

* **`look_trees/obj.item.card.txt`: the generic emissive blocker follows the drawn sprite.** Every card row `overlay: icons/obj/card_new.dmi:<made sprite>:8:#000000` (the plane-8 blocker; 97 card types) now names the sprite the card draws (`base-stamp`) instead of the one it was made with (`generic-nt`, `security-id`, ...): the card is a draw over its tracked `sprite_stack`, and a look that changes an atom's sprite re-syncs its blocker (`look_resync_emissive_blocker()`, as for the table, lightpost and the other converted types). Icon, state, dir and every non-blocker overlay row are unchanged. The guest pass keeps its mapped sprite (`look_parts()` empty, was `APPEARANCE_NONE`).
* **`look_trees/turf.simulated.floor.txt`: two rolled variants moved.** `/turf/simulated/floor/outdoors/fur` `fur15` to `fur6` and `/turf/simulated/floor/plating/eris` `plating18` to `plating7`. The variant of a flooring with a range (`has_base_range`) is rolled in `set_flooring()` (into the tracked `flooring_override`) instead of on the first draw, so the roll happens before the floor's `prob(dirty_prob)`/`rand()` in `Initialize()` instead of after them; the pin reseeds the RNG from the type path, so the number each type draws shifts. Same distribution, rolled once when the flooring is laid. `plating_damage_state` (which of `dmg1`..`dmg4` a broken plate shows) is rolled when the tile is damaged, not on every draw (no pin row: a fresh floor is undamaged).
* **New pins, recorded on the base before any conversion, unchanged by this round:** `look_trees/turf.simulated.floor.txt` (774 rows after the two above), `turf.simulated.wall.txt`, `mob.living.simple_mob.txt`, `mob.living.silicon.robot.txt`, `obj.item.clothing.txt` (recorded for the chains that did not convert; they pin the next round). `dq_look_tree_pin` makes turf types now (the tile east of the test floor is turned into the type and back).
* **Rechecked, unchanged:** `obj.structure.medical_stand`, `obj.machinery.reagent_refinery.furnace` and `.hub`, `obj.structure.table`, `obj.structure.barricade(.sandbag)` look-tree rows and the table look-state rows blessed last round.
* **Not from this branch:** the `blob/core` colour rows (`#639b3f` to `#b68d00`, three types) differ from the recorded pin with no blob code touched here (random colour; the pin was recorded before the last master merges); the `electronic_assembly`, `baton/arm`, `baton/slime` and `ntnet_relay` rows and the `anomalock` heart runtime are the same ones that differ on the base commit.
* **`identity(name =, desc =)` composes:** a call that names only one leaves the other as it was (it used to clear it), so the two `name =` / `desc =` writes a provider makes convert to two calls.

## Draw framework round 2d: furniture, clothing look, closet pins

* **`look_trees/obj.structure.bed.txt`: the generic emissive blocker follows the drawn state.** Every bed, chair, sofa and wheelchair row `overlay: <icon>:<made state>:8:#000000` (75 types) is now `overlay: <icon>::8:#000000`: the furniture look draws the empty base state (`look.state("")`, the seat is an overlay) and a look that changes an atom's sprite re-syncs its blocker. The legacy provider wrote the same empty state on the first `update_icon()`, which a freshly made piece of furniture never got before the pin. All non-blocker rows (the seat, padding, armrest images, planes and tints) are unchanged. The shared image cache is keyed by icon, state, tint and plane (`look_cached_image()`): the old `GLOB.stool_cache` key ignored the icon file and `applies_material_colour`, so two types with one base state shared an image.
* **`look_trees/obj.item.clothing.txt`:** `/obj/item/clothing/suit/armor/shield` draws `shield_armor_0` (state and blocker) from its first draw instead of the mapped `reactive` it was made with (its provider only ran on the first toggle, so a fresh shield suit showed the reactive-armour sprite until it was used); and `/obj/item/clothing/head/hood/winter/ratvar`, which starts with its lamp on, shows `helmet_light` on the item from its first draw. Every other clothing row is unchanged.
* **Open space and cliffs.** Open space draws `edge_spill` and its backdrop from the mask (`update_icon_edge()` is gone); a cliff that blocks edges refreshes the tiles beside it when it is made and when it is taken away (`dq_turf_edges/cliff_blocks_and_releases_edges`, `open_space_takes_edges`).
* **Clothing look (no pin rows change beyond the above):** a garment draws its blood stain from the tracked blood colour (`forensic_blood_color`, `forensic_was_bloodied`, `forensic_fluorescent` are `TRACKED` on `/atom`, written through the `dq_set_*` helpers) and the forensics record, so `add_blood()` adds no overlay to clothing (`stains_in_look()`); a vore gurgle stain is drawn from the tracked `gurgled` / `gurgled_color` (the shoes' wash-and-recontaminate pass on every redraw is gone); a lit helmet draws its lamp as a layer and redraws the wearer's head slot as a look effect. `make_worn_icon()` now builds the worn lamp under the same key it reads: a helmet with a species sheet showed no lamp on that species before (`dq_draw_helmet_lamp_worn_by_sprite_sheet_species`). The kitty ears overlay on the item is gone: the worn sprite is built from the item icon, never from its overlays, so it was never shown.
* **`light_on` is tracked** (`set_light_on()` publishes it, `SETTER(/atom, light_on)`): a drawn thing that shows its lamp redraws when it changes. No bare writes were found.
* **Closet pins** (`look_trees/obj.structure.closet.body_bag`, `.coffin`, `.statue`, `.secure_closet.guncabinet`) are recorded on the base for the next round. The crate and secure-closet roots are not pinned: `crate/oldreactor` and the species egg closets take minutes per type to make in the test world.
* **Look-state pin rows (`aviator`, `hood.toggleable`, `armor.reactive`, `armor.tesla`, `armor.shield`, `obj.structure.bed`):** (1) each probe that changes the sprite now also moves the plane-8 emissive blocker (`+overlay ...:8:#000000` / `-overlay ...:8:#000000` beside the existing `+state` / `-state` row): the same re-sync as the tree rows above, 44 reactive, 8 tesla, 4 aviator, 4 hood rows; (2) the shield armour loses its 100 `-state: reactive` / `+state: shield_armor_0` probe rows, because it is made in `shield_armor_0` already (see the tree rows), and gains the 6 blocker/overlay rows of `active=`; (3) the bed pin gains `occupied=` rows (a chair draws its armrests over a tracked `occupied`) and `applies_material_colour=` rows (the old image cache key ignored the var, so changing it never showed; the draw's key includes it): 496 added rows, none removed. Tracked `on`, `open`, `active`, `ready` give the probes a real redraw where the plain var gave none.

## Batch 11 merge pins (rewrite/integ-11)

Merging master-fails, om-leftovers-2 and draw-framework-2 changed these pins; the rows were reviewed and blessed by class.

* **`hit_pins/` clothing (chameleon, holo badge, omnihud, thermal, bluespace gloves, sechailer, reactive, lasertag; `emag`/`emp 2` `nothing` rows become `refresh_queued: 131071 -> 0`, plus `explosion 2`, `explosion 3`, `projectile`, `thrown`).** Same class as the draw sweep above: clothing now draws over tracked state (forensics blood, gurgled), so its first draw is queued when it is made and the first hit flushes it. `reactive` also shows `refresh_bits: 1 -> 0`.
* **`look_states/` clothing `gurgled=1/2` rows (aviator, toggleable hood, reactive, shield, tesla).** `gurgled` is tracked and the clothing look reads it, so a soggy garment gains `+overlay: icons/effects/sludgeoverlay_vr.dmi:green` instead of the old per-type overlay write.
* **`look_states/obj.machinery.pump.txt`, `obj.vehicle.txt`: rows reordered only.** The same rows in a different order, because the sampled variable set shifted (same cause as the baton class above).
* **`look_trees/mob.living.simple_mob.txt`.** The two `stardog` `runtime: param(child_om_marker ...)` rows are replaced by the real look rows (the declared-ownership runtime no longer happens), and the test-only simple mobs `dq_rocket_probe` and `e0_fixture/denied_counter` are new rows.
* **`look_trees/turf.simulated.floor.txt`: the lighting darkness layer is not a look.** The look pin row builder skips an underlay of `LIGHTING_ICON`; whether a floor has it depends on boot timing, and with it the merged tree recorded 222 `underlay: icons/effects/lighting_object.dmi:dark:5` rows the branch did not.
* **Not blessed** (known): the `electronic_assembly` `op_clash` runtime row and the `blob/core` random colour rows in `look_trees`.

## Master fails round 2 (rewrite/master-fails-2)

Fixes for the failures carried as "known" across the merge batches. Every pin row below changed for a stated cause; nothing else was blessed.

* **`dq_e2/explain_click_golden`: the golden is regenerated (35 lines, was 32).** Three candidates are new correct behaviour, not regressions: `melee_hit` (`item(/obj/item)`, `hostile()`, tier -2009, from the `/obj` capability block: every obj is hittable), `reload` (a `/mob/living/simple_mob` `ai()` op) and `nutrition_heal` (its `menu(button = "Nutrition Heal")`). Every candidate line also gained `claims=... (derived)` and the declaring line numbers moved; the golden had not been refreshed for either. All three new candidates are dropped by match or origin and the winner is still `pry (tier part)`.
* **`look_trees/obj.item.organ.internal.heart.machine.anomalock.txt`: the `prebuilt` runtime row (`Cannot execute null.add overlay()`) is replaced by its look rows.** A prebuilt heart's core makes `handle_organ_mod_special()` run at creation, before the heart has an owner; it drew the lightning overlay on a null owner. It now does nothing without an owner (the same call on removal had the same null owner when the heart's holder was deleted). The look is `anomalock_heart-core`.
* **`look_trees/obj.item.assembly.electronic_assembly.txt`: no row changes, the recorded rows now hold.** The device assembly declared `electronic_assembly_interaction_item` (`item(/obj/item)`) beside the parent `/obj/item/assembly` `attach` op (the same input and tier: `op_clash`, a declaration runtime that replaced the whole look). The device now drops the parent's `attach` (`without("attach")`) and its own op falls through to the parent's attach handler when the case is closed, so attaching two assemblies behaves as before.
* **`look_trees/obj.structure.blob.txt`: the `blob/core` colours are deterministic.** A core made its overmind (and so rolled its blob type, `pick()`) in an `after_init(0)` timer, long after the pin reseeded the RNG from the path, so the colour depended on what had drawn from the RNG in between and changed from run to run. The core now rolls its blob type in `Initialize()` (the random cores through `get_random_blob_type()`, a plain core from all types), which runs inside the seeded `new`. `get_random_blob_type()` also returned no type for `random_easy` (`BLOB_DIFFICULTY_EASY` is 0 and it tested `!difficulty_threshold`), so the easy core got any type at all (a hard one among them); it now tests `isnull()`. The four rows (`core`, `random_easy`, `random_medium`, `random_hard`) are the new seeded values (`fulminant_organism`, `reactive_spines`, `explosive_lattice`, `fabrication_swarm`); a core that is given a type or an overmind is unchanged.
* **`ownership_framework_checks` (`OWN AUDIT: dropped with a rec: .../smoke_spread/chem`).** A chem smoke system is a fire-and-forget datum (`new`, `set_up`, `start`, dropped), and each cloud's fade timer was scheduled on the system, so the system lived on as a datum referenced only by its own timers (and its owned reagent holder with it). The fade timer is now the cloud's own (`fade_out()` on `/obj/effect/effect/smoke/chem`) and the system expires right after `start()`. New test `ownership_chem_smoke_not_dropped`.
* **`dq_lifecycle_sandbox`.** The 7 entries were two snapshot counters that are not registrations: `GLOB.capability_runtime_records` (a holder's own record, made when it first has data: a scrap's rolled materials, a belt's welding tool; removed in that holder's final cleanup, proved by `dq_time_foundation_compatibility_tests`) and `GLOB.caps_interned` (signature -> shared capability definition, filled the first time a type is seen: an MRE's random meal). Neither is world state an Initialize() leaks, so both join the sandbox's ignored first-use caches with the reason beside them.
* **`dq_look_tree_pin` leak.** The pin ended with `UNIT TEST LEAK: ... space_worm/head/severed x7`: deleting a worm's segment severs the back half into a new dead head, and the block's own cleanup then repeated that down the chain. The sweep now drains the test floor (deleting until nothing is left) after its last capture, before the block is released. It is not drained per capture: later captures see what earlier ones left (a closet or fridge takes the items on its tile), and the recorded rows include that.
* **Hit pins and look-state pins:** `baton/arm`, `baton/slime` and `ntnet_relay dos_failure` no longer differ on master; no rows changed.

## Draw mobs: the simple mob and robot looks (rewrite/draw-mobs)

* **One simple mob draw, tracked pounce, eyes as a look layer, fullness from the bellies.** The three providers of `/mob/living/simple_mob` (`appearance.dm`, `simple_mob.dm`, `simple_mob_abilities.dm`) are one `draw()`. `pouncing`, `spitting`, `icon_living`/`icon_dead`/`icon_rest` and the hand sprites are `TRACKED`; the leap swaps the icon file and state through `look.set_icon()`/`look.state()` and shifts the sprite with `look.offset()` (the `icon_pounce_cache` and `icon_pounce_x_old`/`_y_old` caches are gone: the look gives the offset back by itself). `add_eyes()`/`remove_eyes()`/`eye_layer` are `look.eyes()`. `vore_fullness`/`vore_fullness_ex` are `TRACKED` (`set_vore_fullness()`, content-compared `set_vore_fullness_ex()`); `update_fullness()` writes through them, and nothing calls it by hand: a belly publishes `belly_change` on its owner (entry, exit, liquid, a prey's health moving the size, sprite settings edited in the vore panel) and `/mob` hears `/datum/notice/belly_changed`. The ~55 `handle_belly_update()` / `handle_belly_update_buckets()` callers became that publish at the point the belly changes; the two procs are deleted.
* **Look-tree rows, classes (`look_trees/mob.living.simple_mob.txt`, `mob.living.silicon.robot.txt`):**
  * **A look made at creation.** The legacy providers only ran on the first `update_icon()`, so a fresh mob showed its mapped state; it now draws its life state from the start. Rows: `clockwork/fluff/Ignis ignis -> clockwork_marauder_r`, `mechanical/combat_drone/melee droneM -> drone` (and its eyes), the robots (`icons/mob/robots.dmi:robot -> icons/mob/robot/default.dmi:default`, plus the `default-eyes` overlay on every robot that has eyes; the shell is undeployed so `ai_shell` has none), the worms (`spaceworm -> spacewormtail`, `spacewormhead -> spacewormheadN_hunt`), `lion` gains its `mane` layer, the platform's body.
  * **Body effects drawn once as themselves.** `slime/*/ruby` and `humanoid/astral_collective/**`: the legacy `modifier_overlay` was an empty image carrying the effect as a sub-overlay and was added twice (`overlay: ::-32767 x2`). The look draws each effect once (`pink_sparkles`, `poisoned`).
  * **Eyes drawn once, from the state.** `construct/**` `-eyes x2` -> `<state>-eyes`, and `vore/zorgoia` loses its `-eyes x2` (a state that does not exist): `add_eyes()` ran twice and kept the first state it saw.
  * **`cut_overlays()` no longer wipes unrelated layers.** `animal/synx/**` and `vore/bigdragon/**` gain the AI debug layers (`buildmode.dmi:ais_1`, `ai_0`, `win32.dmi`) every other simple mob already had: their icon builders called `cut_overlays()`. The dragon's rolled colours/horns differ because the roll moved out of the draw into `Initialize()` (`randomize_style()`), where the seeded RNG meets it in another order.
  * **Platform body is an overlay, not an underlay.** The look has no underlays; the body is the first overlay (nothing else draws below it), the type's `color` tint (the same as the module's armour colour) is dropped so the body is not tinted twice.
  * **Typo fixed:** `humanoid/merc/ranged/space` `icon_living` read `syndicatespceace-ranged`.
  * `animal/passive/bird/parrot/eclectus` rolls `icon_living` with the gendered state; the row's value follows the seeded roll.
* **`update_transform()` is no longer called from a draw.** It reset the transform to the icon scale on every redraw, which undid a `resize()` animation; scale and rotation are applied where `icon_scale_*`/`icon_rotation` change (`adjust_scale()`, `adjust_rotation()`).
* **Robot.** `sprite_datum` (relation, `on_change` -> `sprite_changed()` sets `vis_height`, the pixel offset, a valid `rest_style` and the status indicators once), `opened`, `wiresexposed`, `lights_on`, `glowy_enabled`, `rest_style`, `sprite_type`, `module_active`, `shell`, `deployed`, the decal list, the sprite customisation, the active module types (`module_slots_changed()` from the slot signal, which is also where melee modules refresh their light) and the platform module's colours (`pupil_color`, `body_color` (was `base_color`, which `/atom` already has a setter for), `eye_color`, `armor_color`, `decals`) are tracked. `apply_base_appearance()` and `handle_status_indicators()` left the provider. The belly lights are computed with the fullness (`update_fullness()` of a robot sets the tracked `vore_light_states`); the sprite datum reads `belly_light()` and `get_rest_sprite()`/`get_belly_resting_overlay()` no longer write `rest_style`. The struggle sprite is a `look_flash()`. `handle_extra_icon_updates()` is `look_extras(look, borg)`: the equipment sprites are look parts and no longer leak as raw overlays. A hat is drawn at the sprite's offset by `pixel_x`/`pixel_y` instead of `pixel_w`/`pixel_z` (the key of a look overlay names the former). The drone and the platform override `look_parts()`; the thinking/typing indicators and status indicators add and remove their own overlays, so the draw no longer re-adds them (it added the typing bubble twice).
* **Ghost-join marker** is a layer of the base draw (`ghostjoin`, already tracked); `ghostjoin_icon()` and its 13 callers are gone.
* **Tests removed:** `round2_lion_cached_mane_parity` and `round2_zorgoia_overlay_cache` pinned the cached mane and the cached zorgoia overlays and the provider procs, which no longer exist. New: `dq_draw_mobs.dm`.
* **New look-state pins (recorded on `8131886557`, before any change here):** `look_states/mob.living.silicon.robot.txt` and the roots of the 25 other provider types (`mob.living.simple_mob.*`: hyena, armadillo, sakimm, fish, opossum, space_worm, synx, mecha, ward.monitor, shadekin, slime, catslug, teppi, bigdragon, blaidd, fennec, gryphon, lamia, morph, spacewhale, raptor, lion, seagull, sonadile, squirrel, swoopie, turkeygirl, zorgoia, xenomorph). Every retained row is unchanged; the blessed files only **lose** rows, in three classes: (1) a probe that used to show the delta between the made look and the first redraw (robot: `robots.dmi:robot -> default.dmi:default` for every probed var; worm head: `spacewormhead -> spacewormheadN_hunt`; lion: `+overlay mane`) writes no row, because the made look is now the drawn look; (2) the `-overlay <state>-eyes` / `+overlay <state>-eyes` pairs of fish, mecha, monitor ward, teppi, fennec shadow, zorgoia: the legacy eye image was rebuilt on every redraw, the eyes are now one stable layer; (3) the same pairs for the teppi `skin_base` / `eye_base` layers, now built per draw from tracked colours. No row is added: the `opened`, `deployed`, `wiresexposed`, fullness and pose rows still show their overlays and states.
* **`look_trees/` rows not from this branch** (`obj.effect.mine`, `obj.item.assembly.electronic_assembly`, `obj.structure.blob`) differ on the base too and were not committed. The turf floor rows (`underlay: ...lighting_object.dmi:dark:5`) are a property of the focused world and were not blessed.

### Draw mobs follow-up (leftovers, teardown, look_converted)

* **`simple_mob/` and `silicon/robot/` join `look_converted`** (hard ban on `update_icon()` and legacy appearance declarations). Converted on the way: the closet mimic, the gripper (it mirrors the held item into a tracked `shown_item`, because a `ref_one` write redraws nothing), the cyborg welder flame (drawn by the belt that carries it), module syringes (`mode` is `TRACKED`, the look is a draw), fleshtaker's mimic (tracked `flesh_mimic`/`mimic_icon`, shown with `look.set_icon()`), the active `hand` (`TRACKED_BRIDGED` with the `CHANGE_MOB_HANDS` channel the checks still listen on). `/mob/living/simple_mob/draws_life_state = FALSE` is the old `APPEARANCE_NONE` (homunculus, illusion).
* **Behaviour changes:** a syringe cartridge shows its loaded syringe and filling as overlays (the look has no underlays); macrophage's decal no longer has its name reset to "blood" by a redraw; the zone-selection HUD overlay is no longer redrawn by the simple mob HUD set-up (the screen is still a legacy provider outside this folder); a mimicking fleshtaker shows its living state rather than the target's state at the moment it copied.
* **Teardown:** deleting a worm from the front, or out of the world, takes its back half with it (it used to leave a severed head that deleted again into another: the cause of the `space_worm/head/severed` leak); a blob core takes its overmind with it (the pins leaked one overmind per core, ~850 in the state pin).
* **Pins:** the committed tree and state pin rows are unchanged by this round. `look_trees/obj.structure.blob.txt` differs on the base (random colour) and was not committed. **Known, not fixed:** the full-directory `dq_look_state_pin` slows to minutes per type after its blob roots (one root alone runs in seconds), so it does not finish inside a 90 minute watchdog; and `dq_look_tree_pin` still reports the anomalock heart runtime (`emp_protection_flags` of null) and `ownership_framework_checks` the chem smoke leak, both present on the base.

## Batch 12 merge pins (rewrite/integ-12)

Merging master-fails-2 and draw-mobs changed these pins; the rows were reviewed and blessed by class.

* **`look_trees/obj.item.assembly.electronic_assembly.txt`: the `op_clash` runtime row is replaced by the real look rows** (`new_assemblies.dmi:setup_device`, its dir and emissive blocker). master-fails-2 removed the clash (the device drops the parent's `attach`) but did not commit the pin; the look is now recorded.
* **`look_trees/obj.structure.blob.txt`: the four `blob/core` colours are the seeded values of the merged tree.** The core rolls its blob type in `Initialize()` (master-fails-2) and a core now takes its overmind with it (draw-mobs), which moves where the seeded RNG lands; the values are deterministic per run (rerun checked).
* **`dq_e2/explain_click_golden`:** the `simple_mob.dm` capability lines moved by 7 (the simple mob's tracked list grew); the rows are otherwise unchanged.
* **`interim_target_zone_hud_actor`** had no `/datum/unit_test/om/` declaration, so it never ran; it is declared and runs.
* **Known, not run:** the full-directory `dq_look_state_pin` (slowdown handled in another lane; the test has no root filter).
### Machinery audit: card dispatch, topic gates and record arguments (2026-10-08)

- `/obj/machinery/computer/teleporter`: the coordinate-card insert op now outranks the inherited computer `use_item` fallback on a plain click. Its priority is DEFAULT + 1. The sticky-card regression again uses real clicks, asserts the selected insert key, preserves a card on a refused sticky update, and consumes it on an allowed update. Pin click rows changing from the generic computer use to Insert data card are intended.
- `/obj/machinery/syndicate_beacon` and `/virgo`: topic usability is checked as an operation requirement before opening the offer, before executing an answered offer, and on inherited UI actions. Removing the effect-only wrapper makes refusals visible at admission and keeps a user who loses access from spending a charge. Refusal/menu pin changes for these classes have this cause.
- `/obj/machinery/computer/med_data`, `/secure_data` and `/skills`: checked modal arguments are supplied with `arg_of("arguments")` to typed record-edit requests. Their native preparation retains the existing field-specific question, choice table and default. This removes computed argument plumbing without changing the edit or cancellation effects.
- Machinery J6 timers: blackhole damage and delayed wish-granter gib no longer opt into execution with a deleted sole target. Nine cleanup continuations retain their opt-out; the J6 table records the cleanup and focused regression for each.


## Machinery timed-action port, 2026-10-08 audit

This port preserves the reviewed `6c7c06f5f2` conversion on current master `6cf9e920d7`. Old-code evidence is historical, not a fresh run: the old pins ran against `059aac8767`; 17 of 18 compared source files are LF-byte-identical, and the three relevant AIcore timed method bodies match exactly despite unrelated master latejoin/admin changes. `doc/machinery_audit_1008_old_pin_provenance.json` records individual SHA-256 hashes. Current-branch focused verification and capture review remain pending; the reused snapshots are expectations, not evidence of a new successful capture.

| Class | Documented native change and preserved behavior |
|---|---|
| IV drip, feeder, doorbell | Existing tool operations own the 1.5-second wait and original start feedback; dismantling and buckle consequences remain unchanged. |
| Food replicator | Existing scanning operation owns its one-second wait, capturing actual food type/name; scanning still updates the registry without consuming food. |
| Supply beacon | Deployment uses the native wait with `deploy_time`; expiry and reactivation handling are retained. |
| Flesh organ printer and full variant | Typed `load_container` glass input replaces the delayed generic item branch. One-second delay, real beaker custody and zero biomass cost remain; loaded-container rejection is a requirement. |
| Clonepod and subtypes | Typed container loading owns the one-second wait and retains capacity, custody and zero biomass expenditure. |
| AIcore | `add_cables` and `add_panel` own two-second waits at states 2 and 3, consuming exactly five cables or two reinforced-glass sheets. State is tracked and recheck refusals have typed reasons. Wrong materials remain filtered; law/MMI behavior and master's latejoin/admin asks are retained. Five other helper-driven construction waits remain legacy. |
| Breaker box and activated variant | Existing hand/remote toggle operations wait five seconds with a target claim. Native claimed refusal replaces the old busy wording; switch effects and 60-second lock remain. |
| Camera and variants | Existing `use_welder` owns the ten-second duration multiplied by the real tool speed and actor skill factor. Start retains eye checking and actual tool sound; completion retains coverage invalidation and the original zero-fuel tool resource commit, including electric welder charge. The published aggregate wire key makes mending during work cancel immediately. |
| Camera assembly | Native `use_welder` replaces the timed welder helper, retaining two-second tool/skill-scaled duration, target claim, states 1/2, eye checking, sound and zero-fuel resource commit. State is tracked. |
| Washing machine | Grab loading waits five seconds and consumes the actual grab only on success. Escape snapshots admission door state for the two-/60-second duration, then checks the live door at completion; resist dispatches the same operation. |
| Oxygen pump | Native human-target drag preserves its 2.5-second wait and actual destination with `at_target`; the explicit actor replaces ambient `usr`. |
| VR sleeper | Self/grab entry retains two-second waits, occupancy checks and completion custody; later avatar-consent requests remain unchanged. |
| Cryopod self-entry | Self-entry retains two seconds, occupant-type filtering and neighboring gateway activation at start. Third-party passenger consent remains legacy because native asks currently answer as the operation actor. |
| Suit storage unit | Existing hide/load keys retain one-second self and two-second grab entry; ordinary suit/helmet/mask insertion remains immediate. Door/power/broken dependencies are tracked, and slot custody, fingerprints, closure and grab consumption remain. Movement or dropping cancels work. |
| Cutout barricade | Current master already owns the native prompted ten-second operation. This port reuses regression coverage only and does not change its production source. |

Faster-welder, immediate wire-mending cancellation and electric-charge-once/cancellation checks are native-added regressions, not historical old-code verified pins. Electric charge expectations use the cell's public delivery-efficiency contract to account for physical delivery loss, rather than a loose tolerance. Existing breaker tests observe native pending/claimed state instead of legacy task internals. No new pin re-bless is approved merely by this provenance record; any fresh difference still requires class-specific review.

### Reviewed machinery audit pin refresh (2026-10-08)

The single focused capture wrote 23 selected pin types, 15 selected i7 types and 18 historical timed-pin types; 38 files changed. No runtime/op-clash capture rows were accepted. Reused timed pins also shed inherited non-harm `Hit` menu rows to match current master; that is a pre-existing master intent gate, not a new harm-intent change here. Each affected class is listed below.

| Type | Cause of changed rows |
|---|---|
| /obj/item/camera_assembly | Native use_welder key replaces the implicit timed tool handler. |
| /obj/machinery/button/doorbell | The reused timed snapshot drops inherited non-harm Hit menu rows to match existing master intent gates; the class-specific timed behavior is documented above. |
| /obj/machinery/camera | Native repair is offered only on a damaged camera; a working fixture no longer offers an irrelevant welder repair. Reused non-harm Hit rows align with master. |
| /obj/machinery/clonepod | Typed glass load_container adds its held-container rows and native key. Reused non-harm Hit rows align with master. |
| /obj/machinery/clonepod/transhuman | Typed glass load_container adds its held-container rows and native key. Reused non-harm Hit rows align with master. |
| /obj/machinery/computer/teleporter | Insert data card now outranks inherited Use item on a plain card click. |
| /obj/machinery/cryopod | Self-entry uses its native operation key. Reused non-harm Hit rows align with master; passenger consent is retained. |
| /obj/machinery/feeder | The reused timed snapshot drops inherited non-harm Hit menu rows to match existing master intent gates; the class-specific timed behavior is documented above. |
| /obj/machinery/food_replicator | The reused timed snapshot drops inherited non-harm Hit menu rows to match existing master intent gates; the class-specific timed behavior is documented above. |
| /obj/machinery/iv_drip | The reused timed snapshot drops inherited non-harm Hit menu rows to match existing master intent gates; the class-specific timed behavior is documented above. |
| /obj/machinery/organ_printer/flesh | The reused timed snapshot drops inherited non-harm Hit menu rows to match existing master intent gates; the class-specific timed behavior is documented above. |
| /obj/machinery/oxygen_pump | The human-target drag now has the native oxygen_place key. Reused non-harm Hit rows align with master. |
| /obj/machinery/oxygen_pump/mobile/stabilizer | The human-target drag now has the native oxygen_place key. Reused non-harm Hit rows align with master. |
| /obj/machinery/power/breakerbox | The reused timed snapshot drops inherited non-harm Hit menu rows to match existing master intent gates; the class-specific timed behavior is documented above. |
| /obj/machinery/suit_cycler | The reused timed snapshot drops inherited non-harm Hit menu rows to match existing master intent gates; the class-specific timed behavior is documented above. |
| /obj/machinery/suit_storage_unit | Closed-door admission now greys Hide in Suit Storage Unit before starting; timed custody and cancellation are unchanged. Reused non-harm Hit rows align with master. |
| /obj/machinery/syndicate_beacon | Topic usability is an admission/recheck requirement, so denied actors see the refused offer row instead of an effect-only failure. |
| /obj/machinery/syndicate_beacon/virgo | Topic usability is an admission/recheck requirement, so denied actors see the refused offer row instead of an effect-only failure. |
| /obj/machinery/vr_sleeper | Entry uses native timed operations and keys, with the same occupancy rules. Reused non-harm Hit rows align with master. |
| /obj/machinery/vr_sleeper/alien | Entry uses native timed operations and keys, with the same occupancy rules. Reused non-harm Hit rows align with master. |
| /obj/machinery/washing_machine | Grab and resist timing use native operation keys. Reused non-harm Hit rows align with master. |
| /obj/structure/AIcore | Native add_cables/add_panel keys expose typed material bindings, adding stack-material held rows; actual construction costs and states are regression tested. |

## Draw structures, effects and HUD buttons (rewrite/draw-structures)

Converted to `draw(look)` over tracked state, with their `update_icon()` and `changed(src)` calls gone: closets, crates and lockers (`closet_look()` is the one overridable part: the egg, the statue, the gun cabinet, the body bags and the mind locker replace it), the gun cabinet, the vehicle cage, the cliff, the railing, the low wall frames (bay, eris), the janitorial cart, the bonfire and fireplace (fuel is a `CONTAINER_SLOT_FUEL` slot), the cleanable decal family (blood, gibs, tracks, reagent puddles, crayon, chem coating), the fire axe cabinet, display case, inflatable door and simple door (their plain vars are `TRACKED`), the ability buttons and the hand screens. New builder forms: `look.contents_of(src, slot, type)` (the types a slot holds, real and declared, nothing made; stands for `SLOT_OCCUPANCY_KEY`), `look.things_in(src, slot, type)`, `look.picture_of(thing)`, `look.show_copy_of(thing, layer)`; `/atom/proc/slot_kinds()` behind the first; the latent ledger now publishes the slot's occupancy when an entry is made or used (`latent_set_count()`) and when a holder declares its generator.

Not converted, and why: the window family (`window.dm`, `window_construction.dm`, the bay and eris windows in `low_wall.dm`) because `/obj/structure/window/fancy_shuttle` (turfs/simulated/fancy_shuttles.dm, another lane) and `survival_pod` windows still draw through legacy providers and inherit the base; the windoor assembly because `windowdoor.dm` (machinery lane) writes its `facing` by hand; the grille's `changed(src)` because the RCD repair in `turfs/simulated/walls.dm` writes `destroyed` by hand; `bombspawner.dm`'s `V.update_icon()` because the transfer valve is still a legacy provider.

Pins were not recorded in this lane (the committed snapshots are the base); the merge blesses against these expected classes. Rows that change, by cause:

* **A look drawn from the start.** The legacy providers ran at the first `update_icon()` (a closet's `closet_after_init`, a cliff's `shape_cliff`); the draw runs at creation. Rows: the cliff roots show `cliff-<dir><variant>...` where the mapped state was; closets show the closed/open state of their decal icon.
* **No `color = null` on a closet.** The decal swap no longer clears the atom colour; the look sets only the icon. No row changes unless a closet type maps a colour.
* **Blockers follow the drawn state.** Closets, crates, the cabinet, the vehicle cage and the cliff change their sprite through the look, so the plane-8 emissive blocker row follows the made state, as in the furniture round.
* **State-probe rows of the draw round.** Cliff corner/bottom rows show the made `cliff-<dir>` state (drawn from creation, as above). Body bags and coffins now show their `open`/`base`/`closed_unlocked` overlay and state rows on every opened toggle, because opening is a tracked write that redraws instead of waiting for `update_icon()`. The morph runtime row names `em_block` before `hud_list` as the refused ownership put, because the draw now runs at creation and makes the blocker first; the refusals themselves are unchanged.
* **Shuttle carry underlays.** `underlay_update()` turned `join_flags` to find the turf opposite a joined diagonal, and an unjoined turf has `join_flags = 0`, for which `turn(0, ...)` picks a random direction: the carry plating's underlay was whatever neighbour the roll landed on (the recorded `steel` tile). An unjoined turf now lies on the area's base turf every time; the two rows (`/turf/simulated/shuttle/plating/carry` and `.../airless/carry`) read the base turf of the test map, space (`icons/turf/space.dmi:white`, plane -82). Pinned by `dq_shuttle_underlay_is_not_random`.
* **Relation writes mark through one path.** The list view write (`_rel_attach`/`_rel_detach`) called both `own_field_changed()` and a second mark-if-read proc; the second is gone and `own_field_changed()` marks what reads the var once for a list write and a single ref alike (`dq_draw_relation_writes_redraw_once`).
* **The gun cabinet's guns are real.** An energy gun is not latent-safe, so a cabinet's starting guns are made when it declares its contents after init; the draw reads the slot's types (`look.contents_of()`) and makes nothing. The tests delete the cabinet and drain the tile, since the guns spill when it goes.
* **Gun cabinet.** Guns are drawn from the slot by type (`laser`/`projectile`, one per gun, three at most) and nothing is made by the draw; rows are the same states, the guns stay declared.
* **Body bags.** The label and the stasis indicator are look layers; the label is the tracked `has_label`.
* **Vehicle cage.** The caged vehicle is an overlay behind the frame (the look has no underlays): an `underlay:` row becomes an `overlay:` row.
* **Cleanable decals.** The janitor mark is `janhud<n>` with `n` rolled at creation (seeded), not `rand()` per draw. Gibs are the file icon tinted by the blood colour with the flesh as a `RESET_COLOR` overlay (the legacy flesh image was built with a direction where the state belonged and never showed; the icon was a blended runtime icon): the `icon:` row is the file, a `<state>_flesh` overlay row appears. Dried decals are drawn darker under their dried name from the tracked `dried`. A reagent puddle of blood or water is named and drawn as the blood decal it is (legacy: no name, no colour).
* **Bonfire.** Its fuel is the `fuel` slot; rows do not change.
* **Ability and hand buttons.** Not pinned (not `/obj`/`/mob`).

Hybrid fixes outside the three folders, each the minimum a conversion needed: callers of the new setters (`set_basecolor()`, `set_fleshcolor()`, `set_synthblood()`, `set_ability_icon_state()`) in `modules/body`, `modules/mob`, `modules/event`, `modules/admin`, `modules/xenoarcheaology`; the body bag providers in `items/bodybag.dm` and `items/robobag.dm` (closet descendants).
## Draw items: cells, guns, devices, weapons, spells (rewrite/draw-items)

Expected pin classes for the merge to bless (look-tree `/obj/item`, look-state `/obj/item/gun`, `/obj/item/cell`, `/obj/item/ammo_magazine`, `/obj/item/ammo_casing`); no pin is blessed in this lane.

* **Cell charge is tracked.** `charge` and `maxcharge` are written through `set_charge()` / `set_maxcharge()`; the cell look is a `draw()` (the quarter-step overlay, unchanged). Everything that draws from a cell (energy guns, magnetic guns, rigs, batons, tools) redraws when the charge changes, with no `update_icon()`. `cell.use(amount, seconds)` and `cell.give(amount)` lost their `update_appearance` argument. Writers in `recharger.dm`, `apc.dm`, `portable_turret.dm` and `lighting.dm` are one-line setter changes for Codex to review.
* **Energy guns.** One `draw()` plus `draw_charge_state()`; `modifystate`, `charge_cost` and `mode_name` are tracked and a firemode switch publishes them. A gun with no cell shows its open state; a cell of zero capacity no longer divides by zero. Pin class: energy guns whose state follows an unusual field (hunter, protector, detective revolver, kinetic accelerator, sizegun, tongue, relic) look the same at creation.
* **Chameleon gun.** The mimicked sprite is the tracked `disguise_state`; a redraw keeps the disguise and an EMP reveals the desert eagle.
* **Magnetic guns.** The indicator state is exact and immediate (it was polled every 2 s); the `state` bitmask var is gone; the capacitor charge redraws the amber/green threshold. Parts and charge overlays were listed twice before and now once (same sprite).
* **Smartgun.** Steady closed state draws the default sprite (not `smartgun_closed`); the magazine is an overlay instead of an underlay (no underlay support in the look): check the art.
* **Magazines, clips, casings, handfuls.** The ammo-count look follows the owned `stored_ammo` list and `latent_rounds`. A handful sets its name through `look.identity()`.
* **Cigarette pack, nicotine gum box.** The `_empty` state is drawn whenever the pack is empty (it was written on open/close and lost at the next redraw).
* **Welding tool.** The fuel counter also redraws on refuel and regeneration (reagent change); in-hand state and light go through the look.
* **Devices.** Flares and glowsticks show `-empty` whenever fuel is 0; the denecrotizer shows `-o` whenever charges is 0 (also a mapped-in empty one); the intercom's powered state is the tracked `on`; the radio jammer always draws its charge overlay; the flash's burnt state is tracked `broken`; the communicator, defib, plushie editor and ghost trap redraw from tracked state. `shockpaddles/set_cooldown(delay)` is now `start_cooldown(delay)`.
* **Spells.** The illusion copy overlay is built by `look_overlay_image` (FLOAT layer and plane); the spell `toggled` overlay is a shared cached image.
* **Blessed in this lane (look_states / look_trees):** `obj.item.ammo_magazine` (m9mm: the ammo-count overlay follows rounds loaded, `m91` to `m91-10` at the full level); `obj.item.gun.projectile.automatic.l6_saw` and `mg42` (a raised cover now draws the open overlay, it drew closed before; the look tree full-ammo state is `l6closed50`); `obj.item.melee.robotic.baton` (the `_active` sprite follows the tracked `status`, the baton's cell charge). Not blessed and reverted: run noise in other types' snapshots (the blob core colour, the morph OWN refusal text, empty-file newlines).
* **Draw reads follow the procs a draw calls.** The draw-read generator (`derived_reads.rs`) now follows, on the drawn type and its parents, every proc a draw calls (transitively, once each), and a subtype's override of a called proc is a read of that subtype. Before, a var read only inside a helper (`ammo_count()`, `charge_state_name()`) was never a draw read. About 66 types gained reads; they only add redraw triggers.
* **Relation writes on a type with no `derived()` table.** `own_field_changed()` did nothing for such a type, so clearing a `ref_one` view (a gun's cell) never redrew the gun. A type that declares nothing keeps the old rule (a change that something reads re-derives everything), and `READERS` knows its generated draw reads, so the write now marks it.
* **Left legacy, with reasons:** the rig look (cache and slot refresh in its provider), tanks and the tank assembly proxy (no tracked gas pressure), transfer valve (needs underlays), glass jar (impure draw), bodybags (legacy closet parent), ticket printer (legacy paper), capture crystal, tape roll pickup/drop, the welding tool's reagent hook.



## Reagent, food and hydroponics draws (rewrite/draw-reagents)

Expected pin classes for the merge to bless (no pin is blessed on this branch; the committed snapshots on master are the base). Rows are icon, state, dir, colour, overlays and underlays of every creatable subtype, so only the classes below should move:

| Class | Types | Expected change and cause |
|---|---|---|
| Fill colour spelling | glass (beakers, bottles, vials), syringes, drinking glass fillings | The filling reads the holder's tracked `tint` (the same `get_color()` value, kept by `update_total()`), so a colour row can differ only where `get_color()` changed between creation and the first draw (a prefilled container is drawn after its prefill, as before). |
| Draw after init | glass2 drinking glasses, mugs, shakers | The legacy provider ran on the first `update_icon()`; the draw runs at the first refresh, after the whole init. A glass that is prefilled in init shows its filling at creation. |
| Glass ice/fizz/underlay | `/obj/item/reagent_containers/food/drinks/glass2` chain | Filling, ice, fizz and fruit-slice layers are `look.underlay()` (new in the builder) instead of raw `underlays +=`; same icon states and layers. The protein and protean shakes draw nothing of the glass (was APPEARANCE_NONE). |
| Variable food scale | `/obj/item/reagent_containers/food/snacks/variable` | The size follows the reagent volume at all times (empty draws at the minimum scale); the size word in the name and the weight class are applied once by `settle_size()` when a dish is finished, not on every redraw (the old provider multiplied the weight class on each redraw). Pins carry no transform, so only the state pin may move. |
| Appliance lights and state | `/obj/machinery/appliance` (oven, grill, fryer, mixer, candy, cereal) | Same states and light overlays. Running sounds moved out of the draw into `loop_sync()` handlers on `cooking`, operable and switched-on changes; a machine no longer restarts its loop on a redraw. |
| Tray alerts | `/obj/machinery/portable_atmospherics/hydroponics` | Alert images are built by the draw (same states, lighting-above plane). Name is the look's identity. |
| Pizza box | `/obj/item/pizzabox` | Same states; the stack is a `ref_many` relation, so a stacked box redraws when it is stacked or its tag is written. |
| Rag underlay | `/obj/item/reagent_containers/food/drinks/bottle` | Same underlay and light; drawn from the rag it watches. |
| Synthesizer | `/obj/machinery/chemical_synthesizer` | Same states; `synth_finished` is a tracked `finishing` flag between the last reaction step and bottling. |

Other changes: `/datum/reagents` tracks `total_volume`, `tint` and `master_id` (kept by `update_total()` for non-mob holders; the sum no longer counts survivors twice when a removal runs inside it). A syringe's mode written by the needle capability publishes a tracked change. Tray, microwave, gibber, alembic and gaia/farmbot/hand-labeler writers use the new setters.

Left on legacy forms, with the cause:

* Syringe pickup/dropped/pick-up `update_icon()` (3): the draw reads `loc` (stored sideways, held shows the mode); `loc` is not a tracked draw input. Needs a design decision.
* Vines (`/obj/effect/plant`, spreading, 6 sites): the provider discounts `max_growth` and rolls a wall offset on every redraw, so it is not idempotent. Needs a decision on when the fringe discount applies.
* Pump (9): the low-power overlay reads the cell's charge, untracked in code/modules/power.
* Distillery (5): the ready/heating/cooling overlay reads the heat body's temperature, not tracked state.
* Chem master (1): `loaded_pill_bottle.update_icon()` for a pill bottle whose wrapper colour is a plain var in code/game/objects/items/weapons/storage.
* Smartfridge `changed(src)` (3): the stock count reads `/datum/stored_item.amount`, shared with vending and untracked.
* Condiments and drinks `on_reagent_change()` handlers still write icon_state, name and desc directly (not a draw).
* `rag.dm` (detectivework) still calls the bottle's `update_icon()`; redundant now.
* `lint_scopes.toml` `look_converted` folders: not added (edit refused by the permission layer). Fully clean now: code/library/reagents/, code/modules/food/, code/modules/hydroponics/{trays/,grown*}, code/modules/reagents/{holder,hose,reactions,reagents,machinery/dispenser}/ and Chemistry*.dm.


### AIcore tool waits (2026-10-08)

Old-code behavior pins passed for all five paths before conversion (completion, dropped tool and moved actor per path). On that code, native item dispatch intercepted real clicks before handwritten wrench_act/welder_act; the old pins therefore exercised the actual tool_act dispatcher. Converted pins drive real clicks and keep the same state, custody, cancellation and cost assertions.

| Class | Cause of interaction changes |
|---|---|
| `/obj/structure/AIcore` | Native `anchor`, `unanchor` and `dismantle` tool ops expose the previously intercepted construction actions. Two-second waits preserve anchoring/state transitions, zero welder fuel cost and the exact four-plasteel refund. Invalid-stage tool inputs retain silent refusal rather than falling through to a hit. New tool menu labels and keys reflect these native bindings; these are the only intended changes to the scoped conversion pin. |
| `/obj/structure/AIcore/deactivated` | Native `bolt`/`unbolt` replace the wrench override, retain four-second waits, start/completion/cancellation messages and tool sounds at volume 50. Inherited base anchor/unanchor/blocked-wrench ops are removed to preserve the subtype override. Existing cable/glass, latejoin, admin and appearance behavior is unchanged. |

AIcore waits explicitly preserve legacy toolspeed and tool_skill_factor, with five fast-tool regression variants. The shared library fuel adapter resolves get_welder() for availability, reservation ownership and commit, matching the lit-welder requirement and supporting real transforming tools. This also fixes zero-cost wrapper commits after native dismantling; engine source is unchanged.


## Notices and asks (D3, H4)

Pinned by `code/modules/unit_tests/dq_notice_late_deleted_tests.dm` and `dq_asks_repeat_tests.dm`.

* **A late notice (published past the depth cap) is no longer dropped when its holder is deleted before the drain.** It is delivered to the holder's observers and legacy
  reactions as the holder's destroy transaction begins, with the holder in its deleting state; the holder's own hooks do not run (as for any notice from a dying holder). A
  notice for a holder that is already gone, or an observer deleted before the drain, is dropped and logged. The queue holds a handle and a notice with no target, so it never keeps
  a deleted datum alive.
* **Ban panel questions are asked by the op, not by re-running the href.** The same questions in the same order (temporary or permanent, how long, why, the IP ban, one
  confirmation per banned job), but: (1) the checks that used to run before the first question (a moderator without the right, a target who holds ban rights, a missing job
  master, a kick of someone with more rights, a ghost-only or client-only target, admin jumping disabled) are refusals of the op with a reason, so the panel says why and
  asks nothing; (2) a job ban of several jobs asks one reason for all of them, as before, and lifting asks once per banned job; (3) the legacy player note, the shuttle time edit and
  the thunderdome, prison, lobby, mob-transform, artillery, get-mob and send-mob confirmations read their answer from their step.
* An admin-authority call (`AUTH_ADMIN`, a forced op or a test) holds every ban right, as `req_rights()` already did.
* `topic_rerun_ask()`, `topic_ask()`, `ban_topic_ask()` and the topic re-run record are deleted and their names are hard-banned.
* **An op's claims are held while its questions are open.** Before, an open question held nothing (only a timed wait held hands and body), so `work_then_question` let other work
  run beside an open question. Now an op that claims hands or body (written, or derived from a wait on an item or tool binding) keeps them through its question: a player's
  other physical input stops the op, an AI's is refused as busy. Ops with no wait and no `claims()` derive no claim and are unchanged. The test that pinned the old behaviour is
  renamed `work_then_question_holds_hands_through_the_question`.
* `asks(answerer =)` and `starts()` returning a reason are additions (no existing op uses them).

## Look state pin slowdown (rewrite/pin-slowdown)

`dq_look_state_pin` over the whole directory could not finish: after the blob roots each closet type took minutes, while the same root run alone took seconds.

* **Cause.** A probe of a type that spills things when it dies (a blob core drops a chunk, a gun cabinet its guns) handed the spill to the test with `own_turf_contents()`, which only deletes it when the whole test ends. Every later probe was made among it. A closet takes every loose item on its floor in when it is made (about 1 ms an item, linear: measured 0.04 s for 50 items, 0.38 s for 400), so with 887 blob chunks on the floor each closet probe cost seconds and a type has up to 72 of them (a coffin took 106 s, a rifle cabinet 600 s). Nothing leaked in a registry: object counts, GLOB list sizes and the kernel lists stayed flat across the sweep; the growth was the litter on the one floor tile.
* **Fix.** The state pin drains the test floor after the made-look capture and after every probe (`dq_look_drain_turf()`), so every probe starts from an empty floor. Coffin went from 106 s to 0.8 s; the full directory now finishes in about 45 minutes. `dq_look_state_probe_leaves_floor_clear` pins it.
* **Rows changed:** `look_states/obj.structure.closet.secure_closet.guncabinet.txt`, the rifle cabinet's `opened=1/2` rows: `-overlay: ...:laser x3` becomes `-overlay: ...:projectile x2`. The old rows recorded the laser cabinet's spilled lasers that the rifle cabinet took in; a rifle cabinet holds two rifles (`starts_with`), which is what the new rows show.
* **Deleted:** the empty `look_states/mob.living.simple_mob.vore.swoopie.txt` and `...xenomorph.txt`: they name no type (the swoopie is `vore/aggressive/corrupthound/swoopie`, the xenomorph root no longer exists) and failed the pin as "names no type".
## Draw framework round 3: turfs (floors, walls, water) over the adjacency index (KD90)

A turf's draw reads its own tracked state and the masks the adjacency index keeps (`doc/rewrite/look.md` section 5, `code/game/turfs/turf_edges.dm`); no draw in these chains reads a neighbour or calls `update_icon()`.

* **`look_trees/turf.simulated.floor.txt`: the water sprite is on the tile once.** Every `water` row `overlay: <icon>:water_shallow:-32767 x2` (21 types: shallow, deep, pool, blood, indoors, hotspring, the digestive enzymes and nanite goo, underwater, the turfpack variants) is now `x1`. The old provider added the sprite with a raw `add_overlay()` on every draw (the init draw and the draw after init), so it piled up; the look draws it once and a redraw keeps one. (Test `dq_turf_edges/water_follows_neighbours` redraws the tile and counts it.)
* **`look_trees/turf.simulated.floor.txt`: seasonal grass overlay rows moved.** `/turf/simulated/floor/outdoors/grass/seasonal` gains `autumn-overlay2` and `.../notrees_nomobs_nosnow` has `autumn-overlay1` where it had `autumn-overlay6`. The flowers or leaves lying on a tile are rolled once at the end of `Initialize()` (`season_overlay`, tracked) instead of on every draw; the pin reseeds the RNG from the path, so the roll reads another number. Same distribution. The tile description follows the season in the draw (`identity(desc =)`). (Rolled first in `Initialize()` it shifted the tile's animal roll and spawned a red panda that leaked onto the pin tile and walked onto the snow and flock tiles; rolled last it does not.)
* **`look_trees/turf.simulated.wall.txt`: solid rock draws.** `/turf/simulated/wall/solidrock` and `.../mossyrockpoi` read `runtime: cannot read from list` (their provider indexed the connections list before the index had computed it); they now draw their sprite (`blank`), the rock connections (`rock0 x2`, `rock3`, `rock6`; `mossyrock*`) and a lip on each open side (`rock_side x3`; the lip is read from the tracked `open_mask`, not from the neighbours). A rock drawn before its neighbours exist reads the unconnected states instead of throwing.
* **Not blessed (order artefact):** `look_trees/turf.simulated.floor.txt` `floor/snow` and `floor/outdoors/snow` `snow_footprints` and `floor/flock` `floor-on`: a living mob leaked by an earlier type stood on the pin tile in this run and walked onto the snow and the flock floor (`Entered()`/`Crossed()` write the footprint and the lit sprite on both the old and the new code). The recorded rows (no footprints, `floor`) stay. Also not from this branch: the `electronic_assembly` `op_clash` row, the `blob/core` colour rows and the `handle_organ_mod_special` runtime (known, unrelated).
* **New pins, recorded on the base before the conversion:** `look_trees/turf.simulated.flesh.txt` and `turf.simulated.shuttle.txt` (the flesh wall is converted here; the shuttle walls and floors are the neighbours of the voidcraft draw that lost its `update_icon()` call). Both are unchanged after it. Water, lava and the underwater tiles are in the floor tree, fancy shuttle, bay, TGMC and Eris walls in the wall tree. The look-state pins cover objs and mobs, not turfs.
* **An opened wall draws its material's `fwall_open` sprite, and thermite shows.** `dungeon/wall.dm` declared a second `/turf/simulated/wall` provider after `wall_icon.dm`'s, so the live one drew `rockvault` for an opened wall and never drew the thermite coating. The duplicate is deleted (its `"thermite"` field watch was the boot-gate runtime): `thermite` is tracked and drawn. No pin row (a wall is made closed).
* **The edges follow the neighbours.** A floor's borders, corners, spilled edges and ceiling gap are recomputed by the index when a neighbour's flooring, its drawn state, a wall, space or open space beside it comes or goes (`dq_turf_edges/*`). Before, only another floor's draw told it (`CHANGE_NEIGHBOURS` of the floor kind), so a wall built or removed beside a carpet left its border stale until something else redrew it. Edges spilled onto a tile by a stronger neighbour were added with raw `add_overlay()` and piled up on each draw; they are drawn once now.
* **The wall thermite scorch (`wall_thermite`) lasts until the floor is covered or welded** (`scorch_state`, tracked). It used to last until the next redraw of the tile, which any neighbour change or damage caused.
* **A floor whose covering is torn off with no plating to show draws the bare deck** (`plating_exposed`: `base_icon`, `base_icon_state`) instead of whatever the last draw left. `make_plating()` no longer cuts the tile's overlays (the look owns them, and a cut that the look does not know of would leave the draw's cached key claiming overlays that are gone).
* **Decals are a tracked list that is replaced** (`set_decals()`), as are the snow footprints; `broken` and `burnt` are tracked and written through `set_broken()` / `set_burnt()`.
* **Engine:** the look builder shows `vis_contents` on a turf (an underwater tile shows one shared weather layer per sprite, `CACHED_KEY(underwater_visuals, ...)`, instead of making a new atom on each draw); `hooks_drain_changes()` skips a hook marked against a turf that was replaced since (a `ChangeTurf` leaves the old turf's reference pointing at the new turf, and the old type's `on_change` condition ran on it: `undefined proc /turf/space/material()`).
* **Renames, not dodges:** `set_flooring(newflooring, initializing)` is `install_flooring()` and the wall's 3-argument `set_material()` is `apply_materials()`, because `TRACKED(flooring)` and `TRACKED(material)` own the setter names.
* **Test harness:** `dq_look_capture_turf()` drains the `on_change` reactions (`stat_drain_point()`) before it flushes the looks, as a kernel tick does between a flooring being laid and the draw.

* **The generated TRACKED setter is null-aware** (`TRACKED_UNCHANGED()` in `code/__defines/capabilities.dm`, used by `TRACKED`, `TRACKED_BRIDGED` and `TRACKED_SCHEMA`). DM reads `null == 0`, `null == ""` and `null == FALSE` as true, so a write between null and one of them was dropped without publishing; it now publishes, and a repeat of the same value (null to null included) still does not. Source audit of tracked vars that default to null and have a `set_x(0|FALSE|"")` caller (each new publish is a real state change that readers should hear): `/area` `eject`, `fire`, `party`; `/obj/machinery/organ_printer` `printing`; `/obj/item/pipe_painter` `mode`; `/obj/item/clothing/accessory/badge/holo` `emagged`; `/mob` `blinded`, `transforming`; `/mob/living/carbon/human` `block_hud`; `/mob/living/simple_mob/vore/blaidd` `blaidd_invisibility`; `/mob/living/simple_mob/vore/bigdragon` `enraged`, `flames`; `/datum/computer_file/program/wordprocessor` `is_edited`; the telecomms consoles' `temp` ("" to null); and `/turf/simulated/floor` `broken`, `burnt`. The audit is by name and file, so a var declared in a parent type in another file is not covered.

### Blessed look_states rows (rewrite/draw-reagents)

Files re-recorded: pizzabox, condiment, drinks, appliance, beehive, bunsen_burner, chem_master, chemical_synthesizer, gibber, microwave, hydroponics, smartfridge.

| Class | Cause |
|---|---|
| Rows `runtime: PURITY ... was written/granted inside an output` and `Division by zero` removed | The base was recorded after a `volume=0` probe divided by zero in a drawn type; the probe's caught exception left the output-evaluation context up, so every later probe of other types in the run reported a purity runtime. The carton draw now guards a zero volume; the rows are replaced by the real look changes. |
| New `open=`, `closed=`, `broken=`, `frozen=`, `busy=`, `heating=`, `bee_count=` rows | These vars now redraw the look (tracked state read by `draw`), which the polluted base could not show. |
| yeoldoven keeps its own `yeoldoven*` states | Oven draws `[state_prefix]open` etc.; the prefix is a var of the type. |
| glass2 claraflask `volume=0` | Same Division by zero, reported by the refresh catch spelling. Still a draw bug at zero volume, left as pinned. |
| Rel list add/remove | `rel_add`/`rel_remove` on a list view now mark outputs that read the var (through `own_field_changed()`, the one path every relation write takes; the second mark-if-read proc is gone), so a beehive's frames and a pizza box's stack redraw. |

### Blessed rows, second pass (rewrite/draw-reagents)

| Class | Files | Cause |
|---|---|---|
| Zero-volume divide removed | look_states glass, drinks (claraflask) | Glass, vial, blood pack and glass2 draws divided by `volume`; a zero volume now draws as an empty level instead of throwing. The `volume=0` rows change from `runtime: Division by zero` to the real fill rows. |
| Pizza box tag at creation | look_trees pizzabox | The tag overlay of a prefilled box is drawn at creation (the draw reads `boxtag`); the old update ran before the tag was set. |
| Oven at creation | look_trees appliance | An unpowered oven draws shut and off (`ovenclosed_off`) from its tracked `open` and `has_condition()`; the old base recorded the open sprite and `yeoldoven` an extra `light_off` overlay left by the earlier runtime. |

Engine: an output that throws (draw, should_run, hidden_verbs, derive_<var>, push_to_rust, window data) now restores the evaluation depth and logs `OUTPUT RUNTIME: type.output` (`output_failed()` in derived.dm), so one runtime no longer reports every later write as made inside an output. Test: `dq_draw_reagents_a_throwing_draw_leaves_the_next_output_working`.

Rows of other lanes left alone: look_states `mob.living.simple_mob.vore.morph` (4 rows) and look_trees `obj.structure.blob` (386 rows).

## Draw pockets: refinery, computers, electronics, HUD, abilities, AI, pAI (rewrite/draw-pockets)

* **Converted to `draw(look)` over tracked state:** the refinery (vat, mixer, pump, filter, pump relay, chemical canister; they read the holder's tracked `total_volume`/`tint` through `look.watch(reagents)`, and neighbours through `look.neighbour()`; `update_neighbours()` is deleted), modular computers (program, bsod, screensaver), integrated electronics (assemblies, clothing, implant, device: `opened` is tracked), organ icon, the shield generator family, holomap, overmap ships (`speed` is tracked and `adjust_speed()` assigns a new list), admin verbs, HUD (hands, abilities), AI, pAI, vore panel/belly leftovers, and the mob leftovers. Folders that joined `look_converted` are listed in `tools/ci/lint_scopes.toml`.
* **Engine fix:** a draw that read other entities (`look.watch()`) but drew nothing yet dropped its subscription (`refresh_look()` returned before syncing the watch), so a hand HUD, an empty vat or an empty tank never heard the state that fills them. The untouched path now syncs the watch too. Covered by `dq_draw_pocket_hand_hud_follows_handcuffs`. New builder part: `look.set_invisibility()` (the ability master hides while it holds no abilities; a draw that stops naming it gets the type default back).
* **Hand HUD:** the handcuff overlay is drawn from the mob's equipped slot (`look.watch(mob)`); `update_hud_handcuffed()` is deleted.
* **Left unconverted, and why:** blood and gore decals (`B.update_icon()` in organs, admin secrets, human, observer, drippy: legacy decal providers, draw-structures), the newscaster (machinery), the farmbot's hydroponics tray (draw-reagents), the protean rig (item), `nano_printer` paper bundle (legacy provider in paperwork), and the size gun and mouse ray, custom items and crackers (energy guns and items: after draw-items batch 18). `modular_computers/hardware/`, `vore/resizing/`, `vore/fluffstuff/`, `body/organs/` (except `organ_icon.dm`), `admin/topic/`, `admin/verbs/secrets.dm` and the rest of `mob/` stay out of `look_converted`.
* **Belly overlay preference of a robot:** a panel edit publishes `belly_change` on the host, which recomputes the robot's tracked `vore_light_states`; the preference itself is read only there, so it is not tracked.
* **Pins:** `dq_look_tree_pin` shows only the eight `obj/structure/blob/core` colour rows (seeded random, the same on the base); no row was blessed. `dq_look_state_pin` was not run here (the merge batch runs it).

## Look pin sweep (rewrite/pin-speed)

The two look pins are one sweep (`code/modules/unit_tests/dq_look_sweep.dm`, doc/rewrite/agent_workflow.md section 9): each type is made once, from a block emptied and
restored to the template's state, with the kernel's zero-delay work settled on a frozen clock; the probes run on that instance and the look must come back after each. The
look-state probes are narrowed to the vars `analyze look-keys` finds a draw reading, and a run probes only types whose key changed since `snapshots/look_keys.txt`.

* **Re-blessed rows (one unsharded, full, unnarrowed `--bless` run; everything else came out byte-identical to the recorded files):**
  * *Leftovers from earlier types, removed.* The old tree pin never emptied the tile between types, so a fridge or cabinet took in what the type before it spilled:
    `look_trees/obj.machinery.smartfridge.txt`, nine `survival_pod` types, the fill overlay `-3` / `boxes3` / `chem3` becomes `-0` (an empty fridge);
    `look_trees/obj.structure.closet.secure_closet.guncabinet.txt`, `guncabinet/rifle`, `laser x2 + projectile` becomes `projectile x2` (its own two rifles).
  * *Blob cores.* The snapshot subject is placed without an overmind and given one of a fixed type (`/datum/blob_type/classic` unless the core names its own,
    `dq_snapshot_allocate()`), so the colour no longer follows what the RNG had drawn: `look_trees/obj.structure.blob.txt`, `core` and `core/random_medium`
    `#8ba6e9` becomes `#aaff00`, `core/random_hard` `#aaaabb` becomes `#aaff00` (`random_easy` already was). A random core's pin is now the pin of the fixed type.
  * *Self-ending mobs.* `morph/dominated_prey` and `overmap` decide in `after_init` (the fix recorded in b27c997ee1, which master reverted along with the rest of its
    merge; only these two files are taken from it) to end themselves when made without prey / a marker, so init no longer writes owned objects into a dying mob.
    `look_trees/mob.living.simple_mob.txt` (both) `runtime: OWN: refused ...` becomes `deleted itself on creation`; `look_states/mob.living.simple_mob.vore.morph.txt` loses
    its `runtime: OWN: refused _own_put(hud_list)` row (the probe makes nothing).
* **Still order dependent, NOT blessed:** `look_trees/turf.simulated.shuttle.txt`, `shuttle/plating/carry` and `shuttle/plating/airless/carry` underlay
  (`tiles_vr.dmi:steel:-45` recorded; a path-order sweep gives `space.dmi:white:-82`, a shuffled one gives either). The settle step did not remove it. Likely cause (not proven): what the floor "landed on" is read from the tile it replaces,
  and the sweep's spot is restored by `ChangeTurf(old_type)`, which keeps state of the turf before it. Proposed fix: make each
  turf probe on a fresh tile of the template's floor type (`ChangeTurf` from a canonical turf, then drop `landed_holder`), then bless the one rule.
* **Harness:** the bless writes CRLF and a lone newline for an empty row set; the committed files are LF and empty files stay empty, so those were normalised back.

## Draw rest: the last legacy look providers (rewrite/draw-rest)

Cash and casino chips, paper family and stamps, bundles, mail, telecube, device assemblies and holder, transfer valve, glass jar, fishing and butterfly nets,
card hands, slot machines, windows (base, bay, eris, fancy shuttle, survival pod), windoor assembly, holo sword, pump, reagent distillery, anomaly harvester,
recycling panels, space vines and the maintenance vendor glow now draw through `draw(look)`.

* **Pin classes blessed (`look_trees/`):**
  * *Drawn at creation.* A legacy provider ran on the first `update_icon()`, so a thing nobody asked to redraw kept its mapped look; the first refresh now draws every atom.
    `obj.item.spacecash` / `spacecasinocash` / `spacecasinocash_fake` roots (a pile of worth 0 shows one note), `obj.machinery.anomaly_harvester` (`harvester_off`),
    the distillery and its industrial type (`distiller-input` / `-output` / `-connector` over the mapped state), `obj.item.mail` (`postmark`, `stamp_*`).
  * *Overlay icon is explicit.* The new overlays name their icon (`telecube.dmi:cube-ready`, `bureaucracy.dmi:postmark`) where a legacy `image("state")` had none. Same sprite.
  * *Preset text shows the written sheet.* 52 papers with `info` set by their type (`paper/Cloning`, `fluff/love_letter`, `carbon/cursedform`, `alien/source`, ...) draw
    `paper_words` (`alienpaper_words`, `paper_stack_words`) at creation; the legacy pin recorded the blank sheet because nothing redrew them.
  * *Full-tile bay and eris windows drop the editor preview.* They draw a blank base state with their joins (`bay_window.dmi::`) where the pin recorded `preview_glass` (the
    legacy `after_init` blanking never ran in the frozen sweep). In the live game the result is the same.
  * *An empty hand.* A `/obj/item/hand` made with no cards ends itself (its `hand_empty` effect) where the legacy pin kept the mapped `empty` state.
* **Cash:** `worth` is tracked; every `.worth -=` / `=` in the registers, ATM, casino machines, arcade and trader goes through `set_worth()`, so a pile is renamed and redrawn
  whenever a machine takes from it (before, the name went stale until the next `update_icon()`). `set_worth()` and `adjust_worth()` lose their `update` argument. Scattered notes use
  the shared seeded layouts (`note_seed`, rolled once); the casino chips no longer re-roll their scatter on every redraw. The charge card keeps its own look.
* **Paper:** stamps are `stamp_marks` (state, x, y) replacing `ico`, `offset_x`, `offset_y` and the raw stamp overlays; the photocopier writes grey marks. `crumpled` is tracked and
  `writable`, the sticky note and the pen check it instead of reading `icon_state == "scrap"`. The words (`info`) are a plain var every printer writes, so the writes after creation in
  `paper.dm` and the admin fax ask `changed(src)`. The clipboard draws the top sheet's stamps (it passed the overlay list as one entry). A bundle with no pages draws nothing.
* **Assemblies:** `attached_overlays` is gone; each part answers `holder_layers()` / `holder_state()` and the holder draws them (watching both parts). A proximity sensor primes its grenade
  from `on_change(scanning)`. A mousetrap's `armed` is tracked.
* **Transfer valve:** the second tank's underlay is shifted with `pixel_x = -13` (it was an `/icon` shifted WEST 13).
* **Jar and nets:** a jar's coin heap is placed by index, not re-rolled; a tank scales its animal by a matrix (no longer `adjust_scale()` on the animal and back); the duplicate glow image is
  dropped (it was the same image). A net names itself for what it holds; `holds_creature()` replaces reading its own `icon_state` for the weight.
* **Hands:** a lone card's jitter is rolled once (`jitter_x`, `jitter_y`); `concealed` and `direction` are tracked.
* **Slot machines:** `slot_phase` ("rolling", "winning", or none) replaces writing `icon_state`; `ispowered` and `isbroken` are tracked.
* **Windows:** the join pieces come from the smoothing index (`connections`) for every window, as for bay and eris, where the base window looked at its anchored same-glass neighbours itself.
  A slim window's lean sign is rolled once (`tilt_sign`); its tilt runs as a look effect. Silicate is a tracked `silicate` and a white sheen layer (`updateSilicate()` and
  `update_nearby_icons()` are gone). `look_overlay_image()` gains `blend_mode` for the bay window's multiplied damage layer.
* **Space vines:** growth is a function of health, the growth threshold and the fringe cap computed afresh (`plant_growth_cap()`), where `refresh_icon()` lowered `max_growth` further on every call.
  The wall shift is rolled once (`wall_shift`).
* **Pump:** its overlays are named from the type's own state (`initial(icon_state)`), where the legacy provider named them from the state the last redraw left (`pump-running-tank`).
* **Not done in this lane:** `rig.dm`, `protean_rig.dm`, `nailpolish.dm`, `mecha.dm` and the mecha appearance files, `mine_turfs.dm` (they still use `task_start` or `datum/interaction`); the maint
  recycler (a vis object), the remote scene tool and voodoo doll (they read another mob's whole look); `code/game/machinery` and `code/modules/power`.
* **Framework gap, not fixed here:** a thing put into another with a plain `forceMove()` never reaches the containment ledger (`slot_contents()` / `look.things_in()` read
  `L.slots`, filled only by `move_into()` / `own_bring_in()`, `code/engine/refs/containment/api.dm:235`, `ledger.dm:591`), so a draw cannot hear a creature scooped into a net or jar. The net
  asks `changed(src)` at its entry and exit sites and the jar redraws through its tracked `contains`; both are temporary until `forceMove()` into a holder registers in the default slot.
* **Space vine with a growth threshold of 0** (`look_states/obj.effect.plant.txt`, `plant` and `plant/single`, `growth_threshold=0`): the draw no longer divides by it; it shows the full
  stage (`mushroom7-3`, `-0` lost) where the legacy provider raised `Division by zero`. The three rows are written by hand to the rows the sweep produced (`growth_threshold=1` is the same).
* **Pump state pin** (`look_states/obj.machinery.pump.txt`, `on=1` and `on=2`): the running pump's rows change from the `pump-running-tank` / `pump-running-glass` layers (named from the state the previous redraw left) to the
  `pump` -> `pump-running` base state, with the tank and glass layers named from the type's own state and so unchanged. Harness: the bless also wrote a lone newline into empty files (six `look_states/` files); restored.

## Draw final: rig, mecha, mineral turfs, paper and the last `changed(src)` calls (rewrite/draw-final)

The hardsuit and the protean rig, nail polish, the mecha and its equipment, mineral turfs, the maintenance recycler, pill bottles, capture crystals, paper `info`, the net and the jar,
and the small items below draw from tracked state, slots and relations. Left as they were, with the reason: the remote scene tool and voodoo doll (the doll composes another mob's
whole look and would have to hear every change of that mob), the compass holder, the omni devices' port icons, the quantum pad (reads `power_region`), and `code/game/machinery` and
`code/modules/power` (the machinery lane).

* **Hardsuit.** The `mob_icon` cache is gone: `get_worn_icon_file()` answers the species' sheet, else the rig's `default_mob_icon` (null for a protean rig: no forced sprite, as the
  empty icon it built before). The rig itself draws nothing of its own. The pieces' sealed or retracted state is still their own `icon_state`, so the wearer redraws the shoes, gloves,
  head, suit and back slots through `refresh_worn_pieces()` where the old redraw did (reset, cut, a finished seal, putting it on). The chestpiece of a deployed suit draws the overlay of each
  installed module (`master_rig`, `look.watch()`); a module's `suit_overlay` is tracked and `refresh_suit_overlay()` writes it through `set_suit_overlay()`. Installing or removing a module
  redraws the chest through the relation; `rig_attackby.dm` and the protean install and removal no longer ask.
* **Nail polish.** `open` and `colour` are tracked (the remover's `open` too: it was drawn from a plain var); the colour and top layers are underlays of the look.
* **Mecha.** `initial_icon` (a paint kit sets it), `show_pilot`, `face_state` and `pilot_lift` are tracked; the base state is `mecha_base_state()` (the type's own state when `initial_icon` is
  empty; it was written by the first draw). The pilot is read from the pilot slot: a mech that shows its pilot watches it, any other only asks whether the slot is occupied. The pilot picture and
  the face are layers of the look; each piece of equipment adds its own through `equip_look()`: the repair droid shows `repair_droid_a` while it works (it showed the idle layer until the next
  redraw), the shield drone and the crisis drone (`enabled` is tracked) are drawn from their state. The gunpod's stripes and the shuttle craft's hull paint are tracked colours. The raw
  `add_overlay()`/`cut_overlay()` calls of equipment attach, detach and destroy are gone.
* **Mineral turfs.** Rock and sand draw from `rock_edges` (the adjacency index: open sides, sides facing space, sides facing rock), `sand_dug`, `overlay_detail`, the two archaeology
  overlays and `mineral_static`. Ore no longer spreads each time the rock is redrawn (the old provider called `MineralSpread()` from the draw: once at creation through `sim_after_init()`
  and once from each spread target stay); the archaeology and excavation marks are drawn once, not once per side. The cave carver, the expedition template and the rogueminer zone
  no longer sweep their turfs for `update_icon()`: density, the masks and the tracked marks redraw each turf.
* **Maintenance recycler.** The item inside is a layer of the machine's look (`look.watch()`), shrunk and offset between the underlay and the machine; the `item_overlay` object and the
  underlay written at `Initialize()` are gone. The hatch and the screen stay objects of their own (they flick).
* **Pill bottle:** `wrapper_color` is tracked and the wrapper is drawn from it (a chem master recolouring it redrew nothing; it cut the overlays).
* **Capture crystal:** the recharge is a tracked `recharging` set when the cooldown starts and cleared by a timer when it ends (the timer called `update_icon()`, a no-op on a drawn type);
  `spawn_mob_type` is tracked; the bound creature is watched and its place read from `loc`.
* **Paper.** `info` is tracked and every writer goes through `set_info()` (the tracked lint listed 219 sites: printers, forms, the ATM, accounts, the noticeboard, the photocopier ...). The sites in
  `code/game/machinery` (card, medical, security, skills, supply, message, adv_med, pandemic, bomb_tester, guestpass, requests console, telecrystal storage) are the same one-line rewrite;
  they are in that lane's files only because the lint is hard. The five `changed(src)` calls of `paper.dm` and the admin fax are gone.
* **Net and jar** declare a slot (`CONTAINER_SLOT_NET`, `CONTAINER_SLOT_JAR`) and draw what it holds through `look.things_in()`; the five `changed(src)` calls of the net are gone.
* **Tracked, with the writers behind setters, and the `changed(src)` after them gone:** the grille's `destroyed`, a snow turf's footprints (the same copy-on-write list as the floor snow; the footprint
  overlay now names its icon, state and direction: the old `image(icon, "footprint1", dir)` passed the state as the location), a vehicle's `on`, `open` and `paint_color`, the panic button's `glass`,
  the ready button's `ready`, the sticky pad's `papers`, the NIF's `stat`, the old two-handed weapon's `wielded`, the spaceflare's `active`, the mech fabricator's `being_built`, the server's `working`,
  the refinery reactor's `toggle_mode`, a sorting junction's `panel_open`, a railing's `icon_modifier` (the nanite goop wrote the state by hand and asked `update_icon()`), the algae farm's
  readout (its `ALLOW(derived_reads)` is gone), a stored item's `amount` (a smartfridge draws its fill from the records it watches).
* **Redundant calls removed:** a dispatched call (an op, a timer, a periodic step) re-runs the draws of what it touched, so the `changed(src)` after one never did anything; those after
  `rel_set()` / `rel_add()` / `move_into()` of something the draw reads were redundant too. They go from the distillery, the grinder, the walkpod, the police tape, the multitool, the DNA console,
  the unary and binary pipe bases, the vent scrubber and the smartfridge; the pump's target-reached hook, the tether host's and handheld's `update_icon()` calls and the defib kit's `paddles in contents`
  (now `look.watch(paddles)` and `paddles.loc == src`) are part of it. `update_icon()` calls on types that are all drawn were deleted (`look_sweep dead` with the unit-test probe types ignored, and by hand:
  the electrovore and turf-transparency behaviours, turf changing, the inducer, blood reveal, stairs, the cargo and vehicle cells, syringes, pill bottles, casino collars, space vines, the turbolift panel).
* **Look ratchet:** `look_converted` now holds 230 more folders (every folder of `code/game`, `code/modules`, `code/datums` and `code/library` that has no `update_icon()` call and no legacy
  appearance declaration left, machinery and power excepted).
* **Pins blessed (`look_trees/`):** one row, by hand: `obj.mecha.combat.hades` `state: hades-open` becomes `hades_broken-open`. The type sets `initial_icon = "hades_broken"`, `Initialize()` writes
  `icon_state += "-open"` and the legacy provider never ran in the frozen sweep (a mech was drawn only when something asked); every mech now draws at creation from `mecha_base_state()`, and
  the other mechs' rows are the same state either way. No `look_states` row moved. Nail polish, the rock and the sand keep their rows (the sand's detail overlay draws from its decals state:
  the legacy provider added the decals *file* as an overlay, which drew nothing; a tile that rolled a detail now shows it).
* **Found by the new tests (no change to the framework, a note for the next conversion):** a `null` argument takes the proc's default in DM, so `look.overlay("state", maybe_null)` always draws:
  the sand's dug mark read `sand_dug` (null until dug) and drew on every sand tile until it was written `!!sand_dug`. The distillery's input and output layers
  (`look.overlay("...-input", InputBeaker)`) have that shape and still draw with no beaker (the pin rows record it; not changed here). A state named `color` beside a named `color =` loses its state when it
  is passed positionally (`look.md`; `dq_draw_final_overlay_image_keeps_a_state_named_color`).
* **Removed behaviour:** `EO.update_icon()` in the NIF's medichines was tested for a return value the base proc never gave, so `UpdateDamageIcon()` never ran; both lines are gone.

## Timed actions wave 9 (rewrite/timed)

* **Lockpick on a simple door.** The legacy pick worked from the lockpick's `afterattack()` after the door's item handler ran. The door's handler hit the door with the pick first (`breakable`); it now returns `OP_PASS` for a lockpick so the pick's own `pick` op works the lock and the door is no longer struck.
* **Sink items.** The sink's item and hand washes refuse a second wash through `claims()` ("in use") instead of the sink's own "Someone's already washing here." text.

## Timed actions round 2: menu pins (rewrite/timed)

Re-blessed rows of `obj.item.ghost_trap`, `obj.item.paicard`, `obj.item.tank` (and `.phoron`, `.jetpack`), `obj.item.toy.minigibber`. Nothing is lost from the base item ops: every key list still holds `pick_up_item`, `move_to_top` and `toggle_digestable`. The classes:
* **A catch-all item or hand op narrowed.** The minigibber's `feed` took any held item and declined all but figures; it is now `item(/obj/item/toy/figure)` and `item(/obj/item/toy/character)` with a `when()`, so a screwdriver or any other item shows `nothing` instead of `Feed`. The ghost trap's `hand` op ("Use", it declined for every click that was not a release or a deactivation) is gone; a bare-hand click on a trap now reads `Pick up`, the base item's op the old op declined to. The tank's `tank_item` still takes every item; `attach_assembly` is new for an assembly holder (its refusal "You need to wire the device up first" is the op's `because`).
* **New ops.** `deploy`, `deactivate`, `free_occupant` (ghost trap), `attach_assembly` (tank), `open_panel` and the seven `install_*` ops (pAI card), with `Install part` rows for each part type and its refusal when the socket is filled.

## Re-land of leftovers and proj-hooks (rewrite/reland)

* **Conversion pins, emag key rename** (`snapshots/pins/mob.living.silicon.robot.txt`, `mob.living.silicon.robot.platform.txt`; 33 rows). The leftovers lane's emag conversion replaced the single `emag`
  interaction key with the ops `emag.subvert` and `emag.use`. Consequences, all one change: the `keys:` row changes; the "Emag" menu rows (the greyed "needs a cryptographic sequencer" entries for each
  hand, and the sequencer's own "Emag" entry) are gone because the ops are not offered in the menu; a human clicking with a sequencer on the platform reads `Click: Use` where it read
  `nothing` / `Click: Platform item`.
* **Hit pins** (`snapshots/hit_pins/`, 174 rows, seven types: energy_field, plant, ammo_magazine.smart, assembly.mousetrap, gun.energy, gun.energy.chameleon, modular_computer). Every class has one cause or the next:
  * `refresh_queued: 131071 -> 0` and `refresh_bits: N -> 0`: a thing made for the pin still has its first refresh pending when the trigger runs; the pin's drain after the hit flushes it (engine refresh, `code/engine/change/refresh.dm`),
    so every trigger of those types now shows the flush, and the former `nothing` rows (emag, emp 2, explosion 3, projectile, thrown) became these rows.
  * `icon_state`, `light_*`, `color`, `disguise_state` rows on `energy_field` (`shield` -> `shield_broken`), `plant` (`bush4-1` -> `mushroom7-0`), `gun.energy` (`energy` -> `energy50/75/100`) and `gun.energy.chameleon`
    (`null` -> `deagle`): the same first flush draws the type's look for the first time; the old rows were recorded after a draw that had already landed (`energy100` -> `energy50`), now the base is the undrawn `energy`.
    The values drawn are the type's initial look, unchanged.
  * `plant` emag: `periodic_pipe: null -> /datum/cadence/plants` is now `growing: 0 -> 1` and `om_rec` (the growth `every()` is keyed on the tracked `growing`, the periodic pipe being retired).
  * Nothing in these rows is a change in what a hit does. `dq_hit_pin` leaves `tools/ci/known_failures.txt`.
* **Projectile hit action.** A projectile's hit action (the `/datum/act/hit/projectile` hooks) now starts in `bullet_act()` before the round's effects (stun, embed, autopsy, reagents), so an `instead()` hook
  stops all of them, a zero-damage round (a taser dart) reaches the hook, and the hook runs once per hit (the damage packet reuses the open action: `projectile_hit_begin()` / `projectile_hit_end()`).

## Loot piles: the search op (rewrite/loot, Option B of `proposals/loot_and_map_resolvers.md`)

The search of a loot pile or trash pile is `op("search", hand(), ..., needs(req_loot_unsearched(), req_loot_not_picked_clean()), ..., wait(...), loot_rolls())`
(`code/library/loot/loot_search.dm`); the roll is the same draw as before (`loot_search_roll()`, the proc `loot_pile_search()` became), with the same seeds, tiers and
messages. The search pin's rows are byte-identical (its driver runs the requirement's refusal and then the roll); the classes below are what the op path changes.

* **The two refusals come first.** "The X has been picked clean." and "You can't find anything else vaguely useful in the X.  Another set of eyes might, however." were said
  after the 4 to 6 second wait; they are requirements now, refused at the click (nothing is spent, no wait), and the menu greys the search out with the same reason.
* **A searcher who already searched cannot flush out a trash pile's hider.** The hider's 50 percent chance to leap out used to run before the pile's refusals; it is the
  effect's `unless = PROC_REF(hider_leaps_out)` now, after the requirements.
* **State.** The per-pile `searchedby` lists (an `ALLOW(instance_list)` each) and the global `GLOB.loot_times_searched` (by `REF()` text, never freed) are two keyed
  stats on the pile: `STAT_LOOT_SEARCHED` (searcher key -> marked) and `STAT_LOOT_FOUND` (key -> searches that yielded something; the sum is what depletion counts). They go
  with the pile. A searcher without a ckey (a test mob, an NPC) is never marked, so is never refused as "already searched"; its yields count under `(no key)`.

## Interactions to ops (rewrite/interactions)

Every site that declared `DECLARE_INTERACTIONS`, `EXTEND_INTERACTIONS` or a `/datum/interaction` subtype in production code is an op now. The forms are deleted and hard-banned
(`[lint.legacy_forms.lists] banned` in `tools/ci/lint_scopes.toml`): `DECLARE_INTERACTIONS`, `EXTEND_INTERACTIONS`, every `INTERACT_*` spec, `get_interactions()` /
`declare_interactions()`, `dq_interaction_from_spec()`, `run_interaction_entry()`, `DECLARE_EMAG*`, `/datum/interaction/{construction,ability,emag,generic}`, `/datum/construction_graph`,
`grant_ability()` / `revoke_ability()`. What is still there is the `/datum/interaction` base and the `cap_op()` / `cap_slot()` bridge, because `/obj/machinery/computer/med_data` (Codex's
`code/game/machinery`) still declares its ID slot and records window through `capabilities()`.

* **Living mobs:** the eight defaults (help, shove, take hold, punch with a hand; use on, shove with, hold with, hit with an item) are `touch_*` / `hit_*` ops in `CAPABILITIES(/mob/living)` at
  `OP_PRIORITY_DEFAULT`. A swing's click parameters and modifier (a cleave's 0.5, an off-hand swing) are set around the whole swing in `resolve_attackby()`, not inside `attackby()`.
  `attackby()` is the gate (`attackby_stopped()`) and `attack_hand()` is `hand_gate()`: code that calls `M.attackby(W, user)` directly no longer reaches the hit; use `item_used_on(W, user)`
  (the holder's forward to the creatures inside, the cyborg's radio forwards).
* **Cyborgs:** crowbar, welder, wirecutter / multitool, screwdriver and wrench on a chassis, the item and touch handlers and the AI's shell deploy are `robot_interactions()` ops (the `*_act`
  overrides are deleted). The crowbar and welder answer outside harm intent only, as before. The wrench takes `wait(2 SECONDS)` with a start message. The old "Block drag" entry is gone: it
  swallowed a drag nothing else took, and `MouseDrop_T` now does nothing by default.
* **Gripper:** the pocket ring is the `pocket_menu` op (`asks()` radial, `claims(CLAIM_TARGET)`); closing it without a choice uses the wrapped item (`on_interrupt`), as before. The gripper is
  "in use" while the op holds it (`op_claimed()`), so the `in_radial_menu` var is gone and a second click gets the engine's "claimed" refusal. An answer dropped for being out of reach also
  falls through to the wrapped item (before: nothing).
* **Abilities (robot, drone, platform, shadekin, attack variants):** each ability is an op with `menu(button =, bind =)` in a capability, granted with `grant()`. The keybind ids and `.use-ability`
  keys are kept (`ability_<old id>`; the op key is `<capability>.<op>`). Targeted abilities (regenerate other, robot nom, robot mount) ask for a choice among adjacent candidates instead of
  taking the hovered target. Dark maw and dark tunnelling are `wait()` channels. Shadekin energy is a requirement plus a spend in the effect (no `RES_DARK_ENERGY` adapter reads the shadekin
  state yet); the phase shift's watcher cost is recomputed in the effect, not cached in a mob var. Disarm and Grab on a living target are ops (`attack_variants.disarm` / `.grab`), not ranked by combat mode.
* **Construction:** vehicle and bot assemblies and the mecha chassis are `construction()` ladders. Wall, floor, window, girder and mech-maintenance steps are ops with `when()` conditions on
  their existing state vars (`construction_stage`, `anchored`, `state`, ...), not ladders: other code writes those vars, and a ladder would be a second copy of the stage. Tool sounds, volumes
  and waits follow the tool profile, not the old per-edge values (wall cut by an energy blade or pickaxe scales by the tool speed; the floor plating cut is now scaled). A chassis undo
  refunds exactly what the step took in (the micro mechs' steel and plasteel refunds become the 5 that went in). The old "Next: ..." step lines in examine and menus are gone.
* **Emag:** the legacy `DECLARE_EMAG` path had no users left; `emag_target()` runs the target's `emag.subvert` op only, and the card's overrides in `cards.dm` are deleted.
* **Replicator, sticky notes, slimes, holders:** insert is an op with a `req()` that keeps `can_insert()`'s reason; a sticky note's pick-up extends the item's `pick_up_item` op; a xenobio slime's
  wrestle-off is an op that only answers while it eats someone; the holder's item op passes the input on (`passes()`), as the old handler did.
* **Conditions of the state-machine ops (wall, floor, window, girder, mech, wreckage, secbot arm and leg, slime, cyborg shell and dents, gripper, replicator):** they read plain vars
  (`state`, `construction_stage`, `salvage_num`, `loc`, `flooring.flags`...) and are wrapped in `read_once()`: they are asked when the click is made and not re-asked while the op waits.
  An op with a `wait()` whose state changes underneath it (a second person finishing the same step) is no longer cancelled by that change; it commits on its own check. Making those vars
  `TRACKED` is the follow-up that gives them the re-check back; it needs every writer behind the generated setters.
* **Op order:** ops of one type that answer the same tool in different states (mech maintenance, window, girder, wall) are ordered by tier (`OP_PRIORITY_PART - n`, `OP_PRIORITY_NORMAL - n`) instead of
  `priority(above(...))`, which the `op_order` ceiling forbids adding. Their `when()` conditions are disjoint, so the tiers change no click.
* **Questions of abilities:** the robot name, drone mail tag and drone shell are `asks()` steps now. A cancel does what the old cancel-answer did through `on_interrupt()` (the default name, a cleared
  tag); a cancel at the drone's eye question applies the shell with what was answered so far (it used to go on to the plating question). The megaphone's shout and settings are `asks()`; the
  robot recolour opens its window through `asks()` and applies in place.
* **Replicator insert:** the requirement is `canremove` only (what is in a hand needs no accessibility check); the "something is in the way" warning of `canUnEquip()` is gone from the menu.
* **Chassis pictures:** the mecha chassis shows the "+o" overlay of each part from its tracked `parts_mask` (`draw()`), and a secbot assembly shows the hole, eye and arm of the stages built
  (`built()`); the raw `add_overlay()` writes are gone.
* **Emag:** a human's sabotage of a robotic limb and a cyborg's cover, interface and operator-seat emag are the `emag()` capability (repeatable, unpowered). The card spends one use on every
  committed try (a failed hack, assigning the operator), a try that did nothing (cover already open, panel exposed) declines and the card goes on as an ordinary item, and the holder's
  `EMAG_EMAGGED` key is set. The cardless `emag_target()` reaches the same effect through the `emag.subvert` op.
* **Clicks that skip the inbox:** the legacy entry procs (`attack_hand`, `attackby`, `attack_self`, `click_alt`, `MouseDrop_T`) no longer run ops; a player's click reaches them in the inbox
  (`input_resolve_click()`). A click that reaches the router another way (`route_click()`: an AI hotkey, a card machine, a test) now resolves the ops of the target, the held item and the
  actor first, as the inbox does, and a tool's own act or an item's plain use called by code (`try_interaction()`) falls back to the same resolution (`try_engine()`), narrowed to the tool
  quality it asked for. `GLOB.op_click_resolved` keeps a click from resolving twice. A right click is a gesture only for that fallback (the secondary use of a tool).
* **Empty-hand ops:** the hand ops that were `EMPTY_HAND` / `INTERACT_HAND` entries answer an empty hand only again (`when(req_empty_hand())`): the living touch defaults, the cyborg's pet, tap,
  hold and punch, the desk bell, the slime wrestle-off and a chassis giving up its cell. An item in hand reaches the item ops instead.
* **Mecha ladders:** a welder step of the chassis ladder burns no fuel again (`costs(RES_FUEL, 0)`, the old `remove_fuel(0)`). Where the tool that undoes a step also builds the next, a click builds;
  the way back is the menu entry `construction.undo:<stage>`.
* **Cyborg tools in harm intent:** the crowbar and welder acts answer `NONE` (not `SKIP_TO_ATTACK`) when no op takes them; the swing follows all the same.
* **Pins blessed with this conversion (`dq_conversion_pin`, `dq_hit_pin`, the i7 snapshots):** by class, none of them a click that stopped answering.
  - A holder's abilities (`when(req_self())`) are in its own menu only. The legacy pins listed every ability on every living mob as "(refused: you don't have that ability)".
  - The eight living defaults and the attack variants are listed with their label for every stance (`Help`, `Shove`, `Take hold`, `Punch`, `Use on`, `Shove with`, `Hold with`, `Hit`) and
    no longer carry "(refused: combat mode is off)" / "(refused: hold Grab)": a stance narrows a click, not a menu pick. A plain click still picks by stance (`click:` rows read `Click: Help`
    where the legacy pins read `nothing`, because the defaults were not visible to the resolver).
  - A tool or item op is listed only for a held item that fits its input; the rows "(refused: needs a welder)" / "(refused: needs a Ripley Torso)" are gone.
  - Construction ladders, ability, mecha, girder, window, floor, wall, cyborg and replicator rows carry the op labels (`Build frame one leg`, `Cut through the plating`, `Insert`) in place of
    the legacy edge names; the `keys:` rows list op keys, not interaction ids.
  - The hit pin's rows are what current `origin/master` records already (its recorded rows were stale: `emag` on an energy field, plants, chameleon guns); the branch adds only the
    `refresh_queued` rows of `mecha_parts/component` and `mecha_tracking`, which the chassis `draw()` brings.
  - The i7 snapshots record the legacy resolver's ids and blocked reasons: the construction edges, the silicon equip-module spec and the disposal ids are ops now.
  - The look state pin gains the cyborg `shell` rows (`shell=1`/`2` drops the eyes, `shell=0` brings them back; `robot_look.dm` draws `!shell || deployed`): the robot's analyzer key moved with
    this branch, so the type was probed again and its recorded rows, never extended since the shell state was tracked, were completed.

## The hand gate audit

Every `hand()` op is refused for an actor who is unconscious or stunned (`op_hand_capable()`); without `ungated()` one on a machine is also refused for a machine that does not work and an actor who is lying down or lacks the dexterity (`op_hand_refusal()`). The user kept the gate on all `hand()` ops. Audit by `dq_hand_gate_audit/escapes_are_not_hand_ops` over the tables built in a test world: **1308 hand ops, 395 `ungated()`, 913 behind the machine half**.

The old rule (the click path in `code/modules/keybindings/adapters.dm`, `/datum/input_adapter/hands/use`): a click is dropped for an actor with `stat`, paralysed or stunned; a restrained actor's click never reaches an empty-hand interaction (`RestrainedClickOn`, adjacent mobs only). The actor half of the new gate is that same rule, and the physical `STAT_CAN_ACT` gate already refused a stunned, weakened, paralysed, sleeping or unconscious actor for every physical binding before it. So no hand op is newly blocked for a down actor.

| Class | Ops | Verdict |
|---|---|---|
| (a) Touching or using a thing: consoles, machines, doors, closet door, chair unbuckle by hand, stasis cage release, pets, hugs | all 1308 hand ops | Correct to block for stunned, paralysed and unconscious actors; the old click did. A restrained actor never reached them by click and still does not. |
| (b) Resist out of cuffs (`cuff_remove`, `cuff_break`) | `ai()`, started by `resist()` with `ORIGIN_SYSTEM` | Not hand ops: the gate never sees them. Pinned for a cuffed, conscious mob. |
| (b) Unbuckle from a bed or chair while restrained (`buckle_escape`) | `ai()`, `ORIGIN_SYSTEM` | Not a hand op. A buckled, cuffed, conscious (or stunned) mob can start it; the by-hand `unbuckle` is a click and was never reachable restrained. |
| (b) Break out of a sealed closet (`break_out`) | `ai()`, `ORIGIN_SYSTEM` | Not a hand op. A cuffed mob inside can break out. |
| (b) Straight jacket (`jacket_escape`), grab release (`resist_grab`), fire (`resist_fire`) | `ai()` or plain procs | Not hand ops; unchanged. |
| Escape from a container interior (`interior` capability `escape`) | `inside()` | Not a hand op and not touched here: it carries the `STAT_CAN_ACT` gate, as before. |
| Unconscious actor resisting | verb rule (`incapacitated(INCAPACITATION_KNOCKOUT)`) | Unchanged: refused, pinned. |

Result: no `ungated()` or narrower gate was needed. The cases the audit worried about are system-origin escapes, outside the hand gate by construction; `escapes_are_not_hand_ops` fails if one of them is ever bound to `hand()`.

## Timed actions round 3 (rewrite/timed3-A)

Classes of behaviour that differ from the old `task_timed` / `task_start` forms. The sites are started from legacy hooks and use `ai()` ops entered with `perform_op(..., with = list(...))`.

| Class | Sites | Difference |
|---|---|---|
| Target of the keep is the op's target | mecha clamp (firedoor, airlock), hardpoint actuator, ore scanner, floor flooring, crawl drag, grave, dirt rocks/pile | The old task watched the thing worked on (door, equipment, scanned turf); the op watches the object whose capability holds the op (the equipment, the turf). A door or equipment deleted during the wait is checked in `then()` and refuses. The crawl drag checks the dragged thing is still where it was picked up. |
| Earlier interruption on death | malf hack of a cyborg or AI | The wait keeps `ALIVE`: an AI that dies stops the hack at once and the victim is told the message of the stage it never reached, instead of when that stage's wait would have ended. |
| Start message order / shock | suit cycler grab insertion | A live machine that shocks the user ends the click with a `suit_cycler/shocked` line (the shock itself already printed its own); no wait starts. The "starts putting X into the cycler" line is the op's `begins()`. |
| Passenger bay removal | mecha maintenance "remove passenger" | The hatch is looked up again when the four seconds end, instead of fixing the occupant at the start. |
| New op keys | mecha (`climb_in`, `mmi_install`), floors (`lay_flooring`), turf (`crawl_drag`, `graffiti`, `dig_grave`), changeling (`absorb_stage`), AI (`malf_hack_cyborg`, `malf_hack_ai`), nanite pool, newdirt, tome, spells, kiosk, cryopod, component, clamp, actuator, ore scanner, passenger | Op key lists in `snapshots/pins/*.txt` for those types change and must be blessed. |
## Timed actions round 3 (rewrite/timed3-B)

Group B (devices, fantasy items, ghost hunting, the holosign creator). Every legacy entry point (`attack()`, `afterattack()`, a confirmed prompt, a game hook such as `container_resist()`) is kept and now ends in `perform_op(actor, <the item>, "key", ..., with = list(...))` of an `ai()` op declared on the item, so the work is a pending op of its actor. The target of the old task (a creature, a locker, a victim) travels as a `takes()` value, not as the op's target.

| Class | Sites | Change |
|---|---|---|
| (a) A moving or lost target no longer cancels at the moment it happens | defib revive and shock (patient), body snatcher, mind binder, sleevemate scans, extrapolator, denecrotizer, translocator, bath buckle, wooden swirlie, hacktool locker/airlock, holosign | The old task watched the creature (`target = M`); the op watches the item. A target that was deleted ends the work with nothing done when it ends; the defib pair also ends when the patient left the tile it was placed on (`patient_left`); the sleevemate scans refuse with "You must remain close to your target!" when the user is no longer adjacent when they end. Nothing happens a second early. |
| (b) The held item is not a keep of an `ai()` wait | all of the above | The legacy default cancelled when the actor's active hand changed; the `ai()` default keeps only the target (the item) and the actor staying put. The ghost catcher keeps `HELD`. Putting the item down mid-wait no longer cancels the work of the others. |
| (c) The ghost catcher's range keep is not enforced | `ghost_catcher` grab | The old task ended when the user got further than `grab_range` from the ghost; there is no range keep yet (framework_gaps K15). The user and the target may still move freely, as before. A grab whose target is deleted does not run its `on_interrupt` (K8), so the box segments the user's client holds are not cleaned up until it logs out. |
| (d) Busy is `op_claimed()` | defib paddles, hacktool, ghost catcher, holosign creator | The same refusals ("already hacking", "already grabbing", "busy creating a hologram"); the claim is `CLAIM_TARGET` on the item only. |
| (e) The multitool recalibration is an op of the item | `multitool.dm` | `attack()` is deleted; the op is `at_target(/mob/living/carbon/human)` on help intent, with the limb read from the aimed zone when the wait ends as well as when it starts (aiming elsewhere during the four seconds recalibrates the newly aimed limb). |
## Timed actions round 3 (rewrite/timed3-C)

Group C: crayons, leash, soap, medical stacks, nanopaste, sandbags, stack builds, toys (plushies), UAV, AI modules, RCD, RMS, RPD, handcuffs and legcuffs, inducer, implanter, reagent egg implants, kitchen utensils, material weapons, the linked medigun, vore eggs and the energy net. Every `task_timed` / `task_start` / `task_busy` caller is now an op with `wait()`; entries that were a legacy `attack()` / `afterattack()` / verb / engine hook still start it with `perform_op(.., with = list(..))` into an `ai()` op (K21).

* **Victim-side cancels (class: target kept by the item, not the person; KC1 in framework_gaps.md).** Where the old task named the person or atom worked on as its target (handcuffs and legcuffs, the implanter, a force-fed utensil, the medical stacks, the nanopaste limb repair, the RCD, RMS, RPD, AI module install, the egg implant squeeze), the op's target is the item in the actor's hand. The actor moving, a changed hand item or a stunned actor still cancel; the victim leaving or being deleted no longer cancels at once, the end of the wait re-checks it (deleted, out of the grip, off the tile) and does nothing. The RCD and RPD no longer notice their target atom moving; a deleted target is caught at the end.
* **Medical wound treatment** is one repeating wait (a lap per wound, in the limb's order) instead of a chain of tasks. A limb that someone else finished bandaging during a lap now stops the series with "already bandaged" and still spends the charges of the wounds treated before (the old code returned without using any); the trauma kit's tissue repair lands once at the end as before. Walking away says "stand still to bandage wounds." and spends what was done.
* **Stack recipes** build through the stack's own `build` op: a second `make` while one runs is refused with the claimed message (the old `task_busy` return was silent), and swapping hands during a build no longer cancels it (the stack may be on the floor).
* **Cyborg nanopaste repair and the soap** are `at_target` ops of the item: the target moving or leaving ends the work as before; an `ITEM_INTERACT` the old override gave (cooldown on the mouth-washing click) is kept in `afterattack()` for the clicks it still answers.
* **The leash** is an `at_target` op: the three refusals (leashed, self, no collar) are still `attack()` messages, and a pet that moves away ends the attempt. The pet's own unhook and the holder's unleash are `ai()` ops of the leash; the pet moving away from the holder no longer cancels the holder's unleash.
* **Sandbag fill** is a repeating wait; the series ends as soon as the pile is gone or the ground is no longer outdoors (it waited one more second before).
* **The linked medigun** cycles with `silent_wait()` (no progress bar, no cog; the old task hid only the cog). Its caller's cleanup still runs the moment the first cycle is started, exactly as before, so only one cycle heals per click; that existing behaviour is reported, not changed.
* **The crayon** keeps its two prompts; the drawing is the crayon's `draw` op, which a crayon in the hand of a walking drawer cancels as before. The energy net, vore egg and plushie searches keep their durations.
