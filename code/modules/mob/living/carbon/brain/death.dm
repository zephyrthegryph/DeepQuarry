/mob/living/carbon/brain/get_death_message(gibbed)
	if(istype(container, /obj/item/mmi))
		return "beeps shrilly as the MMI flatlines!"
	return DEATHGASP_NO_MESSAGE

/mob/living/carbon/brain/on_death(gibbed)
	. = ..()
	if(!gibbed && istype(container, /obj/item/mmi)) //If not gibbed but in a container.
		container.icon_state = "mmi_dead"

/mob/living/carbon/brain/gib()
	if(istype(container, /obj/item/mmi))
		destroyed(container, src, BRUTE)//Gets rid of the MMI if there is one
	if(loc)
		if(istype(loc,/obj/item/organ/internal/brain))
			destroyed(loc, src, BRUTE)//Gets rid of the brain item
	..(null,1)
