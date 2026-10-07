/obj/item/roller
	name = "roller"

CAPABILITIES(/obj/item/roller)
	op("self", in_hand(), label("Unfold"), then(PROC_REF(interaction_self)))
	op("hand", hand(), label("Use"), then(PROC_REF(interaction_hand)))
	op("disk", item(/obj/item/disk), label("Tuck in"), then(PROC_REF(interaction_disk)))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

/obj/item/roller/proc/interaction_self(datum/act/op/A)
	EVENT_HANDLER
	var/mob/user = A.actor
	var/obj/item/self_item = A.held
	to_chat(user, "You unfold [self_item].")
	return FALSE

/obj/item/roller/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, "touched")
	return TRUE

/obj/item/roller/proc/interaction_disk(datum/act/op/A)
	var/obj/item/disk/D = A.held
	qdel(D)
	return TRUE

/obj/item/roller/proc/interaction_item(datum/act/op/A)
	return TRUE
