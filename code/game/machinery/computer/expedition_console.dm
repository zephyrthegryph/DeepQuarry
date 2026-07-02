// Expedition launch console.
//
// The station-side hub of the expedition system: it keeps a board of rolled
// mission offers, launches the selected one (generating a fresh site bound to
// that mission), and bluespace-deploys the crew standing on its pad to the site
// — and recalls them. The matching TGUI is interfaces/ExpeditionConsole.tsx.
//
// Auto-placed by SSexpedition if not mapped in; can also be placed directly on
// a map.
/obj/machinery/computer/expedition
	name = "expedition launch console"
	desc = "Plots, launches, and recalls planetary expeditions. Crew on the pad in front are deployed on launch."
	icon_keyboard = "generic_key"
	icon_screen = "explorer"
	circuit = null
	req_access = list()
	/// Rolled /datum/expedition_mission offers on the board.
	var/list/offers
	/// The site this console currently owns (one at a time).
	var/datum/expedition_site/active_site
	/// world.time the next launch is allowed.
	var/next_launch = 0
	/// Concrete mission types this console can offer.
	var/static/list/mission_types = list(
		/datum/expedition_mission/survey,
		/datum/expedition_mission/extermination,
		/datum/expedition_mission/salvage,
		/datum/expedition_mission/retrieval,
		/datum/expedition_mission/rescue,
		/datum/expedition_mission/derelict,
		/datum/expedition_mission/raid,
		/datum/expedition_mission/recovery,
		/datum/expedition_mission/siege,
		/datum/expedition_mission/recon,
		/datum/expedition_mission/restore,
	)

/obj/machinery/computer/expedition/Initialize(mapload)
	. = ..()
	offers = list()
	SSexpedition.consoles |= src
	roll_offers()

/obj/machinery/computer/expedition/Destroy()
	SSexpedition.consoles -= src
	if(active_site && active_site.origin_console == src)
		active_site.origin_console = null
	active_site = null
	if(offers)
		for(var/datum/expedition_mission/M in offers)
			qdel(M)
		offers = null
	return ..()

/obj/machinery/computer/expedition/attack_hand(mob/user)
	if(..())
		return
	if(stat & (BROKEN|NOPOWER))
		return
	tgui_interact(user)

/obj/machinery/computer/expedition/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "ExpeditionConsole", name)
		ui.open()

/obj/machinery/computer/expedition/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["cooldown"] = max(0, round((next_launch - world.time) / 10))

	var/list/offer_data = list()
	var/idx = 0
	for(var/datum/expedition_mission/M in offers)
		idx++
		offer_data += list(list(
			"index" = idx,
			"name" = M.name,
			"desc" = M.desc,
			"threat" = expedition_faction_name(M.faction_type),
			"brief" = expedition_faction_brief(M.faction_type),
			"difficulty" = difficulty_name(M.difficulty),
			"objective" = M.objective_text(),
			"reward_points" = M.reward_points,
			"reward_cash" = M.reward_cash,
		))
	data["offers"] = offer_data

	if(active_site && !QDELETED(active_site))
		var/datum/expedition_mission/AM = active_site.mission
		data["active"] = list(
			"name" = active_site.name,
			"status" = status_name(active_site.status),
			"difficulty" = difficulty_name(active_site.difficulty),
			"biome" = active_site.biome ? active_site.biome.name : "Unknown",
			"threat" = expedition_faction_name(active_site.faction),
			"brief" = expedition_faction_brief(active_site.faction),
			"size" = expedition_size_name(active_site.size),
			"z" = active_site.z_level,
			"objective" = AM ? AM.objective_text() : "Survey and return.",
			"progress" = AM ? AM.progress_text() : "-",
			"objectives" = AM ? AM.objective_rows() : list(),
			"failed" = AM && AM.state == EXP_MISSION_FAILED,
			"complete" = active_site.status == EXP_STATUS_COMPLETE,
		)
	else
		data["active"] = null

	return data

/obj/machinery/computer/expedition/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	if(..())
		return TRUE
	switch(action)
		if("launch")
			launch(text2num(params["index"]), usr)
			return TRUE
		if("deploy")
			deploy(usr)
			return TRUE
		if("recall")
			recall(usr)
			return TRUE
		if("reroll")
			if(world.time < next_launch)
				to_chat(usr, span_warning("The mission board is locked until the current launch window clears."))
				return TRUE
			roll_offers()
			return TRUE
	return FALSE

// ---- Board ----------------------------------------------------------------

/obj/machinery/computer/expedition/proc/roll_offers()
	if(offers)
		for(var/datum/expedition_mission/M in offers)
			qdel(M)
	offers = list()
	for(var/i in 1 to EXP_OFFER_COUNT)
		offers += make_offer()

