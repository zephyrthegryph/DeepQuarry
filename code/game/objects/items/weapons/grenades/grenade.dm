/obj/item/grenade
	name = "grenade"
	desc = "A hand held grenade, with an adjustable timer."
	w_class = ITEMSIZE_SMALL
	icon = 'icons/obj/grenade.dmi'
	icon_state = "grenade"
	item_state = "grenade"
	throw_speed = 4
	throw_range = 20

	var/active = 0
	var/det_time = 50
	var/loadable = TRUE
	var/arm_sound = SFX_WEAPONS_ARMBOMB
	var/hud_state = "grenade_he" // TGMC Ammo HUD Port
	var/hud_state_empty = "grenade_empty" // TGMC Ammo HUD Port

	///Var for special attack_self handling
	var/special_handling = FALSE


/obj/item/grenade/proc/clown_check(mob/living/user)
	if(CLUMSY_HARM_CHANCE(user))
		to_chat(user, span_warning("Huh? How does this thing work?"))

		activate(user)
		add_fingerprint(user)
		after(src, 0.5 SECONDS, PROC_REF(detonate))
		return 0
	return 1

/obj/item/grenade/examine(mob/user)
	. = ..()
	if(get_dist(user, src) == 0)
		if(det_time > 1)
			. += "The timer is set to [det_time/10] seconds."
		else if(det_time == null)
			. += "\The [src] is set for instant detonation."

TRACKED(/obj/item/grenade, det_time)

MSG_DEF_SELF(grenade/timer_1s, "You set %T% for 1 second detonation time.")
MSG_DEF_SELF(grenade/timer_3s, "You set %T% for 3 second detonation time.")
MSG_DEF_SELF(grenade/timer_5s, "You set %T% for 5 second detonation time.")
MSG_DEF_SELF(grenade/timer_instant, "You set %T% for instant detonation.")

CAPABILITIES(/obj/item/grenade)
	configure(item_worn(slots = SLOT_MASK|SLOT_BELT))
	configure(item_sounds(pickup = SFX_ITEMS_PICKUP_DEVICE, drop = SFX_ITEMS_DROP_DEVICE))
	op("prime", in_hand(), when(cond_not(nameof(special_handling))), label("Prime"), then(PROC_REF(grenade_primed)))
	op("grenade_interaction_hand", hand(), ungated(), then(PROC_REF(grenade_interaction_hand)))
	// the screwdriver turns the timer round: instant, 1 s, 3 s, 5 s; a grenade with another fuse only takes the prints
	stages(nameof(det_time),
		stage_step(1, 10, tool(TOOL_SCREWDRIVER), label("Set the timer"), wait(0), says(MSG(grenade/timer_1s)), then(PROC_REF(timer_handled))),
		stage_step(10, 30, tool(TOOL_SCREWDRIVER), label("Set the timer"), wait(0), says(MSG(grenade/timer_3s)), then(PROC_REF(timer_handled))),
		stage_step(30, 50, tool(TOOL_SCREWDRIVER), label("Set the timer"), wait(0), says(MSG(grenade/timer_5s)), then(PROC_REF(timer_handled))),
		stage_step(50, 1, tool(TOOL_SCREWDRIVER), label("Set the timer"), wait(0), says(MSG(grenade/timer_instant)), then(PROC_REF(timer_handled))))
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), priority(OP_PRIORITY_NORMAL), wait(0), then(PROC_REF(timer_handled)))

/obj/item/grenade/proc/grenade_primed(datum/act/op/A)
	var/mob/user = A.actor
	if(!active)
		if(clown_check(user))
			to_chat(user, span_warning("You prime \the [name]! [det_time/10] seconds!"))

			activate(user)
			add_fingerprint(user)
			if(iscarbon(user))
				var/mob/living/carbon/C = user
				C.throw_mode_on()
	return OP_OK

/obj/item/grenade/proc/activate(mob/user as mob)
	if(active)
		return

	if(user)
		msg_admin_attack("[key_name_admin(user)] primed \a [src.name]")

	set_icon_state(initial(icon_state) + "_active")
	active = 1
	playsound(src, arm_sound, 75, 1, -3)

	after(src, det_time, PROC_REF(detonate))

/obj/item/grenade/proc/detonate()
	var/turf/T = get_turf(src)
	if(T)
		T.hotspot_expose(700,125)
		SSmotiontracker.ping(src,100)

/// The screwdriver leaves its user's prints.
/obj/item/grenade/proc/timer_handled(datum/act/op/A)
	add_fingerprint(A.actor)
	return OP_OK

/// Old attack_hand: stops any throw walk, then the touch goes on to the gate and pickup.
/obj/item/grenade/proc/grenade_interaction_hand(datum/act/op/A)
	walk(src, null, null)
	return OP_DECLINE

/obj/item/grenade/vendor_action(obj/machinery/vending/V)
	activate(V)

/obj/item/grenade/proc/start_effect_sprayer(datum/effect/effect/system/spraying, duration, sound_play, start_data = null)
	playsound(loc, sound_play, 50, 1, -3)
	spraying.set_up(10, 0, loc)
	effect_spraying(spraying, duration, start_data)

/obj/item/grenade/proc/effect_spraying(datum/effect/effect/system/spraying, duration, start_data)
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)

	spraying.start(start_data)
	if(duration > 0)
		after(src, 1 SECOND, PROC_REF(effect_spraying), with = list(spraying, --duration))
		return
	spent(src)
