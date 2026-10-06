/obj/structure/snowman
	name = "snowman"
	icon = 'icons/obj/snowman.dmi'
	icon_state = "snowman"
	desc = "A happy little snowman smiles back at you!"
	anchored = TRUE

CAPABILITIES(/obj/structure/snowman)
	// the old attack_hand: crumple the snowman (combat mode only)
	op("crush", hand(), stance(I_HURT), label("Crush"), then(PROC_REF(snowman_crushed)))

/obj/structure/snowman/proc/snowman_crushed(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_notice("In one hit, [src] easily crumples into a pile of snow. You monster."))
	var/turf/simulated/floor/F = get_turf(src)
	if (istype(F))
		new /obj/item/stack/material/snow(F)
	consume(src, user)
	return OP_OK

/obj/structure/snowman/borg
	name = "snowborg"
	icon_state = "snowborg"
	desc = "A snowy little robot. It even has a monitor for a head."

/obj/structure/snowman/spider
	name = "snow spider"
	icon_state = "snowspider"
	desc = "An impressively crafted snow spider. Not nearly as creepy as the real thing."
