EXTEND_INTERACTIONS(/obj/item/gap_pet, \
	INTERACT_HAND_AS(I_HELP, "Pet", PROC_REF(interaction_pet)), \
	INTERACT_HAND_UNGATED_AS(I_HURT, "Bite", PROC_REF(interaction_bite)), \
	INTERACT_ITEM_PEACEFUL("Feed", PROC_REF(interaction_feed)), \
	INTERACT_INSERT_DEFAULT(/obj/item/pen, PROC_REF(interaction_insert), "Ink"), \
)

/obj/item/gap_pet/proc/interaction_pet(mob/user, obj/item/held, datum/interaction/interaction)
	if(stat)
		return FALSE
	return INTERACTION_HANDLED_PASS

/obj/item/gap_pet/proc/interaction_bite(mob/user, obj/item/held, datum/interaction/interaction)
	to_chat(user, "bite")
	return TRUE

/obj/item/gap_pet/proc/interaction_feed(mob/user, obj/item/food, datum/interaction/interaction)
	if(!istype(food, /obj/item/reagent_containers/food))
		return FALSE
	if(full)
		return INTERACTION_HANDLED_PASS
	return TRUE

/obj/item/gap_pet/proc/interaction_insert(mob/user, obj/item/pen/pen, datum/interaction/interaction)
	return TRUE
