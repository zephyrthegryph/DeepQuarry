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
	return living_vore_abilities() + living_trait_abilities() + living_form_abilities()

/// Abilities that act on another creature: the vore and trait powers whose targets are picked or handed over.
/proc/living_vore_abilities()
	return list(
		// Healing rainbows (living_powers.dm): asks who, charges five seconds while keeping them in sight, then fires.
		op("healing_rainbows", ai(), asks(/datum/prompt/choice/rainbow_target, fields = list("choices" = computed(TYPE_PROC_REF(/mob/living, rainbow_choices))), step = "target", keeps_answer = TRUE),
			starts(TYPE_PROC_REF(/mob/living, rainbows_started)), wait(5 SECONDS, keeps = HELD | TARGET_PRESENT | STAY), then(TYPE_PROC_REF(/mob/living, healing_rainbows_living_done))),
		// The venom trait (station_special_abilities.dm): the pick is next to us, and stays so for the five seconds the injection takes.
		op("injection", ai(), asks(/datum/prompt/choice/victim, fields = list("choices" = computed(TYPE_PROC_REF(/mob/living, injection_choices))), step = "victim", keeps_answer = TRUE),
			starts(TYPE_PROC_REF(/mob/living, injection_started)), wait(5 SECONDS), then(TYPE_PROC_REF(/mob/living, injection_living_done))),
		// The succubus bite: the reagent was chosen with the grip checked; the victim and the choice come with the call and the bite waits half a minute.
		op("succubus_bite", ai(), takes("victim", "choice", "from"), wait(30 SECONDS), then(TYPE_PROC_REF(/mob/living, succubus_bite_living_done))),
		// An absorbed prey grabs for something in reach of its pred's belly (absorb_devour()); the pred and belly were checked when it was chosen.
		op("absorb_devour", ai(), takes("victim", "pred", "belly", "from"), wait(5 SECONDS), then(TYPE_PROC_REF(/mob/living, absorb_devour_living_done))),
		// Tearing a limb or an organ off prey: the limb, organ and belly were chosen by the prompts of the shred_limb review; it takes the mob's own shred time.
		op("shred_limb", ai(), takes("victim", "external", "internal", "belly"), wait(TYPE_PROC_REF(/mob/living, shred_limb_time)), then(TYPE_PROC_REF(/mob/living, shred_limb_living_done))))

/// Abilities that only change the actor.
/proc/living_trait_abilities()
	return list(
		// Egg laying (station_special_abilities.dm): asks what to do, then takes half a minute over it.
		op("egg_laying", ai(), asks(/datum/prompt/choice, fields = list("title" = "Egg Option", "question" = "What do you want to do?", "choices" = list("Make a Egg", "lay your Eggs"), "ask_flags" = ASK_CONSCIOUS, "timeout" = 0), step = "choice"),
			wait(30 SECONDS), then(TYPE_PROC_REF(/mob/living, mobegglaying_living_done))))

/// Changing shape: a beast form taken from a list the verb offered, and the revert from it.
/proc/living_form_abilities()
	return list(
		// Back from a beast form (lleill_abilities.dm).
		op("revert_beast_form", ai(), wait(10 SECONDS), on_interrupt(TYPE_PROC_REF(/mob/living, revert_beast_form_living_failed)), then(TYPE_PROC_REF(/mob/living, revert_beast_form_living_done))),
		// The ddraig's polymorph (ddraig.dm): the form and the list it came from are handed over by the verb's prompt.
		op("polymorph", ai(), takes("beast", "options"), wait(10 SECONDS), on_interrupt(TYPE_PROC_REF(/mob/living, polymorph_living_failed)), then(TYPE_PROC_REF(/mob/living, polymorph_living_done))))
