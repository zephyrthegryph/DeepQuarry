#define SECBOT_WAIT_TIME	3		//Around number*2 real seconds to surrender.
#define SECBOT_THREAT_ARREST 4		//threat level at which we decide to arrest someone
#define SECBOT_THREAT_ATTACK 8		//threat level at which was assume immediate danger and attack right away

/mob/living/bot/secbot
	name = "Securitron"
	desc = "A little security robot.  He looks less than thrilled."
	icon_state = "secbot0"
	endurance = 100
	req_one_access = list(ACCESS_SECURITY, ACCESS_FORENSICS_LOCKERS)
	botcard_access = list(ACCESS_SECURITY, ACCESS_SEC_DOORS, ACCESS_FORENSICS_LOCKERS, ACCESS_MAINT_TUNNELS)
	patrol_speed = 2
	target_speed = 3
	max_frustration = 7

	density = TRUE

	var/default_icon_state = "secbot"
	var/idcheck = FALSE // If true, arrests for having weapons without authorization.
	var/check_records = FALSE // If true, arrests people without a record.
	var/check_arrest = TRUE // If true, arrests people who are set to arrest.
	var/arrest_type = FALSE // If true, doesn't handcuff. You monster.
	var/datum/declare_arrests = FALSE // If true, announces arrests over sechuds.
	var/threat = 0 // How much of a threat something is. Set upon acquiring a target.
	var/attacked = FALSE // If true, gives the bot enough threat assessment to attack immediately.
	var/retaliates = TRUE //If this type of secbot should retaliate at all - so that slime securitrons don't go ballistic the second they get glomped.

	var/is_ranged = FALSE
	var/awaiting_surrender = 0
	var/can_next_insult = 0			// Uses world.time
	var/stun_strength = 60			// For humans.
	var/xeno_harm_strength = 15 	// How hard to hit simple_mobs.
	var/baton_glow = "#FF6A00"

	var/used_weapon	= /obj/item/melee/baton	//Weapon used by the bot

	var/static/list/threat_found_sounds = list('sound/voice/bcriminal.ogg', 'sound/voice/bjustice.ogg', 'sound/voice/bfreeze.ogg')
	var/list/preparing_arrest_sounds = list('sound/voice/bgod.ogg', 'sound/voice/biamthelaw.ogg', 'sound/voice/bsecureday.ogg', 'sound/voice/bradio.ogg', 'sound/voice/bcreep.ogg')
	var/static/list/fighting_sounds = list('sound/voice/biamthelaw.ogg', 'sound/voice/bradio.ogg', 'sound/voice/bjustice.ogg')
// They don't like being pulled. This is going to fuck with slimesky, but meh. //Screw you. Just screw you and your 'meh'
/datum/om/stage/life/type_post/bot/secbot
	of = /mob/living/bot/secbot

/datum/om/stage/life/type_post/bot/secbot/perform(mob/living/bot/secbot/self, datum/om/frame/life/ctx)
	..()
	if(self.stat != DEAD && self.on && self.pulledby)
		if(isliving(self.pulledby))
			var/pull_allowed = FALSE
			for(var/A in self.req_one_access)
				if(A in self.pulledby.GetAccess())
					pull_allowed = TRUE
			if(!pull_allowed)
				var/mob/living/L = self.pulledby
				INVOKE_ASYNC(self, TYPE_PROC_REF(/mob, UnarmedAttack), L)
				INVOKE_ASYNC(self, TYPE_PROC_REF(/mob/living, say), "Do not interfere with active law enforcement routines!")
				GLOB.global_announcer.autosay("[self] was interfered with in <b>[get_area(self)]</b>, activating defense routines.", "[self]", "Security")
/mob/living/bot/secbot/beepsky
	name = "Officer Beepsky"
	desc = "It's Officer Beep O'sky! Powered by a potato and a shot of whiskey."
	will_patrol = TRUE
	endurance = 130

/mob/living/bot/secbot/slime
	name = "Slime Securitron"
	desc = "A little security robot, with a slime baton subsituted for the regular one."
	default_icon_state = "slimesecbot"
	stun_strength = 10 // Slimebatons aren't meant for humans.
	retaliates = FALSE // No, you're not allowed to beat the slimes to death just because they scratched you.

	xeno_harm_strength = 9 // Weaker than regular slimesky but they can stun.
	baton_glow = "#33CCFF"
	req_one_access = list(ACCESS_RESEARCH, ACCESS_ROBOTICS)
	botcard_access = list(ACCESS_RESEARCH, ACCESS_ROBOTICS, ACCESS_XENOBIOLOGY, ACCESS_XENOARCH, ACCESS_TOX, ACCESS_TOX_STORAGE, ACCESS_MAINT_TUNNELS)
	used_weapon = /obj/item/melee/baton/slime
	var/xeno_stun_strength = 5 // How hard to slimebatoned()'d naughty slimes. 5 works out to 2 discipline and 5 weaken.

