/obj/structure/snowman
	name = "snowman"
	icon = 'icons/obj/snowman.dmi'
	icon_state = "snowman"
	desc = "A happy little snowman smiles back at you!"
	anchored = TRUE

/obj/structure/snowman/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_hand/snowman_crush,
	)
	..()

/// Old attack_hand: crumple the snowman (combat mode only).
/datum/interaction/entry_hand/snowman_crush
	id = "snowman_crush"
	name = "Crush"
	effect = /obj/structure/snowman/proc/interaction_crush
	offered_when = list(REQ_HARMING)
	tags = list(INTERACTION_TAG_HOSTILE)

/obj/structure/snowman/proc/interaction_crush(mob/user, obj/item/held, datum/interaction/interaction)
	to_chat(user, span_notice("In one hit, [src] easily crumples into a pile of snow. You monster."))
	var/turf/simulated/floor/F = get_turf(src)
	if (istype(F))
		new /obj/item/stack/material/snow(F)
	qdel(src)
	return TRUE

/obj/structure/snowman/borg
	name = "snowborg"
	icon_state = "snowborg"
	desc = "A snowy little robot. It even has a monitor for a head."

/obj/structure/snowman/spider
	name = "snow spider"
	icon_state = "snowspider"
	desc = "An impressively crafted snow spider. Not nearly as creepy as the real thing."
