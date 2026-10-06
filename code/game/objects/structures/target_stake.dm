// Basically they are for the firing range
/obj/structure/target_stake
	name = "target stake"
	desc = "A thin platform with negatively-magnetized wheels."
	icon = 'icons/obj/objects.dmi'
	icon_state = "target_stake"
	density = TRUE
	w_class = ITEMSIZE_HUGE
	var/obj/item/target/pinned_target // the current pinned target

/obj/structure/target_stake/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()
	// Move the pinned target along with the stake
	if(pinned_target in view(3, src))
		pinned_target.forceMove(loc)

	else // Sanity check: if the pinned target can't be found in immediate view
		rel_clear(src, nameof(pinned_target))
		set_density(TRUE)

CAPABILITIES(/obj/structure/target_stake)
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))
	op("hand", hand(), label("Use"), then(PROC_REF(interaction_hand)))

/obj/structure/target_stake/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	// Putting objects on the stake. Most importantly, targets
	if(pinned_target)
		return TRUE // get rid of that pinned target first!

	if(istype(W, /obj/item/target))
		var/atom/destination = loc
		if(!destination)
			return TRUE
		var/reason = own_transfer_refusal(destination, W, null, user)
		if(reason)
			refuse(user, "[capitalize(reason)].")
			return TRUE
		var/atom/source = W.loc
		if(source)
			source.release_to(W, destination, null, user)
		if(W.loc != destination)
			return TRUE
		set_density(FALSE)
		W.set_density(TRUE)
		W.layer = ABOVE_JUNK_LAYER
		rel_set(src, nameof(pinned_target), W)
		to_chat(user, "You slide the target into the stake.")
	return TRUE

/obj/structure/target_stake/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	// taking pinned targets off!
	if(pinned_target)
		set_density(TRUE)
		pinned_target.set_density(FALSE)
		pinned_target.layer = OBJ_LAYER

		pinned_target.forceMove(user.loc)
		if(ishuman(user))
			if(!user.get_active_hand())
				user.put_in_hands(pinned_target)
				to_chat(user, "You take the target out of the stake.")
		else
			pinned_target.forceMove(get_turf(user))
			to_chat(user, "You take the target out of the stake.")

		rel_clear(src, nameof(pinned_target))
	return TRUE

// pinned_target sits on the stake's turf (not in it): a one-sided REL view.

/// Relation teardown clears the pinned target before the target's own hooks run.
/obj/structure/target_stake/reactions()
	. = ..()
	. += on_change(list(nameof(pinned_target)), PROC_REF(pinned_target_changed))

/obj/structure/target_stake/proc/pinned_target_changed(list/keys)
	set_density(!pinned_target)
