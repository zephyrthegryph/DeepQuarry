/datum/tgui_module/crew_monitor
	name = "Crew monitor"

/datum/tgui_module/crew_monitor/ui_assets(mob/user)
	return list(
		get_asset_datum(/datum/asset/simple/holo_nanomap),
	)

/// Every button clicks (unless a silicon presses it) and works only on the station's levels.
/datum/tgui_module/crew_monitor/proc/ui_typed(datum/act/op/A)
	if(!(A.authority & AUTH_REMOTE_ACCESS))
		play_sfx(tgui_host(), SFX_TERMINAL_TYPE)
	return OP_OK

/datum/tgui_module/crew_monitor/proc/ui_in_range(datum/act/op/A)
	var/turf/T = get_turf(A.actor)
	return T && (T.z in using_map.player_levels)

MSG_DEF_SELF(crew_monitor/out_of_range, "Unable to establish a connection: You're too far away from the station!")

/datum/tgui_module/crew_monitor/ui_opening(mob/user, datum/tgui/ui)
	..()
	ui.set_autoupdate(TRUE)

CAPABILITIES(/datum/tgui_module/crew_monitor)
	interface("CrewMonitor")
	extend(TAG_UI, then(PROC_REF(ui_typed), early = TRUE))
	extend(TAG_UI, needs(req_bool(PROC_REF(ui_in_range), because = MSG(crew_monitor/out_of_range))))
	op("track", ui_act("track", arg("track", schema_ref(/mob/living/carbon/human))), needs(req_actor_kind(/mob/living/silicon/ai, because = /datum/msg/req_silent)), then(PROC_REF(ui_act_track)))
	op("setZLevel", ui_act("setZLevel", arg("mapZLevel", num())), then(PROC_REF(ui_act_setzlevel)))

/datum/tgui_module/crew_monitor/proc/ui_act_track(datum/act/op/A, mob/living/carbon/human/track)
	var/mob/living/silicon/ai/AI = A.actor
	var/mob/living/carbon/human/H = track
	if(istype(H) && hassensorlevel(H, SUIT_SENSOR_TRACKING))
		AI.ai_actual_track(H)
	return TRUE

/datum/tgui_module/crew_monitor/proc/ui_act_setzlevel(datum/act/op/A, mapZLevel)
	var/datum/tgui/ui = SStgui.get_open_ui(A.actor, src)
	ui?.set_map_z_level(mapZLevel)
	return TRUE

/datum/tgui_module/crew_monitor/ui_prepare(mob/user, datum/tgui/ui)
	var/z = get_z(user)
	var/list/map_levels = using_map.get_visible_map_levels(z, TRUE)

	if(!map_levels.len)
		to_chat(user, span_warning("The crew monitor doesn't seem like it'll work here."))
		return FALSE

	return TRUE

/datum/tgui_module/crew_monitor/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/list/data = list()

	data["isAI"] = istype(user, /mob/living/silicon/ai)

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
CAPABILITIES(/datum/tgui_module/crew_monitor/glasses)
	interface("CrewMonitor", state = nameof(GLOB.tgui_glasses_state))

// Subtype for self_state
/datum/tgui_module/crew_monitor/robot
CAPABILITIES(/datum/tgui_module/crew_monitor/robot)
	interface("CrewMonitor", state = nameof(GLOB.tgui_self_state))

// Subtype for nif_state
/datum/tgui_module/crew_monitor/nif
CAPABILITIES(/datum/tgui_module/crew_monitor/nif)
	interface("CrewMonitor", state = nameof(GLOB.tgui_nif_state))
