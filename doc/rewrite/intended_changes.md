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
