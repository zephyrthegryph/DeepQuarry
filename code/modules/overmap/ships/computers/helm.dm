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
	started_work(step = PROC_REF(work_step), starts = TRUE, when = cond_all(nameof(autopilot), cond_not(nameof(autopilot_disabled))), wakes_on = list(nameof(autopilot), nameof(autopilot_disabled)))
	owns_many(nameof(known_sectors))
	// The helm's buttons (its window is the overmap console's, opened by the console's own interactions). A navigation entry's name and
	// coordinates and the autopilot limits are asked in the op (asks()); the handler applies the answers.
	op("update_camera_view", ui_act("update_camera_view"), then(PROC_REF(ui_act_update_camera_view)))
	op("add", ui_act("add", arg("add", schema_text(4096))),
		asks(/datum/prompt/text, fields = list("title" = "New navigation entry", "question" = "Input navigation entry name", "default" = computed(PROC_REF(add_name_default)), "max_len" = MAX_NAME_LEN, "timeout" = 0), step = "name"),
		asks(/datum/prompt/number, fields = list("title" = "Coordinate input", "question" = "Input new entry x coordinate", "default" = computed(PROC_REF(add_x_default)), "max_value" = computed(PROC_REF(map_max_x)), "min_value" = 1, "timeout" = 0), step = "x", when = PROC_REF(add_is_new)),
		asks(/datum/prompt/number, fields = list("title" = "Coordinate input", "question" = "Input new entry y coordinate", "default" = computed(PROC_REF(add_y_default)), "max_value" = computed(PROC_REF(map_max_y)), "min_value" = 1, "timeout" = 0), step = "y", when = PROC_REF(add_is_new)),
		then(PROC_REF(ui_act_add)))
	op("remove", ui_act("remove", arg("remove", schema_ref(/datum/computer_file/data/waypoint))), then(PROC_REF(ui_act_remove)))
	op("setcoord", ui_act("setcoord", arg("setx", bool()), arg("sety", bool())),
		asks(/datum/prompt/number, fields = list("title" = "Coordinate input", "question" = "Input new destiniation x coordinate", "default" = computed(PROC_REF(setcoord_x_default)), "max_value" = computed(PROC_REF(map_max_x)), "min_value" = 1, "timeout" = 0), step = "x", when = PROC_REF(setcoord_x)),
		asks(/datum/prompt/number, fields = list("title" = "Coordinate input", "question" = "Input new destiniation y coordinate", "default" = computed(PROC_REF(setcoord_y_default)), "max_value" = computed(PROC_REF(map_max_y)), "min_value" = 1, "timeout" = 0), step = "y", when = PROC_REF(setcoord_y)),
		then(PROC_REF(ui_act_setcoord)))
	op("setds", ui_act("setds", arg("x", num()), arg("y", num())), then(PROC_REF(ui_act_setds)))
	op("reset", ui_act("reset"), then(PROC_REF(ui_act_reset)))
	op("speedlimit", ui_act("speedlimit"), asks(/datum/prompt/number/helm_limit/speed, fields = list("default" = computed(PROC_REF(speedlimit_default))), step = "limit"), then(PROC_REF(ui_act_speedlimit)))
	op("accellimit", ui_act("accellimit"), asks(/datum/prompt/number/helm_limit/acceleration, fields = list("default" = computed(PROC_REF(accellimit_default))), step = "limit"), then(PROC_REF(ui_act_accellimit)))
	op("move", ui_act("move", arg("dir", num())), then(PROC_REF(ui_act_move)))
	op("brake", ui_act("brake"), then(PROC_REF(ui_act_brake)))
	op("apilot", ui_act("apilot"), then(PROC_REF(ui_act_apilot)))
	op("apilot_lock", ui_act("apilot_lock"), then(PROC_REF(ui_act_apilot_lock)))
	op("manual", ui_act("manual"), then(PROC_REF(ui_act_manual)))

/obj/machinery/computer/ship/helm/var/autopilot = FALSE
TRACKED(/obj/machinery/computer/ship/helm, autopilot)
/obj/machinery/computer/ship/helm/var/autopilot_disabled = TRUE
TRACKED(/obj/machinery/computer/ship/helm, autopilot_disabled)
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

/obj/machinery/computer/ship/helm/proc/work_step(datum/act/timer/A)
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

