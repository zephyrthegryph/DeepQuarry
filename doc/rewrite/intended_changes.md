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
