CAPABILITIES(/obj/item/picky)
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

/obj/item/picky/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	if(!istype(I, /obj/item/pen))
		return OP_DECLINE
	if(user.incapacitated()) return OP_DECLINE
	to_chat(user, "inked")
	return TRUE
