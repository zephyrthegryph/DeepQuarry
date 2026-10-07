#define FARMBOT_COLLECT 1
#define FARMBOT_WATER 2
#define FARMBOT_UPROOT 3
#define FARMBOT_NUTRIMENT 4

/mob/living/bot/farmbot
	name = "Farmbot"
	desc = "The botanist's best friend."
	icon = 'icons/obj/chemical_tanks.dmi'
	icon_state = "farmbot0"
	endurance = 50
	req_one_access = list(ACCESS_ROBOTICS, ACCESS_HYDROPONICS, ACCESS_XENOBIOLOGY)

	var/action = "" // Used to update icon
	var/waters_trays = 1
	var/refills_water = 1
	var/uproots_weeds = 1
	var/replaces_nutriment = 0
	var/collects_produce = 0
	var/removes_dead = 0
	var/times_idle = 0
	var/obj/structure/reagent_dispensers/watertank/tank


/// The water tank handed over by the arm assembly that built it (its constructor param), or null for a new one.
/mob/living/bot/farmbot/var/tmp/obj/structure/reagent_dispensers/watertank/tank_at_make

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm).
/mob/living/bot/farmbot/proc/take_tank(obj/structure/reagent_dispensers/watertank/W)
	if(!W)
		W = new /obj/structure/reagent_dispensers/watertank(src)
	W.forceMove(src)
	own_move(W, src, nameof(tank)) // handed over from the arm assembly, when built from one

// The controls open on a touch in help intent (the hand op below), so the window's own open op answers the menu and a remote user only.
CAPABILITIES(/mob/living/bot/farmbot)
	interface("Farmbot", input = menu())
	op("touch", hand(), stance(I_HELP), label("Open controls"), then(PROC_REF(farmbot_touched)))
	op("power", ui_act("power"), then(PROC_REF(ui_act_power)))
	op("water", ui_act("water"), then(PROC_REF(ui_act_water)))
	op("refill", ui_act("refill"), then(PROC_REF(ui_act_refill)))
	op("weed", ui_act("weed"), then(PROC_REF(ui_act_weed)))
	op("replacenutri", ui_act("replacenutri"), then(PROC_REF(ui_act_replacenutri)))
	param(nameof(tank_at_make), pos = 1, apply = PROC_REF(take_tank), keep = FALSE)

/// The window's data: the bot's state, its tank, and the settings while the panel is unlocked.
/mob/living/bot/farmbot/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["on"] = on
	data["locked"] = locked
	data["tank"] = !!tank
	if(tank)
		data["tankVolume"] = tank.reagents.total_volume
		data["tankMaxVolume"] = tank.reagents.maximum_volume

	data["waters_trays"] = null
	data["refills_water"] = null
	data["uproots_weeds"] = null
	data["replaces_nutriment"] = null
	data["collects_produce"] = null
	data["removes_dead"] = null

	if(!locked)
		data["waters_trays"] = waters_trays
		data["refills_water"] = refills_water
		data["uproots_weeds"] = uproots_weeds
		data["replaces_nutriment"] = replaces_nutriment
		data["collects_produce"] = collects_produce
		data["removes_dead"] = removes_dead

	return data


/// A touch in help intent (other stances fall to the living defaults): the help touch first; if that did nothing, open the controls.
/mob/living/bot/farmbot/proc/farmbot_touched(datum/act/op/A)
	var/mob/user = A.actor
	if(!unarmed_touch(user, I_HELP))
		tgui_interact(user)

/mob/living/bot/farmbot/on_emag(remaining_charges, mob/user, obj/item/emag_source)
	. = ..()
	if(!emagged)
		if(user)
			to_chat(user, span_notice("You short out [src]'s plant identifier circuits."))
		after(src, rand(3 SECONDS, 5 SECONDS), PROC_REF(emag_takes))
		return 1

/mob/living/bot/farmbot/proc/ui_act_power(datum/act/op/A)
	if(!access_scanner.allowed(A.actor))
		return FALSE
	if(on)
		turn_off()
	else
		turn_on()
	. = TRUE

/mob/living/bot/farmbot/proc/ui_act_water(datum/act/op/A)
	if(locked)
		return TRUE
	waters_trays = !waters_trays
	. = TRUE

