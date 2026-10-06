/mob/living/bot
	name = "Bot"
	endurance = 20
	icon = 'icons/obj/aibots.dmi'
	layer = MOB_LAYER
	universal_speak = 1
	density = FALSE

	makes_dirt = FALSE	// No more dirt from Beepsky

	var/obj/item/card/id/botcard = null
	var/list/botcard_access = list() // ALLOW(instance_list): d: per-mob botcard_access, filled at runtime; mobs are few
	var/on = 1
	var/open = 0
	var/locked = 1
	var/emagged = 0
	var/light_strength = 3
	var/obj/item/paicard/paicard = null
	var/obj/access_scanner = null
	var/list/req_access = list() // ALLOW(instance_list): d: per-mob req_access, filled at runtime; mobs are few
	var/list/req_one_access = list() // ALLOW(instance_list): d: per-mob req_one_access, filled at runtime; mobs are few

	var/atom/target = null
	/// How often each target was given up on, keyed by REF(target) text: AI memory, not a reference.
	var/list/ignore_past
	/// Targets the bot is currently ignoring (REL_LIST, cleared by the framework when they die).
	var/list/ignore_list
	var/list/patrol_path = list() // ALLOW(instance_list): d: per-mob patrol_path, sized at creation and filled in place; mobs are few
	var/list/target_path = list() // ALLOW(instance_list): d: per-mob target_path, sized at creation and filled in place; mobs are few
	var/turf/obstacle = null
	/// TRUE while a detached handleAI() tick is still running (see start_ai()).
	var/ai_running = FALSE

	var/wait_if_pulled = 0 // Only applies to moving to the target
	var/will_patrol = 0 // If set to 1, will patrol, duh
	var/patrol_speed = 1 // How many times per tick we move when patrolling
	var/target_speed = 2 // Ditto for chasing the target
	var/panic_on_alert = FALSE	// Will the bot go faster when the alert level is raised?
	var/min_target_dist = 1 // How close we try to get to the target
	var/max_target_dist = 50 // How far we are willing to go
	var/max_patrol_dist = 250

	var/target_patience = 5
	var/frustration = 0
	var/max_frustration = 0
	can_pain_emote = FALSE // Sanity/safety, if bots ever get emotes later, undo this

	can_pain_emote = FALSE // Sanity/safety, if bots ever get emotes later, undo this
	allow_mind_transfer = TRUE

/// Whoever presses a button of the bot's window leaves their prints on it.
/mob/living/bot/proc/ui_fingerprint(datum/act/op/A)
	add_fingerprint(A.actor)

/mob/living/bot/Initialize(mapload)
	. = ..()

	botcard.access = botcard_access.Copy()

	access_scanner.req_access = req_access.Copy()
	access_scanner.req_one_access = req_one_access.Copy()

	if(!using_map.bot_patrolling)
		will_patrol = FALSE

	if(on)
		turn_on() // Update lights and other stuff
	update_icons()
	default_language = GLOB.all_languages[LANGUAGE_GALCOM]

/// Bots shrug off stuns and run their AI (the old bot Life() tail after ..()).
/mob/living/bot/proc/life_bot_core(datum/seq_frame/life/F)
	if(src.stat == DEAD)
		return
	src.status_set(STAT_WEAKENED, 0)
	src.status_set(STAT_STUNNED, 0)
	src.status_set(STAT_PARALYZED, 0)

	if(src.on && !src.client && !task_busy(src) && !src.paicard && !src.ai_running)
		after(src, 0, TYPE_PROC_REF(/mob/living/bot, start_ai)) // deferred off the Life stage (was spawn)

/mob/living/bot/life_type_post_due()
	return TRUE