/mob/living/bot/secbot/slime/slimesky
	name = "Doctor Slimesky"
	desc = "An old friend of Officer Beep O'sky.  He prescribes beatings to rowdy slimes so that real doctors don't need to treat the xenobiologists."
	endurance = 130

/mob/living/bot/secbot/update_icons()
	if(on && busy)
		icon_state = "[default_icon_state]-c"
	else
		icon_state = "[default_icon_state][on]"

	if(on)
		set_light(2, 1, baton_glow)
	else
		set_light(0)

/mob/living/bot/secbot/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "Secbot", name)
		ui.open()

/mob/living/bot/secbot/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = ..()

	data["on"] = on
	data["open"] = open
	data["locked"] = locked

	data["idcheck"] = null
	data["check_records"] = null
	data["check_arrest"] = null
	data["arrest_type"] = null
	data["declare_arrests"] = null
	data["bot_patrolling"] = null
	data["will_patrol"] = null

	if(!locked || issilicon(user))
		data["idcheck"] = idcheck
		data["check_records"] = check_records
		data["check_arrest"] = check_arrest
		data["arrest_type"] = arrest_type
		data["declare_arrests"] = declare_arrests
		data["bot_patrolling"] = using_map.bot_patrolling
		data["patrol"] = will_patrol

	return data

/mob/living/bot/secbot/attack_hand(mob/user)
	tgui_interact(user)

/mob/living/bot/secbot/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	if(..())
		return

	add_fingerprint(ui.user)

	switch(action)
		if("power")
			if(!access_scanner.allowed(ui.user))
				return FALSE
			if(on)
				turn_off()
			else
				turn_on()
			. = TRUE

	if(locked && !issilicon(ui.user))
		return TRUE

	switch(action)
		if("idcheck")
			idcheck = !idcheck
			. = TRUE
		if("ignorerec")
			check_records = !check_records
			. = TRUE
		if("ignorearr")
			check_arrest = !check_arrest
			. = TRUE
		if("switchmode")
			arrest_type = !arrest_type
			. = TRUE
		if("patrol")
			will_patrol = !will_patrol
			. = TRUE
		if("declarearrests")
			declare_arrests = !declare_arrests
			. = TRUE

/mob/living/bot/secbot/emag_act(remaining_uses, mob/user)
	. = ..()
	if(!emagged)
		if(user)
			to_chat(user, span_notice("\The [src] buzzes and beeps."))
		emagged = TRUE
		patrol_speed = 3
		target_speed = 4
		return TRUE
	else
		to_chat(user, span_notice("\The [src] is already corrupt."))

/mob/living/bot/secbot/Initialize(mapload)
	. = ..()
	RegisterSignal(src, COMSIG_LIVING_INJURED, PROC_REF(on_injured))

/// Anything that actually hurt us is an attack: find who did it and retaliate.
/mob/living/bot/secbot/proc/on_injured(datum/source, kind, amount, zone, atom/injury_source, flags)
	SIGNAL_HANDLER
	if(amount <= 0 || !injury_source)
		return
	var/mob/attacker
	if(istype(injury_source, /obj/item/projectile))
		var/obj/item/projectile/P = injury_source
		attacker = P.firer
		//if we already have a target just ignore to avoid lots of checking
		if(target || !attacker || !(attacker in view(world.view, src)))
			return
	else if(ismob(injury_source))
		attacker = injury_source
	else if(ismob(injury_source.loc))
		attacker = injury_source.loc // a held weapon
	if(!attacker || attacker == src || on != TRUE)
		return
	INVOKE_ASYNC(src, PROC_REF(react_to_attack), attacker)

/mob/living/bot/secbot/attack_generic(mob/attacker)
	if(attacker)
		react_to_attack(attacker)
	..()

