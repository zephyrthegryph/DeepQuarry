//RD 'gun'
/obj/item/bluespace_harpoon
	name = "bluespace harpoon"
	desc = "For climbing on bluespace mountains!"

	icon = 'icons/obj/gun.dmi'
	icon_state = "harpoon-2"

	w_class = ITEMSIZE_NORMAL

	throw_speed = 4
	throw_range = 20


	var/mode = 1  // 1 mode - teleport you to turf  0 mode teleport turf to you
	COOLDOWN_DECLARE(firable)
	var/failure_chance = 15 // This can become negative with part tiers above 3, which helps offset penalties
	var/obj/item/stock_parts/scanning_module/scanmod
	var/dropnoms_active = TRUE

/obj/item/bluespace_harpoon/Initialize(mapload)
	. = ..()
	update_fail_chance()

/obj/item/bluespace_harpoon/examine(mob/user)
	. = ..()
	. += "It is currently in [mode ? "transmitting" : "receiving"] mode."
	. += "Spatial rearrangement is [dropnoms_active ? "active" : "inactive"]."
	if(Adjacent(user))
		. += "It has [scanmod ? scanmod : "no scanner module"] installed."

/obj/item/bluespace_harpoon/proc/update_fail_chance()
	if(scanmod)
		failure_chance = initial(failure_chance) - (scanmod.rating * 5)
	else
		failure_chance = 75 // You can't even use it if there's no scanmod, but why not.

/obj/item/bluespace_harpoon/proc/screwdriver_used(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/item/tool = A.held
	if(!istype(user))
		return OP_OK

	if(!scanmod)
		to_chat(user, span_warning("There's no scanner module installed!"))
		return OP_OK
	var/turf/T = get_turf(src)
	to_chat(user, span_notice("You remove [scanmod] from [src]."))
	playsound(src, tool.usesound, 75, 1)
	scanmod.forceMove(T)
	rel_take(src, nameof(scanmod))
	update_fail_chance()
	return OP_OK

CAPABILITIES(/obj/item/bluespace_harpoon)
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))
	op("fire_mode", in_hand(), label("Change fire mode"), then(PROC_REF(interaction_fire_mode)))
	op("harpoon_verb_fire_mode", menu(), label("Change Fire Mode"), needs(carried()), then(PROC_REF(harpoon_verb_fire_mode_op)))
	op("harpoon_verb_dropnom_mode", menu(), label("Toggle Spatial Rearrangement"), needs(carried()), then(PROC_REF(harpoon_verb_dropnom_mode)))
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), wait(0), then(PROC_REF(screwdriver_used)))

/// The harpoon_verb_fire_mode op: the verb's effect, as the old resolver ran it.
/obj/item/bluespace_harpoon/proc/harpoon_verb_fire_mode_op(datum/act/op/A)
	harpoon_verb_fire_mode(A.actor, A.held)
	return OP_OK