/mob/living/bot/farmbot/proc/ui_act_refill(datum/act/op/A)
	if(locked)
		return TRUE
	refills_water = !refills_water
	. = TRUE

/mob/living/bot/farmbot/proc/ui_act_weed(datum/act/op/A)
	if(locked)
		return TRUE
	uproots_weeds = !uproots_weeds
	. = TRUE

/mob/living/bot/farmbot/proc/ui_act_replacenutri(datum/act/op/A)
	if(locked)
		return TRUE
	replaces_nutriment = !replaces_nutriment
	. = TRUE
// No automatic hydroponics
// if("collect")
// 	collects_produce = !collects_produce
// 	. = TRUE
// if("removedead")
// 	removes_dead = !removes_dead
// 	. = TRUE


/mob/living/bot/farmbot/update_icons()
	if(on && action)
		icon_state = "farmbot_[action]"
	else
		icon_state = "farmbot[on]"

/mob/living/bot/farmbot/handleRegular()
	if(emagged && prob(1))
		flick("farmbot_broke", src)

/mob/living/bot/farmbot/handleAdjacentTarget()
	UnarmedAttack(target)

/mob/living/bot/farmbot/lookForTargets()
	if(emagged)
		for(var/mob/living/carbon/human/H in view(7, src))
			rel_set(src, nameof(target), H)
			times_idle = 0 // Idle shutoff time
			return
	else
		for(var/obj/machinery/portable_atmospherics/hydroponics/tray in view(7, src))
			if(confirmTarget(tray))
				rel_set(src, nameof(target), tray)
				times_idle = 0 // Idle shutoff time
				return
		if(!target && refills_water && tank && tank.reagents?.total_volume < tank.reagents.maximum_volume) // runtime
			for(var/obj/structure/sink/source in view(7, src))
				rel_set(src, nameof(target), source)
				times_idle = 0 // Idle shutoff time
				return
	if(++times_idle == 150) turn_off() // Idle shutoff time

/mob/living/bot/farmbot/calcTargetPath() // We need to land NEXT to the tray, because the tray itself is impassable
	if(isnull(target))
		return
	target_path = om_pathfinder().default_bot_pathfinding(src, get_turf(target), 1, 32)
	if(!target_path)
		rel_add(src, nameof(ignore_list), target)
		rel_clear(src, nameof(target))
		target_path = list()
	return

/mob/living/bot/farmbot/stepToTarget() // Same reason
	var/turf/T = get_turf(target)
	if(!target_path.len || !T.Adjacent(target_path[target_path.len]))
		calcTargetPath()
	makeStep(target_path)
	return

/mob/living/bot/farmbot/UnarmedAttack(atom/A, proximity)
	if(!..())
		return

	if(bot_busy())
		return

	if(istype(A, /obj/machinery/portable_atmospherics/hydroponics))
		var/obj/machinery/portable_atmospherics/hydroponics/T = A

		var/t = confirmTarget(T)
		switch(t)
			if(0)
				return
			if(FARMBOT_COLLECT)
				action = "water" // Needs a better one
				update_icons()
				act_message(src, A, others = span_notice("%U% starts [T.dead? "removing the plant from" : "harvesting"] %T%."))

				bot_work(3 SECONDS, T, PROC_REF(farm_job_done), FARMBOT_COLLECT, PROC_REF(farm_job_end))
			if(FARMBOT_WATER)
				action = "water"
				update_icons()
				act_message(src, A, others = span_notice("%U% starts watering %T%."))

				bot_work(3 SECONDS, T, PROC_REF(farm_job_done), FARMBOT_WATER, PROC_REF(farm_job_end))
			if(FARMBOT_UPROOT)
				action = "hoe"
				update_icons()
				act_message(src, A, others = span_notice("%U% starts uprooting the weeds in %T%."))

				bot_work(3 SECONDS, T, PROC_REF(farm_job_done), FARMBOT_UPROOT, PROC_REF(farm_job_end))
			if(FARMBOT_NUTRIMENT)
				action = "fertile"
				update_icons()
				act_message(src, A, others = span_notice("%U% starts fertilizing %T%."))

				bot_work(3 SECONDS, T, PROC_REF(farm_job_done), FARMBOT_NUTRIMENT, PROC_REF(farm_job_end))

	else if(istype(A, /obj/structure/sink))
		if(!tank || tank.reagents.total_volume >= tank.reagents.maximum_volume)
			return
		action = "water"
		update_icons()
		act_message(src, A, others = span_notice("%U% starts refilling its tank from %T%."))

		refill_step(A)
	else if(emagged && ishuman(A))
		var/action = pick("weed", "water")

		bot_hold(5 SECONDS) // Some delay
		switch(action)
			if("weed")
				flick("farmbot_hoe", src)
				do_attack_animation(A)
				if(prob(50))
					act_message(src, A, others = span_danger("%U% swings wildly at %T% with a minihoe, missing completely!"))
					return
				var/t = pick("slashed", "sliced", "cut", "clawed")
				generic_hit(A, src, 5, t)
			if("water")
				flick("farmbot_water", src)

				act_message(src, A, others = span_danger("%U% splashes %T% with water!"))
				tank.reagents.splash(A, 100)

