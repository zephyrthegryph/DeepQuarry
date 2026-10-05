CAPABILITIES(/obj/item/gap_pet)
	op("pet", hand(), stance(I_HELP), label("Pet"), then(PROC_REF(interaction_pet)))
	op("bite", hand(), ungated(), stance(I_HURT), label("Bite"), then(PROC_REF(interaction_bite)))
	op("feed", item(/obj/item), stance(I_HELP), label("Feed"), then(PROC_REF(interaction_feed)))
	op("insert", item(/obj/item/pen), priority(OP_PRIORITY_DEFAULT), label("Ink"), then(PROC_REF(interaction_insert)))

/obj/item/gap_pet/proc/interaction_pet(datum/act/op/A)
	if(stat)
		return OP_DECLINE
	return OP_PASS

/obj/item/gap_pet/proc/interaction_bite(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, "bite")
	return TRUE

/obj/item/gap_pet/proc/interaction_feed(datum/act/op/A)
	var/obj/item/food = A.held
	if(!istype(food, /obj/item/reagent_containers/food))
		return OP_DECLINE
	if(full)
		return OP_PASS
	return TRUE

/obj/item/gap_pet/proc/interaction_insert(datum/act/op/A)
	return TRUE
