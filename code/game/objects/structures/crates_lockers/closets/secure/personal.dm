/obj/structure/closet/secure_closet/personal
	name = "personal closet"
	desc = "It's a secure locker for personnel. The first card swiped gains control."
	req_access = list(ACCESS_ALL_PERSONAL_LOCKERS)
	var/registered_name = null
	/* // Removal
	starts_with = list(
		/obj/item/radio/headset)
	*/

/obj/structure/closet/secure_closet/personal/patient
	name = "patient's closet"
	closet_appearance = /datum/decl/closet_appearance/secure_closet/patient
	starts_with = list(
		/obj/item/clothing/under/medigown,
		/obj/item/clothing/under/color/white,
		/obj/item/clothing/shoes/white)

/obj/structure/closet/secure_closet/personal/cabinet
	closet_appearance = /datum/decl/closet_appearance/cabinet/secure
	open_sound = SFX_EFFECTS_WOODEN_CLOSET_OPEN
	close_sound = SFX_EFFECTS_WOODEN_CLOSET_CLOSE
	starts_with = list(
		/obj/item/storage/backpack/satchel/withwallet,
		/obj/item/radio/headset
		)

MSG_DEF_SELF(personal/blank_card, "That card has no name on it.")
MSG_DEF_SELF(personal/unlock_first, "You need to unlock it first.")

// The first ID swiped on a personal locker gains control of it: its name is the owner's, and only that card (or the master access) locks and unlocks it
// from then on. The Reset Lock entry frees it for the next card.
CAPABILITIES(/obj/structure/closet/secure_closet/personal)
	op("swipe", item(/obj/item), label("Swipe ID"), when(cond_not(nameof(opened))), when(req(PROC_REF(carries_id))), priority(above("lock.toggle")),
		needs(req_is(nameof(broken), FALSE, because = MSG(secure_closet/broken)), req(PROC_REF(card_has_name), because = MSG(personal/blank_card))), then(PROC_REF(card_swiped)))
	op("reset_lock", menu(), label("Reset Lock"), needs(req_capable(), req(PROC_REF(can_reset), because = PROC_REF(reset_refusal))), then(PROC_REF(lock_reset)))

/// The held item is, or carries, an ID card.
/obj/structure/closet/secure_closet/personal/proc/carries_id(datum/act/op/A)
	return !!A.held?.GetID()

/// The card has a name on it.
/obj/structure/closet/secure_closet/personal/proc/card_has_name(datum/act/op/A)
	var/obj/item/card/id/I = A.held?.GetID()
	return !!I?.registered_name

/// A swipe: the master access, an unowned locker or the owner's own card works the lock, and the first card swiped claims it.
/obj/structure/closet/secure_closet/personal/proc/card_swiped(datum/act/op/A)
	var/obj/item/card/id/I = A.held.GetID()
	if(allowed(A.actor) || !registered_name || (istype(I) && registered_name == I.registered_name))
		//they can open all lockers, or nobody owns this, or they own this locker
		force_lock(!lock_locked(src))
		if(!registered_name)
			registered_name = I.registered_name
			desc = "Owned by [I.registered_name]."
		return OP_OK
	A.reason = /datum/msg/lock/denied
	return OP_REFUSED

/obj/structure/closet/secure_closet/personal/break_lock(mob/user, obj/item/emag_source, visual_feedback, audible_feedback)
	if(!broken)
		set_broken(TRUE)
		force_lock(FALSE)
		desc = "It appears to be broken."
		if(visual_feedback)
			visible_message(span_warning("[visual_feedback]"), span_warning("[audible_feedback]"))
		return 1

/// An unlocked, owned locker that is not broken can be reset.
/obj/structure/closet/secure_closet/personal/proc/can_reset(datum/act/A)
	return !lock_locked(src) && registered_name && !broken // ALLOW(reads): who owns it and whether it is locked is read when the entry is offered and when it is picked

/obj/structure/closet/secure_closet/personal/proc/reset_refusal(datum/act/A)
	if(lock_locked(src) || !registered_name)
		return /datum/msg/personal/unlock_first
	return /datum/msg/secure_closet/broken

/// Shuts it, locks it and forgets the owner.
/obj/structure/closet/secure_closet/personal/proc/lock_reset(datum/act/op/A)
	add_fingerprint(A.actor)
	if(opened)
		if(!close())
			return OP_REFUSED
	force_lock(TRUE)
	registered_name = null
	desc = "It's a secure locker for personnel. The first card swiped gains control."
	return OP_OK