/*
/mob/living/bot/examine(mob/user)
	. = ..()
	if(is_injured())
		if(vitality() > 1/3)
			. += "[src]'s parts look loose."
		else
			. += "[src]'s parts look very loose!"
	else
		. += "[src] is in pristine condition."
	. += span_notice("Its maintenance panel is [open ? "open" : "closed"].")
	. += span_info("You can use a <b>screwdriver</b> to [open ? "close" : "open"] it.")
	. += span_notice("Its control panel is [locked ? "locked" : "unlocked"].")
	if(paicard)
		. += span_notice("It has a pAI device installed.")
		if(open)
			. += span_info("You can use a <b>crowbar</b> to remove it.")
*/
/// Bots don't leave a corpse: they blow apart instead of dying.
/mob/living/bot/replace_death(gibbed)
	explode()
	return TRUE

EXTEND_INTERACTIONS(/mob/living/bot, INTERACT_ITEM(null, PROC_REF(bot_interaction_item)))

/// Old attackby: ID lock toggle, prox-sensor repair, pAI card; anything else reaches the attack.
/mob/living/bot/proc/bot_interaction_item(mob/user, obj/item/O, datum/interaction/interaction)
	if(O.GetID())
		if(access_scanner.allowed(user) && !open)
			locked = !locked
			to_chat(user, span_notice("Controls are now [locked ? "locked." : "unlocked."]"))
			attack_hand(user)
			if(emagged)
				to_chat(user, span_warning("ERROR! SYSTEMS COMPROMISED!"))
		else
			if(open)
				to_chat(user, span_warning("Please close the access panel before locking it."))
			else
				to_chat(user, span_warning("Access denied."))
		return TRUE
	else if(istype(O, /obj/item/assembly/prox_sensor) && emagged)
		if(open)
			to_chat(user, span_notice("You repair the bot's systems."))
			emagged = 0
			consume(O, user)
		else
			to_chat(user, span_notice("Unable to repair with the maintenance panel closed."))
		return TRUE
	else if(istype(O, /obj/item/paicard))
		if(open)
			insertpai(user, O)
			to_chat(user, span_notice("You slot the card into \the [initial(src.name)]."))
		else
			to_chat(user, span_notice("You must open the panel first!"))
		return TRUE
	return FALSE

/mob/living/bot/screwdriver_act(mob/user, obj/item/tool)
	if(locked)
		to_chat(user, span_notice("You need to unlock the controls first."))
		return ITEM_INTERACT_BLOCKING
	open = !open
	to_chat(user, span_notice("Maintenance panel is now [open ? "opened" : "closed"]."))
	playsound(src, tool.usesound, 50, TRUE)
	return ITEM_INTERACT_SUCCESS

/mob/living/bot/welder_act(mob/user, obj/item/tool)
	if(!is_injured() || !open)
		return ITEM_INTERACT_BLOCKING
	mend(TREAT_PLATING_REPAIR, 10)
	mend(TREAT_WIRING_REPAIR, 10)
	act_message(user, src, MSG_SELF(span_notice("You repair %T%.")), MSG_OTHERS(span_notice("%U% repairs %T%.")))
	playsound(src, tool.usesound, 50, TRUE)
	return ITEM_INTERACT_SUCCESS

/mob/living/bot/crowbar_act(mob/user, obj/item/tool)
	if(!open || !paicard)
		return ITEM_INTERACT_BLOCKING
	to_chat(user, span_notice("You are attempting to remove the pAI."))
	task_timed(user, 1 SECOND * tool.toolspeed, target = src, receiver = src, on_done = PROC_REF(crowbar_act_bot_done), done_args = list(user))
	return ITEM_INTERACT_SUCCESS

/mob/living/bot/proc/crowbar_act_bot_done(mob/user)
	ejectpai(user)
	return ITEM_INTERACT_SUCCESS

/mob/living/bot
	silicon_use = SILICON_USE_HAND

/mob/living/bot/say_quote(message, datum/language/speaking = null)
	return "beeps"

/mob/living/bot/speech_bubble_appearance()
	return "machine"

/mob/living/bot/Bump(atom/A)
	if(on && botcard && istype(A, /obj/machinery/door))
		var/obj/machinery/door/D = A
		if(!istype(D, /obj/machinery/door/firedoor) && !istype(D, /obj/machinery/door/blast) && !istype(D, /obj/machinery/door/airlock/lift) && D.check_access(botcard))
			D.open()
	else
		..()

