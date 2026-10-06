/obj/structure/tanning_rack
	name = "tanning rack"
	desc = "A rack used to stretch leather out and hold it taut during the tanning process."
	icon = 'icons/obj/kitchen.dmi'
	icon_state = "spike"


/// The leather hung on the rack.
OM_FIELD_VIEW(/obj/structure/tanning_rack, obj/item/stack/wetleather, drying, CHANGE_EXPLICIT)
/// Holds wet leather: periodic_step() dries it (DECLARE_PERIODIC_WHILE). Adding wet leather raises
/// its view (and the leather's wetness, a cross-entity input) re-evaluates it.
OM_DERIVE_FIELD(/obj/structure/tanning_rack, has_wet_leather, list("drying", "drying.wetness"))
DECLARE_PERIODIC_WHILE(/obj/structure/tanning_rack, PERIODIC_SLOW, "has_wet_leather") // SSObj fires ~every 2s , starting from wetness 30 takes ~1m

/obj/structure/tanning_rack/proc/has_wet_leather()
	var/obj/item/stack/wetleather/W = drying()
	return !QDELETED(W) && W.wetness

/// Dries its leather while it holds wet leather; otherwise it sleeps until some is hung on it.
/obj/structure/tanning_rack/periodic_step()
	if(QDELETED(drying()))
		rel_clear(src, nameof(drying))
		return
	drying().set_wetness(max(drying().wetness - 1, 0))
	if(!drying().wetness)
		visible_message("The [drying()] is dry!")

/obj/structure/tanning_rack/examine(mob/user)
	. = ..()
	if(drying() && !QDELETED(drying()))
		. += "\The [drying()] is [drying().get_dryness_text()]."

/obj/structure/tanning_rack/draw(datum/look/look)
	..()
	if(drying())
		if(drying().wetness)
			look.overlay("leather_wet")
		else
			look.overlay("leather_dry")

/// Old attackby.
/obj/structure/tanning_rack/proc/interaction_item(mob/user, atom/A, datum/interaction/interaction)
	if(istype(A, /obj/item/stack/wetleather))
		if(!drying()) // If not drying anything, start drying the thing
			if(user.unEquip(A, target = src))
				rel_set(src, nameof(drying), A)
		else // Drying something, add if possible
			var/obj/item/stack/wetleather/W = A
			W.transfer_to(drying(), W.get_amount(), TRUE)
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
		rel_clear(src, nameof(drying))
	return TRUE

/obj/structure/tanning_rack
	silicon_use = ROBOT_USE_HAND // attack_hand has the adjacency checks

/// the drying this refers to (a relation view: null once it is deleted).
/obj/structure/tanning_rack/proc/drying() as /obj/item/stack/wetleather
	return drying
