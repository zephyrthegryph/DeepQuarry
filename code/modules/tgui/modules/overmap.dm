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

/datum/tgui_module/ship/tgui_interact(mob/user, datum/tgui/ui, datum/tgui/parent_ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		if(linked())
			user.client.register_map_obj(linked().cam_screen)
			for(var/plane in linked().cam_plane_masters)
				user.client.register_map_obj(plane)
			user.client.register_map_obj(linked().cam_background)
			linked().update_screen()

		ui = new(user, src, tgui_id, name, parent_ui)
		ui.open()

/datum/tgui_module/ship/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = ..()
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
		rel_set(src, "linked", sector)
		return 1

/datum/tgui_module/ship/look(mob/user)
	rel_add(src, "watchers", user)
	user.set_viewsize(world.view + extra_view)
	if(!map_view_used)
		map_view_used = TRUE

/datum/tgui_module/ship/unlook(mob/user)
	rel_remove(src, "watchers", user)
	user.set_viewsize() // reset to default
	if(map_view_used)
		map_view_used = FALSE

/datum/tgui_module/ship/proc/viewing_overmap(mob/user)
	return (user in watchers)

// Navigation
/datum/tgui_module/ship/nav
	name = "Navigation Display"
	tgui_id = "OvermapNavigation"

/datum/tgui_module/ship/nav/tgui_interact(mob/user, datum/tgui/ui)
	if(!linked())
		sync_linked()
	if(!linked())
		var/obj/machinery/computer/ship/navigation/host = tgui_host()
		if(istype(host))
			// Real Computer path
			host.display_reconnect_dialog(user, "Navigation")
			return

		// NTOS Path
		if(!sync_linked())
			to_chat(user, span_warning("You don't appear to be on a spaceship..."))
			if(ui)
				ui.close(can_be_suspended = FALSE)
			if(ntos)
				var/obj/item/modular_computer/M = tgui_host()
				if(istype(M))
					M.kill_program()
		return

	. = ..()

/datum/tgui_module/ship/nav/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
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

/datum/tgui_module/ship/nav/tgui_act(action, params, datum/tgui/ui)
	if(..())
		return TRUE

	if(!linked())
		return FALSE

	if(action == "viewing")
		if(!get_dist(ui.user, src) > 1 || ui.user.blinded || !linked())
			return FALSE
		else if(!viewing_overmap(ui.user))
			start_coordinated_remoteview(src, ui.user, linked(), viewers, /datum/remote_view_config/overmap_ship_control)
		else
			ui.user.reset_perspective()
		return TRUE

/datum/tgui_module/ship/nav/ntos
	ntos = TRUE

// Full monty control computer
/datum/tgui_module/ship/fullmonty
	name = "Full Monty Overmap Control"
	tgui_id = "OvermapFull"
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

/datum/tgui_module/ship/fullmonty/tgui_state(mob/user)
	return ADMIN_STATE(R_ADMIN|R_EVENT|R_DEBUG)

/datum/tgui_module/ship/fullmonty/tgui_close(mob/user)
	. = ..()
	if(!QDELETED(src))
		qdel(src)

/datum/tgui_module/ship/fullmonty/New(host, obj/effect/overmap/visitable/ship/new_linked)
	. = ..()
	if(!istype(new_linked))
		CRASH("Warning, [new_linked] is not an overmap ship! Something went horribly wrong for [usr]!")
	rel_set(src, "linked", new_linked)
	name = initial(name) + " ([linked().name])"
	// HELM
	// ALLOW(spatial): world search
	var/area/overmap/map = locate() in world
	for(var/obj/effect/overmap/visitable/sector/S in area_contents_of_type(map, /obj/effect/overmap/visitable/sector))
		if(S.known)
			var/datum/computer_file/data/waypoint/R = new()
			R.fields["name"] = S.name
			R.fields["x"] = S.x
			R.fields["y"] = S.y
			LAZYSET(known_sectors, S.name, R)
	// SENSORS
	for(var/obj/machinery/shipsensors/S in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(linked().check_ownership(S))
			rel_set(src, "sensors", S)
			break

/datum/tgui_module/ship/fullmonty/relaymove(mob/user, direction)
	if(viewing_overmap(user) && linked())
		direction = turn(direction,pick(90,-90))
		linked().relaymove(user, direction, accellimit)
		return 1
	return ..()

// Beware ye eyes. This holds all of the data from helm, engine, and sensor control all at once.
/datum/tgui_module/ship/fullmonty/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = ..()

	// HELM
	var/turf/T = get_turf(linked())
	var/obj/effect/overmap/visitable/sector/current_sector = locate_on(T, /obj/effect/overmap/visitable/sector)

	data["sector"] = current_sector ? current_sector.name : "Deep Space"
	data["sector_info"] = current_sector ? current_sector.desc : "Not Available"
	data["landed"] = linked().get_landed_info()
	data["s_x"] = linked().x
	data["s_y"] = linked().y
	data["dest"] = dy && dx
	data["d_x"] = dx
	data["d_y"] = dy
	data["speedlimit"] = speedlimit ? speedlimit*1000 : "Halted"
	data["accel"] = min(round(linked().get_acceleration()*1000, 0.01),accellimit*1000)
	data["heading"] = linked().get_heading_degrees()
	data["autopilot_disabled"] = autopilot_disabled
	data["autopilot"] = autopilot
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
/datum/tgui_module/ship/fullmonty/tgui_act(action, params, datum/tgui/ui)
	if(..())
		return TRUE

	switch(action)
		/* HELM */
		if("add")
			var/sec_name = act_ask(ui.user, action, params, ui, "a1", /datum/om/prompt/text, message = "Input navigation entry name", title = "New navigation entry", default = "Sector #[length(known_sectors)]", max_length = MAX_NAME_LEN)
			if(isnull(sec_name))
				return
			if(!sec_name)
				sec_name = "Sector #[length(known_sectors)]"
			if(sec_name in known_sectors)
				to_chat(ui.user, span_warning("Sector with that name already exists, please input a different name."))
				return TRUE
			var/datum/computer_file/data/waypoint/R
			switch(params["add"])
				if("current")
					R = new()
					R.fields["x"] = linked().x
					R.fields["y"] = linked().y
				if("new")
					var/newx = act_ask(ui.user, action, params, ui, "a2", /datum/om/prompt/number, message = "Input new entry x coordinate", title = "Coordinate input", default = linked().x, max = world.maxx, min = 1)
					if(isnull(newx))
						return
					var/newy = act_ask(ui.user, action, params, ui, "a3", /datum/om/prompt/number, message = "Input new entry y coordinate", title = "Coordinate input", default = linked().y, max = world.maxy, min = 1)
					if(isnull(newy))
						return
					R = new()
					R.fields["x"] = CLAMP(newx, 1, world.maxx)
					R.fields["y"] = CLAMP(newy, 1, world.maxy)
			if(!R)
				return TRUE
			R.fields["name"] = sec_name
			LAZYSET(known_sectors, sec_name, R)
			. = TRUE

		if("remove")
			var/datum/computer_file/data/waypoint/R = locate(params["remove"])
			if(R)
				LAZYREMOVE(known_sectors, R.fields["name"])
				qdel(R)
			. = TRUE

		if("setcoord")
			if(params["setx"])
				var/newx = act_ask(ui.user, action, params, ui, "a4", /datum/om/prompt/number, message = "Input new destiniation x coordinate", title = "Coordinate input", default = dx, max = world.maxx, min = 1)
				if(isnull(newx))
					return
				if(newx)
					dx = CLAMP(newx, 1, world.maxx)

			if(params["sety"])
				var/newy = act_ask(ui.user, action, params, ui, "a5", /datum/om/prompt/number, message = "Input new destiniation y coordinate", title = "Coordinate input", default = dy, max = world.maxy, min = 1)
				if(isnull(newy))
					return
				if(newy)
					dy = CLAMP(newy, 1, world.maxy)
			. = TRUE

		if("setds")
			dx = text2num(params["x"])
			dy = text2num(params["y"])
			. = TRUE

		if("reset")
			dx = 0
			dy = 0
			. = TRUE

		if("speedlimit")
			var/newlimit = act_ask(ui.user, action, params, ui, "a6", /datum/om/prompt/number, message = "Input new speed limit for autopilot (0 to brake)", title = "Autopilot speed limit", default = speedlimit*1000, max = 100000)
			if(isnull(newlimit))
				return
			if(newlimit)
				speedlimit = CLAMP(newlimit/1000, 0, 100)
			. = TRUE

		if("accellimit")
			var/newlimit = act_ask(ui.user, action, params, ui, "a7", /datum/om/prompt/number, message = "Input new acceleration limit", title = "Acceleration limit", default = accellimit*1000)
			if(isnull(newlimit))
				return
			if(newlimit)
				accellimit = max(newlimit/1000, 0)
			. = TRUE

		if("move")
			var/ndir = text2num(params["dir"])
			ndir = turn(ndir,pick(90,-90))
			linked().relaymove(ui.user, ndir, accellimit)
			. = TRUE

		if("brake")
			linked().decelerate()
			. = TRUE

		if("apilot")
			if(autopilot_disabled)
				autopilot = FALSE
			else
				autopilot = !autopilot
			. = TRUE

		if("apilot_lock")
			autopilot_disabled = !autopilot_disabled
			autopilot = FALSE
			. = TRUE

		if("manual")
			if(ui.user.blinded || !linked())
				return FALSE
			else  if(!viewing_overmap(ui.user))
				start_coordinated_remoteview(src, ui.user, linked(), viewers, /datum/remote_view_config/overmap_ship_control)
			else
				ui.user.reset_perspective()
			. = TRUE
		/* END HELM */
		/* ENGINES */
		if("global_toggle")
			linked().engines_state = !linked().engines_state
			for(var/datum/ship_engine/E in linked().engines)
				if(linked().engines_state == !E.is_on())
					E.toggle()
			. = TRUE

		if("set_global_limit")
			var/newlim = act_ask(ui.user, action, params, ui, "a8", /datum/om/prompt/number, message = "Input new thrust limit (0..100%)", title = "Thrust limit", default = linked().thrust_limit*100, max = 100)
			if(isnull(newlim))
				return
			linked().thrust_limit = clamp(newlim/100, 0, 1)
			for(var/datum/ship_engine/E in linked().engines)
				E.set_thrust_limit(linked().thrust_limit)
			. = TRUE

		if("global_limit")
			linked().thrust_limit = clamp(linked().thrust_limit + text2num(params["global_limit"]), 0, 1)
			for(var/datum/ship_engine/E in linked().engines)
				E.set_thrust_limit(linked().thrust_limit)
			. = TRUE

		if("set_limit")
			var/datum/ship_engine/E = locate(params["engine"])
			if(!istype(E))
				return TRUE
			var/newlim = act_ask(ui.user, action, params, ui, "a9", /datum/om/prompt/number, message = "Input new thrust limit (0..100)", title = "Thrust limit", default = E.get_thrust_limit(), max = 100)
			if(isnull(newlim))
				return
			var/limit = clamp(newlim/100, 0, 1)
			E.set_thrust_limit(limit)
			. = TRUE

		if("limit")
			var/datum/ship_engine/E = locate(params["engine"])
			if(!istype(E))
				return TRUE
			var/limit = clamp(E.get_thrust_limit() + text2num(params["limit"]), 0, 1)
			E.set_thrust_limit(limit)
			. = TRUE

		if("toggle_engine")
			var/datum/ship_engine/E = locate(params["engine"])
			if(istype(E))
				E.toggle()
			. = TRUE
		/* END ENGINES */
		/* SENSORS */
		if("range")
			var/nrange = act_ask(ui.user, action, params, ui, "a10", /datum/om/prompt/number, message = "Set new sensors range", title = "Sensor range", default = sensors().range, max = world.view, round_entry = FALSE)
			if(isnull(nrange))
				return
			if(nrange)
				sensors().set_range(CLAMP(nrange, 1, world.view))
			. = TRUE
		if("toggle_sensor")
			sensors().toggle()
			. = TRUE
		if("viewing")
			if(ui.user && !isAI(ui.user))
				viewing_overmap(ui.user) ? unlook(ui.user) : look(ui.user)
			. = TRUE
		/* END SENSORS */

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
