/datum/tgui_module/ship
	var/tmp/obj/effect/overmap/visitable/ship/linked
	var/list/viewers // Mobs in coordinated remote view (relation list, filled by /datum/remote_view/viewer_managed)
	var/list/watchers //Who is viewing through us (a relation list, kept by look()/unlook())
	var/extra_view = 0
	var/map_view_used = FALSE

/datum/tgui_module/ship/New()
	. = ..()
	sync_linked()
	if(linked())
		name = "[linked().name] [name]"

/datum/tgui_module/ship/ui_opening(mob/user, datum/tgui/ui)
	..()
	if(linked())
		user.client.register_map_obj(linked().cam_screen)
		for(var/plane in linked().cam_plane_masters)
			user.client.register_map_obj(plane)
		user.client.register_map_obj(linked().cam_background)
		linked().update_screen()

/datum/tgui_module/ship/ui_data(datum/act/eval/A)
	var/list/data = list()
	if(linked())
		data["mapRef"] = linked().map_name
	return data

/datum/tgui_module/ship/tgui_status(mob/user)
	. = ..()
	if(viewing_overmap(user) && (!user.check_current_machine(src)))
		user.reset_perspective()

/datum/tgui_module/ship/tgui_close(mob/user)
	. = ..()
	// Unregister map objects
	user.client?.clear_map(linked()?.map_name)
	user.reset_perspective()

/datum/tgui_module/ship/proc/sync_linked()
	var/obj/effect/overmap/visitable/ship/sector = get_overmap_sector(get_z(tgui_host()))
	if(!sector)
		return
	return attempt_hook_up_recursive(sector)

/datum/tgui_module/ship/proc/attempt_hook_up_recursive(obj/effect/overmap/visitable/ship/sector)
	if(attempt_hook_up(sector))
		return sector
	for(var/obj/effect/overmap/visitable/ship/candidate in sector)
		if((. = .(candidate)))
			return

/datum/tgui_module/ship/proc/attempt_hook_up(obj/effect/overmap/visitable/ship/sector)
	if(!istype(sector))
		return
	if(sector.check_ownership(tgui_host()))
		rel_set(src, nameof(linked), sector)
		return 1

/datum/tgui_module/ship/look(mob/user)
	rel_add(src, nameof(watchers), user)
	user.set_viewsize(world.view + extra_view)
	if(!map_view_used)
		map_view_used = TRUE

/datum/tgui_module/ship/unlook(mob/user)
	rel_remove(src, nameof(watchers), user)
	user.set_viewsize() // reset to default
	if(map_view_used)
		map_view_used = FALSE

/datum/tgui_module/ship/proc/viewing_overmap(mob/user)
	return (user in watchers)

// Navigation
/datum/tgui_module/ship/nav
	name = "Navigation Display"

/datum/tgui_module/ship/nav/ui_prepare(mob/user, datum/tgui/ui)
	if(!linked())
		sync_linked()
	if(!linked())
		var/obj/machinery/computer/ship/navigation/host = tgui_host()
		if(istype(host))
			// Real Computer path
			host.display_reconnect_dialog(user, "Navigation")
			return FALSE

		// NTOS Path
		if(!sync_linked())
			to_chat(user, span_warning("You don't appear to be on a spaceship..."))
			if(ntos)
				var/obj/item/modular_computer/M = tgui_host()
				if(istype(M))
					M.kill_program(FALSE, user)
		return FALSE
	return ..()

CAPABILITIES(/datum/tgui_module/ship/nav)
	interface("OvermapNavigation")
	extend(TAG_UI, needs(req_bool(PROC_REF(ui_gate), silent = TRUE)))
	op("viewing", ui_act("viewing"), then(PROC_REF(ui_act_viewing)))

/datum/tgui_module/ship/nav/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/list/data = ..()

	var/turf/T = get_turf(linked())
	var/obj/effect/overmap/visitable/sector/current_sector = locate_on(T, /obj/effect/overmap/visitable/sector)

	data["sector"] = current_sector ? current_sector.name : "Deep Space"
	data["sector_info"] = current_sector ? current_sector.desc : "Not Available"
	data["s_x"] = linked().x
	data["s_y"] = linked().y
	data["speed"] = round(linked().get_speed()*1000, 0.01)
	data["accel"] = round(linked().get_acceleration()*1000, 0.01)
	data["heading"] = linked().get_heading_degrees()
	data["viewing"] = viewing_overmap(user)

	if(linked().get_speed())
		data["ETAnext"] = "[round(linked().ETA()/10)] seconds"
	else
		data["ETAnext"] = "N/A"

	return data

