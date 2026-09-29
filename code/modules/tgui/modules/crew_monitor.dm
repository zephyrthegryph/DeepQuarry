/datum/tgui_module/crew_monitor
	name = "Crew monitor"
	tgui_id = "CrewMonitor"

/datum/tgui_module/crew_monitor/ui_assets(mob/user)
	return list(
		get_asset_datum(/datum/asset/simple/holo_nanomap),
	)

/datum/tgui_module/crew_monitor/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	var/turf/T = get_turf(ui.user)
	if(action && !issilicon(ui.user))
		play_sfx(tgui_host(), SFX_TERMINAL_TYPE)
	if(!T || !(T.z in using_map.player_levels))
		to_chat(ui.user, span_boldwarning("Unable to establish a connection") + ": You're too far away from the station!")
		return FALSE
	return TRUE

UI_ACT(/datum/tgui_module/crew_monitor, "track", ui_act_track, UI_ARG_REF("track", "proc:ui_source_registry_members_registry_mobs", /mob/living/carbon/human))
UI_ACT_PROC(/datum/tgui_module/crew_monitor, ui_act_track)
	if(isAI(ui.user))
		var/mob/living/silicon/ai/AI = ui.user
		var/mob/living/carbon/human/H = params["track"]
		if(hassensorlevel(H, SUIT_SENSOR_TRACKING))
			AI.ai_actual_track(H)
	return TRUE

UI_ACT(/datum/tgui_module/crew_monitor, "setZLevel", ui_act_setzlevel, UI_ARG_VALUE("mapZLevel"))
UI_ACT_PROC(/datum/tgui_module/crew_monitor, ui_act_setzlevel)
	ui.set_map_z_level(params["mapZLevel"])
	return TRUE

/// The list the UI_ARG_REF rows resolve refs in.
/datum/tgui_module/crew_monitor/proc/ui_source_registry_members_registry_mobs()
	return REGISTRY_MEMBERS(REGISTRY_MOBS)

DECLARE_UI(/datum/tgui_module/crew_monitor, UI_FROM_VAR("tgui_id"), UI_AUTOUPDATE)

/datum/tgui_module/crew_monitor/ui_prepare(mob/user, datum/tgui/ui)
	var/z = get_z(user)
	var/list/map_levels = using_map.get_visible_map_levels(z, TRUE)

	if(!map_levels.len)
		to_chat(user, span_warning("The crew monitor doesn't seem like it'll work here."))
		return FALSE

	return TRUE

/datum/tgui_module/crew_monitor/tgui_data(mob/user)
	var/data[0]

	data["isAI"] = isAI(user)

	var/z = get_z(user)
	var/list/map_levels = uniqueList(using_map.get_visible_map_levels(z, TRUE))
	data["map_levels"] = map_levels

	var/list/crewmembers = list()
	for(var/zlevel in map_levels)
		crewmembers += GLOB.crew_repository.health_data(zlevel)

	// This is apparently necessary, because the above loop produces an emergent behavior
	// of telling you what coordinates someone is at even without sensors on,
	// because it strictly sorts by zlevel from bottom to top, and by coordinates from top left to bottom right.
	shuffle_inplace(crewmembers)
	data["crewmembers"] = crewmembers

	return data

/datum/tgui_module/crew_monitor/ntos
	ntos = TRUE

// Subtype for glasses_state
/datum/tgui_module/crew_monitor/glasses
/datum/tgui_module/crew_monitor/glasses/tgui_state(mob/user)
	return GLOB.tgui_glasses_state

// Subtype for self_state
/datum/tgui_module/crew_monitor/robot
/datum/tgui_module/crew_monitor/robot/tgui_state(mob/user)
	return GLOB.tgui_self_state

// Subtype for nif_state
/datum/tgui_module/crew_monitor/nif
/datum/tgui_module/crew_monitor/nif/tgui_state(mob/user)
	return GLOB.tgui_nif_state
