//Monster bait for triggering vore interactions without being hostile

/obj/item/toy/monster_bait
	name = "bait toy"
	desc = "A cute little fluffy wiggly worm toy dangling from the end of a stick. Be careful what you wave this in front of!"
	icon = 'icons/obj/items.dmi'
	icon_state = "monster_bait"
	w_class = ITEMSIZE_SMALL

/obj/item/toy/monster_bait/afterattack(atom/A, mob/user)
	var/mob/living/simple_mob/M = A
	if(M.z != user.z || get_dist(user,M) > 1)
		to_chat(user, span_notice("You need to stand right next to \the [M] to bait it."))
		return
	if(!istype(M))
		return
	if(!M.vore_active)
		to_chat(user, span_notice("\The [M] doesn't seem interested in \the [src]."))
		return
	if(M.stat)
		to_chat(user, span_notice("\The [M] doesn't look like it's any condition to do that."))
		return
	act_message(user, src, others = span_danger("%U% waves %T% in front of the [M]!"))
	M.PounceTarget(user,100)
