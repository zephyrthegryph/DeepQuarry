/obj/item/organ/external/chest/unathi
	max_damage = 100
	min_broken_damage = 80 // Flat doubling of all min_broken_damage
	encased = "upper ribplates"

/obj/item/organ/external/groin/unathi
	max_damage = 100
	min_broken_damage = 80 // Flat doubling of all min_broken_damage
	encased = "lower ribplates"

/obj/item/organ/external/head/unathi
	max_damage = 75
	min_broken_damage = 70 // Flat doubling of all min_broken_damage
	eye_icon = "eyes_s"
	force = 5
	throwforce = 10

/obj/item/organ/internal/eyes/unathi
	icon_state = "unathi_eyes"

/obj/item/organ/internal/heart/unathi
	icon_state = "unathi_heart-on"
	dead_icon = "unathi_heart-off"

/obj/item/organ/internal/lungs/unathi
	color = "#b3cbc3"

/obj/item/organ/internal/liver/unathi
	name = "filtration organ"
	icon_state = "unathi_liver"

//Unathi liver acts as kidneys, too.
/obj/item/organ/internal/liver/unathi/organ_tick(cycles)
	..()
	if(!owner) return

	var/datum/reagent/coffee = locate_in_list(owner.reagents.reagent_list, /datum/reagent/drink/coffee)
	if(coffee)
		if(is_bruised())
			owner.injure(INJURY_TOXIN, 0.1 * ORGAN_LEGACY_BURST * cycles, flags = INJURE_SILENT)
		else if(is_broken())
			owner.injure(INJURY_TOXIN, 0.3 * ORGAN_LEGACY_BURST * cycles, flags = INJURE_SILENT)

	var/datum/reagent/sugar = locate_in_list(owner.reagents.reagent_list, /datum/reagent/sugar)
	if(sugar)
		if(is_bruised())
			owner.injure(INJURY_TOXIN, 0.1 * ORGAN_LEGACY_BURST * cycles, flags = INJURE_SILENT)
		else if(is_broken())
			owner.injure(INJURY_TOXIN, 0.3 * ORGAN_LEGACY_BURST * cycles, flags = INJURE_SILENT)

/obj/item/organ/internal/brain/unathi
	color = "#b3cbc3"

/obj/item/organ/internal/stomach/unathi
	color = "#b3cbc3"
	max_acid_volume = 40

/obj/item/organ/internal/intestine/unathi
	color = "#b3cbc3"

// This organ has work every organ_tick(), so the body's organ clock stays running for it.
/obj/item/organ/internal/liver/unathi/life_step_idle()
	return FALSE

