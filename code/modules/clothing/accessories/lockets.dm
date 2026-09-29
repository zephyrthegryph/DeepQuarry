/obj/item/clothing/accessory/locket
	name = "silver locket"
	desc = "A small locket of high-quality metal."
	icon_state = "locket"
	drop_sound = 'sound/items/drop/ring.ogg'
	pickup_sound = 'sound/items/pickup/ring.ogg'
	w_class = ITEMSIZE_SMALL
	slot_flags = SLOT_MASK | SLOT_TIE
	slot = ACCESSORY_SLOT_DECOR
	var/base_icon
	var/open
	var/tmp/held_handle	//Item inside locket.
	special_handling = TRUE

EXTEND_INTERACTIONS(/obj/item/clothing/accessory/locket, \
	INTERACT_USE("Flip open", PROC_REF(locket_flip_self)), \
	INTERACT_ITEM(null, PROC_REF(locket_insert_item)), \
)

/// Old attack_self: flip the locket open or closed.
/obj/item/clothing/accessory/locket/proc/locket_flip_self(mob/user, obj/item/held_item, datum/interaction/interaction)
	if(!base_icon)
		base_icon = icon_state

	if(!icon_exists(icon, "[base_icon]_open"))
		to_chat(user, "\The [src] doesn't seem to open.")
		return

	open = !open
	to_chat(user, "You flip \the [src] [open?"open":"closed"].")
	if(open)
		icon_state = "[base_icon]_open"
		if(held())
			to_chat(user, "\The [held()] falls out!")
			held().forceMove(get_turf(user))
			held_handle = null
	else
		icon_state = "[base_icon]"

/// Old attackby: slip a paper or photo inside.
/obj/item/clothing/accessory/locket/proc/locket_insert_item(mob/user, obj/item/O, datum/interaction/interaction)
	if(!open)
		to_chat(user, "You have to open it first.")
		return INTERACTION_HANDLED_PASS

	if(istype(O,/obj/item/paper) || istype(O, /obj/item/photo))
		if(held())
			to_chat(user, "\The [src] already has something inside it.")
		else
			to_chat(user, "You slip [O] into [src].")
			user.drop_item()
			O.forceMove(src)
			held_handle = om_handle(O)
		return INTERACTION_HANDLED_PASS
	return FALSE

/// LC-refs: Item inside locket. -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/item/clothing/accessory/locket/proc/held() as /obj/item
	return om_resolve(held_handle)
