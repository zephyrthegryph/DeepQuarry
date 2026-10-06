//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:32

/obj/item/storage/lockbox
	name = "lockbox"
	desc = "A locked box."
	icon_state = "lockbox+l"
	item_state_slots = list(slot_r_hand_str = "syringe_kit", slot_l_hand_str = "syringe_kit")
	w_class = ITEMSIZE_LARGE
	max_storage_space = ITEMSIZE_COST_NORMAL * 4 //The sum of the w_classes of all the items in this storage item.
	req_access = list(ACCESS_ARMORY)
	preserve_item = 1
	var/broken = 0
	var/icon_locked = "lockbox+l"
	var/icon_closed = "lockbox"
	var/icon_broken = "lockbox+b"

TRACKED(/obj/item/storage/lockbox, broken)

MSG_DEF_SELF(lockbox/broken, "It appears to be broken.")
MSG_DEF_SELF(lockbox/locked, "It's locked!")

// A lockbox starts locked. An ID with the access locks and unlocks it (locking shuts the window of whoever is looking into it); a broken lock
// stays open for good; locked, it takes nothing and does not open; an energy blade slices the lock open, and an emag shorts it out.
CAPABILITIES(/obj/item/storage/lockbox)
	configure(storage(max_size = ITEMSIZE_NORMAL))
	lock(id_types = list(/obj/item/card/id), starts_locked = TRUE, alt = FALSE)
	emag(then(PROC_REF(on_emag)), repeatable = TRUE)
	extend("lock.toggle", needs(req(PROC_REF(lock_works), because = MSG(lockbox/broken))))
	extend("storage.put_in", when(cond_not(LOCK_LOCKED)))
	extend("storage.refuse", when(cond_not(LOCK_LOCKED)))
	on_change(LOCK_LOCKED, ANY, then(PROC_REF(lock_changed)))
	op("slice", item(/obj/item/melee/energy/blade), when(PROC_REF(blade_can_slice)), label("Slice open"), then(PROC_REF(slice_open)), passes())
	op("locked_click", item(/obj/item), priority(below("storage.put_in")), when(LOCK_LOCKED), label("Put in"), says(MSG(lockbox/locked)), passes())

/// The lock still works: a broken one stays open.
/obj/item/storage/lockbox/proc/lock_works(datum/act/A)
	return !broken

/// Locking it shuts the window of whoever is looking inside; either way it is drawn again.
/obj/item/storage/lockbox/proc/lock_changed(datum/act/A)
	if(lock_locked(src))
		close_all()

/obj/item/storage/lockbox/proc/blade_can_slice(datum/act/op/A)
	return !broken

/// An energy blade slices the lock open; the click goes on (the blade may then go in).
/obj/item/storage/lockbox/proc/slice_open(datum/act/op/A)
	if(break_lock("The locker has been sliced open by [A.actor] with an energy blade!", "You hear metal being sliced and sparks flying."))
		fx_sparks(src.loc, 5, FALSE)
		play_sfx(src, SFX_WEAPONS_BLADE1)
		play_sfx(src, SFX_SPARKS)
	return OP_OK

/obj/item/storage/lockbox/draw(datum/look/look)
	. = ..()
	if(broken)
		look.state(icon_broken)
	else if(lock_locked(src))
		look.state(icon_locked)
	else
		look.state(icon_closed)

/obj/item/storage/lockbox/show_to(mob/user as mob)
	if(lock_locked(src))
		to_chat(user, span_warning("It's locked!"))
	else
		..()
	return

/obj/item/storage/lockbox/proc/on_emag(datum/act/op/A)
	break_lock(null, null, A.actor)
	return OP_OK

/// Breaks the lock open (an emag, or a blade slicing it). Returns 1 if it was still intact.
/obj/item/storage/lockbox/proc/break_lock(visual_feedback, audible_feedback, mob/user)
	if(!broken)
		if(visual_feedback)
			visual_feedback = span_warning("[visual_feedback]")
		else
			visual_feedback = span_warning("The locker has been sliced open by [user] with an electromagnetic card!")
		if(audible_feedback)
			audible_feedback = span_warning("[audible_feedback]")
		else
			audible_feedback = span_warning("You hear a faint electrical spark.")

		set_broken(1)
		key_set(src, LOCK_LOCKED, FALSE)
		desc = "It appears to be broken."
		visible_message(visual_feedback, audible_feedback)
		return 1

/obj/item/storage/lockbox/loyalty
	name = "lockbox of loyalty implants"
	req_access = list(ACCESS_SECURITY)
	starts_with = list(
		/obj/item/implantcase/loyalty = 3,
		/obj/item/implanter/loyalty
	)

/obj/item/storage/lockbox/clusterbang
	name = "lockbox of clusterbangs"
	desc = "You have a bad feeling about opening this."
	req_access = list(ACCESS_SECURITY)
	starts_with = list(/obj/item/grenade/flashbang/clusterbang)

/obj/item/storage/lockbox/medal
	name = "lockbox of medals"
	desc = "A lockbox filled with commemorative medals, it has the NanoTrasen logo stamped on it."
	req_access = list(ACCESS_HEADS)
	storage_slots = 7
	starts_with = list(
		/obj/item/clothing/accessory/medal/conduct,
		/obj/item/clothing/accessory/medal/bronze_heart,
		/obj/item/clothing/accessory/medal/nobel_science,
		/obj/item/clothing/accessory/medal/silver/valor,
		/obj/item/clothing/accessory/medal/silver/security,
		/obj/item/clothing/accessory/medal/gold/captain,
		/obj/item/clothing/accessory/medal/gold/heroism
	)
