/obj/structure/tanning_rack
	name = "tanning rack"
	desc = "A rack used to stretch leather out and hold it taut during the tanning process."
	icon = 'icons/obj/kitchen.dmi'
	icon_state = "spike"

	var/tmp/obj/item/stack/wetleather/drying

DECLARE_PERIODIC(/obj/structure/tanning_rack, PERIODIC_SLOW) // SSObj fires ~every 2s , starting from wetness 30 takes ~1m

/// Dries its leather while it holds wet leather; otherwise it sleeps until some is hung on it.
/obj/structure/tanning_rack/periodic_step()
	if(QDELETED(drying()))
		rel_clear(src, "drying")
		return PROCESS_KILL
	if(!drying().wetness)
		return PROCESS_KILL
	if(drying() && drying().wetness)
		drying().wetness = max(drying().wetness - 1, 0)
		if(!drying().wetness)
			visible_message("The [drying()] is dry!")
			update_icon()

/obj/structure/tanning_rack/examine(mob/user)
	. = ..()
	if(drying() && !QDELETED(drying()))
		. += "\The [drying()] is [drying().get_dryness_text()]."

/obj/structure/tanning_rack/update_icon()
	cut_overlays()
	if(drying())
		if(drying().wetness)
			add_overlay("leather_wet")
		else
			add_overlay("leather_dry")

/// Old attackby.
/obj/structure/tanning_rack/proc/interaction_item(mob/user, atom/A, datum/interaction/interaction)
	if(istype(A, /obj/item/stack/wetleather))
		if(!drying()) // If not drying anything, start drying the thing
			if(user.unEquip(A, target = src))
				rel_set(src, "drying", A)
				om_task_periodic(src, PERIODIC_SLOW)
		else // Drying something, add if possible
			var/obj/item/stack/wetleather/W = A
			W.transfer_to(drying(), W.get_amount(), TRUE)
			om_task_periodic(src, PERIODIC_SLOW)
		update_icon()
		return TRUE
	return FALSE

DECLARE_INTERACTIONS(/obj/structure/tanning_rack, \
	INTERACT_HAND_UNGATED(null, PROC_REF(interaction_hand)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
)

/// Old attack_hand.
/obj/structure/tanning_rack/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	if(drying())
		var/obj/item/stack/S = drying()
		if(!drying().wetness) // If it's dry, make a stack of dry leather and prepare to put that in their hands
			var/obj/item/stack/material/leather/L = new(src, drying().get_amount())
			drying().set_amount(0)
			S = L

		if(ishuman(user))
			var/mob/living/carbon/human/H = user
			if(!H.put_in_any_hand_if_possible(S))
				S.forceMove(get_turf(src))
		else
			S.forceMove(get_turf(src))
		rel_clear(src, "drying")
		update_icon()
	return TRUE

/obj/structure/tanning_rack
	silicon_use = ROBOT_USE_HAND // attack_hand has the adjacency checks

/// the drying this refers to (a relation view: null once it is deleted).
/obj/structure/tanning_rack/proc/drying() as /obj/item/stack/wetleather
	return drying
