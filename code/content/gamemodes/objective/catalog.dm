/datum/objective/nuclear
	explanation_text = "Destroy the station with a nuclear device."

/datum/objective/vore/check_completion()
	if(owner && owner.vore_prey_eaten >= target_amount)
		return 1
	else
		return 0

// Heist objectives.
/datum/objective/heist/proc/choose_target()
	return

/datum/objective/heist/preserve_crew
	explanation_text = "Do not leave anyone behind, alive or dead."

/datum/objective/heist/preserve_crew/check_completion()
	if(antag_raiders() && antag_raiders().is_raider_crew_safe()) return 1
	return 0

/datum/objective/borer_reproduce
	explanation_text = "Reproduce at least once."

/datum/objective/borer_reproduce/check_completion()
	if(owner && owner.current)
		var/mob/living/simple_mob/animal/borer/B = owner.current
		if(istype(B) && B.has_reproduced) return 1
	return 0

/datum/objective/cult/eldergod
	explanation_text = "Summon Nar-Sie via the use of the appropriate rune (Hell join self). It will only work if nine cultists stand on and around it. The convert rune is join blood self."

/datum/objective/cult/eldergod/check_completion()
	return (locate_in_list(REGISTRY_MEMBERS(REGISTRY_MACHINES), /obj/singularity/narsie/large))