/// The window data.
/obj/machinery/computer/ship/helm/ui_data(datum/act/eval/A)
	var/list/data = ..()
	data["d_x"] = dx
	data["d_y"] = dy
	data["autopilot_disabled"] = autopilot_disabled
	data["autopilot"] = autopilot
	var/list/computed = ui_data_obj_machinery_computer_ship_helm(A.actor, null, null)
	for(var/key in computed)
		data[key] = computed[key]
	return data

/// /obj/machinery/computer/ship/helm's window data.
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

/// The helm's guard: it works a linked ship.
/obj/machinery/computer/ship/helm/ui_gate(datum/act/op/A)
	if(!..())
		return FALSE
	return !!linked()

/obj/machinery/computer/ship/helm/proc/ui_act_update_camera_view(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	if(!COOLDOWN_FINISHED(src, map_refresh_cd))
		to_chat(user, span_warning("You cannot refresh the map so often."))
		return
	update_map()
	COOLDOWN_START(src, map_refresh_cd, 5 SECONDS)
	helm_terminal_feedback(user)
	return TRUE

/obj/machinery/computer/ship/helm/proc/add_is_new(datum/act/op/A)
	return A.args["add"] == "new"

/obj/machinery/computer/ship/helm/proc/add_name_default(datum/act/op/A)
	return "Sector #[length(known_sectors)]"

/obj/machinery/computer/ship/helm/proc/add_x_default(datum/act/op/A)
	return linked()?.x

/obj/machinery/computer/ship/helm/proc/add_y_default(datum/act/op/A)
	return linked()?.y

/obj/machinery/computer/ship/helm/proc/map_max_x(datum/act/op/A)
	return world.maxx

/obj/machinery/computer/ship/helm/proc/map_max_y(datum/act/op/A)
	return world.maxy

/obj/machinery/computer/ship/helm/proc/ui_act_add(datum/act/op/A, add)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	if(tgui_status(A.actor, tgui_state()) != STATUS_INTERACTIVE) // the answer counts while the console still lets its asker work it
		return FALSE
	var/sec_name = A.step_value("name")
	if(!sec_name)
		sec_name = "Sector #[length(known_sectors)]"
	if(sec_name in known_sectors)
		to_chat(user, span_warning("Sector with that name already exists, please input a different name."))
		return TRUE
	var/entry_x
	var/entry_y
	switch(add)
		if("current")
			entry_x = linked().x
			entry_y = linked().y
		if("new")
			entry_x = CLAMP(A.step_value("x"), 1, world.maxx)
			entry_y = CLAMP(A.step_value("y"), 1, world.maxy)
	var/datum/computer_file/data/waypoint/R = new()
	R.fields["name"] = sec_name
	if(add == "current" || add == "new")
		R.fields["x"] = entry_x
		R.fields["y"] = entry_y
	rel_add(src, nameof(known_sectors), R, sec_name)
	helm_terminal_feedback(user)
	return TRUE

/obj/machinery/computer/ship/helm/proc/ui_act_remove(datum/act/op/A, datum/computer_file/data/waypoint/remove)
	if(!ui_gate(A))
		return FALSE
	if(istype(remove) && LAZYACCESS(known_sectors, remove.fields["name"]) == remove) // only our own entries
		rel_add(src, nameof(known_sectors), null, remove.fields["name"]) // disposes of the owned record
	helm_terminal_feedback(A.actor)
	return TRUE

/obj/machinery/computer/ship/helm/proc/setcoord_x(datum/act/op/A)
	return !!A.args["setx"]

/obj/machinery/computer/ship/helm/proc/setcoord_y(datum/act/op/A)
	return !!A.args["sety"]

/obj/machinery/computer/ship/helm/proc/setcoord_x_default(datum/act/op/A)
	return dx

/obj/machinery/computer/ship/helm/proc/setcoord_y_default(datum/act/op/A)
	return dy

/obj/machinery/computer/ship/helm/proc/ui_act_setcoord(datum/act/op/A, setx, sety)
	if(!ui_gate(A))
		return FALSE
	if(tgui_status(A.actor, tgui_state()) != STATUS_INTERACTIVE) // the answer counts while the console still lets its asker work it
		return FALSE
	var/newx = setx ? A.step_value("x") : null
	if(newx)
		dx = CLAMP(newx, 1, world.maxx)
	var/newy = sety ? A.step_value("y") : null
	if(newy)
		dy = CLAMP(newy, 1, world.maxy)
	helm_terminal_feedback(A.actor)
	return TRUE

/obj/machinery/computer/ship/helm/proc/ui_act_setds(datum/act/op/A, x, y)
	if(!ui_gate(A))
		return FALSE
	dx = x
	dy = y
	helm_terminal_feedback(A.actor)
	return TRUE

/obj/machinery/computer/ship/helm/proc/ui_act_reset(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	dx = 0
	dy = 0
	helm_terminal_feedback(A.actor)
	return TRUE

/obj/machinery/computer/ship/helm/proc/speedlimit_default(datum/act/op/A)
	return speedlimit * 1000

/obj/machinery/computer/ship/helm/proc/accellimit_default(datum/act/op/A)
	return accellimit * 1000

/obj/machinery/computer/ship/helm/proc/ui_act_speedlimit(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	var/newlimit = A.step_value("limit")
	if(newlimit)
		speedlimit = CLAMP(newlimit/1000, 0, 100)
	helm_terminal_feedback(A.actor)
	return TRUE

/obj/machinery/computer/ship/helm/proc/ui_act_accellimit(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	var/newlimit = A.step_value("limit")
	if(newlimit)
		accellimit = max(newlimit/1000, 0)
	helm_terminal_feedback(A.actor)
	return TRUE

/// Apply the helm's fingerprint and actor-specific keyboard presentation together.
/obj/machinery/computer/ship/helm/proc/helm_terminal_feedback(mob/user)
	add_fingerprint(user)
	if(!issilicon(user))
		play_sfx(src, SFX_TERMINAL_TYPE)

/datum/prompt/number/helm_limit
	min_value = 0
	step = FALSE
	timeout = 0

/datum/prompt/number/helm_limit/normalize(given)
	return isnum(given) ? given : null

/datum/prompt/number/helm_limit/speed
	question = "Input new speed limit for autopilot (0 to brake)"
	title = "Autopilot speed limit"
	max_value = 100000

/datum/prompt/number/helm_limit/acceleration
	question = "Input new acceleration limit"
	title = "Acceleration limit"
	max_value = INFINITY

/obj/machinery/computer/ship/helm/proc/ui_act_move(datum/act/op/A, dir)
	if(!ui_gate(A))
		return FALSE
	linked().relaymove(A.actor, dir, accellimit)
	helm_terminal_feedback(A.actor)
	return TRUE

/obj/machinery/computer/ship/helm/proc/ui_act_brake(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	linked().decelerate()
	helm_terminal_feedback(A.actor)
	return TRUE

/obj/machinery/computer/ship/helm/proc/ui_act_apilot(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	if(autopilot_disabled)
		set_autopilot(FALSE)
	else
		set_autopilot(!autopilot)
	helm_terminal_feedback(A.actor)
	return TRUE

/obj/machinery/computer/ship/helm/proc/ui_act_apilot_lock(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	set_autopilot_disabled(!autopilot_disabled)
	set_autopilot(FALSE)
	helm_terminal_feedback(A.actor)
	return TRUE

/obj/machinery/computer/ship/helm/proc/ui_act_manual(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	if(get_dist(user, src) > 1 || user.blinded || !linked())
		return FALSE
	else if(!viewing_overmap(user) && linked())
		start_coordinated_remoteview(src, user, linked(), viewers, /datum/remote_view_config/overmap_ship_control)
	else
		user.reset_perspective()
	helm_terminal_feedback(user)
	return TRUE

/obj/machinery/computer/ship/navigation
	name = "navigation console"
	icon_keyboard = "generic_key"
	icon_screen = "helm"
	circuit = /obj/item/circuitboard/nav
	var/datum/tgui_module/ship/nav/nav_tgui

CAPABILITIES(/obj/machinery/computer/ship/navigation)
	op("ship_emote_beyond", menu(), ungated(), reach(REACH_ANY), label("Emote Beyond"), needs(req_bool(PROC_REF(ship_emote_in_view), because = MSG(ship_emote/too_far)), req_bool(PROC_REF(ship_emoter_capable), because = MSG(ship_emote/incapable)), req_bool(PROC_REF(ship_emoter_not_muted), because = MSG(fur/ic_muted))), asks(/datum/prompt/text, step = "message", fields = list("title" = "Emote Beyond", "question" = "Type a message to emote.", "encode" = FALSE, "timeout" = 0)), then(PROC_REF(emote_beyond_entered)))
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

/obj/machinery/computer/ship/navigation/telescreen/draw(datum/look/look)
	..()
	if(power_lost() || broken_now())
		look.state("tele_off")
		look.light_off()
	else
		look.state("tele_nav")
