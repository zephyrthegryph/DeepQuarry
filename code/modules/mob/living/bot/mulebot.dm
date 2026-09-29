#define MULE_IDLE 0
#define MULE_MOVING 1
#define MULE_UNLOAD 2
#define MULE_LOST 3
#define MULE_CALC_MIN 4
#define MULE_CALC_MAX 10
#define MULE_PATH_DONE 11
// IF YOU CHANGE THOSE, UPDATE THEM IN pda.tmpl TOO

/mob/living/bot/mulebot
	name = "Mulebot"
	desc = "A Multiple Utility Load Effector bot."
	icon_state = "mulebot0"
	/// Last accountable operator for generic automation-contract attribution.
	var/contract_operator_account
	var/contract_operator_name
	var/contract_operator_department
	anchored = TRUE
	density = TRUE
	endurance = 150
	mob_bump_flag = HEAVY

	min_target_dist = 0
	max_target_dist = 250
	target_speed = 3
	max_frustration = 5
	botcard_access = list(ACCESS_MAINT_TUNNELS, ACCESS_MAILSORTING, ACCESS_CARGO, ACCESS_CARGO_BOT, ACCESS_QM, ACCESS_MINING, ACCESS_MINING_STATION)

	var/atom/movable/load

	var/paused = 0
	var/crates_only = 1
	var/auto_return = 1
	var/safety = 1

	var/targetName
	var/turf/home
	var/homeName

	var/global/amount = 0

/mob/living/bot/mulebot/Initialize(mapload)
	. = ..()

	var/turf/T = get_turf(loc)
	var/obj/machinery/navbeacon/N = locate_on(T, /obj/machinery/navbeacon)
	if(N)
		rel_set(src, "home", T)
		homeName = N.location
	else
		homeName = "Unset"

	suffix = num2text(++amount) // Starts from 1

	name = "Mulebot #[suffix]"

// DECLARE, not EXTEND: the item effect calls the bot's own effect first (old `..()` then update_icons()),
// so the inherited bot spec must not run a second time.
DECLARE_INTERACTIONS(/mob/living/bot/mulebot, \
	INTERACT_ITEM(null, PROC_REF(mulebot_interaction_item)), \
	INTERACT_HAND_UNGATED("Open controls", TYPE_PROC_REF(/atom, interaction_open_ui)), \
	INTERACT_DRAG("Load", PROC_REF(mulebot_interaction_drag)))

/// Old MouseDrop_T: load the dropped thing. Takes every drop (the old override never reached the drag-buckle).
/mob/living/bot/mulebot/proc/mulebot_interaction_drag(mob/user, atom/movable/C, datum/interaction/interaction)
	if(user.stat)
		return TRUE

	if(!istype(C) || C.anchored || get_dist(user, src) > 1 || get_dist(src, C) > 1 )
		return TRUE

	load(C)
	return TRUE

/mob/living/bot/mulebot/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "MuleBot", "Mulebot [suffix ? "([suffix])" : ""]")
		ui.open()

/mob/living/bot/mulebot/tgui_data(mob/user)
	var/list/data = ..()
	data["suffix"] = suffix
	data["power"] = on
	data["issillicon"] = issilicon(user)
	data["load"] = load
	data["locked"] = locked
	data["auto_return"] = auto_return
	data["crates_only"] = crates_only
	data["hatch"] = open
	data["safety"] = safety
	return data

/mob/living/bot/mulebot/tgui_act(action, params, datum/tgui/ui)
	if(..())
		return TRUE

	add_fingerprint(ui.user)
	switch(action)
		if("power")
			if(on)
				turn_off()
			else
				turn_on()
			visible_message("[ui.user] switches [on ? "on" : "off"] [src].")
			. = TRUE

		if("stop")
			obeyCommand(ui.user, "Stop")
			. = TRUE

		if("go")
			obeyCommand(ui.user, "GoTD")
			. = TRUE

		if("home")
			obeyCommand(ui.user, "Home")
			. = TRUE

		if("destination")
			obeyCommand(ui.user, "SetD")
			. = TRUE

		if("sethome")
			var/list/beaconlist = GetBeaconList()
			if(beaconlist.len)
				om_ask(ui.user, /datum/om/prompt/choice/mulebot_beacon, PROC_REF(home_tag_chosen), message = "Select new home tag", choices = beaconlist)
			else
				tgui_alert_async(ui.user, "No destination beacons available.")
			. = TRUE

		if("unload")
			unload()
			. = TRUE

		if("autoret")
			auto_return = !auto_return
			. = TRUE

		if("cargotypes")
			crates_only = !crates_only
			. = TRUE

		if("safety")
			safety = !safety
			. = TRUE