DECLARE_EMAG_REPEATABLE(/mob/living/bot, PROC_REF(on_emag), null)
/mob/living/bot/proc/on_emag(remaining_charges, mob/user, obj/item/emag_source)
	return 0

/// Calls `step_proc` `count` times, `delay` apart (the bot's movement within one AI tick).
/mob/living/bot/proc/bot_steps(count, delay, step_proc)
	if(count <= 0)
		return
	after(src, delay, PROC_REF(bot_step), with = list(count, delay, step_proc))

/// OM callback: a step can path (calcTargetPath/startPatrol sleep on the pathfinder), so it runs detached.
/mob/living/bot/proc/bot_step(count, delay, step_proc)
	INVOKE_ASYNC(src, PROC_REF(run_bot_step), count, delay, step_proc) // ALLOW(scheduler): a bot step can sleep on the pathfinder, which scheduler callbacks must not

/mob/living/bot/proc/run_bot_step(count, delay, step_proc)
	call(src, step_proc)()
	bot_steps(count - 1, delay, step_proc)

/// OM callback for one AI tick. handleAI() can legitimately sleep (pathfinding waits on the
/// pathfinder mutex and CHECK_TICKs through its search), and scheduler callbacks must not
/// sleep, so the tick runs detached. `ai_running` keeps a slow tick from overlapping the next.
/mob/living/bot/proc/start_ai()
	if(ai_running)
		return
	ai_running = TRUE
	INVOKE_ASYNC(src, PROC_REF(run_ai)) // ALLOW(scheduler): handleAI() sleeps on the pathfinder mutex; ai_running guards overlap

/mob/living/bot/proc/run_ai()
	try
		handleAI()
	catch(var/exception/e)
		ai_running = FALSE
		throw e
	ai_running = FALSE

/mob/living/bot/proc/handleAI()
	if(length(ignore_list))
		for(var/atom/A as anything in ignore_list.Copy())
			if(!A.loc || prob(1))
				var/past_key = REF(A)
				if(past_key in ignore_past)
					if(prob(10/ignore_past[past_key]) || !A.loc)
						ignore_past[past_key]++
						rel_remove(src, nameof(ignore_list), A)
				else
					LAZYSET(ignore_past, past_key, 1)
					rel_remove(src, nameof(ignore_list), A)
	handleRegular()

	var/panic_speed_mod = 0

	if(panic_on_alert)
		panic_speed_mod = handlePanic()

	if(target && confirmTarget(target))
		if(Adjacent(target))
			handleAdjacentTarget()
		else
			handleRangedTarget()
		if(!wait_if_pulled || !src?.pulled_by_mob())
			bot_steps(target_speed + panic_speed_mod, 20 / (target_speed + panic_speed_mod + 1), PROC_REF(stepToTarget))
		if(max_frustration && frustration > max_frustration * target_speed)
			handleFrustrated(1)
	else
		resetTarget()
		lookForTargets()
		if(will_patrol && !src?.pulled_by_mob() && !target)
			if(patrol_path && patrol_path.len)
				bot_steps(patrol_speed + panic_speed_mod, 20 / (patrol_speed + 1), PROC_REF(handlePatrol))
				if(max_frustration && frustration > max_frustration * patrol_speed)
					handleFrustrated(0)
			else
				startPatrol()
		else
			if((locate_within(loc, /obj/machinery/door)) && !src?.pulled_by_mob()) //Don't hang around blocking doors, but don't run off if someone tries to pull us through one.
				var/turf/my_turf = get_turf(src)
				var/list/can_go = my_turf.CardinalTurfsWithAccess(botcard)
				if(LAZYLEN(can_go))
					if(step_towards(src, pick(can_go)))
						return
			for(var/mob in contents_of(loc))
				if(isbot(mob) && mob != src) // Same as above, but we also don't want to have bots ontop of bots. Cleanbots shouldn't stack >:(
					var/turf/my_turf = get_turf(src)
					var/list/can_go = my_turf.CardinalTurfsWithAccess(botcard)
					if(LAZYLEN(can_go))
						if(step_towards(src, pick(can_go)))
							return
			handleIdle()