/mob/living/bot/secbot/proc/react_to_attack(mob/attacker)
	if(!on || !retaliates)		// We don't want it to react if it's off or doesn't care
		return

	if(!target)
		playsound(src, pick(threat_found_sounds), 50)
		GLOB.global_announcer.autosay("[src] was attacked by a hostile <b>[target_name(attacker)]</b> in <b>[get_area(src)]</b>.", "[src]", "Security")
	target = attacker
	attacked = TRUE

// Say "freeze!" and demand surrender
/mob/living/bot/secbot/proc/demand_surrender(mob/target, threat)
	var/suspect_name = target_name(target)
	if(declare_arrests)
		GLOB.global_announcer.autosay("[src] is [arrest_type ? "detaining" : "arresting"] a level [threat] suspect <b>[suspect_name]</b> in <b>[get_area(src)]</b>.", "[src]", "Security")
	say("Down on the floor, [suspect_name]! You have [SECBOT_WAIT_TIME*2] seconds to comply.")
	playsound(src, pick(preparing_arrest_sounds), 50)
	// Register to be told when the target moves
	target.AddComponent(/datum/component/recursive_move)
	RegisterSignal(target, COMSIG_MOVABLE_ATTEMPTED_MOVE, /mob/living/bot/secbot/proc/target_moved)

// Callback invoked if the registered target moves
/mob/living/bot/secbot/proc/target_moved(atom/movable/moving_instance, atom/old_loc, atom/new_loc)
	SIGNAL_HANDLER
	if(get_dist(get_turf(src), get_turf(target)) >= 1)
		awaiting_surrender = INFINITY	// Done waiting!
		UnregisterSignal(moving_instance, COMSIG_MOVABLE_ATTEMPTED_MOVE)

/mob/living/bot/secbot/resetTarget()
	..()
	if(target)
		UnregisterSignal(target, COMSIG_MOVABLE_ATTEMPTED_MOVE)
	awaiting_surrender = 0
	attacked = FALSE
	walk_to(src, 0)

/mob/living/bot/secbot/startPatrol()
	if(!locked) // Stop running away when we set you up
		return
	..()

/mob/living/bot/secbot/confirmTarget(atom/A)
	if(!..())
		return FALSE
	check_threat(A)
	if(threat >= SECBOT_THREAT_ARREST)
		return TRUE

/mob/living/bot/secbot/lookForTargets()
	for(var/mob/living/M in view(src))
		if(M.stat == DEAD)
			continue
		if(confirmTarget(M))
			target = M
			awaiting_surrender = 0
			say("Level [threat] infraction alert!")
			automatic_custom_emote(VISIBLE_MESSAGE, "points at [M.name]!")
			playsound(src, pick(threat_found_sounds), 50)
			return

/mob/living/bot/secbot/handleAdjacentTarget()
	var/mob/living/carbon/human/H = target
	check_threat(target)
	if(awaiting_surrender < SECBOT_WAIT_TIME && istype(H) && !H.lying && threat < SECBOT_THREAT_ATTACK)
		if(awaiting_surrender == 0) // On first tick of awaiting...
			demand_surrender(target, threat)
		++awaiting_surrender
	else
		if(declare_arrests)
			var/action = arrest_type ? "detaining" : "arresting"
			if(!ishuman(target))
				action = "fighting"
			GLOB.global_announcer.autosay("[src] is [action] a level [threat] [action != "fighting" ? "suspect" : "threat"] <b>[target_name(target)]</b> in <b>[get_area(src)]</b>.", "[src]", "Security")
		UnarmedAttack(target)

/mob/living/bot/secbot/handlePanic()	// Speed modification based on alert level.
	. = 0
	switch(get_security_level())
		if("green")
			. = 0

		if("yellow")
			. = 0

		if("violet")
			. = 0

		if("orange")
			. = 0

		if("blue")
			. = 1

		if("red")
			. = 2

		if("delta")
			. = 2

	return .

// So Beepsky talks while beating up simple mobs.
/mob/living/bot/secbot/proc/insult(mob/living/L)
	if(can_next_insult > world.time)
		return
	if(threat >= 10)
		playsound(src, 'sound/voice/binsult.ogg', 75)
		can_next_insult = world.time + 20 SECONDS
	else
		playsound(src, pick(fighting_sounds), 75)
		can_next_insult = world.time + 5 SECONDS


