/obj/structure/tanning_rack
	name = "tanning rack"
	desc = "A rack used to stretch leather out and hold it taut during the tanning process."
	icon = 'icons/obj/kitchen.dmi'
	icon_state = "spike"


/// The leather hung on the rack.
OM_FIELD_VIEW(/obj/structure/tanning_rack, obj/item/stack/wetleather, drying, CHANGE_EXPLICIT)
CAPABILITIES(/obj/structure/tanning_rack)
	/// Holds wet leather: dries it every 2 s (starting from wetness 30 it takes about a minute); the gate is polled, the leather's wetness is another entity's state.
	every(2 SECONDS, then(PROC_REF(tanning_rack_step)), when = nameof(drying))
	op("hand", hand(), ungated(), then(PROC_REF(interaction_hand)))
	op("item", item(/obj/item), then(PROC_REF(interaction_item)))

/// Dries its leather while it holds wet leather.
/obj/structure/tanning_rack/proc/tanning_rack_step(datum/act/timer/A)
	if(QDELETED(drying()))
		rel_clear(src, nameof(drying))
		return
	if(!drying().wetness)
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
/obj/structure/tanning_rack/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/held = A.held
	if(istype(held, /obj/item/stack/wetleather))
		if(!drying()) // If not drying anything, start drying the thing
			if(user.unEquip(held, target = src))
				rel_set(src, nameof(drying), held)
		else // Drying something, add if possible
			var/obj/item/stack/wetleather/W = held
			W.transfer_to(drying(), W.get_amount(), TRUE)
		return OP_OK
	return OP_DECLINE

/// Old attack_hand.
/obj/structure/tanning_rack/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
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
	return OP_OK

/obj/structure/tanning_rack
	silicon_use = ROBOT_USE_HAND // attack_hand has the adjacency checks

/// the drying this refers to (a relation view: null once it is deleted).
/obj/structure/tanning_rack/proc/drying() as /obj/item/stack/wetleather
	return drying
