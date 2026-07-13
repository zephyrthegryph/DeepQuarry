// Handles the subjugation of slimes by force.
//bodies of adjust_discipline / is_justified_to_discipline moved to
// modular_dq/code/modules/combat_ai/ports/slime_mob_overrides.dm where they
// now drive /datum/slime_state instead of the deleted ai_holder.

/mob/living/simple_mob/slime/xenobio/proc/adjust_discipline(amount, silent)
	return

/mob/living/simple_mob/slime/xenobio/proc/is_justified_to_discipline()
	return FALSE
