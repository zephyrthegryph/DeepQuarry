/obj/item/offhand
	icon = 'icons/obj/weapons.dmi'
	icon_state = "offhand"
	name = "offhand that shouldn't exist doo dee doo"
	w_class = ITEMSIZE_NO_CONTAINER

/obj/item/offhand/crushergauntlets
	var/tmp/obj/item/kinetic_crusher/machete/gauntlets/linked

CAPABILITIES(/obj/item/offhand/crushergauntlets)
	ref_one(nameof(linked))

/obj/item/offhand/crushergauntlets/dropped(mob/user, equipping, slot)
	SHOULD_CALL_PARENT(FALSE)
	if(linked().wielded)
		linked().ready_toggle(TRUE)

/// Accessor for the linked var.
/obj/item/offhand/crushergauntlets/proc/linked() as /obj/item/kinetic_crusher/machete/gauntlets
	return linked
