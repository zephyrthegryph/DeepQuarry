/obj/structure/alien //Gurg Addition, framework for alien structures.
	name = "alien thing"
	desc = "There's something alien about this."
	icon = 'icons/mob/alien.dmi'
	layer = ABOVE_JUNK_LAYER
	max_integrity = 50
	unacidable = TRUE
	anchored = TRUE

/obj/structure/alien/atom_destruction(damage_flag)
	set_density(0)
	return ..()

/obj/structure/alien/bullet_act(obj/item/projectile/Proj)
	take_damage(Proj.damage, Proj.damage_type, BULLET)
	return ..()

/obj/structure/alien/ex_act(severity)
	switch(severity)
		if(1.0)
			take_damage(50, BRUTE, BOMB)
		if(2.0)
			take_damage(50, BRUTE, BOMB)
		if(3.0)
			if (prob(50))
				take_damage(50, BRUTE, BOMB)
			else
				take_damage(25, BRUTE, BOMB)
	return

/obj/structure/alien/hitby(atom/movable/source, datum/thrownthing/throwingdatum)
	visible_message(span_danger("\The [src] was hit by \the [source]."))
	var/tforce
	if(ismob(source))
		tforce = 15
	else if(isobj(source))
		var/obj/object = source
		if(isitem(object))
			var/obj/item/our_item = object
			tforce = our_item.throwforce
		else
			tforce = object.w_class
	playsound(loc, 'sound/effects/attackblob.ogg', 100, 1)
	take_damage(tforce, BRUTE, MELEE, sound_effect = FALSE)
	..()
	return

/obj/structure/alien/attack_generic(mob/user, damage, attack_verb)
	visible_message(span_danger("[user] [attack_verb] the [src]!"))
	playsound(src, 'sound/effects/attackblob.ogg', 100, 1)
	user.do_attack_animation(src)
	take_damage(damage, BRUTE, MELEE, sound_effect = FALSE)
	return

/obj/structure/alien/attackby(obj/item/W as obj, mob/user as mob)

	user.setClickCooldown(user.get_attack_speed(W))
	playsound(src, 'sound/effects/attackblob.ogg', 100, 1)
	visible_message(span_danger("[user] attacks the [src]!"))
	take_damage(W.force, W.damtype, MELEE, sound_effect = FALSE)
	..()
	return

/obj/structure/alien/attack_hand(mob/user as mob)
	usr.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	if (HULK in usr.mutations)
		visible_message(span_warning("[usr] destroys the [name]!"))
		take_damage(get_integrity(), BRUTE, MELEE, sound_effect = FALSE)
	else

		// Aliens can get straight through these.
		if(istype(usr,/mob/living/carbon))
			if(user.a_intent == I_HURT)
				var/mob/living/carbon/M = usr
				if(locate(/obj/item/organ/internal/xenos/hivenode) in M.internal_organs)
					visible_message (span_warning("[usr] strokes the [name] and it melts away!"), 1)
					take_damage(get_integrity(), BRUTE, MELEE, sound_effect = FALSE)
					return
				if(locate(/obj/item/organ/internal/xenos/resinspinner/replicant) in M.internal_organs)
					if(!do_after(M, 3 SECONDS, src))
						return
					visible_message (span_warning("[usr] strokes the [name] and it melts away!"), 1)
					take_damage(get_integrity(), BRUTE, MELEE, sound_effect = FALSE)
					return
			visible_message(span_warning("[usr] claws at the [name]!"))
			take_damage(rand(5,10), BRUTE, MELEE, sound_effect = FALSE)
	return

/obj/structure/alien/CanPass(atom/movable/mover, turf/target, height=0, air_group=0)
	if(air_group) return 0
	if(istype(mover) && mover.checkpass(PASSGLASS))
		return !opacity
	return !density
