// The abilities every living mob can have (K23, doc/rewrite/proposals/mob_living_root.md): a species or trait gives its mob a verb, the verb
// checks what is instant and names the op, and the work (the question, the wait, what is kept, the effect) is declared here. The one
// CAPABILITIES(/mob/living) block is in code/modules/combat_ai/integration/mob_living.dm; it names living_abilities() once, the way it names
// living_action_status_contributions(), so these entries sit next to the other mob library code and the analyzer reads each key as it reads any op.
//
// The ops have an ai() binding and are performed on the actor (perform_op(src, src, key, null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL)), so the
// handlers run on the mob that does the thing. Whom it is done to is the answer of the op's own question (asks(keeps_answer = TRUE): the wait ends
// when they get away) or a value the verb hands over (takes(), read with A.arg("name")). The handler procs stay with the content they belong to.
//
// living_abilities() returns the groups of entries; a group is a plain proc of entries so a file with many abilities can keep its own.

/proc/living_abilities()
	return living_vore_abilities() + living_care_abilities() + living_butchering() + living_combat_abilities() + living_climbing() + living_ventcrawling() + living_trait_abilities() + living_form_abilities()

/// Abilities that act on another creature: the vore and trait powers whose targets are picked or handed over.
/proc/living_vore_abilities()
	return list(
		// Healing rainbows (living_powers.dm): asks who, charges five seconds while keeping them in sight, then fires.
		op("healing_rainbows", ai(), needs(req_capable()), asks(/datum/prompt/choice/rainbow_target, fields = list("choices" = computed(TYPE_PROC_REF(/mob/living, rainbow_choices))), step = "target", keeps_answer = TRUE),
			starts(TYPE_PROC_REF(/mob/living, rainbows_started)), wait(5 SECONDS, keeps = HELD | TARGET_PRESENT | STAY), then(TYPE_PROC_REF(/mob/living, healing_rainbows_living_done))),
		// The venom trait (station_special_abilities.dm): the pick is next to us, and stays so for the five seconds the injection takes.
		op("injection", ai(), needs(req_capable()), asks(/datum/prompt/choice/victim, fields = list("choices" = computed(TYPE_PROC_REF(/mob/living, injection_choices))), step = "victim", keeps_answer = TRUE),
			starts(TYPE_PROC_REF(/mob/living, injection_started)), wait(5 SECONDS), then(TYPE_PROC_REF(/mob/living, injection_living_done))),
		// The succubus bite: the reagent was chosen with the grip checked; the victim and the choice come with the call and the bite waits half a minute.
		op("succubus_bite", ai(), needs(req_capable()), takes("victim", "choice", "from"), wait(30 SECONDS), then(TYPE_PROC_REF(/mob/living, succubus_bite_living_done))),
		// An absorbed prey grabs for something in reach of its pred's belly (absorb_devour()); the pred and belly were checked when it was chosen.
		op("absorb_devour", ai(), takes("victim", "pred", "belly", "from"), wait(5 SECONDS), then(TYPE_PROC_REF(/mob/living, absorb_devour_living_done))),
		// Taking over a body or gathering a mind (dominated_brain.dm): the minds agreed in the review; ten seconds of the will shifting.
		op("dominate_predator", ai(), needs(req_capable()), takes("pred", "from"), wait(10 SECONDS), on_interrupt(TYPE_PROC_REF(/mob, dominate_predator_mob_failed)), then(TYPE_PROC_REF(/mob, dominate_predator_mob_done))),
		op("dominate_prey", ai(), needs(req_capable()), takes("prey", "grab"), wait(10 SECONDS), on_interrupt(TYPE_PROC_REF(/mob/living, dominate_prey_living_failed)), then(TYPE_PROC_REF(/mob/living, dominate_prey_living_done))),
		op("lend_prey_control", ai(), needs(req_capable()), takes("prey", "from"), wait(10 SECONDS), on_interrupt(TYPE_PROC_REF(/mob/living, lend_prey_control_living_failed)), then(TYPE_PROC_REF(/mob/living, lend_prey_control_living_done))),
		// Tearing a limb or an organ off prey: the limb, organ and belly were chosen by the prompts of the shred_limb review; it takes the mob's own shred time.
		op("shred_limb", ai(), needs(req_capable()), takes("victim", "external", "internal", "belly"), wait(TYPE_PROC_REF(/mob/living, shred_limb_time)), then(TYPE_PROC_REF(/mob/living, shred_limb_living_done))))

/// Things done to a living mob by someone beside it (the actor is who does it, the mob the op is on): feeding, writing on, and so on (vore/eating/living.dm).
/proc/living_care_abilities()
	return list(
		op("beacon_insert", ai(), needs(req_capable()), takes("beacon", "belly"), wait(3 SECONDS), then(TYPE_PROC_REF(/mob/living, beacon_insert_done))),
		op("body_writing", ai(), needs(req_capable()), takes("limb", "message"), wait(3 SECONDS), on_interrupt(TYPE_PROC_REF(/mob/living, body_writing_stopped)), then(TYPE_PROC_REF(/mob/living, body_writing_done))),
		// Eating a mineral on the move: the feeder may walk, not change hands or leave the eater.
		op("eat_minerals", ai(), needs(req_capable()), takes("snack", "nom", "time"), wait(TYPE_PROC_REF(/mob/living, eat_minerals_time), keeps = HELD | ADJACENT | TARGET_PRESENT | ALIVE), on_interrupt(TYPE_PROC_REF(/mob/living, eat_minerals_interrupted)), then(TYPE_PROC_REF(/mob/living, eat_minerals_done))))

