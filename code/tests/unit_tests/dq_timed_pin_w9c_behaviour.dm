// Behaviour pins for the timed actions of the species, simple mob, vore and projectile files (worker C, wave 9), recorded on the legacy task_timed /
// task_start forms before they become ops with wait(). Same harness as dq_timed_pin_w8_behaviour.dm: every pin drives the real click path and records the
// duration, the start message, what a move, a dropped held item or a lost target does, the completion effect and a refusal.
//
// unpinned: code/modules/projectiles/guns/launcher/bows.dm: drawing is a gun self-use chain with no helper that drives it from a test
// unpinned: code/modules/projectiles/guns/launcher/crossbow.dm: same self-use chain, and the draw repeats in notches
// unpinned: code/modules/projectiles/broken.dm: inspect starts from examine(), which no harness helper drives; repair needs per-gun material fixtures
// unpinned: code/modules/projectiles/*: clockwork, energy, particle, magnetic bore, modular, projectile, special guns: need cells, ammo or charged fixtures
// unpinned: code/modules/mob/*, species/*, simple_mob/*, vore/*, robot/dogborg: abilities start from verbs, prompts or ghosts and need clients, belly or species fixtures

/datum/unit_test/dq_timed_pin_w9c
	abstract_type = /datum/unit_test/dq_timed_pin_w9c
	parent_type = /datum/unit_test/dq_timed_pin_w8
	// the w8 scene machinery is reused whole: setup_scene, is_done and the numbers below are all a pin has to give

// ---- A double-barrelled shotgun: a saw held to its barrel shortens it in three seconds ----

/datum/unit_test/dq_timed_pin_w9c/shotgun_saw_off
	duration = 3 SECONDS
	began = "You begin to shorten the barrel"
	finished = "You shorten the barrel"
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w9c/shotgun_saw_off/setup_scene()
	user = person()
	target = allocate(/obj/item/gun/projectile/shotgun/doublebarrel, run_loc_floor_bottom_left)
	held = hold(/obj/item/surgical/circular_saw)
	var/obj/item/gun/projectile/shotgun/doublebarrel/G = target
	// a loaded gun goes off instead of being cut (saw_off_loaded): empty it
	for(var/obj/item/ammo_casing/C in G.loaded)
		G.loaded -= C
		qdel(C)

/datum/unit_test/dq_timed_pin_w9c/shotgun_saw_off/is_done()
	var/obj/item/gun/projectile/shotgun/doublebarrel/G = target
	return !QDELETED(G) && G.icon_state == "sawnshotgun" // the timed action only redraws the gun; it never set sawn_off

/datum/unit_test/dq_timed_pin_w9c/shotgun_saw_off/extra_pin()
	// an already shortened barrel is told so and starts nothing
	setup_scene()
	var/obj/item/gun/projectile/shotgun/doublebarrel/G = target
	G.sawn_off = TRUE
	refused("already shortened")
	clear_scene()