/// A job on a tray that ended (done or broken off): the bot stops showing the work.
/mob/living/bot/farmbot/proc/farm_job_end(datum/act/op/A)
	action = ""
	update_icons()
	var/atom/tray = A.target
	tray?.update_icon()

/// One second of refilling from a sink, repeated until the tank is full or interrupted.
/mob/living/bot/farmbot/proc/refill_step(atom/A)
	if(tank.reagents.total_volume < tank.reagents.maximum_volume)
		bot_work(1 SECOND, A, PROC_REF(refill_pulse), null, PROC_REF(refill_end))
		return
	refill_end()

/mob/living/bot/farmbot/proc/refill_pulse(datum/act/op/A)
	tank.reagents.add_reagent("water", 100)
	if(prob(5))
		play_sfx(src, SFX_EFFECTS_SLOSH)
	refill_step(A.target)

/mob/living/bot/farmbot/proc/refill_end(datum/act/op/A = null)
	action = ""
	update_icons()
	act_message(src, null, others = span_notice("%U% finishes refilling its tank."))

/mob/living/bot/farmbot/proc/farm_job_done(datum/act/op/A)
	var/obj/machinery/portable_atmospherics/hydroponics/T = A.target
	switch(work_arg)
		if(FARMBOT_COLLECT)
			act_message(src, T, others = span_notice("%U% [T.dead? "removes the plant from" : "harvests"] %T%."))
			T.attack_hand(src)
		if(FARMBOT_WATER)
			play_sfx(src, SFX_EFFECTS_SLOSH)
			act_message(src, T, others = span_notice("%U% waters %T%."))
			tank.reagents.trans_to(T, 100 - T.waterlevel)
		if(FARMBOT_UPROOT)
			act_message(src, T, others = span_notice("%U% uproots the weeds in %T%."))
			T.weedlevel = 0
		if(FARMBOT_NUTRIMENT)
			act_message(src, T, others = span_notice("%U% fertilizes %T%."))
			T.reagents.add_reagent(REAGENT_ID_AMMONIA, 10)
	farm_job_end(A)

/mob/living/bot/farmbot/explode()
	act_message(src, null, others = span_danger("%U% blows apart!"))
	var/turf/Tsec = get_turf(src)

	new /obj/item/material/minihoe(Tsec)
	new /obj/item/reagent_containers/glass/bucket(Tsec)
	new /obj/item/assembly/prox_sensor(Tsec)
	new /obj/item/analyzer/plant_analyzer(Tsec)

	if(tank)
		tank.forceMove(Tsec)
		rel_take(src, nameof(tank))

	if(prob(50))
		new /obj/item/robot_parts/l_arm(Tsec)

	fx_sparks(src, 3)
	return ..()


/mob/living/bot/farmbot/confirmTarget(atom/targ)
	if(!..())
		return 0

	if(emagged && ishuman(targ))
		if(targ in view(world.view, src))
			return 1
		return 0

	if(istype(targ, /obj/structure/sink))
		if(!tank || tank.reagents.total_volume >= tank.reagents.maximum_volume)
			return 0
		return 1

	var/obj/machinery/portable_atmospherics/hydroponics/tray = targ
	if(!istype(tray))
		return 0

	if(tray.closed_system || !tray.seed)
		return 0

	if(tray.dead && removes_dead || tray.harvest && collects_produce)
		return FARMBOT_COLLECT

	else if(refills_water && tray.waterlevel < 40 && !tray.reagents.has_reagent("water") && tank.reagents.total_volume > 0)
		return FARMBOT_WATER

	else if(uproots_weeds && tray.weedlevel > 3)
		return FARMBOT_UPROOT

	else if(replaces_nutriment && tray.nutrilevel < 1 && tray.reagents.total_volume < 1)
		return FARMBOT_NUTRIMENT

	return 0

