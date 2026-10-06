/datum/species/shadow
	name = SPECIES_SHADOW
	name_plural = "shadows"

	icobase = 'icons/mob/human_races/r_shadow.dmi'
	deform = 'icons/mob/human_races/r_shadow.dmi'

	language = "Sol Common" //todo?
	unarmed_types = list(/datum/unarmed_attack/claws/strong, /datum/unarmed_attack/bite/sharp)
	darksight = 8
	has_organ = list()
	siemens_coefficient = 0

	// No sounds for this species

	blood_color = "#CCCCCC"
	flesh_color = "#AAAAAA"

	virus_immune = 1

	remains_type = /obj/effect/decal/cleanable/ash
	death_message = "dissolves into ash..."

	flags = NO_DNA | NO_SLEEVE | NO_SLIP | NO_POISON | NO_MINOR_CUT | NO_DEFIB
	spawn_flags = SPECIES_IS_RESTRICTED

	genders = list(NEUTER)

	assisted_langs = list()

	species_component = list(/datum/trait_state/burninlight/shadow) // Until a parent component like xenochimera have is needed, only handles burning in light.

/datum/species/shadow/handle_death(mob/living/carbon/human/H)
	after(H, 0.1 SECONDS, TYPE_PROC_REF(/mob/living/carbon/human, species_death_crumble))

/// A species death that leaves only ash.
/mob/living/carbon/human/proc/species_death_crumble()
	new /obj/effect/decal/cleanable/ash(loc)
	dissolved(src)
