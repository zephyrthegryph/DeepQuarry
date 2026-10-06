/****************************************************
				INTERNAL ORGANS DEFINES
****************************************************/
/obj/item/organ/internal
	var/dead_icon // Icon to use when the organ has died.

	var/supply_conversion_value = 0


/obj/item/organ/internal/Initialize(mapload, internal)
	. = ..()
	if(supply_conversion_value)
		make_sellable(/datum/sellable/organ)

/obj/item/organ/internal/die()
	..()
	if((status & ORGAN_DEAD) && dead_icon)
		icon_state = dead_icon

/obj/item/organ/internal/robotize()
	..()
	name = "prosthetic [initial(name)]"
	icon_state = "[initial(icon_state)]_prosthetic"
	if(dead_icon)
		dead_icon = "[initial(dead_icon)]_prosthetic"

/obj/item/organ/internal/mechassist()
	..()
	name = "assisted [initial(name)]"
	icon_state = "[initial(icon_state)]_assisted"
	if(dead_icon)
		dead_icon = "[initial(dead_icon)]_assisted"

// Brain is defined in brain.dm
/obj/item/organ/internal/handle_germ_effects(cycles)
	. = ..() //Should be an interger value for infection level
	if(!.) return

	var/antibiotics = owner.factor(BF_ANTIMICROBIAL)

	if(. >= 2 && antibiotics < ANTIBIO_NORM) //INFECTION_LEVEL_TWO
		if (prob(3))
			apply_lesion_damage(1, /datum/affliction/lesion/necrosis, prob(30))

	if(. >= 3 && antibiotics < ANTIBIO_OD)	//INFECTION_LEVEL_THREE
		if (prob(50))
			apply_lesion_damage(1, /datum/affliction/lesion/necrosis, prob(15))