/obj/machinery/computer/expedition/proc/make_offer()
	var/mission_type = pick(mission_types)
	// Difficulty skews toward the low/medium end (weighted by repetition, since
	// numeric associative keys aren't allowed for pickweight()).
	var/diff = pick(
		EXP_DIFF_LOW, EXP_DIFF_LOW, EXP_DIFF_LOW, EXP_DIFF_LOW, EXP_DIFF_LOW,
		EXP_DIFF_MED, EXP_DIFF_MED, EXP_DIFF_MED,
		EXP_DIFF_HIGH, EXP_DIFF_HIGH,
	)
	var/datum/expedition_mission/M = new mission_type(diff)
	// Lock in the enemy faction now so the board can advertise the threat, and the
	// generated site uses this exact one (generate_site honours mission.faction_type).
	if(!M.faction_type)
		M.faction_type = expedition_pick_faction(diff)
	// Pay a threat premium for the scarier factions, reflected on the board and at payout.
	var/mult = expedition_faction_danger(M.faction_type)
	M.reward_points = round(M.reward_points * mult)
	M.reward_cash = round(M.reward_cash * mult)
	return M

// ---- Launch / deploy / recall ---------------------------------------------

/obj/machinery/computer/expedition/proc/launch(index, mob/user)
	if(world.time < next_launch)
		to_chat(user, span_warning("Launch systems are recharging."))
		return
	if(active_site && !QDELETED(active_site) && active_site.status != EXP_STATUS_EXPIRED)
		to_chat(user, span_warning("An expedition is already underway. Recall or conclude it first."))
		return
	if(!isnum(index) || index < 1 || index > length(offers))
		return
	var/datum/expedition_mission/mission = offers[index]
	var/datum/expedition_site/site = SSexpedition.generate_site(mission)
	if(!site)
		to_chat(user, span_warning("Site generation failed — no expedition plotted. (See world log.)"))
		return
	site.origin_console = src
	active_site = site
	offers -= mission       // ownership passed to the site
	offers += make_offer()  // refill the board
	next_launch = world.time + EXP_LAUNCH_COOLDOWN
	visible_message(span_notice("[src] chimes: \"[mission.name] plotted to [site.name]. Board the pad and deploy.\""))

/obj/machinery/computer/expedition/proc/deploy(mob/user)
	if(!active_site || QDELETED(active_site))
		to_chat(user, span_warning("No expedition is plotted."))
		return
	if(!active_site.landing)
		to_chat(user, span_warning("No safe landing point on the plotted site."))
		return
	var/turf/center = get_turf(src)
	var/deployed = 0
	for(var/mob/living/L in range(EXP_PAD_RADIUS, center))
		do_teleport(L, active_site.landing, precision = 1, channel = TELEPORT_CHANNEL_BLUESPACE, forced = TRUE)
		active_site.participants |= L
		deployed++
	if(!deployed)
		to_chat(user, span_warning("No one is standing on the launch pad."))
		return
	active_site.status = EXP_STATUS_ACTIVE
	active_site.last_occupied = world.time
	visible_message(span_notice("[src] hums as the pad fires — [deployed] crew deployed to [active_site.name]."))

/obj/machinery/computer/expedition/proc/recall(mob/user)
	if(!active_site || QDELETED(active_site))
		to_chat(user, span_warning("No expedition is plotted."))
		return
	var/turf/dest = get_return_turf()
	if(!dest)
		to_chat(user, span_warning("No clear return point on the station pad."))
		return
	var/recalled = 0
	for(var/mob/M in GLOB.player_list)
		if(M.z != active_site.z_level)
			continue
		do_teleport(M, dest, precision = 1, channel = TELEPORT_CHANNEL_BLUESPACE, forced = TRUE)
		recalled++
	visible_message(span_notice("[src] pulses — emergency recall fired ([recalled] aboard)."))

// ---- Pad helpers ----------------------------------------------------------

/obj/machinery/computer/expedition/proc/get_return_turf()
	var/turf/center = get_turf(src)
	for(var/turf/T in range(1, center))
		if(T == center)
			continue
		if(!T.density && !istype(T, /turf/space))
			return T
	return center

/obj/machinery/computer/expedition/proc/count_on_pad(typepath)
	var/turf/center = get_turf(src)
	var/count = 0
	for(var/turf/T in range(EXP_PAD_RADIUS, center))
		for(var/atom/movable/A in T)
			if(istype(A, typepath))
				count++
	return count

// ---- Display helpers ------------------------------------------------------

/obj/machinery/computer/expedition/proc/difficulty_name(d)
	switch(d)
		if(EXP_DIFF_LOW)
			return "Low"
		if(EXP_DIFF_MED)
			return "Medium"
		if(EXP_DIFF_HIGH)
			return "High"
	return "Unknown"

/obj/machinery/computer/expedition/proc/status_name(s)
	switch(s)
		if(EXP_STATUS_GENERATING)
			return "Plotting"
		if(EXP_STATUS_READY)
			return "Ready — awaiting deployment"
		if(EXP_STATUS_ACTIVE)
			return "In progress"
		if(EXP_STATUS_COMPLETE)
			return "Objective complete"
		if(EXP_STATUS_EXPIRED)
			return "Concluded"
	return "Unknown"