// Assembly

/obj/item/farmbot_arm_assembly
	name = "water tank/robot arm assembly"
	desc = "A water tank with a robot arm permanently grafted to it."
	icon = 'icons/obj/chemical_tanks.dmi'
	icon_state = "water_arm"
	var/build_step = 0
	var/created_name = "Farmbot"
	var/obj/tank
	w_class = ITEMSIZE_NORMAL


CAPABILITIES(/obj/item/farmbot_arm_assembly)
	param(nameof(tank_at_make), pos = 1, apply = PROC_REF(take_tank), keep = FALSE)
	op("hand", hand(), ungated(), label("Use"), then(PROC_REF(interaction_hand)))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

/// The water tank the assembly is built around (its constructor param), or null for a new one (an admin spawn).
/obj/item/farmbot_arm_assembly/var/tmp/obj/tank_at_make

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm).
/obj/item/farmbot_arm_assembly/proc/take_tank(obj/O)
	if(!O)
		rel_set(src, nameof(tank), new /obj/structure/reagent_dispensers/watertank(src))
		return
	O.forceMove(src)
	own_move(O, src, nameof(tank))

/// Old attackby.
/obj/structure/reagent_dispensers/watertank/proc/watertank_interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/S = A.held
	// Accept either a robotic arm part or a robotic external arm organ to build the assembly.
	var/is_robot_arm = istype(S, /obj/item/robot_parts/l_arm) || istype(S, /obj/item/robot_parts/r_arm)
	var/is_robotic_organ = FALSE
	if(istype(S, /obj/item/organ/external/arm))
		var/obj/item/organ/external/arm/organ_arm = S
		is_robotic_organ = (organ_arm.robotic == ORGAN_ROBOT)

	if(!is_robot_arm && !is_robotic_organ)
		return OP_DECLINE

	to_chat(user, "You add the robot arm to [src].")

	consume(S, user)

	new /obj/item/farmbot_arm_assembly(loc, src)
	return OP_PASS

/// Old attackby.
/obj/item/farmbot_arm_assembly/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if((istype(W, /obj/item/analyzer/plant_analyzer)) && (build_step == 0))
		build_step++
		to_chat(user, "You add the plant analyzer to [src].")
		name = "farmbot assembly"

		consume(W, user)

	else if((istype(W, /obj/item/reagent_containers/glass/bucket)) && (build_step == 1))
		build_step++
		to_chat(user, "You add a bucket to [src].")
		name = "farmbot assembly with bucket"

		consume(W, user)

	else if((istype(W, /obj/item/material/minihoe)) && (build_step == 2))
		build_step++
		to_chat(user, "You add a minihoe to [src].")
		name = "farmbot assembly with bucket and minihoe"

		consume(W, user)

	else if((isprox(W)) && (build_step == 3))
		build_step++
		to_chat(user, "You complete the Farmbot! Beep boop.")

		var/mob/living/bot/farmbot/S = new /mob/living/bot/farmbot(get_turf(src), tank)
		S.name = created_name

		consume(W, user)
		consume(src, user)

	else if(istype(W, /obj/item/pen))
		ask_name_var(user)
	return OP_PASS

/// Old attack_hand.
/obj/item/farmbot_arm_assembly/proc/interaction_hand(datum/act/op/A)
	return TRUE

#undef FARMBOT_COLLECT
#undef FARMBOT_WATER
#undef FARMBOT_UPROOT
#undef FARMBOT_NUTRIMENT

/mob/living/bot/farmbot/proc/emag_takes()
	act_message(src, null, others = span_warning("%U% buzzes oddly."))
	emagged = 1

/obj/item/farmbot_arm_assembly/ownership()
	. = ..()
	. += owns(nameof(tank), policy = OWN_CONTAINED)
/mob/living/bot/farmbot/ownership()
	. = ..()
	. += owns(nameof(tank), policy = OWN_CONTAINED)
