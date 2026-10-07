/obj/item/clothing/accessory/locket
	name = "silver locket"
	desc = "A small locket of high-quality metal."
	icon_state = "locket"
	drop_sound = SFX_ITEMS_DROP_RING
	pickup_sound = SFX_ITEMS_PICKUP_RING
	w_class = ITEMSIZE_SMALL
	slot_flags = SLOT_MASK | SLOT_TIE
	slot = ACCESSORY_SLOT_DECOR
	var/base_icon
	var/open
	var/tmp/obj/item/held	//Item inside locket.
	special_handling = TRUE

CAPABILITIES(/obj/item/clothing/accessory/locket)
	op("locket_flip_self", in_hand(), priority(OP_PRIORITY_DEFAULT - 1), label("Flip open"), then(PROC_REF(locket_flip_self)))
	op("locket_insert_item", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Locket insert item"), needs(req_is(nameof(open), TRUE, because = MSG(locket/no_open)), req(PROC_REF(can_insert_keepsake_holds), because = PROC_REF(can_insert_keepsake_refusal))), then(PROC_REF(locket_insert_item)))

MSG_DEF_SELF(locket/no_open, "you have to open it first")

/// Requirement (was REQ_* can_insert_keepsake): the legacy check answers TRUE to pass.
/obj/item/clothing/accessory/locket/proc/can_insert_keepsake_holds(datum/act/op/A)
	var/answer = can_insert_keepsake(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why can_insert_keepsake_holds refuses: the legacy check's text, else the clause's own reason.
/obj/item/clothing/accessory/locket/proc/can_insert_keepsake_refusal(datum/act/op/A)
	var/answer = can_insert_keepsake(A.actor, src, A.held)
	return istext(answer) ? answer : /datum/msg/req_failed

/// Old attack_self: flip the locket open or closed.
/obj/item/clothing/accessory/locket/proc/locket_flip_self(datum/act/op/A)
	var/mob/user = A.actor
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
			rel_clear(src, nameof(held))
	else
		icon_state = "[base_icon]"

/// A paper or photo must be releasable from its current holder before insertion.
/obj/item/clothing/accessory/locket/proc/can_insert_keepsake(mob/user, atom/target, obj/item/held_item)
	if(!istype(held_item, /obj/item/paper) && !istype(held_item, /obj/item/photo))
		return TRUE
	if(held())
		return "the locket already has something inside"
	var/reason = held_item.loc?.release_refusal(held_item, user)
	if(reason)
		return reason
	return TRUE

/// Old attackby: slip a paper or photo inside.
/obj/item/clothing/accessory/locket/proc/locket_insert_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/O = A.held
	if(istype(O,/obj/item/paper) || istype(O, /obj/item/photo))
		if(held())
			to_chat(user, "\The [src] already has something inside it.")
		else
			if(can_insert_keepsake(user, src, O) != TRUE)
				return OP_PASS
			if(!O.loc.release_to(O, src, null, user))
				return OP_PASS
			rel_set(src, nameof(held), O)
			to_chat(user, "You slip [O] into [src].")
		return OP_PASS
	return OP_DECLINE

/// Item inside locket. (a relation view: null once it is deleted).
/obj/item/clothing/accessory/locket/proc/held() as /obj/item
	return held
