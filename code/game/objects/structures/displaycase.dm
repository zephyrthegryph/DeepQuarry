/obj/structure/displaycase
	name = "display case"
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "glassbox1"
	desc = "A display case for prized possessions. It taunts you to kick it."
	density = TRUE
	anchored = TRUE
	unacidable = TRUE//Dissolving the case would also delete the gun.
	max_integrity = 30
	var/occupied = 1
	var/destroyed = 0

/obj/structure/displaycase/ex_act(severity)
	switch(severity)
		if (1)
			new /obj/item/material/shard( src.loc )
			if (occupied)
				new /obj/item/gun/energy/captain( src.loc )
				occupied = 0
			qdel(src)
		if (2)
			if (prob(50))
				take_damage(15, BRUTE, BOMB)
		if (3)
			if (prob(50))
				take_damage(5, BRUTE, BOMB)


/obj/structure/displaycase/bullet_act(obj/item/projectile/Proj)
	take_damage(Proj.get_structure_damage(), Proj.damage_type, BULLET)
	..()
	return

// Glass-on-glass hit sound while the case still stands.
/obj/structure/displaycase/play_attack_sound(damage_amount, damage_type, damage_flag)
	playsound(src, 'sound/effects/Glasshit.ogg', 75, 1)

// Reaching 0 integrity shatters the front glass into a passable, looted shell.
/obj/structure/displaycase/atom_destruction(damage_flag)
	if(!destroyed)
		density = FALSE
		destroyed = 1
		new /obj/item/material/shard( src.loc )
		playsound(src, "shatter", 70, 1)
		update_icon()

/obj/structure/displaycase/update_icon()
	if(src.destroyed)
		src.icon_state = "glassboxb[src.occupied]"
	else
		src.icon_state = "glassbox[src.occupied]"
	return


/obj/structure/displaycase/attackby(obj/item/W as obj, mob/user as mob)
	user.setClickCooldown(user.get_attack_speed(W))
	user.do_attack_animation(src)
	playsound(src, 'sound/effects/Glasshit.ogg', 50, 1)
	take_damage(W.force, W.damtype, MELEE, sound_effect = FALSE)
	..()
	return

/obj/structure/displaycase/attack_hand(mob/user as mob)
	if (src.destroyed && src.occupied)
		new /obj/item/gun/energy/captain( src.loc )
		to_chat(user, span_notice("You deactivate the hover field built into the case."))
		src.occupied = 0
		src.add_fingerprint(user)
		update_icon()
		return
	else
		to_chat(user, span_warning("You kick the display case."))
		for(var/mob/O in oviewers())
			if ((O.client && !( O.blinded )))
				to_chat(O, span_warning("[user] kicks the display case."))
		take_damage(2, BRUTE, MELEE)
		return
