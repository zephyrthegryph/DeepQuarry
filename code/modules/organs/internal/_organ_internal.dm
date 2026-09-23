/****************************************************
				INTERNAL ORGANS DEFINES
****************************************************/
/obj/item/organ/internal
	var/dead_icon // Icon to use when the organ has died.

	var/supply_conversion_value = 0

/obj/item/organ/internal/Initialize(mapload, internal)
	. = ..()
	if(supply_conversion_value)
		AddElement(/datum/element/sellable/organ)

/obj/item/organ/internal/die()
	..()
	if((status & ORGAN_DEAD) && dead_icon)
		icon_state = dead_icon

/obj/item/organ/internal/Destroy()
	if(owner)
		owner.internal_organs -= src
		owner.internal_organs_by_name -= organ_tag
		var/obj/item/organ/external/E = owner.organs_by_name[parent_organ]
		if(istype(E)) E.internal_organs -= src
	return ..()

/obj/item/organ/internal/remove_rejuv()
	if(owner)
		owner.internal_organs -= src
		owner.internal_organs_by_name -= organ_tag
		var/obj/item/organ/external/E = owner.organs_by_name[parent_organ]
		if(istype(E)) E.internal_organs -= src
	..()

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
/obj/item/organ/internal/handle_germ_effects()
	. = ..() //Should be an interger value for infection level
	if(!.) return

	var/antibiotics = owner.factor(BF_ANTIMICROBIAL)

	if(. >= 2 && antibiotics < ANTIBIO_NORM) //INFECTION_LEVEL_TWO
		if (prob(3))
			apply_lesion_damage(1, /datum/affliction/lesion/necrosis, prob(30))

	if(. >= 3 && antibiotics < ANTIBIO_OD)	//INFECTION_LEVEL_THREE
		if (prob(50))
			apply_lesion_damage(1, /datum/affliction/lesion/necrosis, prob(15))
