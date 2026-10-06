/obj/item/nullrod
	name = "null rod"
	desc = "A rod of pure obsidian, its very presence disrupts and dampens the powers of paranormal phenomenae."
	icon_state = "nullrod"
	item_state = "nullrod"
	slot_flags = SLOT_BELT
	force = 15
	throw_speed = 1
	throw_range = 4
	throwforce = 10
	w_class = ITEMSIZE_SMALL
	drop_sound = SFX_ITEMS_DROP_SWORD
	pickup_sound = SFX_ITEMS_PICKUP_SWORD

/obj/item/nullrod/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)

	add_attack_logs(user,M,"Hit with [src] (nullrod)")

	user.setClickCooldown(user.get_attack_speed(src))
	user.do_attack_animation(M)

	if(!user.IsAdvancedToolUser())
		to_chat(user, span_danger("You don't have the dexterity to do this!"))
		return ITEM_INTERACT_FAILURE

	if(CLUMSY_HARM_CHANCE(user))
		to_chat(user, span_danger("The rod slips out of your hand and hits your head."))
		user.injure(INJURY_BLUNT, 10, source = src)
		user.status_at_least(STAT_PARALYZED, 20)
		return ITEM_INTERACT_SUCCESS

	if(M.stat != DEAD)
		if(user?.mind?.assigned_role != JOB_CHAPLAIN)
			to_chat(user, span_danger("You feel that only a chaplain can wield the null rod's true power!"))
			..()
			return ITEM_INTERACT_FAILURE

		if(ishuman(M))
			var/mob/living/carbon/human/infected = M
			if(infected.has_body_effect(/datum/body_effect/redspace_corruption))
				infected.remove_body_effect(/datum/body_effect/redspace_corruption)
				to_chat(user, "You wave [src] over [infected]'s head, and feel a dark presence leave [M.p_their()] body.")
				to_chat(infected, "[user] waves [src] over your head and you feel a dark presence leave your body.")

			if(infected.has_contagion(/datum/affliction/contagion/fleshy_spread))
				for(var/datum/affliction/contagion/fleshy_spread/disease in infected.get_contagions())
					disease.cure()
					break
				to_chat(user, "You wave [src] over [infected]'s head, curing them of their infection.")
				to_chat(infected, "[user] waves [src] over your head, curing you of your infection.")

		//Chaplain null rod removes ALL unholy traits.
		remove_traits_in(M, UNHOLY_TRAIT)

		if(GLOB.cult && (M.mind in GLOB.cult.current_antagonists) && prob(33))
			to_chat(M, span_danger("The power of [src] clears your mind of the cult's influence!"))
			to_chat(user, span_danger("You wave [src] over [M]'s head and see their eyes become clear, their mind returning to normal."))
			GLOB.cult.remove_antagonist(M.mind)
			act_message(user, M, others = span_danger("%U% waves \the [src] over %T%'s head."))
		else
			to_chat(user, span_danger("The rod appears to do nothing."))
			act_message(user, M, others = span_danger("%U% waves \the [src] over %T%'s head."))
		return ITEM_INTERACT_SUCCESS

/obj/item/nullrod/afterattack(atom/A, mob/user as mob, proximity)
	if(!proximity)
		return
	if (istype(A, /turf/simulated/floor))
		to_chat(user, span_notice("You hit the floor with the [src]."))
		call(/obj/effect/rune/proc/revealrunes)(src)

/obj/item/energy_net
	name = "energy net"
	desc = "It's a net made of green energy."
	icon = 'icons/effects/effects.dmi'
	icon_state = "energynet"
	throwforce = 0
	force = 0
	var/net_type = /obj/effect/energy_net
	item_flags = DROPDEL

/obj/item/energy_net/throw_impact(atom/hit_atom)
	..()

	var/mob/living/M = hit_atom

	if(!istype(M) || locate_within(M.loc, /obj/effect/energy_net))
		consume(src)
		return 0

	var/turf/T = get_turf(M)
	if(T)
		var/obj/effect/energy_net/net = new net_type(T)
		if(net.buckle_mob(M))
			T.visible_message("[M] was caught in an energy net!")
		if(consume(src))
			return

	// If we miss or hit an obstacle, we still want to delete the net.
	expire(1 SECOND)

/obj/effect/energy_net
	name = "energy net"
	desc = "It's a net made of green energy."
	icon = 'icons/effects/effects.dmi'
	icon_state = "energynet"

	density = TRUE
	opacity = 0
	mouse_opacity = 1
	anchored = FALSE

	can_buckle = TRUE
	buckle_lying = 0
	buckle_dir = SOUTH

	var/escape_time = 8 SECONDS

CAPABILITIES(/obj/effect/energy_net)
	after_init(2 SECONDS, then(PROC_REF(check_empty))) // a net that caught nobody goes away

/obj/effect/energy_net/proc/check_empty(datum/act/A)
	if(!has_buckled_mobs())
		consume(src)

// netted mobs are told they're free.
/obj/effect/energy_net/lifecycle_prerelease()
	..()
	if(has_buckled_mobs())
		for(var/A in src?.buckled_mob_list())
			to_chat(A, span_notice("You are free of the net!"))
			unbuckle_mob(A)

/obj/effect/energy_net/user_unbuckle_mob(mob/living/buckled_mob, mob/user)
	user.setClickCooldown(user.get_attack_speed())
	act_message(user, src, others = span_danger("%U% begins to tear at %T%!"))
	om_task_timed(user, escape_time, target = src, timed_action_flags = IGNORE_INCAPACITATED, receiver = src, on_done = PROC_REF(user_unbuckle_mob_timed_done), done_args = list(buckled_mob, user))

/obj/effect/energy_net/proc/user_unbuckle_mob_timed_done(mob/living/buckled_mob, mob/user)
	if(!has_buckled_mobs())
		return
	act_message(user, src, others = span_danger("%U% manages to tear %T% apart!"))
	unbuckle_mob(buckled_mob)

/obj/effect/energy_net/post_buckle_mob(mob/living/M)
	if(M?.buckled_to() == src) //Just src?.buckled_to() someone
		..()
		layer = M.layer+1
		M.can_pull_size = 0
	else //Just unbuckled someone
		M.can_pull_size = initial(M.can_pull_size)
		consume(src)

/obj/item/energy_net/shrink
	name = "compactor energy net"
	desc = "It's a net made of cyan energy."
	icon_state = "shrinkenergynet"
	net_type = /obj/effect/energy_net/shrink

/obj/effect/energy_net/shrink
	name = "compactor energy net"
	desc = "It's a net made of cyan energy."
	icon_state = "shrinkenergynet"

	var/size_increment = 0.01

/obj/effect/energy_net/shrink/periodic_step()
	..()
	for(var/A in src?.buckled_mob_list())
		if(istype(A, /mob/living))
			var/mob/living/L = A
			L.resize((L.size_multiplier - size_increment), uncapped = L.has_large_resize_bounds(), aura_animation = FALSE)
