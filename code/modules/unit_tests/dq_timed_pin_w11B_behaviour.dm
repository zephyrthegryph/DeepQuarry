// Behaviour pins for the timed actions of group B of timed-actions round 3 (rewrite/timed3-B): the devices of code/game/objects/items/devices,
// fantasy_items, ghost_hunting and the holosign creator. Same harness as dq_timed_pin_w8_behaviour.dm (base type /datum/unit_test/dq_timed_pin_w8).
//
// Only what the test driver reaches is pinned. A legacy attack() / afterattack() override is driven through the mob's own ClickOn() (legacy_click),
// and the entries that need a live AI, a diseased host, a minded body with a NIF, a resisting target, an open prompt or a charged cell are covered by
// the converted forms' own tests (interim_hacktool_supported_table, dq_denecrotizer_tests) rather than a scene here:
// unpinned: aicard.dm (grab_ai needs a live AI), body_snatcher.dm (a confirmed prompt and two minds), defib.dm (a patient in a shockable rhythm and a wielded charged pair),
// extrapolator.dm (a diseased host and two prompts), mind_binder.dm (prompts and minds), multitool.dm (a synthetic limb), sleevemate.dm (a minded body, a NIF and the topic window),
// translocator.dm (beacons and a charged cell), fantasy_items.dm (a grabbed victim), trap.dm container_resist (a captured entity), weapons.dm (a ghost to grab).

// ---- A denecrotizer: a dead creature is revived, thirty seconds, the faction follows the user ----

/datum/unit_test/dq_timed_pin_w8/denecrotizer_ghostjoin
	duration = 30 SECONDS
	drop_cancels = TRUE
	legacy_click = TRUE // the denecrotizer is used through attack()

/datum/unit_test/dq_timed_pin_w8/denecrotizer_ghostjoin/setup_scene()
	user = person()
	var/mob/living/simple_mob/animal = allocate(/mob/living/simple_mob, get_step(user, NORTH))
	animal.death()
	target = animal
	held = hold(/obj/item/denecrotizer)

/datum/unit_test/dq_timed_pin_w8/denecrotizer_ghostjoin/is_done()
	var/mob/living/simple_mob/animal = target
	return !QDELETED(animal) && animal.stat != DEAD

// ---- A commercial denecrotizer: the plain revive, thirty seconds ----

/datum/unit_test/dq_timed_pin_w8/denecrotizer_basic
	duration = 30 SECONDS
	drop_cancels = TRUE
	legacy_click = TRUE

/datum/unit_test/dq_timed_pin_w8/denecrotizer_basic/setup_scene()
	user = person()
	var/mob/living/simple_mob/animal = allocate(/mob/living/simple_mob, get_step(user, NORTH))
	animal.death()
	target = animal
	held = hold(/obj/item/denecrotizer/medical)

/datum/unit_test/dq_timed_pin_w8/denecrotizer_basic/is_done()
	var/mob/living/simple_mob/animal = target
	return !QDELETED(animal) && animal.stat != DEAD
