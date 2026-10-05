/datum/computer_file/data/waypoint
	var/list/fields
	filetype = "WPT"

/datum/computer_file/data/waypoint/New()
	..()
	fields = list()
	join_registries()

REGISTRY_MEMBERSHIP(/datum/computer_file/data/waypoint, REGISTRY_WAYPOINTS)
// End LEGACY_RECORD_STRUCTURE(all_waypoints, waypoint)

/obj/machinery/computer/ship/helm
	name = "flight operations console"
	icon_keyboard = "teleport_key"
	icon_screen = "helm"
	COOLDOWN_DECLARE(map_refresh_cd)
	light_color = "#7faaff"
	circuit = /obj/item/circuitboard/helm
	var/list/known_sectors
	var/dx		//desitnation
	var/dy		//coordinates
	var/speedlimit = 1/(20 SECONDS) //top speed for autopilot, 5
	var/accellimit = 0.001 //manual limiter for acceleration
	// req_one_access = list(ACCESS_PILOT) // // removed hard access locks.
	ai_control = FALSE // AI/Borgs shouldn't really be flying off in ships without crew help

CAPABILITIES(/obj/machinery/computer/ship/helm)
	owns_many(nameof(known_sectors))

OM_FIELD(/obj/machinery/computer/ship/helm, autopilot, FALSE, CHANGE_MACHINE_SETTINGS)
OM_FIELD(/obj/machinery/computer/ship/helm, autopilot_disabled, TRUE, CHANGE_MACHINE_SETTINGS)
DECLARE_PERIODIC_WHILE_ALL(/obj/machinery/computer/ship/helm, MACHINE_PIPELINE, list("autopilot", "!autopilot_disabled"))

// fancy sprite
/obj/machinery/computer/ship/helm/adv
	icon_keyboard = null
	icon_state = "adv_helm"
	icon_screen = "adv_helm_screen"
	light_color = "#70ffa0"

/obj/machinery/computer/ship/helm/Initialize(mapload)
	. = ..()
	get_known_sectors()

/obj/machinery/computer/ship/helm/proc/get_known_sectors()
	// ALLOW(spatial): a deliberate whole-world search: the target is not tied to any holder or z-level index
	var/area/overmap/map = locate() in world
	for(var/obj/effect/overmap/visitable/S in area_contents_of_type(map, /obj/effect/overmap/visitable))
		if(!istype(S,/obj/effect/overmap/visitable/sector) && !istype(S,/obj/effect/overmap/visitable/planet)) // let planets also be favorited via GPS
			continue
		if(S.known)
			var/datum/computer_file/data/waypoint/R = new()
			R.fields["name"] = S.name
			R.fields["x"] = S.x
			R.fields["y"] = S.y
			rel_add(src, nameof(known_sectors), R, S.name)

/obj/machinery/computer/ship/helm/machine_step()
	..()
	if(!dx || !dy || !linked() || !using_map)
		return PROCESS_KILL
	var/turf/T = locate(dx,dy,using_map.overmap_z)
	if(linked().loc == T)
		if(linked().is_still())
			set_autopilot(FALSE)
		else
			linked().decelerate()
	else
		var/brake_path = linked().get_brake_path()
		var/direction = get_dir(linked().loc, T)
		var/acceleration = min(linked().get_acceleration(), accellimit)
		var/speed = linked().get_speed()
		var/heading = linked().get_heading()

		// Destination is current grid or speedlimit is exceeded
		if((get_dist(linked().loc, T) <= brake_path) || speed > speedlimit)
			linked().decelerate()
		// Heading does not match direction
		else if(heading & ~direction)
			linked().accelerate(turn(heading & ~direction, 180), accellimit)
		// All other cases, move toward direction
		else if(speed + acceleration <= speedlimit)
			linked().accelerate(direction, accellimit)

/obj/machinery/computer/ship/helm/relaymove(mob/user, direction)
	if(viewing_overmap(user) && linked())
		linked().relaymove(user, direction, accellimit)
		return 1



/obj/machinery/computer/ship/helm/proc/update_map()
	linked().update_screen()

/obj/machinery/computer/ship/helm/tgui_close(mob/user)
	. = ..()
	// Unregister map objects
	user.client?.clear_map(linked()?.map_name)
	user.reset_perspective()

