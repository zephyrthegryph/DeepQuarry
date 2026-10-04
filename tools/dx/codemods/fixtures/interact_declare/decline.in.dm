DECLARE_INTERACTIONS(/obj/item/picky, INTERACT_ITEM(null, PROC_REF(interaction_item)))

/obj/item/picky/proc/interaction_item(mob/user, obj/item/I, datum/interaction/interaction)
	if(!istype(I, /obj/item/pen))
		return FALSE
	if(user.incapacitated()) return 0
	to_chat(user, "inked")
	return TRUE
