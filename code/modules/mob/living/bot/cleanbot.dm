/mob/living/bot/cleanbot
	name = "Cleanbot"
	desc = "A little cleaning robot, it looks so excited!"
	icon_state = "cleanbot0"
	req_one_access = list(ACCESS_ROBOTICS, ACCESS_JANITOR)
	botcard_access = list(ACCESS_JANITOR)
	pass_flags = PASSTABLE

	max_frustration = 12
	locked = 0 // Start unlocked so roboticist can set them to patrol.
	wait_if_pulled = 1
	min_target_dist = 0

	var/cTimeMult = 1 // A multiplier for how long it should take to clean. Anything bigger than one will increase time, less than one will make it faster.
	var/vocal = 1
	var/cleaning = 0
	var/wet_floors = 0
	var/spray_blood = 0
	var/blood = 1
	var/list/target_types = list() // ALLOW(instance_list): d: per-mob target_types, sized at creation and filled in place; mobs are few

/mob/living/bot/cleanbot/Initialize(mapload)
	. = ..()
	get_targets()

/// Phase 2: releases the turf it reserved.
/mob/living/bot/cleanbot/lifecycle_dematerialize()
	. = ..()
	if(target)
		registry_leave(REGISTRY_CLEANBOT_RESERVED_TURFS, target)

/mob/living/bot/cleanbot/handleIdle()
	if(!wet_floors && !spray_blood && vocal && prob(2))
		automatic_custom_emote(AUDIBLE_MESSAGE, "makes an excited booping sound!")
		play_sfx(src, SFX_MACHINES_SYNTH_YES)

	if(wet_floors && prob(5)) // Make a mess
		if(istype(loc, /turf/simulated))
			var/turf/simulated/T = loc
			T.wet_floor()

	if(spray_blood && prob(5)) // Make a big mess
		act_message(src, null, others = "Something flies out of %U%. It seems to be acting oddly.")
		var/obj/effect/decal/cleanable/blood/gibs/gib = new /obj/effect/decal/cleanable/blood/gibs(get_turf(src))
		rel_add(src, nameof(ignore_list), gib)
		after(src, 1 MINUTE, PROC_REF(clear_ignored_gib), with = list(gib))

/mob/living/bot/cleanbot/proc/clear_ignored_gib(obj/gibref)
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)
	rel_remove(src, nameof(ignore_list), gibref)

/mob/living/bot/cleanbot/handlePanic()	// Speed modification based on alert level.
	. = 0
	switch(get_security_level())
		if("green")
			. = 0

		if("yellow")
			. = 1

		if("violet")
			. = 1

		if("orange")
			. = 1

		if("blue")
			. = 2

		if("red")
			. = 2

		if("delta")
			. = 2

	return .

/mob/living/bot/cleanbot/lookForTargets()
	for(var/i = 0, i <= world.view, i++)
		for(var/obj/effect/decal/cleanable/D in view(i, src))
			if (i > 0 && get_dist(src, D) < i)
				continue // already checked this one
			else if(confirmTarget(D))
				rel_set(src, nameof(target), D)
				registry_join(REGISTRY_CLEANBOT_RESERVED_TURFS, D)
				return

/mob/living/bot/resetTarget()
	registry_leave(REGISTRY_CLEANBOT_RESERVED_TURFS, target)
	..()

/mob/living/bot/cleanbot/confirmTarget(obj/effect/decal/cleanable/D)
	if(!..())
		return FALSE
	if(D.loc in REGISTRY_MEMBERS(REGISTRY_CLEANBOT_RESERVED_TURFS))
		return FALSE
	for(var/T in target_types)
		if(istype(D, T))
			return TRUE
	return FALSE

/mob/living/bot/cleanbot/handleAdjacentTarget()
	if(get_turf(target) == src.loc)
		UnarmedAttack(target)

