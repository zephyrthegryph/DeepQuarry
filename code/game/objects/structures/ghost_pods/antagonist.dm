//Antagonist ghost pods for potentially self replicating creatures, xenomorphs as one example. These should not naturally spawn on their own.

/obj/structure/ghost_pod/automatic/xenomorph_egg
	name = "xenomorph egg"
	desc = "A disgusting egg dripping with clear ooze, the existence of this is a omen for what is to come."
	description_info = "This contains a growing xenomorph larva, which may wake up at any moment. The larva will be another player, once activated."
	icon = 'icons/mob/alien.dmi'
	icon_state = "egg"
	icon_state_opened = "egg_opened"
	max_integrity = 50 //So they can be destroyed by the crew
	density = FALSE
	ghost_query_type = /datum/ghost_query/xenomorph_larva
	delay_to_try_again = 1 MINUTES //10 minutes for egg to grow, 5 minutes for larva to mature
	anchored = TRUE

/obj/structure/ghost_pod/automatic/xenomorph_egg/create_occupant(mob/M)
	var/mob/living/carbon/alien/larva/R = new(get_turf(src))
	if(M.mind)
		M.mind.transfer_to(R)
	// Description for new larva, so they understand what to expect.
	to_chat(M, span_notice("You are a <b>Xenomorph Larva</b>, freshly slithered out of their egg to serve the hive."))
	to_chat(M, span_boldnotice("Be sure to carefully listen to your queen, as xenomorph egg spawns may act different to loner xenomorph spawns."))
	to_chat(M, span_boldwarning("Remember, you are technically a antagonist. Be sure to learn the context of your existence via IC or ahelp to prevent headaches, and follow the orders of your queen to the letter."))
	to_chat(M, span_notice(" Your life for the hive!"))
	R.ckey = M.ckey
	visible_message(span_warning("\the [src] peels open, and a fresh larva slithers out!"))
	..()

/obj/structure/ghost_pod/automatic/xenomorph_egg/atom_destruction(damage_flag)
	visible_message(span_warning("\the [src] splatters everywhere as it cracks open!"))
	playsound(src, 'sound/effects/slime_squish.ogg', 50, 1)
	return ..()

/obj/structure/ghost_pod/automatic/xenomorph_egg/attackby(obj/item/W as obj, mob/user as mob)
	user.setClickCooldown(user.get_attack_speed(W))
	playsound(src, 'sound/effects/attackblob.ogg', 50, 1)
	switch(W.obj_damage_type())
		if(BURN)
			receive_weapon_hit(W, user, W.force * 1.25, INJURY_BURN) //It really doesn't like fire
		if(BRUTE)
			receive_weapon_hit(W, user, W.force * 0.75) //Bit hard to cut
	..()
	return

/// Eggs burn easily.
/obj/structure/ghost_pod/automatic/xenomorph_egg/projectile_damage(obj/item/projectile/P, def_zone)
	return receive_projectile(P, def_zone, P.obj_damage_type() == BURN ? 1.5 : 1)
