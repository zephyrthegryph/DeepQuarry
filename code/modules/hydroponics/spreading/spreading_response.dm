/obj/effect/plant/HasProximity(turf/T, WF, old_loc)
	if(isnull(WF))
		return
	var/atom/movable/AM = WF
	if(isnull(AM))
		log_runtime("DEBUG: HasProximity called without reference on [src].")
		return
	if(!is_mature() || seed().get_trait(TRAIT_SPREAD) != 2)
		return

	var/mob/living/M = AM
	if(!istype(M))
		return

	if(M.is_incorporeal()) // Don't buckle phased entities.
		return

	if(!has_buckled_mobs() && !M?.buckled_to() && !M.anchored && (issmall(M) || prob(round(seed().get_trait(TRAIT_POTENCY)/3))))
		//wait a tick for the Entered() proc that called HasProximity() to finish (and thus the moving animation),
		//so we don't appear to teleport from two tiles away when moving into a turf adjacent to vines.
		after(src, 0.1 SECONDS, PROC_REF(entangle), with = list(M))

/obj/effect/plant/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()
	if(seed().get_trait(TRAIT_SPREAD)==2)
		if(isturf(old_loc))
			unsense_proximity(callback = TYPE_PROC_REF(/atom,HasProximity), center = old_loc)
		if(isturf(loc))
			sense_proximity(callback = TYPE_PROC_REF(/atom,HasProximity))

/obj/effect/plant/attack_generic(mob/user)
	manual_unbuckle(user)

/obj/effect/plant/Crossed(atom/movable/O)
	if(O.is_incorporeal())
		return
	if(isliving(O))
		trodden_on(O)

/obj/effect/plant/proc/trodden_on(mob/living/victim)
	if(!is_mature())
		return
	var/mob/living/carbon/human/H = victim
	if(prob(round(seed().get_trait(TRAIT_POTENCY)/3)))
		entangle(victim)
	if(istype(H) && H.get_equipped_item(SLOT_ID_SHOES))
		return
	seed().do_thorns(victim,src)
	seed().do_sting(victim,src,pick(BP_R_FOOT,BP_L_FOOT,BP_R_LEG,BP_L_LEG))

	if(seed().get_trait(TRAIT_SPORING) && prob(round(seed().get_trait(TRAIT_POTENCY)/2)))
		seed().create_spores(get_turf(victim))

/obj/effect/plant/proc/unbuckle()
	unbuckle_all_mobs(TRUE)
	return

/obj/effect/plant/proc/manual_unbuckle(mob/user as mob)
	if(has_buckled_mobs())
		var/chance = 20
		if(seed())
			chance = round(100/(20*seed().get_trait(TRAIT_POTENCY)/100))
		if(prob(chance))
			for(var/mob/living/L as anything in src?.buckled_mob_list())
				if(!(user in src?.buckled_mob_list()))
					act_message(L, user, MSG_SELF(span_infoplain(span_bold("%T%") + " frees you from \the [src].")), \
						MSG_OTHERS(span_infoplain(span_bold("%T%") + " frees %U% from \the [src].")), \
						MSG_BLIND(span_warning("You hear shredding and ripping.")))
				else
					act_message(L, src, MSG_SELF(span_notice("You untangle %T% from around yourself.")), \
						MSG_OTHERS(span_infoplain(span_bold("%U%") + " struggles free of %T%.")), \
						MSG_BLIND(span_warning("You hear shredding and ripping.")))
				unbuckle()
		else
			user.setClickCooldown(user.get_attack_speed())
			set_health(health - rand(1,5))
			var/text = pick("rip","tear","pull", "bite", "tug")
			act_message(user, src, MSG_SELF(span_warning("You [text] at %T%.")), \
				MSG_OTHERS(span_warning("%U% [text]s at %T%.")), \
				MSG_BLIND(span_warning("You hear shredding and ripping.")))
			check_health()
			return

/obj/effect/plant/proc/entangle(mob/living/victim)

	if(has_buckled_mobs())
		return

	if(!victim || victim.buckled_to() || victim.anchored)
		return

	//grabbing people
	if(!victim.anchored && Adjacent(victim) && victim.loc != src.loc)
		var/can_grab = 1
		if(ishuman(victim))
			var/mob/living/carbon/human/H = victim
			if(istype(H.get_equipped_item(SLOT_ID_SHOES), /obj/item/clothing/shoes/magboots) && (H.get_equipped_item(SLOT_ID_SHOES).item_flags & NOSLIP))
				can_grab = 0
		if(can_grab)
			src.visible_message(span_danger("Tendrils lash out from \the [src] and drag \the [victim] in!"))
			victim.forceMove(src.loc)
			buckle_mob(victim)
			victim.set_dir(pick(GLOB.cardinal))
			to_chat(victim, span_danger("Tendrils [pick("wind", "tangle", "tighten")] around you!"))
			victim.status_at_least(STAT_WEAKENED, 0.5)
			seed().do_thorns(victim,src)