//mob/living/bot/cleanbot/UnarmedAttack(obj/effect/decal/cleanable/D, proximity)
/mob/living/bot/cleanbot/UnarmedAttack(atom/D, proximity)
	if(!..())
		return


	if(D.loc != loc)
		return

	var/cleantime = 0
	if(istype(D, /obj/effect/decal/cleanable))
		cleantime = istype(D, /obj/effect/decal/cleanable/dirt) ? 10 : 50
		if(prob(20))
			automatic_custom_emote(AUDIBLE_MESSAGE, "begins to clean up \the [D]")
		bot_work(cleantime * cTimeMult, D, PROC_REF(UnarmedAttack_cleanbot_done), list(D))
	else if(D == src)
		for(var/obj/effect/O in contents_of(loc))
			if(istype(O, /obj/effect/decal/cleanable/dirt))
				cleantime += 10
			if(istype(O,/obj/effect/rune) || istype(O,/obj/effect/decal/cleanable) || istype(O,/obj/effect/overlay))
				cleantime += 50
		if(cleantime != 0)
			if(prob(20))
				automatic_custom_emote(AUDIBLE_MESSAGE, "begins to clean up \the [loc]")
			bot_work(cleantime * cTimeMult, loc, PROC_REF(UnarmedAttack_cleanbot_done2))
		else
			handleIdle()

/mob/living/bot/cleanbot/proc/UnarmedAttack_cleanbot_done(atom/D)
	var/cleaned_target_id = REF(D)
	if(istype(loc, /turf/simulated))
		var/turf/simulated/f = loc
		f.dirt = 0
	if(!D)
		return
	spent(D)
	if(SScontracts)
		emit_contract_event(CONTRACT_EVENT_SANITATION_COMPLETED, list(
			"department" = DEPARTMENT_CIVILIAN,
			"target_id" = cleaned_target_id,
			"method" = "cleanbot",
			"cleaned_units" = 1,
			"detail" = "[src] removed a station contaminant.",
		), "sanitation-bot:[REF(src)]:[cleaned_target_id]:[world.time]", src)
		emit_contract_event(CONTRACT_EVENT_AUTOMATION_TASK_COMPLETED, list(
			"department" = DEPARTMENT_SYNTHETIC,
			"bot_id" = REF(src),
			"task_kind" = "sanitation",
			"target_id" = cleaned_target_id,
			"successful" = TRUE,
			"work_units" = 1,
			"detail" = "[src] completed an autonomous sanitation task.",
		), "automation:[REF(src)]:sanitation:[world.time]", src)
	if(D == target)
		registry_leave(REGISTRY_CLEANBOT_RESERVED_TURFS, target)
		rel_clear(src, nameof(target))
/mob/living/bot/cleanbot/proc/UnarmedAttack_cleanbot_done2()
	var/cleaned_turf_id = REF(loc)
	if(blood)
		wash(CLEAN_TYPE_BLOOD)
	if(istype(loc, /turf/simulated))
		var/turf/simulated/T = loc
		T.dirt = 0
	for(var/obj/effect/O in contents_of(loc))
		if(istype(O,/obj/effect/rune) || istype(O,/obj/effect/decal/cleanable) || istype(O,/obj/effect/overlay))
			spent(O)
	if(SScontracts)
		emit_contract_event(CONTRACT_EVENT_SANITATION_COMPLETED, list(
			"department" = DEPARTMENT_CIVILIAN,
			"target_id" = cleaned_turf_id,
			"method" = "cleanbot",
			"cleaned_units" = 1,
			"detail" = "[src] sanitized a station floor.",
		), "sanitation-bot:[REF(src)]:[cleaned_turf_id]:[world.time]", src)
		emit_contract_event(CONTRACT_EVENT_AUTOMATION_TASK_COMPLETED, list(
			"department" = DEPARTMENT_SYNTHETIC,
			"bot_id" = REF(src),
			"task_kind" = "sanitation",
			"target_id" = cleaned_turf_id,
			"successful" = TRUE,
			"work_units" = 1,
			"detail" = "[src] completed an autonomous sanitation task.",
		), "automation:[REF(src)]:sanitation:[world.time]", src)

/mob/living/bot/cleanbot/explode()
	set_on(0)
	act_message(src, null, others = span_danger("%U% blows apart!"))
	var/turf/Tsec = get_turf(src)

	new /obj/item/reagent_containers/glass/bucket(Tsec)
	new /obj/item/assembly/prox_sensor(Tsec)
	if(prob(50))
		new /obj/item/robot_parts/l_arm(Tsec)

	fx_sparks(src, 3)
	return ..()

