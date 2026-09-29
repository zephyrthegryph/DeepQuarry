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
		pinned_target = null
		density = TRUE

/obj/structure/target_stake/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_item/target_stake_item,
		/datum/interaction/entry_hand/target_stake_hand,
	)
	..()

/// Old attackby: put a target on the stake.
/datum/interaction/entry_item/target_stake_item
	id = "target_stake_item"
	name = "Use"
	effect = /obj/structure/target_stake/proc/interaction_item

/obj/structure/target_stake/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	// Putting objects on the stake. Most importantly, targets
	if(pinned_target)
		return TRUE // get rid of that pinned target first!

	if(istype(W, /obj/item/target))
		density = FALSE
		W.density = TRUE
		user.remove_from_mob(W)
		W.forceMove(loc)
		W.layer = ABOVE_JUNK_LAYER
		pinned_target = W
		to_chat(user, "You slide the target into the stake.")
	return TRUE

/// Old attack_hand: take pinned targets off.
/datum/interaction/entry_hand/target_stake_hand
	id = "target_stake_hand"
	name = "Use"
	effect = /obj/structure/target_stake/proc/interaction_hand

/obj/structure/target_stake/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	// taking pinned targets off!
	if(pinned_target)
		density = TRUE
		pinned_target.density = FALSE
		pinned_target.layer = OBJ_LAYER

		pinned_target.forceMove(user.loc)
		if(ishuman(user))
			if(!user.get_active_hand())
				user.put_in_hands(pinned_target)
				to_chat(user, "You take the target out of the stake.")
		else
			pinned_target.forceMove(get_turf(user))
			to_chat(user, "You take the target out of the stake.")

		pinned_target = null
	return TRUE

OWN(/obj/structure/target_stake, pinned_target, OWN_CONTAINED)