/// Picking a beacon for the mulebot (the subject). Re-checked on the answer: its UI is still usable.
/datum/om/prompt/choice/mulebot_beacon
	requires = PROMPT_USABLE

/datum/om/prompt/choice/mulebot_beacon/prepare()
	var/mob/living/bot/mulebot/bot = subject
	title = "Mulebot [bot.suffix ? "([bot.suffix])" : ""]"
	return TRUE

/mob/living/bot/mulebot/proc/home_tag_chosen(datum/om/prompt/choice/mulebot_beacon/ask)
	rel_set(src, "home", get_turf(ask.choices[ask.choice]))
	homeName = ask.choice

/// Old attackby: the bot's item handling (old ..()), then an icon refresh. A FALSE result still reaches the attack.
/mob/living/bot/mulebot/proc/mulebot_interaction_item(mob/user, obj/item/O, datum/interaction/interaction)
	. = bot_interaction_item(user, O, interaction)
	update_icons()

/mob/living/bot/mulebot/proc/obeyCommand(mob/user, command)
	var/mob/living/living_user = user
	var/datum/money_account/operator_account = contract_account_for_mob(living_user)
	if(operator_account)
		contract_operator_account = operator_account.account_number
		contract_operator_name = operator_account.owner_name
		contract_operator_department = operator_account.department_id
	switch(command)
		if("Home")
			resetTarget()
			rel_set(src, "target", home)
			targetName = "Home"
		if("SetD")
			var/list/beaconlist = GetBeaconList()
			if(beaconlist.len)
				om_ask(user, /datum/om/prompt/choice/mulebot_beacon, PROC_REF(destination_tag_chosen), message = "Select new destination tag", choices = beaconlist)
			else
				tgui_alert_async(user, "No destination beacons available.")
		if("GoTD")
			paused = 0
		if("Stop")
			paused = 1

/mob/living/bot/mulebot/proc/destination_tag_chosen(datum/om/prompt/choice/mulebot_beacon/ask)
	resetTarget()
	rel_set(src, "target", get_turf(ask.choices[ask.choice]))
	targetName = ask.choice

/mob/living/bot/mulebot/emag_act(remaining_charges, user)
	locked = !locked
	to_chat(user, span_notice("You [locked ? "lock" : "unlock"] the mulebot's controls!"))
	flick("mulebot-emagged", src)
	play_sfx(src, SFX_EFFECTS_SPARKS1, vary = FALSE)
	return 1

/mob/living/bot/mulebot/update_icons()
	if(open)
		icon_state = "mulebot-hatch"
		return
	if(target_path.len && !paused)
		icon_state = "mulebot1"
		return
	icon_state = "mulebot0"

/mob/living/bot/mulebot/handleRegular()
	if(!safety && prob(1))
		flick("mulebot-emagged", src)
	update_icons()

/mob/living/bot/mulebot/handleFrustrated(has_target)
	automatic_custom_emote(AUDIBLE_MESSAGE, "makes a sighing buzz.")
	play_sfx(src, SFX_MACHINES_BUZZ_SIGH)
	..()

/mob/living/bot/mulebot/handleAdjacentTarget()
	if(target == src.loc)
		var/completed_target = targetName
		var/completed_target_id = target ? REF(target) : completed_target
		var/cargo_type = load?.type
		automatic_custom_emote(AUDIBLE_MESSAGE, "makes a chiming sound.")
		play_sfx(src, SFX_MACHINES_CHIME, vary = FALSE)
		UnarmedAttack(target)
		if(SScontracts && completed_target != "Home")
			emit_contract_event(CONTRACT_EVENT_AUTOMATION_TASK_COMPLETED, list(
				"department" = DEPARTMENT_SYNTHETIC,
				"actor_account" = contract_operator_account,
				"actor_name" = contract_operator_name,
				"actor_department" = contract_operator_department,
				"bot_id" = REF(src),
				"task_kind" = "cargo_delivery",
				"target_id" = completed_target_id,
				"successful" = TRUE,
				"work_units" = 1,
				"cargo_type" = cargo_type,
				"detail" = "[src] completed an autonomous delivery to [completed_target].",
			), "automation:[REF(src)]:delivery:[world.time]", src)
		resetTarget()
		if(auto_return && home && (loc != home))
			rel_set(src, "target", home)
			targetName = "Home"

/mob/living/bot/mulebot/confirmTarget()
	return 1

/mob/living/bot/mulebot/calcTargetPath()
	..()
	if(!target_path.len && target != home) // I presume that target is not null
		resetTarget()
		rel_set(src, "target", home)
		targetName = "Home"

/mob/living/bot/mulebot/stepToTarget()
	if(paused)
		return
	..()

/mob/living/bot/mulebot/UnarmedAttack(turf/T)
	if(T == src.loc)
		unload(dir)