/// Old attackby.
/obj/item/bluespace_harpoon/proc/interaction_item(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/item/I = A.held
	if(!istype(user))
		return OP_PASS

	if(istype(I, /obj/item/stock_parts/scanning_module))
		if(scanmod)
			to_chat(user, span_warning("There's already [scanmod] installed! Remove it first."))
			return OP_PASS
		if(!move_into(src, nameof(src.scanmod), I, user))
			return OP_PASS
		to_chat(user, span_notice("You install [scanmod] into [src]."))
		update_fail_chance()
	else
		return OP_DECLINE
	return OP_PASS

/obj/item/bluespace_harpoon/afterattack(atom/A, mob/user as mob)
	if(!user || !A || isstorage(A))
		return
	if(!scanmod)
		to_chat(user,span_warning("The scanning module has been removed from [src]!"))
		return
	if(!COOLDOWN_FINISHED(src, firable))
		to_chat(user,span_warning("\The [src] is recharging..."))
		return
	if(is_jammed(A) || is_jammed(user))
		COOLDOWN_START(src, firable, 30 SECONDS)
		to_chat(user,span_warning("\The [src] shot fizzles due to interference!"))
		play_sfx(src, SFX_WEAPONS_WAVE, vary = TRUE)
		return
	var/turf/T = get_turf(A)
	if(!T || (T.check_density(ignore_mobs = TRUE) && mode == 1))
		to_chat(user,span_warning("That's a little too solid to harpoon into!"))
		return
	var/turf/ownturf = get_turf(src)
	if(ownturf.z != T.z || get_dist(T,ownturf) > world.view)
		to_chat(user, span_warning("The target is out of range!"))
		return
	if((get_area(A).flag_check(BLUE_SHIELDED)) || (T.block_tele) || (ownturf.block_tele)) // consistency smh
		to_chat(user, span_warning("The target area protected by bluespace shielding!"))
		return
	if(!(A in view(user, world.view)))
		to_chat(user, span_warning("Harpoon fails to lock on the obstructed target!"))
		return

	COOLDOWN_START(src, firable, 30 SECONDS)
	play_sfx(src, SFX_WEAPONS_WAVE, vary = TRUE)

	act_message(user, src, MSG_SELF(span_warning("You fire %T%!")), MSG_OTHERS(span_warning("%U% fires %T%!")))

	fx_sparks(A, 4)
	fx_sparks(user, 4)

	var/turf/FromTurf = mode ? get_turf(user) : get_turf(A)
	var/turf/ToTurf = mode ? get_turf(A) : get_turf(user)

	var/recievefailchance = failure_chance
	var/sendfailchance = failure_chance
	if(isliving(user))
		var/mob/living/L = user
		if(LAZYLEN(L?.buckled_mob_list()))
			for(var/rider in L?.buckled_mob_list())
				sendfailchance += 15

	var/mob/living/living_user = user
	var/can_dropnom = TRUE
	if(!dropnoms_active || !istype(living_user))
		can_dropnom = FALSE

	if(mode)
		if(user in FromTurf)
			if(prob(sendfailchance))
				user.forceMove(pick(trange(24,user)))
			else
				user.forceMove(ToTurf)
				var/vore_happened = FALSE
				if(can_dropnom && living_user.can_be_drop_pred)
					var/obj/belly/belly_dest
					if(living_user.vore_selected)
						belly_dest = living_user.vore_selected
					else if(length(living_user.vore_organs))
						belly_dest = pick(living_user.vore_organs)
					if(belly_dest)
						for(var/mob/living/prey in turf_contents_of_type(ToTurf, /mob/living))
							if(can_drop_vore(user, prey))
								prey.forceMove(belly_dest)
								vore_happened = TRUE
								to_chat(prey, span_vdanger("[living_user] materializes around you, as you end up in their [belly_dest]!"))
								to_chat(living_user, span_vnotice("You materialize around [prey] as they end up in your [belly_dest]!"))
				if(can_dropnom && !vore_happened && living_user.can_be_drop_prey)
					var/mob/living/pred
					for(var/mob/living/potential_pred in turf_contents_of_type(ToTurf, /mob/living))
						if(potential_pred != user && potential_pred.can_be_drop_pred)
							pred = potential_pred
					if(pred)
						var/obj/belly/belly_dest
						if(pred.vore_selected)
							belly_dest = pred.vore_selected
						else if(length(pred.vore_organs))
							belly_dest = pick(pred.vore_organs)
						if(belly_dest)
							living_user.forceMove(belly_dest)
							to_chat(pred, span_vnotice("[living_user] materializes inside you as they end up in your [belly_dest]!"))
							to_chat(living_user, span_vdanger("You materialize inside [pred] as you end up in their [belly_dest]!"))

	else
		for(var/obj/O in turf_contents_of_type(FromTurf, /obj))
			if(O.anchored) continue
			if(prob(recievefailchance))
				O.forceMove(pick(trange(24,user)))
			else
				O.forceMove(ToTurf)

		var/user_vored = FALSE

		for(var/mob/living/M in turf_contents_of_type(FromTurf, /mob/living))
			if(prob(recievefailchance))
				M.forceMove(pick(trange(24,user)))
			else
				M.forceMove(ToTurf)
				if(can_dropnom && living_user.can_be_drop_pred && M.can_be_drop_prey)
					var/obj/belly/belly_dest
					if(living_user.vore_selected)
						belly_dest = living_user.vore_selected
					else if(length(living_user.vore_organs))
						belly_dest = pick(living_user.vore_organs)
					if(belly_dest)
						M.forceMove(belly_dest)
						to_chat(living_user, span_vnotice("[M] materializes inside you as they end up in your [belly_dest]!"))
						to_chat(M, span_vdanger("You materialize inside [living_user] as you end up in their [belly_dest]!"))
				else if(can_dropnom && living_user.can_be_drop_prey && M.can_be_drop_pred && !user_vored)
					var/obj/belly/belly_dest
					if(M.vore_selected)
						belly_dest = M.vore_selected
					else if(length(M.vore_organs))
						belly_dest = pick(M.vore_organs)
					if(belly_dest)
						living_user.forceMove(belly_dest)
						user_vored = TRUE
						to_chat(living_user, span_vdanger("[M] materializes around you, as you end up in their [belly_dest]!"))
						to_chat(M, span_vnotice("You materialize around [living_user] as they end up in your [belly_dest]!"))



/// Old attack_self: switch the fire mode.
/obj/item/bluespace_harpoon/proc/interaction_fire_mode(datum/act/op/A)
	var/mob/user = A.actor
	harpoon_verb_fire_mode(user)
	return TRUE

/// Old Change Fire Mode verb.
/obj/item/bluespace_harpoon/proc/harpoon_verb_fire_mode(mob/user, obj/item/held)
	set_mode(!mode)
	to_chat(user,span_info("You change \the [src]'s mode to [mode ? "transmiting" : "receiving"]."))

/// Old Toggle Spatial Rearrangement verb.
/obj/item/bluespace_harpoon/proc/harpoon_verb_dropnom_mode(datum/act/op/A)
	var/mob/user = A.actor
	dropnoms_active = !dropnoms_active
	to_chat(user,span_info("You switch \the [src]'s spatial rearrangement [dropnoms_active ? "on" : "off"]. (Telenoms [dropnoms_active ? "enabled" : "disabled"])"))

TRACKED(/obj/item/bluespace_harpoon, mode)

/// The look: the mode's sprite, and the change animation of the mode it switched to.
/obj/item/bluespace_harpoon/draw(datum/look/look)
	..()
	look.state(mode ? "harpoon-2" : "harpoon-1")
	look.play_flick(mode ? "harpoon-1-change" : "harpoon-2-change")

/obj/item/bluespace_harpoon/ownership()
	. = ..()
	. += owns(nameof(scanmod), policy = OWN_CONTAINED, starts = /obj/item/stock_parts/scanning_module)