/// A navigation display with no ship linked answers nothing (silently).
/datum/tgui_module/ship/nav/proc/ui_gate(datum/act/op/A)
	return !!linked()

/datum/tgui_module/ship/nav/proc/ui_act_viewing(datum/act/op/A)
	var/mob/user = A.actor
	if(!get_dist(user, src) > 1 || user.blinded || !linked())
		return FALSE
	else if(!viewing_overmap(user))
		start_coordinated_remoteview(src, user, linked(), viewers, /datum/remote_view_config/overmap_ship_control)
	else
		user.reset_perspective()
	return TRUE

/datum/tgui_module/ship/nav/ntos
	ntos = TRUE

// Full monty control computer
/datum/tgui_module/ship/fullmonty
	name = "Full Monty Overmap Control"
	// HELM
	var/autopilot = 0
	var/autopilot_disabled = TRUE
	var/list/known_sectors
	var/dx		//desitnation
	var/dy		//coordinates
	var/speedlimit = 1/(20 SECONDS) //top speed for autopilot, 5
	var/accellimit = 0.001 //manual limiter for acceleration
	// SENSORS
	var/tmp/obj/machinery/shipsensors/sensors

CAPABILITIES(/datum/tgui_module/ship/fullmonty)
	op("reset", ui_act("reset"), then(PROC_REF(ui_act_reset)))
	op("brake", ui_act("brake"), then(PROC_REF(ui_act_brake)))
	op("apilot", ui_act("apilot"), then(PROC_REF(ui_act_apilot)))
	op("apilot_lock", ui_act("apilot_lock"), then(PROC_REF(ui_act_apilot_lock)))
	op("global_toggle", ui_act("global_toggle"), then(PROC_REF(ui_act_global_toggle)))
	op("toggle_sensor", ui_act("toggle_sensor"), then(PROC_REF(ui_act_toggle_sensor)))
	owns_many(nameof(known_sectors))
	interface("OvermapFull", rights = R_ADMIN|R_EVENT|R_DEBUG)
	op("add", ui_act("add", arg("add", schema_text(4096))), asks(/datum/prompt/text, fields = list("title" = "New navigation entry", "question" = "Input navigation entry name", "default" = computed(PROC_REF(add_name_default)), "max_len" = MAX_NAME_LEN, "name_text" = TRUE), step = "name"), asks(/datum/prompt/number, fields = list("title" = "Coordinate input", "question" = "Input new entry x coordinate", "default" = computed(PROC_REF(add_x_default)), "max_value" = world.maxx, "min_value" = 1), step = "x", when = PROC_REF(add_is_new)), asks(/datum/prompt/number, fields = list("title" = "Coordinate input", "question" = "Input new entry y coordinate", "default" = computed(PROC_REF(add_y_default)), "max_value" = world.maxy, "min_value" = 1), step = "y", when = PROC_REF(add_is_new)), then(PROC_REF(ui_act_add)))
	op("remove", ui_act("remove", arg("remove", schema_ref(/datum/computer_file/data/waypoint))), then(PROC_REF(ui_act_remove)))
	op("setcoord", ui_act("setcoord", arg("setx", bool()), arg("sety", bool())), asks(/datum/prompt/number, fields = list("title" = "Coordinate input", "question" = "Input new destiniation x coordinate", "default" = computed(PROC_REF(setcoord_x_default)), "max_value" = world.maxx, "min_value" = 1), step = "x", when = PROC_REF(setcoord_x)), asks(/datum/prompt/number, fields = list("title" = "Coordinate input", "question" = "Input new destiniation y coordinate", "default" = computed(PROC_REF(setcoord_y_default)), "max_value" = world.maxy, "min_value" = 1), step = "y", when = PROC_REF(setcoord_y)), then(PROC_REF(ui_act_setcoord)))
	op("setds", ui_act("setds", arg("x", num()), arg("y", num())), then(PROC_REF(ui_act_setds)))
	op("speedlimit", ui_act("speedlimit"), then(PROC_REF(ui_act_speedlimit)))
	op("accellimit", ui_act("accellimit"), then(PROC_REF(ui_act_accellimit)))
	op("move", ui_act("move", arg("dir", num())), then(PROC_REF(ui_act_move)))
	op("manual", ui_act("manual"), then(PROC_REF(ui_act_manual)))
	op("set_global_limit", ui_act("set_global_limit"), then(PROC_REF(ui_act_set_global_limit)))
	op("global_limit", ui_act("global_limit", arg("global_limit", num())), then(PROC_REF(ui_act_global_limit)))
	op("set_limit", ui_act("set_limit", arg("engine", schema_ref(/datum/ship_engine))), asks(/datum/prompt/number, fields = list("title" = "Thrust limit", "question" = "Input new thrust limit (0..100)", "default" = computed(PROC_REF(thrust_limit_default)), "max_value" = 100)), then(PROC_REF(ui_act_set_limit)))
	op("limit", ui_act("limit", arg("engine", schema_ref(/datum/ship_engine)), arg("limit", num())), then(PROC_REF(ui_act_limit)))
	op("toggle_engine", ui_act("toggle_engine", arg("engine", schema_ref(/datum/ship_engine))), then(PROC_REF(ui_act_toggle_engine)))
	op("range", ui_act("range"), then(PROC_REF(ui_act_range)))
	op("viewing", ui_act("viewing"), then(PROC_REF(ui_act_viewing)))