/mob/living/bot/mulebot/Bump(mob/living/M)
	if(!safety && istype(M))
		visible_message(span_warning("[src] knocks over [M]!"))
		M.status_at_least(EFFECT_STUNNED, 8)
		M.status_at_least(EFFECT_WEAKENED, 5)
	..()

/mob/living/bot/mulebot/proc/runOver(mob/living/M)
	if(istype(M)) // At this point, MULEBot has somehow crossed over onto your tile with you still on it. CRRRNCH.
		visible_message(span_warning("[src] drives over [M]!"))
		play_sfx(src, SFX_EFFECTS_SPLAT)

		var/damage = rand(5, 7)
		M.injure(INJURY_BLUNT, 2 * damage, BP_HEAD, src)
		M.injure(INJURY_BLUNT, 2 * damage, BP_TORSO, src)
		M.injure(INJURY_BLUNT, 0.5 * damage, BP_L_LEG, src)
		M.injure(INJURY_BLUNT, 0.5 * damage, BP_R_LEG, src)
		M.injure(INJURY_BLUNT, 0.5 * damage, BP_L_ARM, src)
		M.injure(INJURY_BLUNT, 0.5 * damage, BP_R_ARM, src)

		blood_splatter(src, M, 1)

/mob/living/bot/mulebot/relaymove(mob/user, direction)
	if(load == user)
		unload(direction)

/mob/living/bot/mulebot/explode()
	unload(pick(0, 1, 2, 4, 8))

	visible_message(span_danger("[src] blows apart!"))

	var/turf/Tsec = get_turf(src)
	new /obj/item/assembly/prox_sensor(Tsec)
	new /obj/item/stack/rods(Tsec)
	new /obj/item/stack/rods(Tsec)
	new /obj/item/stack/cable_coil/cut(Tsec)

	fx_sparks(src, 3)

	new /obj/effect/decal/cleanable/blood/oil(Tsec)
	..()

/mob/living/bot/mulebot/proc/GetBeaconList()
	var/list/beaconlist = list()
	for(var/obj/machinery/navbeacon/N in REGISTRY_MEMBERS(REGISTRY_NAVBEACONS))
		if(!LAZYACCESS(N.codes, "delivery"))
			continue
		beaconlist.Add(N.location)
		beaconlist[N.location] = N
	return beaconlist

/mob/living/bot/mulebot/proc/load(atom/movable/C)
	if(om_busy(src) || load || get_dist(C, src) > 1 || !isturf(C.loc))
		return

	for(var/obj/structure/plasticflaps/P in src.loc)//Takes flaps into account
		if(!CanPass(C,P))
			return

	if(crates_only && !istype(C,/obj/structure/closet/crate))
		automatic_custom_emote(AUDIBLE_MESSAGE, "makes a sighing buzz.")
		play_sfx(src, SFX_MACHINES_BUZZ_SIGH)
		return

	var/obj/structure/closet/crate/crate = C
	if(istype(crate))
		crate.close()

	// Busy while the crate settles onto the bot.
	if(istext(om_hold_busy(src, 2)))
		return
	C.forceMove(loc)
	om_after(src, 2, PROC_REF(load_finish), C)

/mob/living/bot/mulebot/proc/load_finish(atom/movable/C)
	if(C.loc != loc) //To prevent you from going onto more than one bot.
		return
	C.forceMove(src)
	own_set(src, "load", C)

	C.pixel_y += 9
	if(C.layer < layer)
		C.layer = layer + 0.1
	add_overlay(C)

/mob/living/bot/mulebot/proc/unload(dirn = 0)
	if(!load || om_busy(src))
		return

	cut_overlays()

	load.forceMove(loc)
	load.pixel_y -= 9
	load.layer = initial(load.layer)

	if(dirn)
		step(load, dirn)

	own_take(src, "load")

	for(var/atom/movable/AM in contents_of(src))
		if(AM == botcard || AM == access_scanner)
			continue

		AM.forceMove(loc)
		AM.layer = initial(AM.layer)
		AM.pixel_y = initial(AM.pixel_y)

#undef MULE_IDLE
#undef MULE_MOVING
#undef MULE_UNLOAD
#undef MULE_LOST
#undef MULE_CALC_MIN
#undef MULE_CALC_MAX
#undef MULE_PATH_DONE


// === merged from mulebot_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/mob/living/bot/mulebot/handle_micro_bump_helping() // Can't drive over micros or macros regardless of intent.
	return 0

/mob/living/bot/mulebot/handle_micro_bump_other() // Can't drive over micros or macros regardless of intent.
	return 0

OWN(/mob/living/bot/mulebot, load, OWN_CONTAINED)