/mob/living/bot/secbot/UnarmedAttack(mob/M, proximity)
	if(!..())
		return

	if(!istype(M))
		return

	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		var/cuff = TRUE

		if(!H.lying || H.get_equipped_item(SLOT_ID_HANDCUFFED) || arrest_type)
			cuff = FALSE
		if(!cuff)
			H.stun_effect_act(0, stun_strength, null, electric = TRUE)
			playsound(src, 'sound/weapons/egloves.ogg', 50, 1, -1)
			do_attack_animation(H)
			busy = TRUE
			update_icons()
			spawn(2)
				busy = FALSE
				update_icons()
			visible_message(span_warning("\The [H] was prodded by \the [src] with a stun baton!"))
			insult(H)
		else
			playsound(src, 'sound/weapons/handcuffs.ogg', 30, 1, -2)
			visible_message(span_warning("\The [src] is trying to put handcuffs on \the [H]!"))
			busy = TRUE
			if(do_after(src, 6 SECONDS, H))
				if(!H.get_equipped_item(SLOT_ID_HANDCUFFED))
					if(istype(H.get_equipped_item(SLOT_ID_BACK), /obj/item/rig) && istype(H.get_equipped_item(SLOT_ID_GLOVES),/obj/item/clothing/gloves/gauntlets/rig))
						H.equip_to_slot_or_del(new /obj/item/handcuffs/cable(H), slot_handcuffed) // Better to be cable cuffed than stun-locked
					else
						H.equip_to_slot_or_del(new /obj/item/handcuffs(H), slot_handcuffed)
			busy = FALSE
	else if(isliving(M))
		var/mob/living/L = M
		L.injure(INJURY_BLUNT, xeno_harm_strength, null, src)
		do_attack_animation(M)
		playsound(src, "swing_hit", 50, 1, -1)
		busy = TRUE
		update_icons()
		spawn(2)
			busy = FALSE
			update_icons()
		visible_message(span_warning("\The [M] was beaten by \the [src] with a stun baton!"))
		insult(L)

/mob/living/bot/secbot/slime/UnarmedAttack(mob/living/L, proximity)
	..()

	if(istype(L, /mob/living/simple_mob/slime/xenobio))
		var/mob/living/simple_mob/slime/xenobio/S = L
		S.slimebatoned(src, xeno_stun_strength)

/mob/living/bot/secbot/explode()
	visible_message(span_warning("[src] blows apart!"))
	var/turf/Tsec = get_turf(src)

	var/obj/item/secbot_assembly/Sa = new /obj/item/secbot_assembly(Tsec)
	Sa.build_step = 1
	Sa.add_overlay("hs_hole")
	Sa.created_name = name
	new /obj/item/assembly/prox_sensor(Tsec)
	new used_weapon(Tsec)
	if(prob(50))
		new /obj/item/robot_parts/l_arm(Tsec)

	var/datum/effect/effect/system/spark_spread/s = new /datum/effect/effect/system/spark_spread
	s.set_up(3, 1, src)
	s.start()

	new /obj/effect/decal/cleanable/blood/oil(Tsec)
	//qdel(src)
	return ..()

/mob/living/bot/secbot/proc/target_name(mob/living/T)
	if(ishuman(T))
		var/mob/living/carbon/human/H = T
		return H.get_id_name("unidentified person")
	return "unidentified lifeform"

/mob/living/bot/secbot/proc/check_threat(mob/living/M)
	if(!M || !istype(M) || M.stat == DEAD || src == M)
		threat = 0

	else if(emagged && !M.incapacitated()) //check incapacitated so emagged secbots don't keep attacking the same target forever
		threat = 10

	else
		threat = M.assess_perp(access_scanner, 0, idcheck, check_records, check_arrest) // Set base threat level
		if(attacked)
			threat += SECBOT_THREAT_ATTACK // Increase enough so we can attack immediately in return

//Secbot Construction

/obj/item/clothing/head/helmet/attackby(obj/item/assembly/signaler/S, mob/user as mob)
	..()
	if(!issignaler(S))
		..()
		return

	if(type != /obj/item/clothing/head/helmet) //Eh, but we don't want people making secbots out of space helmets.
		return

	if(S.secured)
		qdel(S)
		var/obj/item/secbot_assembly/A = new /obj/item/secbot_assembly
		user.put_in_hands(A)
		to_chat(user, "You add the signaler to the helmet.")
		user.drop_from_inventory(src)
		qdel(src)
	else
		return

