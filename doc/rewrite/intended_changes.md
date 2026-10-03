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

* **A hostile click on a person with an open container still does nothing.** The old splash of a person (and of yourself) has been unreachable since the
  interaction migration (the container's attack handler consumed the click before its afterattack ran); the tests pin that, and the converted container
  keeps it (`splash_mobs = FALSE` in `glass_container()`). Letting a hostile click splash a person is that one param.
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
  `feed`/`feed_wait`, `examine_range`, `splash_mobs` (engine_contracts.md, "Reagent containers"). Tests: `dq_lib/reagent_*`.
* A legacy entry interaction answers the input its handler did (`op_legacy_fits()`): a held item is no longer offered the empty-hand touches of its target.
  A turf is reachable as the target of an op (`reach_surface()`). Tests: `dq_p2_engine/legacy_entries_fit_the_input`, `an_op_at_a_turf_is_reached`.
* `req_reagents(units, more =)`, `reagent_transfer_amount()`, `atom/legacy_transfer_amount()`; `atom/is_open_container()` follows the capability's lid.
* The old `cap_reagent_container()` library, its test and the `CAP_LID_OPEN` bit are deleted (nothing used them).