/mob/living/bot/proc/handleRegular()
	return

/mob/living/bot/proc/handleAdjacentTarget()
	return

/mob/living/bot/proc/handleRangedTarget()
	return

/mob/living/bot/proc/handlePanic()	// Speed modification based on alert level.
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

/mob/living/bot/proc/stepToTarget()
	if(!target || !target.loc)
		return
	if(get_dist(src, target) > min_target_dist)
		if(!target_path.len || get_turf(target) != target_path[target_path.len])
			calcTargetPath()
		if(makeStep(target_path))
			frustration = 0
		else if(max_frustration)
			frustration++
	return

/mob/living/bot/proc/handleFrustrated(has_target)
	rel_clear(src, nameof(obstacle))
	if (has_target)
		if (length(target_path))
			rel_set(src, nameof(obstacle), target_path[1])
	else if (length(patrol_path))
		rel_set(src, nameof(obstacle), patrol_path[1])
	target_path = list()
	patrol_path = list()

/mob/living/bot/proc/lookForTargets()
	return

/mob/living/bot/proc/confirmTarget(atom/A)
	if(A.invisibility >= INVISIBILITY_LEVEL_ONE)
		return 0
	if(A in ignore_list)
		return 0
	if(!A.loc)
		return 0
	return 1

/mob/living/bot/proc/handlePatrol()
	if(makeStep(patrol_path))
		frustration = 0
	else if(max_frustration)
		frustration++
	return

/mob/living/bot/proc/startPatrol()
	var/turf/T = getPatrolTurf()
	if(T)
		patrol_path = om_pathfinder().default_bot_pathfinding(src, T, 1)
		if(!patrol_path)
			patrol_path = list()
		rel_clear(src, nameof(obstacle))
	return

/mob/living/bot/proc/getPatrolTurf()
	var/minDist = INFINITY
	var/obj/machinery/navbeacon/targ = locate_within(get_turf(src), /obj/machinery/navbeacon)

	if(!targ)
		for(var/obj/machinery/navbeacon/N in REGISTRY_MEMBERS(REGISTRY_NAVBEACONS))
			if(!LAZYACCESS(N.codes, "patrol"))
				continue
			if(get_dist(src, N) < minDist)
				minDist = get_dist(src, N)
				targ = N

	if(targ && LAZYACCESS(targ.codes, "next_patrol"))
		for(var/obj/machinery/navbeacon/N in REGISTRY_MEMBERS(REGISTRY_NAVBEACONS))
			if(N.location == LAZYACCESS(targ.codes, "next_patrol"))
				targ = N
				break

	if(targ)
		return get_turf(targ)
	return null

/mob/living/bot/proc/handleIdle()
	return

/mob/living/bot/proc/calcTargetPath()
	target_path = om_pathfinder().default_bot_pathfinding(src, get_turf(target), 0)
	if(!target_path)
		if(target && target.loc)
			rel_add(src, nameof(ignore_list), target)
		resetTarget()
		rel_clear(src, nameof(obstacle))
	else if(target)
		LAZYREMOVE(ignore_past, REF(target))
	return

/mob/living/bot/proc/makeStep(list/path)
	if(!path.len)
		return 0
	var/turf/T = path[1]
	if(get_turf(src) == T)
		path -= T
		return makeStep(path)

	return step_towards(src, T)

/mob/living/bot/proc/resetTarget()
	rel_clear(src, nameof(target))
	target_path = list()

/mob/living/bot/proc/turn_on()
	if(stat)
		return 0
	set_on(1)
	set_light(light_strength)
	update_icons()
	resetTarget()
	patrol_path = list()
	rel_clear(src, nameof(ignore_list))
	update_canmove()
	return 1

