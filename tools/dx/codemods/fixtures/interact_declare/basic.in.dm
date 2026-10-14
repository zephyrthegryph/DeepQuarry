/obj/item/roller
	name = "roller"

DECLARE_INTERACTIONS(/obj/item/roller, \
	INTERACT_USE("Unfold", PROC_REF(interaction_self)), \
	INTERACT_HAND(null, PROC_REF(interaction_hand)), \
	INTERACT_INSERT(/obj/item/disk, PROC_REF(interaction_disk), "Tuck in"), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
)

/obj/item/roller/proc/interaction_self(mob/user, obj/item/self_item, datum/interaction/interaction)
	EVENT_HANDLER
	to_chat(user, "You unfold [self_item].")
	return FALSE

/obj/item/roller/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	to_chat(user, "touched")
	return TRUE

/obj/item/roller/proc/interaction_disk(mob/user, obj/item/disk/D, datum/interaction/interaction)
	qdel(D)
	return TRUE

/obj/item/roller/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	return TRUE
