//Pounce stuff for K-9
/obj/item/dogborg/pounce
	name = "pounce"
	icon = 'icons/mob/dogborg_vr.dmi'
	icon_state = "pounce"
	desc = "Leap at your target to momentarily stun them."
	var/bluespace = FALSE
	flags = NOBLUDGEON

CAPABILITIES(/obj/item/dogborg/pounce)
	configure(item_thrown(force = 0))
	configure(item_combat(force = 0))
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/dogborg/pounce/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	var/mob/living/silicon/robot/R = user
	R.leap(bluespace)
	return TRUE