/obj/item/secbot_assembly
	name = "helmet/signaler assembly"
	desc = "Some sort of bizarre assembly."
	icon = 'icons/obj/aibots.dmi'
	icon_state = "helmet_signaler"
	item_icons = list(
			slot_l_hand_str = 'icons/mob/items/lefthand_hats.dmi',
			slot_r_hand_str = 'icons/mob/items/righthand_hats.dmi',
			)
	item_state = "helmet"
	var/build_step = 0
	var/created_name = "Securitron"
	construction_graph = /datum/construction_graph/secbot_assembly

// Renaming the finished bot is not construction: keep it a plain interaction.
/obj/item/secbot_assembly/attackby(obj/item/W, mob/user)
	..()
	if(istype(W, /obj/item/pen))
		var/t = sanitizeSafe(tgui_input_text(user, "Enter new robot name", name, created_name, MAX_NAME_LEN, encode = FALSE), MAX_NAME_LEN)
		if(!t)
			return
		if(!in_range(src, user) && loc != user)
			return
		created_name = t

/**
 * The Securitron assembly: a helmet welded open, then a signaler (added by
 * the helmet itself, see above), a prox sensor, a robot arm and a baton.
 * `build_step` is the graph's state_var. The baton step branches by type
 * (a slime baton makes a `/mob/living/bot/secbot/slime`) without a state fork.
 */
/datum/construction_graph/secbot_assembly
	id = "secbot_assembly"
	states = list(0, 1, 2, 3)
	initial_states = list(0)
	state_var = "build_step"
	edge_types = list(
		/datum/interaction/construction/secbot/weld_hole,
		/datum/interaction/construction/secbot/prox,
		/datum/interaction/construction/secbot/arm,
		/datum/interaction/construction/secbot/baton,
	)

/datum/interaction/construction/secbot/weld_hole
	from_state = 0
	to_state = 1
	step_text = "weld a hole in it"
	tool = TOOL_WELDER

/datum/interaction/construction/secbot/weld_hole/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	target.add_overlay("hs_hole")
	to_chat(actor, span_notice("You weld a hole in \the [target]."))
	return TRUE

/datum/interaction/construction/secbot/prox
	from_state = 1
	to_state = 2
	step_text = "add a proximity sensor"
	item_type = /obj/item/assembly/prox_sensor
	item_use = CONSTRUCTION_ITEM_DELETE

/datum/interaction/construction/secbot/prox/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	target.add_overlay("hs_eye")
	target.name = "helmet/signaler/prox sensor assembly"
	to_chat(actor, span_notice("You add \the [held] to [target]."))
	return TRUE

/datum/interaction/construction/secbot/arm
	from_state = 2
	to_state = 3
	step_text = "add a robot arm"
	item_type = list(/obj/item/robot_parts/l_arm, /obj/item/robot_parts/r_arm, /obj/item/organ/external/arm)
	item_name = "a robot arm"
	item_use = CONSTRUCTION_ITEM_DELETE

/datum/interaction/construction/secbot/arm/item_matches(obj/item/held)
	if(istype(held, /obj/item/robot_parts/l_arm) || istype(held, /obj/item/robot_parts/r_arm))
		return TRUE
	return istype(held, /obj/item/organ/external/arm) && (held.name == "robotic right arm" || held.name == "robotic left arm")

/datum/interaction/construction/secbot/arm/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	target.name = "helmet/signaler/prox sensor/robot arm assembly"
	target.add_overlay("hs_arm")
	to_chat(actor, span_notice("You add \the [held] to [target]."))
	return TRUE

/datum/interaction/construction/secbot/baton
	from_state = 3
	to_state = CONSTRUCTION_DONE
	step_text = "attach a stun baton to finish it"
	item_type = /obj/item/melee/baton
	item_use = CONSTRUCTION_ITEM_DELETE

/datum/interaction/construction/secbot/baton/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/secbot_assembly/assembly = target
	to_chat(actor, span_notice("You complete the Securitron! Beep boop."))
	var/turf/where = get_turf(assembly)
	if(istype(held, /obj/item/melee/baton/slime))
		var/mob/living/bot/secbot/slime/bot = new /mob/living/bot/secbot/slime(where)
		bot.name = assembly.created_name
	else
		var/mob/living/bot/secbot/bot = new /mob/living/bot/secbot(where)
		bot.name = assembly.created_name
	actor.drop_from_inventory(assembly)
	qdel(assembly)
	return TRUE

#undef SECBOT_WAIT_TIME
#undef SECBOT_THREAT_ARREST
#undef SECBOT_THREAT_ATTACK