/datum/tgui_module/ship/fullmonty/tgui_close(mob/user)
	. = ..()
	if(!QDELETED(src))
		spent(src, user)

/datum/tgui_module/ship/fullmonty/New(host, obj/effect/overmap/visitable/ship/new_linked)
	. = ..()
	if(!istype(new_linked))
		CRASH("Warning, [new_linked] is not an overmap ship! Something went horribly wrong for [usr]!")
	rel_set(src, nameof(linked), new_linked)
	name = initial(name) + " ([linked().name])"
	// HELM
	// ALLOW(spatial): a deliberate whole-world search: the target is not tied to any holder or z-level index
	var/area/overmap/map = locate() in world
	for(var/obj/effect/overmap/visitable/sector/S in area_contents_of_type(map, /obj/effect/overmap/visitable/sector))
		if(S.known)
			var/datum/computer_file/data/waypoint/R = new()
			R.fields["name"] = S.name
			R.fields["x"] = S.x
			R.fields["y"] = S.y
			rel_add(src, nameof(known_sectors), R, S.name)
	// SENSORS
	for(var/obj/machinery/shipsensors/S in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(linked().check_ownership(S))
			rel_set(src, nameof(sensors), S)
			break

/datum/tgui_module/ship/fullmonty/relaymove(mob/user, direction)
	if(viewing_overmap(user) && linked())
		direction = turn(direction,pick(90,-90))
		linked().relaymove(user, direction, accellimit)
		return 1
	return ..()

// Beware ye eyes. This holds all of the data from helm, engine, and sensor control all at once.

/datum/tgui_module/ship/fullmonty/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/list/data = ..()
	data["d_x"] = dx
	data["d_y"] = dy
	data["autopilot_disabled"] = autopilot_disabled
	data["autopilot"] = autopilot

	// HELM
	var/turf/T = get_turf(linked())
	var/obj/effect/overmap/visitable/sector/current_sector = locate_on(T, /obj/effect/overmap/visitable/sector)

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

	// ENGINES
	data["global_state"] = linked().engines_state
	data["global_limit"] = round(linked().thrust_limit*100)
	var/total_thrust = 0

	var/list/enginfo = list()
	for(var/datum/ship_engine/E in linked().engines)
		var/list/rdata = list()
		rdata["eng_type"] = E.name
		rdata["eng_on"] = E.is_on()
		rdata["eng_thrust"] = E.get_thrust()
		rdata["eng_thrust_limiter"] = round(E.get_thrust_limit()*100)
		var/list/status = E.get_status()
		if(!islist(status))
			log_runtime(EXCEPTION("Warning, ship [E.name] (\ref[E]) for [linked().name] returned a non-list status!"))
			status = list("Error")
		rdata["eng_status"] = status
		rdata["eng_reference"] = "\ref[E]"
		total_thrust += E.get_thrust()
		enginfo.Add(list(rdata))

	data["engines_info"] = enginfo
	data["total_thrust"] = total_thrust

	// SENSORS
	data["viewing"] = viewing_overmap(user)
	data["on"] = 0
	data["range"] = "N/A"
	data["health"] = 0
	data["max_health"] = 0
	data["heat"] = 0
	data["critical_heat"] = 0
	data["status"] = "MISSING"
	data["contacts"] = list()

	if(sensors())
		data["on"] = sensors().use_power
		data["range"] = sensors().range
		data["health"] = sensors().get_integrity()
		data["max_health"] = sensors().max_integrity
		data["heat"] = sensors().heat
		data["critical_heat"] = sensors().critical_heat
		if(sensors().get_integrity() <= 0)
			data["status"] = "DESTROYED"
		else if(!sensors().powered())
			data["status"] = "NO POWER"
		else if(!sensors().in_vacuum())
			data["status"] = "VACUUM SEAL BROKEN"
		else
			data["status"] = "OK"
		var/list/contacts = list()
		for(var/obj/effect/overmap/O in view(7,linked()))
			if(linked() == O)
				continue
			if(!O.scannable)
				continue
			var/bearing = round(90 - ATAN2(O.x - linked().x, O.y - linked().y),5)
			if(bearing < 0)
				bearing += 360
			contacts.Add(list(list("name"=O.name, "ref"="\ref[O]", "bearing"=bearing)))
		data["contacts"] = contacts

	return data

// Beware ye eyes. This holds all of the ACTIONS from helm, engine, and sensor control all at once.
/datum/tgui_module/ship/fullmonty/proc/add_is_new(datum/act/op/A)
	return A.args["add"] == "new"

/datum/tgui_module/ship/fullmonty/proc/add_name_default(datum/act/op/A)
	return "Sector #[length(known_sectors)]"

/datum/tgui_module/ship/fullmonty/proc/add_x_default(datum/act/op/A)
	return linked().x

/datum/tgui_module/ship/fullmonty/proc/add_y_default(datum/act/op/A)
	return linked().y

/datum/tgui_module/ship/fullmonty/proc/ui_act_add(datum/act/op/A, add)
	var/mob/user = A.actor
	var/datum/prompt/name_answer = A.step_answer("name")
	var/sec_name = name_answer?.value
	if(!sec_name)
		sec_name = "Sector #[length(known_sectors)]"
	if(sec_name in known_sectors)
		to_chat(user, span_warning("Sector with that name already exists, please input a different name."))
		return TRUE
	var/datum/computer_file/data/waypoint/R
	switch(add)
		if("current")
			R = new()
			R.fields["x"] = linked().x
			R.fields["y"] = linked().y
		if("new")
			var/datum/prompt/x_answer = A.step_answer("x")
			var/datum/prompt/y_answer = A.step_answer("y")
			var/newx = x_answer?.value
			var/newy = y_answer?.value
			if(isnull(newx) || isnull(newy))
				return TRUE
			R = new()
			R.fields["x"] = CLAMP(newx, 1, world.maxx)
			R.fields["y"] = CLAMP(newy, 1, world.maxy)
	if(!R)
		return TRUE
	R.fields["name"] = sec_name
	rel_add(src, nameof(/datum/tgui_module/ship/fullmonty::known_sectors), R, sec_name)
	. = TRUE

/datum/tgui_module/ship/fullmonty/proc/ui_act_remove(datum/act/op/A, remove)
	var/datum/computer_file/data/waypoint/R = remove
	if(istype(R) && known_sectors?[R.fields["name"]] == R) // only one of our own entries
		rel_add(src, nameof(/datum/tgui_module/ship/fullmonty::known_sectors), null, R.fields["name"]) // removes and disposes of it
	. = TRUE

/datum/tgui_module/ship/fullmonty/proc/setcoord_x(datum/act/op/A)
	return !!A.args["setx"]

/datum/tgui_module/ship/fullmonty/proc/setcoord_x_default(datum/act/op/A)
	return dx

/datum/tgui_module/ship/fullmonty/proc/setcoord_y_default(datum/act/op/A)
	return dy

/datum/tgui_module/ship/fullmonty/proc/setcoord_y(datum/act/op/A)
	return !!A.args["sety"]

/datum/tgui_module/ship/fullmonty/proc/ui_act_setcoord(datum/act/op/A, setx, sety)
	var/datum/prompt/x_answer = A.step_answer("x")
	var/datum/prompt/y_answer = A.step_answer("y")
	var/newx = x_answer?.value
	if(newx)
		dx = CLAMP(newx, 1, world.maxx)
	var/newy = y_answer?.value
	if(newy)
		dy = CLAMP(newy, 1, world.maxy)
	. = TRUE

/datum/tgui_module/ship/fullmonty/proc/ui_act_setds(datum/act/op/A, x, y)
	dx = x
	dy = y
	. = TRUE

/datum/tgui_module/ship/fullmonty/proc/ui_act_reset(datum/act/op/A)
	dx = 0
	dy = 0
	return OP_OK

/datum/tgui_module/ship/fullmonty/proc/ui_act_speedlimit(datum/act/op/A)
	open_request(src, /datum/prompt/number, PROC_REF(speedlimit_answered), valid = PROC_REF(request_usable), answerer = A.actor, question = "Input new speed limit for autopilot (0 to brake)", title = "Autopilot speed limit", default = speedlimit*1000, max_value = 100000, timeout = 0)

/datum/tgui_module/ship/fullmonty/proc/speedlimit_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/newlimit = A.answer.value
	if(newlimit)
		speedlimit = CLAMP(newlimit/1000, 0, 100)
	. = TRUE
	SStgui.update_uis(src)

/datum/tgui_module/ship/fullmonty/proc/ui_act_accellimit(datum/act/op/A)
	open_request(src, /datum/prompt/number, PROC_REF(accellimit_answered), valid = PROC_REF(request_usable), answerer = A.actor, question = "Input new acceleration limit", title = "Acceleration limit", default = accellimit*1000, timeout = 0)

/datum/tgui_module/ship/fullmonty/proc/accellimit_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/newlimit = A.answer.value
	if(newlimit)
		accellimit = max(newlimit/1000, 0)
	. = TRUE
	SStgui.update_uis(src)

/datum/tgui_module/ship/fullmonty/proc/ui_act_move(datum/act/op/A, dir)
	var/mob/user = A.actor
	var/ndir = dir
	ndir = turn(ndir,pick(90,-90))
	linked().relaymove(user, ndir, accellimit)
	. = TRUE

/datum/tgui_module/ship/fullmonty/proc/ui_act_brake(datum/act/op/A)
	linked().decelerate()
	return OP_OK

/datum/tgui_module/ship/fullmonty/proc/ui_act_apilot(datum/act/op/A)
	if(autopilot_disabled)
		autopilot = FALSE
	else
		autopilot = !autopilot
	return OP_OK

/datum/tgui_module/ship/fullmonty/proc/ui_act_apilot_lock(datum/act/op/A)
	autopilot_disabled = !autopilot_disabled
	autopilot = FALSE
	return OP_OK

/datum/tgui_module/ship/fullmonty/proc/ui_act_manual(datum/act/op/A)
	var/mob/user = A.actor
	if(user.blinded || !linked())
		return FALSE
	else  if(!viewing_overmap(user))
		start_coordinated_remoteview(src, user, linked(), viewers, /datum/remote_view_config/overmap_ship_control)
	else
		user.reset_perspective()
	. = TRUE
// END HELM
// ENGINES

/datum/tgui_module/ship/fullmonty/proc/ui_act_global_toggle(datum/act/op/A)
	linked().engines_state = !linked().engines_state
	for(var/datum/ship_engine/E in linked().engines)
		if(linked().engines_state == !E.is_on())
			E.toggle()
	return OP_OK

/datum/tgui_module/ship/fullmonty/proc/ui_act_set_global_limit(datum/act/op/A)
	open_request(src, /datum/prompt/number, PROC_REF(set_global_limit_answered), valid = PROC_REF(request_usable), answerer = A.actor, question = "Input new thrust limit (0..100%)", title = "Thrust limit", default = linked().thrust_limit*100, max_value = 100, timeout = 0)

/datum/tgui_module/ship/fullmonty/proc/set_global_limit_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/newlim = A.answer.value
	linked().thrust_limit = clamp(newlim/100, 0, 1)
	for(var/datum/ship_engine/E in linked().engines)
		E.set_thrust_limit(linked().thrust_limit)
	. = TRUE
	SStgui.update_uis(src)

/datum/tgui_module/ship/fullmonty/proc/ui_act_global_limit(datum/act/op/A, global_limit)
	linked().thrust_limit = clamp(linked().thrust_limit + global_limit, 0, 1)
	for(var/datum/ship_engine/E in linked().engines)
		E.set_thrust_limit(linked().thrust_limit)
	. = TRUE

/datum/tgui_module/ship/fullmonty/proc/thrust_limit_default(datum/act/op/A)
	var/datum/ship_engine/E = A.args["engine"]
	return istype(E) ? E.get_thrust_limit() : 0

/datum/tgui_module/ship/fullmonty/proc/ui_act_set_limit(datum/act/op/A, engine)
	var/datum/ship_engine/E = engine
	if(!istype(E))
		return TRUE
	var/datum/prompt/P = A.answer
	var/newlim = P?.value
	if(isnull(newlim))
		return TRUE
	var/limit = clamp(newlim/100, 0, 1)
	E.set_thrust_limit(limit)
	. = TRUE

/datum/tgui_module/ship/fullmonty/proc/ui_act_limit(datum/act/op/A, engine, limit_arg)
	var/datum/ship_engine/E = engine
	if(!istype(E))
		return TRUE
	var/limit = clamp(E.get_thrust_limit() + limit_arg, 0, 1)
	E.set_thrust_limit(limit)
	. = TRUE

/datum/tgui_module/ship/fullmonty/proc/ui_act_toggle_engine(datum/act/op/A, engine)
	var/datum/ship_engine/E = engine
	if(istype(E))
		E.toggle()
	. = TRUE
// END ENGINES
// SENSORS

/datum/tgui_module/ship/fullmonty/proc/ui_act_range(datum/act/op/A)
	open_request(src, /datum/prompt/number, PROC_REF(range_answered), valid = PROC_REF(request_usable), answerer = A.actor, question = "Set new sensors range", title = "Sensor range", default = sensors().range, max_value = world.view, step = 0.01, timeout = 0)

/datum/tgui_module/ship/fullmonty/proc/range_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/nrange = A.answer.value
	if(nrange)
		sensors().set_range(CLAMP(nrange, 1, world.view))
	. = TRUE
	SStgui.update_uis(src)

/datum/tgui_module/ship/fullmonty/proc/ui_act_toggle_sensor(datum/act/op/A)
	sensors().toggle()
	return OP_OK

/datum/tgui_module/ship/fullmonty/proc/ui_act_viewing(datum/act/op/A)
	var/mob/user = A.actor
	if(user && !istype(user, /mob/living/silicon/ai))
		viewing_overmap(user) ? unlook(user) : look(user)
	. = TRUE
// END SENSORS

// We don't want these to do anything.
/datum/tgui_module/ship/fullmonty/sync_linked()
	return
/datum/tgui_module/ship/fullmonty/attempt_hook_up_recursive()
	return
/datum/tgui_module/ship/fullmonty/attempt_hook_up()
	return

////
////  Settings for remote view
////
/datum/remote_view_config/overmap_ship_control
	relay_movement = TRUE

/datum/remote_view_config/overmap_ship_control/handle_relay_movement( datum/remote_view/owner_component, mob/host_mob, direction)
	var/datum/tgui_module/ship/tgui_owner = owner_component.get_coordinator()
	if(tgui_owner?.linked())
		return tgui_owner.relaymove(host_mob, direction)
	return FALSE

/datum/remote_view_config/overmap_ship_control/handle_apply_visuals( datum/remote_view/owner_component, mob/host_mob)
	var/datum/tgui_module/ship/tgui_owner = owner_component.get_coordinator()
	if(!tgui_owner)
		return
	if(get_dist(host_mob, tgui_owner.tgui_host()) > 1 || !tgui_owner.linked())
		host_mob.reset_perspective()
		return

/// The linked this refers to (a relation view: null once that is deleted).
/datum/tgui_module/ship/proc/linked() as /obj/effect/overmap/visitable/ship
	return linked

/// The sensors this refers to (a relation view: null once that is deleted).
/datum/tgui_module/ship/fullmonty/proc/sensors() as /obj/machinery/shipsensors
	return sensors
