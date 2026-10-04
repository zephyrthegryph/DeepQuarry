/proc/create_new_xenomorph(alien_caste,target)

	target = get_turf(target)
	if(!target || !alien_caste) return

	var/mob/living/carbon/human/new_alien = new(target)
	new_alien.set_species("Xenomorph [alien_caste]")
	return new_alien

TYPE_TABLE(/mob/living/carbon/human/xdrone, forced_initial_species, SPECIES_XENO_DRONE)
TYPE_TABLE(/mob/living/carbon/human/xdrone, forced_initial_hair, "Bald")
TYPE_TABLE(/mob/living/carbon/human/xdrone, forced_initial_faction, FACTION_XENO)

TYPE_TABLE(/mob/living/carbon/human/xsentinel, forced_initial_species, SPECIES_XENO_SENTINEL)
TYPE_TABLE(/mob/living/carbon/human/xsentinel, forced_initial_hair, "Bald")
TYPE_TABLE(/mob/living/carbon/human/xsentinel, forced_initial_faction, FACTION_XENO)

TYPE_TABLE(/mob/living/carbon/human/xhunter, forced_initial_species, SPECIES_XENO_HUNTER)
TYPE_TABLE(/mob/living/carbon/human/xhunter, forced_initial_hair, "Bald")
TYPE_TABLE(/mob/living/carbon/human/xhunter, forced_initial_faction, FACTION_XENO)

TYPE_TABLE(/mob/living/carbon/human/xqueen, forced_initial_species, SPECIES_XENO_QUEEN)
TYPE_TABLE(/mob/living/carbon/human/xqueen, forced_initial_hair, "Bald")
TYPE_TABLE(/mob/living/carbon/human/xqueen, forced_initial_faction, FACTION_XENO)

//Removed AddInfectionImages, no longer required.