/// The bot works on `A` for `delay` (a timed action): it is busy -- its task claims it -- until
/// the work ends, then `on_done`(done_args...) runs and the icon refreshes (also on failure).
/// Returns the task, or a reason it didn't start.
/mob/living/bot/proc/bot_work(delay, atom/A, on_done, list/done_args, timed_action_flags = NONE)
	. = task_timed(src, delay, target = A, receiver = src, on_done = PROC_REF(bot_work_done), done_args = list(on_done) + (done_args || list()), timed_action_flags = timed_action_flags, on_fail = PROC_REF(update_icons), busy = src)
	update_icons()

/mob/living/bot/proc/bot_work_done(on_done, ...)
	call(src, on_done)(arglist(args.Copy(2)))
	update_icons()

/mob/living/bot/proc/turn_off()
	set_on(0)
	task_release_busy(src, "turned off") // If ever stuck... reboot!
	set_light(0)
	update_icons()
	update_canmove()

/mob/living/bot/proc/explode()
	if(paicard)
		ejectpai()
	release_vore_contents()
	destroyed(src, null, "explosion")

/mob/living/bot/is_sentient()
	if(paicard)
		return TRUE
	return FALSE

/******************************************************************/
// Navigation procs
// Used for A-star pathfinding

// Returns the surrounding GLOB.cardinal turfs with open links
// Including through doors openable with the ID
/turf/proc/CardinalTurfsWithAccess(obj/item/card/id/ID)
	var/L[] = new()


	for(var/d in GLOB.cardinal)
		var/turf/T = get_step(src, d)
		if(istype(T) && !T.density)
			if(!LinkBlockedWithAccess(src, T, ID))
				L.Add(T)
	return L

// Diagonal-friendly version of CardinalTurfWithAccess
/turf/proc/AdjacentTurfsWithAccess(obj/item/card/id/ID)
	var/list/L = new()

	for(var/dir_to_check in GLOB.alldirs) // Cardinals first.
		var/turf/T = get_step(src, dir_to_check)
		if(!T || T.density || !T.Adjacent(src))
			continue
		if(!LinkBlockedWithAccess(src, T, ID))
			L.Add(T)

	return L

// Similar to above but not restricted to just GLOB.cardinal directions.
/turf/proc/TurfsWithAccess(obj/item/card/id/ID)
	var/L[] = new()

	for(var/d in GLOB.alldirs)
		var/turf/T = get_step(src, d)
		if(istype(T) && !T.density)
			if(!LinkBlockedWithAccess(src, T, ID))
				L.Add(T)
	return L

// Returns true if a link between A and B is blocked
// Movement through doors allowed if ID has access
/proc/LinkBlockedWithAccess(turf/A, turf/B, obj/item/card/id/ID)

	if(A == null || B == null) return 1
	var/adir = get_dir(A,B)
	var/rdir = get_dir(B,A)
	if((adir & (NORTH|SOUTH)) && (adir & (EAST|WEST)))	//	diagonal
		var/iStep = get_step(A,adir&(NORTH|SOUTH))
		if(!LinkBlockedWithAccess(A,iStep, ID) && !LinkBlockedWithAccess(iStep,B,ID))
			return 0

		var/pStep = get_step(A,adir&(EAST|WEST))
		if(!LinkBlockedWithAccess(A,pStep,ID) && !LinkBlockedWithAccess(pStep,B,ID))
			return 0
		return 1

	if(DirBlockedWithAccess(A,adir, ID))
		return 1

	if(DirBlockedWithAccess(B,rdir, ID))
		return 1

	for(var/obj/O in turf_contents_of_type(B, /obj))
		if(O.density && !istype(O, /obj/machinery/door) && !(O.flags & ON_BORDER))
			return 1

	return 0

