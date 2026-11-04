/obj/structure/bed/roller/massage
	name = "massage bed"
	desc = "A portable bed-on-wheels wish extra padding for getting people comfortable for massages. It can be locked in place (with alt-click)."
	icon = 'icons/obj/entrepreneur.dmi'
	icon_state = "rollerbed"
	rollertype = /obj/item/roller/massage
	bedtype = /obj/structure/bed/roller/massage

CAPABILITIES(/obj/structure/bed/roller/massage)
	op("alt", hand(), ungated(), gesture(GESTURE_ALT), label("Alternate use"), then(PROC_REF(interaction_alt)))

/// Old click_alt.
/obj/structure/bed/roller/massage/proc/interaction_alt(datum/act/op/A)
	var/mob/living/carbon/user = A.actor
	if(anchored)
		set_anchored(0)
		act_message(user, src, others = span_notice("%U% turns the breaks off on %T%!"))
	else if(!anchored)
		set_anchored(1)
		act_message(user, src, others = span_notice("%U% turns the breaks on for %T%!"))
	return TRUE

/obj/structure/bed/roller/massage/buckle_mob(mob/living/M)
	..()
	M.set_dir(1)
