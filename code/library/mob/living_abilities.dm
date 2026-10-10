// living_abilities() (proposals/mob_living_root.md, option B): the ops every /mob/living holds that belong to no narrower type. The one
// CAPABILITIES(/mob/living) block (code/modules/combat_ai/integration/mob_living.dm) names this proc once, like living_action_status_contributions().
//
// The holder of each op is the mob the work is done to (the dead animal, the prey, the grabbed mob); the actor is whoever does it (A.actor), and a
// mob doing something to itself is both. The values a handler needs travel as takes() names, passed with perform_op(..., with = list()). The handler procs
// stay on the content types (butchering.dm, melee_swing.dm, dominated_brain.dm, vore/eating/*.dm, ...); only the declarations live here.

/proc/living_abilities()
	return list(
		// butchering: Carving a dead animal: a cut of meat per lap, then the carcass.
		// One cut per lap while the animal has meat left (the meat is counted down by each cut); the claim keeps a second butcher off the carcass.
		op("harvest_cut", ai(), reach(REACH_ANY), claims(), wait(TYPE_PROC_REF(/mob/living, harvest_cut_time), repeats = TYPE_PROC_REF(/mob/living, harvest_more), after_step = TYPE_PROC_REF(/mob/living, harvest_cut_done)), then(TYPE_PROC_REF(/mob/living, harvest_finished))),
		op("butcher_mob", ai(), reach(REACH_ANY), claims(), wait(TYPE_PROC_REF(/mob/living, butcher_time)), then(TYPE_PROC_REF(/mob/living, butcher_finished))),
		// combat: A phased melee swing: the windup, then the blow against whoever stands in the telegraphed tiles.
		op("melee_swing", ai(), reach(REACH_ANY), takes("swing_target", "windup", "swing_tiles"), silent_wait(), wait(TYPE_PROC_REF(/mob/living, melee_swing_time), keeps = HELD | ALIVE | STAY), on_interrupt(TYPE_PROC_REF(/mob/living, melee_swing_failed)), then(TYPE_PROC_REF(/mob/living, melee_swing_done))),
		// shapes: Species and trait abilities that change what the mob is.
		op("revert_beast_form", ai(), reach(REACH_ANY), wait(10 SECONDS), on_interrupt(TYPE_PROC_REF(/mob/living, revert_beast_form_failed)), then(TYPE_PROC_REF(/mob/living, revert_beast_form_done))),
		op("mobegglaying", ai(), reach(REACH_ANY), takes("choice"), wait(30 SECONDS), then(TYPE_PROC_REF(/mob/living, mobegglaying_done))),
		// vore: Eating, being eaten and the mind games that go with it.
		// The prey (inside a belly) reaching out for a victim: the work is done to the victim, and fails if it leaves the tile it stood on.
		op("absorb_devour", ai(), reach(REACH_ANY), takes("pred", "belly", "starting_loc"), wait(5 SECONDS, keeps = TARGET_PRESENT | ALIVE | STAY), then(TYPE_PROC_REF(/mob/living, absorb_devour_done))),
		op("vertical_nom", ai(), reach(REACH_ANY), takes("starting_loc"), wait(5 SECONDS, keeps = TARGET_PRESENT | ALIVE | STAY), then(TYPE_PROC_REF(/mob/living, vertical_nom_finished))),
		op("holo_nom", ai(), reach(REACH_ANY), takes("holo_ai"), wait(5 SECONDS, keeps = TARGET_PRESENT | STAY), then(TYPE_PROC_REF(/mob/living, holo_nom_finished))),
		op("beacon_insert", ai(), reach(REACH_RANGE(1)), takes("belly"), wait(3 SECONDS), then(TYPE_PROC_REF(/mob/living, beacon_insert_finished))),
		op("body_writing", ai(), reach(REACH_RANGE(1)), takes("limb", "message"), wait(3 SECONDS), on_interrupt(TYPE_PROC_REF(/mob/living, body_writing_stopped)), then(TYPE_PROC_REF(/mob/living, body_writing_finished))),
		// The feeder may walk while the eater chews (the old task ignored the feeder's own movement).
		op("eat_minerals", ai(), reach(REACH_ANY), claims(CLAIM_TARGET), takes("item", "nom", "chew_time"), wait(TYPE_PROC_REF(/mob/living, eat_minerals_time), keeps = TARGET_PRESENT | ALIVE), on_interrupt(TYPE_PROC_REF(/mob/living, eat_minerals_interrupted)), then(TYPE_PROC_REF(/mob/living, eat_minerals_finished))),
		// minds: Taking over, or handing over, the body of a predator.
		op("dominate_predator", ai(), reach(REACH_ANY), wait(10 SECONDS, keeps = TARGET_PRESENT | ALIVE | STAY), on_interrupt(TYPE_PROC_REF(/mob/living, dominate_predator_failed)), then(TYPE_PROC_REF(/mob/living, dominate_predator_done))),
		op("dominate_prey", ai(), reach(REACH_ANY), takes("grab"), wait(10 SECONDS, keeps = TARGET_PRESENT | ALIVE | STAY), on_interrupt(TYPE_PROC_REF(/mob/living, dominate_prey_failed)), then(TYPE_PROC_REF(/mob/living, dominate_prey_done))),
		op("lend_prey_control", ai(), reach(REACH_ANY), wait(10 SECONDS, keeps = TARGET_PRESENT | ALIVE | STAY), on_interrupt(TYPE_PROC_REF(/mob/living, lend_prey_control_failed)), then(TYPE_PROC_REF(/mob/living, lend_prey_control_done))),
		// climbing: Climbing down a wall: a fall if the climber is cut short after the grace time.
		op("climb_down", ai(), reach(REACH_ANY), takes("duration", "front_of_us", "destination", "below_wall", "fall_chance", "nutrition_cost", "fall_at"), wait(TYPE_PROC_REF(/mob/living, climb_down_time)), on_interrupt(TYPE_PROC_REF(/mob/living, climb_down_interrupted)), then(TYPE_PROC_REF(/mob/living, climb_down_done))))
