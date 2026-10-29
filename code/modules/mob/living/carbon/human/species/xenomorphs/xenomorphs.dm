/proc/create_new_xenomorph(alien_caste,target)

	target = get_turf(target)
	if(!target || !alien_caste) return

	var/mob/living/carbon/human/new_alien = new(target)
	new_alien.set_species("Xenomorph [alien_caste]")
	return new_alien

/mob/living/carbon/human/xdrone
	species_at_make = SPECIES_XENO_DRONE

CAPABILITIES(/mob/living/carbon/human/xdrone)
	configure(mob_rules(faction = FACTION_XENO))
	profile(nameof(looks), /datum/record/appearance, fields = list("hair_style" = "Bald"))
/mob/living/carbon/human/xdrone
/mob/living/carbon/human/xdrone

/mob/living/carbon/human/xsentinel
	species_at_make = SPECIES_XENO_SENTINEL

CAPABILITIES(/mob/living/carbon/human/xsentinel)
	configure(mob_rules(faction = FACTION_XENO))
	profile(nameof(looks), /datum/record/appearance, fields = list("hair_style" = "Bald"))
/mob/living/carbon/human/xsentinel
/mob/living/carbon/human/xsentinel

/mob/living/carbon/human/xhunter
	species_at_make = SPECIES_XENO_HUNTER

CAPABILITIES(/mob/living/carbon/human/xhunter)
	configure(mob_rules(faction = FACTION_XENO))
	profile(nameof(looks), /datum/record/appearance, fields = list("hair_style" = "Bald"))
/mob/living/carbon/human/xhunter
/mob/living/carbon/human/xhunter

/mob/living/carbon/human/xqueen
	species_at_make = SPECIES_XENO_QUEEN

CAPABILITIES(/mob/living/carbon/human/xqueen)
	configure(mob_rules(faction = FACTION_XENO))
	profile(nameof(looks), /datum/record/appearance, fields = list("hair_style" = "Bald"))
/mob/living/carbon/human/xqueen
/mob/living/carbon/human/xqueen

//Removed AddInfectionImages, no longer required.