UI_DATA(/obj/machinery/computer/ship/helm, "d_x=dx", "d_y=dy", "autopilot_disabled:num", "autopilot:num", "merge:ui_data_obj_machinery_computer_ship_helm{mapRef:unknown,sector:text,sector_info:text,landed:unknown,s_x:num,s_y:num,dest:bool,speedlimit:unknown,accel:num,heading:unknown,manual_control:unknown,canburn:unknown,accellimit:unknown,speed:num,speed_color:unknown,ETAnext:text,locations:unknown}")

/// The computed part of /obj/machinery/computer/ship/helm's window data (declared on its UI_DATA row).
/obj/machinery/computer/ship/helm/proc/ui_data_obj_machinery_computer_ship_helm(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	var/turf/T = get_turf(linked())
	var/obj/effect/overmap/visitable/sector/current_sector = locate_on(T, /obj/effect/overmap/visitable/sector)
	if(linked())
		data["mapRef"] = linked().map_name
	data["sector"] = current_sector ? current_sector.name : "Deep Space"
	data["sector_info"] = current_sector ? current_sector.desc : "Not Available"
	data["landed"] = linked().get_landed_info()
	data["s_x"] = linked().x
	data["s_y"] = linked().y
	data["dest"] = dy && dx
	data["speedlimit"] = speedlimit ? speedlimit*1000 : "Halted"
	data["accel"] = min(round(linked().get_acceleration()*1000, 0.01),accellimit*1000)
	data["heading"] = linked().get_heading_degrees()
	data["manual_control"] = viewing_overmap(user)
	data["canburn"] = linked().can_burn()
	data["accellimit"] = accellimit*1000

	var/speed = round(linked().get_speed()*1000, 0.01)
	var/speed_color = null
	if(linked().get_speed() < SHIP_SPEED_SLOW)
		speed_color = "good"
	if(linked().get_speed() > SHIP_SPEED_FAST)
		speed_color = "average"
	data["speed"] = speed
	data["speed_color"] = speed_color

	if(linked().get_speed())
		data["ETAnext"] = "[round(linked().ETA()/10)] seconds"
	else
		data["ETAnext"] = "N/A"

	var/list/locations[0]
	for (var/key in known_sectors)
		var/datum/computer_file/data/waypoint/R = LAZYACCESS(known_sectors, key)
		var/list/rdata[0]
		rdata["name"] = R.fields["name"]
		rdata["x"] = R.fields["x"]
		rdata["y"] = R.fields["y"]
		rdata["reference"] = "\ref[R]"
		locations.Add(list(rdata))

	data["locations"] = locations
	return data

/obj/machinery/computer/ship/helm/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(!linked())
		return FALSE
	return TRUE

UI_ACT(/obj/machinery/computer/ship/helm, "update_camera_view", ui_act_update_camera_view)
UI_ACT_PROC(/obj/machinery/computer/ship/helm, ui_act_update_camera_view)
	if(!COOLDOWN_FINISHED(src, map_refresh_cd))
		to_chat(ui.user, span_warning("You cannot refresh the map so often."))
		return
	update_map()
	COOLDOWN_START(src, map_refresh_cd, 5 SECONDS)
	. = TRUE
	add_fingerprint(ui.user)
	if(. && !issilicon(ui.user))
		play_sfx(src, SFX_TERMINAL_TYPE)

UI_ACT(/obj/machinery/computer/ship/helm, "add", ui_act_add, UI_ARG_TEXT("add"))
UI_ACT_PROC(/obj/machinery/computer/ship/helm, ui_act_add)
	var/datum/computer_file/data/waypoint/R = new()
	var/sec_name = act_ask(ui.user, action, params, ui, "k180", /datum/om/prompt/text, message = "Input navigation entry name", title = "New navigation entry", default = "Sector #[length(known_sectors)]", max_length = MAX_NAME_LEN)
	if(isnull(sec_name))
		return
	if(tgui_status(ui.user, state) != STATUS_INTERACTIVE)
		return FALSE
	if(!sec_name)
		sec_name = "Sector #[length(known_sectors)]"
	R.fields["name"] = sec_name
	if(sec_name in known_sectors)
		to_chat(ui.user, span_warning("Sector with that name already exists, please input a different name."))
		return TRUE
	switch(params["add"])
		if("current")
			R.fields["x"] = linked().x
			R.fields["y"] = linked().y
		if("new")
			var/newx = act_ask(ui.user, action, params, ui, "k194", /datum/om/prompt/number, message = "Input new entry x coordinate", title = "Coordinate input", default = linked().x, max = world.maxx, min = 1)
			if(isnull(newx))
				return
			if(tgui_status(ui.user, state) != STATUS_INTERACTIVE)
				return TRUE
			var/newy = act_ask(ui.user, action, params, ui, "k197", /datum/om/prompt/number, message = "Input new entry y coordinate", title = "Coordinate input", default = linked().y, max = world.maxy, min = 1)
			if(isnull(newy))
				return
			if(tgui_status(ui.user, state) != STATUS_INTERACTIVE)
				return FALSE
			R.fields["x"] = CLAMP(newx, 1, world.maxx)
			R.fields["y"] = CLAMP(newy, 1, world.maxy)
	rel_add(src, nameof(/datum/tgui_module/ship/fullmonty::known_sectors), R, sec_name)
	. = TRUE
	add_fingerprint(ui.user)
	if(. && !issilicon(ui.user))
		play_sfx(src, SFX_TERMINAL_TYPE)

UI_ACT(/obj/machinery/computer/ship/helm, "remove", ui_act_remove, UI_ARG_REF("remove", null, /datum/computer_file/data/waypoint))
UI_ACT_PROC(/obj/machinery/computer/ship/helm, ui_act_remove)
	var/datum/computer_file/data/waypoint/R = params["remove"]
	if(istype(R) && LAZYACCESS(known_sectors, R.fields["name"]) == R) // only our own entries
		rel_add(src, nameof(/datum/tgui_module/ship/fullmonty::known_sectors), null, R.fields["name"]) // disposes of the owned record
	. = TRUE
	add_fingerprint(ui.user)
	if(. && !issilicon(ui.user))
		play_sfx(src, SFX_TERMINAL_TYPE)

UI_ACT(/obj/machinery/computer/ship/helm, "setcoord", ui_act_setcoord, UI_ARG_BOOL("setx"), UI_ARG_BOOL("sety"))
UI_ACT_PROC(/obj/machinery/computer/ship/helm, ui_act_setcoord)
	return helm_coordinate_stage(ui, list("setx" = params["setx"], "sety" = params["sety"]))

/obj/machinery/computer/ship/helm/proc/helm_coordinate_stage(datum/tgui/ui, list/answers, datum/request/request)
	if(answers["setx"])
		if(!("x" in answers))
			open_request(ui, /datum/prompt/number/helm_coordinates, TYPE_PROC_REF(/datum/tgui, helm_coordinates_entered), answerer = ui.user, captured = answers.Copy(), step_name = "x", question = "Input new destiniation x coordinate", default = dx, max_value = world.maxx)
			return
		var/newx = answers["x"]
		if(helm_coordinate_recheck(ui, request))
			return
		if(newx)
			dx = CLAMP(newx, 1, world.maxx)
	if(answers["sety"])
		if(!("y" in answers))
			open_request(ui, /datum/prompt/number/helm_coordinates, TYPE_PROC_REF(/datum/tgui, helm_coordinates_entered), answerer = ui.user, captured = answers.Copy(), step_name = "y", question = "Input new destiniation y coordinate", default = dy, max_value = world.maxy)
			return
		var/newy = answers["y"]
		if(helm_coordinate_recheck(ui, request))
			return
		if(newy)
			dy = CLAMP(newy, 1, world.maxy)
	helm_terminal_feedback(ui.user)
	return TRUE

/datum/tgui/proc/helm_coordinates_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/obj/machinery/computer/ship/helm/helm = src_object()
	var/list/answers = A.request.captured.Copy()
	answers[A.request.step_name] = A.answer.answer_value
	if(helm.helm_coordinate_stage(src, answers, A.request))
		SStgui.update_uis(helm)

/// Prepare the original virtual status query, then route only a pure scalar refusal.
/obj/machinery/computer/ship/helm/proc/helm_coordinate_recheck(datum/tgui/ui, datum/request/request)
	var/current_status = tgui_status(ui.user, ui.state())
	var/reason = helm_coordinate_status_refusal(current_status)
	if(!request)
		return reason
	request.captured["late_refusal"] = reason
	return request_recheck(request)

/proc/helm_coordinate_status_refusal(current_status)
	if(current_status != STATUS_INTERACTIVE)
		return "the helm window is not interactive"
	return null

/datum/prompt/number/helm_coordinates
	title = "Coordinate input"
	min_value = 1
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/number/helm_coordinates/normalize(given)
	return isnum(given) ? given : null

/datum/prompt/number/helm_coordinates/recheck_extra()
	var/datum/tgui/original_ui = owner
	if(!istype(original_ui) || QDELETED(original_ui) || QDELETED(answerer))
		return "gone"
	var/obj/machinery/computer/ship/helm/helm = original_ui.src_object()
	if(!istype(helm) || QDELETED(helm))
		return "gone"
	if(original_ui.status != STATUS_INTERACTIVE)
		return "the original window is not interactive"
	if(!helm.ui_act_allowed(original_ui.user, "setcoord", original_ui, original_ui.state()))
		return "the helm action is unavailable"
	return captured?["late_refusal"]

UI_ACT(/obj/machinery/computer/ship/helm, "setds", ui_act_setds, UI_ARG_NUM("x"), UI_ARG_NUM("y"))
UI_ACT_PROC(/obj/machinery/computer/ship/helm, ui_act_setds)
	dx = params["x"]
	dy = params["y"]
	. = TRUE
	add_fingerprint(ui.user)
	if(. && !issilicon(ui.user))
		play_sfx(src, SFX_TERMINAL_TYPE)

UI_ACT(/obj/machinery/computer/ship/helm, "reset", ui_act_reset)
UI_ACT_PROC(/obj/machinery/computer/ship/helm, ui_act_reset)
	dx = 0
	dy = 0
	. = TRUE
	add_fingerprint(ui.user)
	if(. && !issilicon(ui.user))
		play_sfx(src, SFX_TERMINAL_TYPE)

UI_ACT(/obj/machinery/computer/ship/helm, "speedlimit", ui_act_speedlimit)
UI_ACT_PROC(/obj/machinery/computer/ship/helm, ui_act_speedlimit)
	open_request(ui, /datum/prompt/number/helm_limit/speed, TYPE_PROC_REF(/datum/tgui, helm_limit_entered), answerer = ui.user, default = speedlimit*1000)

UI_ACT(/obj/machinery/computer/ship/helm, "accellimit", ui_act_accellimit)
UI_ACT_PROC(/obj/machinery/computer/ship/helm, ui_act_accellimit)
	open_request(ui, /datum/prompt/number/helm_limit/acceleration, TYPE_PROC_REF(/datum/tgui, helm_limit_entered), answerer = ui.user, default = accellimit*1000)

/datum/tgui/proc/helm_limit_entered(datum/act/request/A)
	var/datum/tgui/ui = src
	if(!A.answer)
		return
	var/obj/machinery/computer/ship/helm/helm = src_object()
	var/datum/prompt/number/helm_limit/ask = A.answer
	var/newlimit = ask.answer_value
	if(newlimit)
		if(ask.limit_action == "speedlimit")
			helm.speedlimit = CLAMP(newlimit/1000, 0, 100)
		else
			helm.accellimit = max(newlimit/1000, 0)
	helm.helm_terminal_feedback(ui.user)
	SStgui.update_uis(helm)

/// Apply the helm's fingerprint and actor-specific keyboard presentation together.
/obj/machinery/computer/ship/helm/proc/helm_terminal_feedback(mob/user)
	add_fingerprint(user)
	if(!issilicon(user))
		play_sfx(src, SFX_TERMINAL_TYPE)

/datum/prompt/number/helm_limit
	min_value = 0
	step = FALSE
	timeout = 0
	recheck_on_open = TRUE
	var/limit_action

/datum/prompt/number/helm_limit/normalize(given)
	return isnum(given) ? given : null

/datum/prompt/number/helm_limit/recheck_extra()
	var/datum/tgui/original_ui = owner
	if(!istype(original_ui) || QDELETED(original_ui) || QDELETED(answerer))
		return "gone"
	var/obj/machinery/computer/ship/helm/helm = original_ui.src_object()
	if(!istype(helm) || QDELETED(helm))
		return "gone"
	if(original_ui.status != STATUS_INTERACTIVE)
		return "the original window is not interactive"
	if(!helm.ui_act_allowed(original_ui.user, limit_action, original_ui, original_ui.state()))
		return "the helm action is unavailable"
	return null

/datum/prompt/number/helm_limit/speed
	question = "Input new speed limit for autopilot (0 to brake)"
	title = "Autopilot speed limit"
	max_value = 100000
	limit_action = "speedlimit"

/datum/prompt/number/helm_limit/acceleration
	question = "Input new acceleration limit"
	title = "Acceleration limit"
	max_value = INFINITY
	limit_action = "accellimit"

UI_ACT(/obj/machinery/computer/ship/helm, "move", ui_act_move, UI_ARG_NUM("dir"))
UI_ACT_PROC(/obj/machinery/computer/ship/helm, ui_act_move)
	var/ndir = params["dir"]
	linked().relaymove(ui.user, ndir, accellimit)
	. = TRUE
	add_fingerprint(ui.user)
	if(. && !issilicon(ui.user))
		play_sfx(src, SFX_TERMINAL_TYPE)

UI_ACT(/obj/machinery/computer/ship/helm, "brake", ui_act_brake)
UI_ACT_PROC(/obj/machinery/computer/ship/helm, ui_act_brake)
	linked().decelerate()
	. = TRUE
	add_fingerprint(ui.user)
	if(. && !issilicon(ui.user))
		play_sfx(src, SFX_TERMINAL_TYPE)

UI_ACT(/obj/machinery/computer/ship/helm, "apilot", ui_act_apilot)
UI_ACT_PROC(/obj/machinery/computer/ship/helm, ui_act_apilot)
	if(autopilot_disabled)
		set_autopilot(FALSE)
	else
		set_autopilot(!autopilot)
	. = TRUE
	add_fingerprint(ui.user)
	if(. && !issilicon(ui.user))
		play_sfx(src, SFX_TERMINAL_TYPE)

UI_ACT(/obj/machinery/computer/ship/helm, "apilot_lock", ui_act_apilot_lock)
UI_ACT_PROC(/obj/machinery/computer/ship/helm, ui_act_apilot_lock)
	set_autopilot_disabled(!autopilot_disabled)
	set_autopilot(FALSE)
	. = TRUE
	add_fingerprint(ui.user)
	if(. && !issilicon(ui.user))
		play_sfx(src, SFX_TERMINAL_TYPE)

UI_ACT(/obj/machinery/computer/ship/helm, "manual", ui_act_manual)
UI_ACT_PROC(/obj/machinery/computer/ship/helm, ui_act_manual)
	if(get_dist(ui.user, src) > 1 || ui.user.blinded || !linked())
		return FALSE
	else if(!viewing_overmap(ui.user) && linked())
		start_coordinated_remoteview(src, ui.user, linked(), viewers, /datum/remote_view_config/overmap_ship_control)
	else
		ui.user.reset_perspective()
	. = TRUE
	add_fingerprint(ui.user)
	if(. && !issilicon(ui.user))
		play_sfx(src, SFX_TERMINAL_TYPE)

/obj/machinery/computer/ship/navigation
	name = "navigation console"
	icon_keyboard = "generic_key"
	icon_screen = "helm"
	circuit = /obj/item/circuitboard/nav
	var/datum/tgui_module/ship/nav/nav_tgui

CAPABILITIES(/obj/machinery/computer/ship/navigation)
	owns_one(nameof(nav_tgui), starts = /datum/tgui_module/ship/nav)

/obj/machinery/computer/ship/navigation/Initialize(mapload)
	. = ..()
	if(linked())
		nav_tgui.attempt_hook_up(linked())

/obj/machinery/computer/ship/navigation/attempt_hook_up(obj/effect/overmap/visitable/ship/sector)
	. = ..()
	if(.)
		nav_tgui?.attempt_hook_up(sector)


/obj/machinery/computer/ship/navigation/sync_linked(user)
	return nav_tgui?.sync_linked()

/obj/machinery/computer/ship/navigation/ui_redirect(mob/user)
	return nav_tgui

/obj/machinery/computer/ship/navigation/telescreen	//little hacky but it's only used on one ship so it should be okay
	icon_state = "tele_nav"
	layer = ABOVE_WINDOW_LAYER
	icon_keyboard = null
	icon_screen = null
	circuit = /obj/item/circuitboard/nav/tele
	density = FALSE

DECLARE_APPEARANCE_PROC(/obj/machinery/computer/ship/navigation/telescreen, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/computer/ship/navigation/telescreen/appearance_overlays()
	. = list()
	if(has_stat(NOPOWER) || has_stat(BROKEN))
		icon_state = "tele_off"
		set_light(0)
	else
		icon_state = "tele_nav"
		set_light(light_range_on, light_power_on)
	. += ..()