/// Cutting up a carcass (butchering.dm): a lap of cutting per piece of meat, then the butchering itself. Nobody else may work on it meanwhile (the carcass is claimed, not the butcher's hands).
/proc/living_butchering()
	return list(
		op("harvest", ai(), claims(CLAIM_TARGET), needs(req_capable()), wait(TYPE_PROC_REF(/mob/living, harvest_time), repeats = TYPE_PROC_REF(/mob/living, harvest_more), after_step = TYPE_PROC_REF(/mob/living, harvest_cut)), then(TYPE_PROC_REF(/mob/living, harvest_finished))),
		op("butcher", ai(), claims(CLAIM_TARGET), needs(req_capable()), wait(TYPE_PROC_REF(/mob/living, butcher_time)), then(TYPE_PROC_REF(/mob/living, butcher_finished))))

/// The windup of an armed swing (melee_swing.dm): no bar, no cog, and nothing held but the swinger's own feet and weapon hand.
/proc/living_combat_abilities()
	return list(
		op("melee_swing", ai(), claims(0), needs(req_capable()), takes("target", "weapon", "tiles", "windup"), silent_wait(), wait(TYPE_PROC_REF(/mob/living, melee_swing_windup)), on_interrupt(TYPE_PROC_REF(/mob/living, begin_melee_swing_living_failed)), then(TYPE_PROC_REF(/mob/living, begin_melee_swing_living_done))))

/// Climbing a wall (multiz/movement.dm): the one climbing is still for as long as it takes, and falls if it is broken off late.
/proc/living_climbing()
	return list(
		op("climb_wall", ai(), needs(req_capable()), takes("wall", "time", "above_mob", "above_wall", "fall_chance", "drop_held", "nutrition_cost", "fall_at"), wait(TYPE_PROC_REF(/mob/living, climb_time_of)), on_interrupt(TYPE_PROC_REF(/mob/living, climb_wall_interrupted)), then(TYPE_PROC_REF(/mob/living, climb_wall_done))),
		op("climb_down", ai(), needs(req_capable()), takes("time", "front_of_us", "destination", "below_wall", "fall_chance", "nutrition_cost", "fall_at"), wait(TYPE_PROC_REF(/mob/living, climb_time_of)), on_interrupt(TYPE_PROC_REF(/mob/living, climb_down_interrupted)), then(TYPE_PROC_REF(/mob/living, climb_down_done))))

/// Climbing into a vent (ventcrawl.dm): the crawler is claimed while the animation fades them in, and stays where they are.
/proc/living_ventcrawling()
	return list(
		op("ventcrawl_in", ai(), claims(CLAIM_TARGET), needs(req_capable()), takes("vent", "time"), wait(TYPE_PROC_REF(/mob/living, ventcrawl_time)), then(TYPE_PROC_REF(/mob/living, ventcrawl_in_done))))

/// Abilities that only change the actor.
/proc/living_trait_abilities()
	return list(
		// Egg laying (station_special_abilities.dm): asks what to do, then takes half a minute over it.
		op("egg_laying", ai(), needs(req_capable()), asks(/datum/prompt/choice, fields = list("title" = "Egg Option", "question" = "What do you want to do?", "choices" = list("Make a Egg", "lay your Eggs"), "ask_flags" = ASK_CONSCIOUS, "timeout" = 0), step = "choice"),
			wait(30 SECONDS), then(TYPE_PROC_REF(/mob/living, mobegglaying_living_done))))

/// Changing shape: a beast form taken from a list the verb offered, and the revert from it.
/proc/living_form_abilities()
	return list(
		// Eating someone from the level above (vertical_nom.dm): the prey was picked, and has to still be where they were.
		op("vertical_nom", ai(), needs(req_capable()), takes("prey", "from"), wait(5 SECONDS), then(TYPE_PROC_REF(/mob/living, vertical_nom_done))),
		// Back from a beast form (lleill_abilities.dm).
		op("revert_beast_form", ai(), needs(req_capable()), wait(10 SECONDS), on_interrupt(TYPE_PROC_REF(/mob/living, revert_beast_form_living_failed)), then(TYPE_PROC_REF(/mob/living, revert_beast_form_living_done))),
		// The ddraig's polymorph (ddraig.dm): the form and the list it came from are handed over by the verb's prompt.
		op("polymorph", ai(), needs(req_capable()), takes("beast", "options"), wait(10 SECONDS), on_interrupt(TYPE_PROC_REF(/mob/living, polymorph_living_failed)), then(TYPE_PROC_REF(/mob/living, polymorph_living_done))))