/mob/living/bot/cleanbot/update_icons()
	if(task_busy(src))
		icon_state = "cleanbot-c"
	else
		icon_state = "cleanbot[on]"

CAPABILITIES(/mob/living/bot/cleanbot)
	interface("Cleanbot")
	op("start", ui_act("start"), then(PROC_REF(ui_act_start)))
	op("blood", ui_act("blood"), then(PROC_REF(ui_act_blood)))
	op("patrol", ui_act("patrol"), then(PROC_REF(ui_act_patrol)))
	op("vocal", ui_act("vocal"), then(PROC_REF(ui_act_vocal)))
	op("wet_floors", ui_act("wet_floors"), then(PROC_REF(ui_act_wet_floors)))
	op("spray_blood", ui_act("spray_blood"), then(PROC_REF(ui_act_spray_blood)))

/// The window's data: the bot's state and settings.
/mob/living/bot/cleanbot/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["on"] = on
	data["open"] = open
	data["locked"] = locked
	data["blood"] = blood
	data["patrol"] = will_patrol
	data["vocal"] = vocal
	data["wet_floors"] = wet_floors
	data["spray_blood"] = spray_blood
	data["version"] = "v2.0"
	return data

/mob/living/bot/cleanbot/proc/ui_act_start(datum/act/op/A)
	if(on)
		turn_off()
	else
		turn_on()
	. = TRUE

/mob/living/bot/cleanbot/proc/ui_act_blood(datum/act/op/A)
	blood = !blood
	. = TRUE

/mob/living/bot/cleanbot/proc/ui_act_patrol(datum/act/op/A)
	will_patrol = !will_patrol
	patrol_path = null
	. = TRUE

/mob/living/bot/cleanbot/proc/ui_act_vocal(datum/act/op/A)
	vocal = !vocal
	. = TRUE

/mob/living/bot/cleanbot/proc/ui_act_wet_floors(datum/act/op/A)
	wet_floors = !wet_floors
	to_chat(A.actor, span_notice("You twiddle the screw."))
	. = TRUE

/mob/living/bot/cleanbot/proc/ui_act_spray_blood(datum/act/op/A)
	spray_blood = !spray_blood
	to_chat(A.actor, span_notice("You press the weird button."))
	. = TRUE

/mob/living/bot/cleanbot/on_emag(remaining_charges, mob/user, obj/item/emag_source)
	. = ..()
	if(!wet_floors || !spray_blood)
		if(user)
			to_chat(user, span_notice("The [src] buzzes and beeps."))
			play_sfx(src, SFX_MACHINES_BUZZBEEP)
		spray_blood = 1
		wet_floors = 1
		return 1

/mob/living/bot/cleanbot/proc/get_targets()
	target_types = list(/obj/effect/decal/cleanable)

/* Assembly */

/obj/item/bucket_sensor
	desc = "It's a bucket. With a sensor attached."
	name = "proxy bucket"
	icon = 'icons/obj/aibots.dmi'
	icon_state = "bucket_proxy"
	force = 3.0
	throwforce = 10.0
	throw_speed = 2
	throw_range = 5
	w_class = ITEMSIZE_NORMAL
	var/created_name = "Cleanbot"

CAPABILITIES(/obj/item/bucket_sensor)
	op("item", item(/obj/item), then(PROC_REF(interaction_item)))

/// Old attackby.
/obj/item/bucket_sensor/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(istype(W, /obj/item/robot_parts/l_arm) || istype(W, /obj/item/robot_parts/r_arm) || (istype(W, /obj/item/organ/external/arm) && ((W.name == "robotic left arm") || (W.name == "robotic right arm"))))
		user.drop_item()
		consume(W, user)
		var/turf/T = get_turf(loc)
		var/mob/living/bot/cleanbot/new_bot = new /mob/living/bot/cleanbot(T)
		new_bot.name = created_name
		to_chat(user, span_notice("You add the robot arm to the bucket and sensor assembly. Beep boop!"))
		consume(src, user)

	else if(istype(W, /obj/item/pen))
		ask_name_var(user)
	return OP_PASS