// Returns true if direction is blocked from loc
// Checks doors against access with given ID
/proc/DirBlockedWithAccess(turf/loc,dir,obj/item/card/id/ID)
	for(var/obj/structure/window/D in turf_contents_of_type(loc, /obj/structure/window))
		if(!D.density)			continue
		if(D.dir == SOUTHWEST)	return 1
		if(D.dir == dir)		return 1

	for(var/obj/machinery/door/D in turf_contents_of_type(loc, /obj/machinery/door))
		if(!D.density)			continue

		if(istype(D, /obj/machinery/door/airlock))
			var/obj/machinery/door/airlock/A = D
			if(!A.can_open())	return 1

		if(istype(D, /obj/machinery/door/window))
			if( dir & D.dir )	return !D.check_access(ID)

		else return !D.check_access(ID)	// it's a real, air blocking door
	return 0

/mob/living/bot/update_canmove()
	..()
	canmove = on
	return canmove

/mob/living/bot/proc/insertpai(mob/user, obj/item/paicard/card)
	var/mob/living/silicon/pai/AI = card.pai
	if(paicard)
		to_chat(user, span_notice("This bot is already under PAI Control!"))
		return
	if(!istype(card)) // TODO: Add sleevecard support.
		return
	if(client)
		to_chat(user, span_notice("Higher levels of processing are already present!"))
		return
	if(!card.pai)
		to_chat(user, span_notice("This card does not currently have a personality!"))
		return
	if(!move_into(src, nameof(src.paicard), card, user))
		return
	transfer_mind(AI.mind, src, "pAI installed into [src]")
	name = AI.name
	to_chat(src, span_notice("You feel a tingle in your circuits as your systems interface with \the [initial(src.name)]."))
	if(AI.idcard.GetAccess())
		botcard.access	|= AI.idcard.GetAccess()

/mob/living/bot/proc/ejectpai(mob/user)
	if(paicard)
		var/mob/living/silicon/pai/AI = paicard.pai
		transfer_mind(mind, AI, "pAI ejected from [src]")
		paicard.forceMove(src.loc)
		own_take(src, nameof(paicard))
		name = initial(name)
		botcard.access = botcard_access.Copy()
		to_chat(AI, span_notice("You feel a tad claustrophobic as your mind closes back into your card, ejecting from \the [initial(src.name)]."))

		if(user)
			to_chat(user, span_notice("You eject the card from \the [initial(src.name)]."))

/mob/living/bot/verb/bot_nom(mob/living/T in oview(1))
	set name = "Bot Nom"
	set category = VERB_CAT_BOT_COMMANDS
	set desc = "Allows you to eat someone. Yum."

	if (stat != CONSCIOUS)
		return
	return feed_grabbed_to_self(src,T)

/mob/living/bot/verb/ejectself()
	set name = "Eject pAI"
	set category = VERB_CAT_BOT_COMMANDS
	set desc = "Eject your card, return to smole."

	return ejectpai()

/mob/living/bot/Login()
	no_vore = FALSE // ROBOT VORE
	grant(src, granted_verb(/mob/proc/insidePanel), src)

	return ..()

/mob/living/bot/Logout()
	release_vore_contents()
	revoke(src, granted_verb(/mob/proc/insidePanel), src)
	no_vore = TRUE
	devourable = FALSE
	feeding = FALSE
	can_be_drop_pred = FALSE

	return ..()

// === merged from bot_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/mob/living/bot
	no_vore = TRUE
	devourable = FALSE
	feeding = FALSE
	can_be_drop_pred = FALSE

CAPABILITIES(/mob/living/bot)
	/// Things the bot gave up on: AI memory, re-learned as it patrols. The bot owns none of them.
	ref_many(nameof(ignore_list))
	owns_one(nameof(botcard), starts = /obj/item/card/id)
	owns_one(nameof(access_scanner), starts = /obj)
	extend(TAG_UI, then(PROC_REF(ui_fingerprint)))

/mob/living/bot/ownership()
	. = ..()
	. += owns(nameof(paicard), policy = OWN_CONTAINED)


// Tracked inputs of the Life presentation reactions (HUD, sight, canmove; living_systems.dm): their setters publish.
TRACKED(/mob/living/bot, on)
