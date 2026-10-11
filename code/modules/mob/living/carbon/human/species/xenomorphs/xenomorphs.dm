/proc/create_new_xenomorph(alien_caste,target)

	target = get_turf(target)
	if(!target || !alien_caste) return

	var/mob/living/carbon/human/new_alien = new(target)
	new_alien.set_species("Xenomorph [alien_caste]")
	return new_alien

/mob/living/carbon/human/xdrone
	species_at_make = SPECIES_XENO_DRONE
/mob/living/carbon/human/xdrone
	h_style = "Bald"
/mob/living/carbon/human/xdrone
	faction = FACTION_XENO

/mob/living/carbon/human/xsentinel
	species_at_make = SPECIES_XENO_SENTINEL
/mob/living/carbon/human/xsentinel
	h_style = "Bald"
/mob/living/carbon/human/xsentinel
	faction = FACTION_XENO

/mob/living/carbon/human/xhunter
	species_at_make = SPECIES_XENO_HUNTER
/mob/living/carbon/human/xhunter
	h_style = "Bald"
/mob/living/carbon/human/xhunter
	faction = FACTION_XENO

/mob/living/carbon/human/xqueen
	species_at_make = SPECIES_XENO_QUEEN
/mob/living/carbon/human/xqueen
	h_style = "Bald"
/mob/living/carbon/human/xqueen
	faction = FACTION_XENO

//Removed AddInfectionImages, no longer required.
