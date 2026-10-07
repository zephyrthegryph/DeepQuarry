
/obj/machinery/camera
	name = "security camera"
	desc = "It's used to monitor rooms."
	icon = 'icons/obj/monitors_vr.dmi' // New Icons
	icon_state = "camera"
	use_power = USE_POWER_ACTIVE
	idle_power_usage = 5
	active_power_usage = 10
	plane = MOB_PLANE
	layer = BELOW_MOB_LAYER
	max_integrity = 80
	integrity_failure = 0.5
	damage_deflection = 5

	var/list/network = list(NETWORK_DEFAULT) // ALLOW(instance_list): d: replaced per instance at runtime (26 assignments)
	var/c_tag = null
	var/c_tag_order = 999
	var/status = 1
	anchored = TRUE
	var/invuln = 0
	var/bugged = 0
	var/obj/item/camera_assembly/assembly = null

	var/toughness = 5 //sorta fragile

	//OTHER

	var/view_range = 7
	var/short_range = 2

	var/light_disabled = 0
	var/in_use_lights = 0 // TO BE IMPLEMENTED - LIES.
	var/alarm_on = 0

	var/on_open_network = 0
	var/always_visible = FALSE //Visable from any map, good for entertainment network cameras

	EXPIRY_DECLARE(affected_by_emp_until)
	/// The deadline the `camera_timer_token` timer slot was last set for (next_camera_deadline()).
	var/tmp/camera_timer_at = 0

	var/client_huds = null

MSG_DEF_SELF(camera/nonfunctional, "camera non-functional")

CAPABILITIES(/obj/machinery/camera)
	op("camera_shred", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 1), hostile(), label("Slash"), when(PROC_REF(actor_can_shred_holds)), then(PROC_REF(interaction_shred)))
	op("camera_update_coverage", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(interaction_update_coverage)))
	op("camera_paper_show", inputs(item(/obj/item/paper), item(/obj/item/pda)), priority(OP_PRIORITY_DEFAULT - 2), label("Show to camera"), when(PROC_REF(paper_show_meant_holds)), then(PROC_REF(interaction_show_paper)))
	op("camera_bug_toggle", item(/obj/item/camera_bug), priority(OP_PRIORITY_DEFAULT - 3), label("Bug camera"), needs(req(PROC_REF(camera_can_use_holds), because = MSG(camera/nonfunctional))), then(PROC_REF(interaction_toggle_bug)))
	op("camera_bash", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 4), hostile(), label("Attack"), when(PROC_REF(held_is_bashing_holds)), then(PROC_REF(interaction_bash)))
	op("camera_silicon_look", remote(), priority(OP_PRIORITY_DEFAULT - 1), label("Look through"), then(PROC_REF(camera_silicon_look)))
	extend(/datum/act/hit/generic, instead(then(PROC_REF(smashed_by))))
	owns_one(nameof(assembly), /obj/item/camera_assembly)
	extend(/datum/act/hit/emp, instead(then(PROC_REF(camera_emp))))
	space(SPACE_PANEL, door = nameof(panel_open))
	wires(name = "Camera", count = 6, randomize = TRUE, tools = FALSE, status_lines = PROC_REF(wire_lights))
	on_wire(WIRE_FOCUS, cut = PROC_REF(focus_wire_cut), pulse = PROC_REF(focus_wire_pulsed))
	on_wire(WIRE_MAIN_POWER1, cut = PROC_REF(power_wire_cut))
	on_wire(WIRE_CAM_LIGHT, cut = PROC_REF(light_wire_cut), pulse = PROC_REF(light_wire_pulsed))
	on_wire(WIRE_CAM_ALARM, cut = PROC_REF(alarm_wire_cut), pulse = PROC_REF(alarm_wire_pulsed))
	op("use_welder", tool(TOOL_WELDER), priority(OP_PRIORITY_DEFAULT), wait(0), costs(RES_FUEL, 0), then(PROC_REF(welder_used)))
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(screwdriver_used)))
	op("use_wire_tools", any_of_tools(TOOL_WIRECUTTER, TOOL_MULTITOOL), priority(OP_PRIORITY_DEFAULT), wait(0), label("Wires"), then(PROC_REF(wire_tool_used)))

TYPE_TABLE_DECLARE(/obj/machinery/camera, camera_initial_emp_proof, FALSE)
TYPE_TABLE_DECLARE(/obj/machinery/camera, camera_initial_xray, FALSE)
TYPE_TABLE_DECLARE(/obj/machinery/camera, camera_initial_motion, FALSE)

/obj/machinery/camera/Initialize(mapload)
	if(invuln)
		resistance_flags |= BOMB_PROOF
	observe(src, /datum/notice/machinery_power_lost, src, then(PROC_REF(on_power_signal)))
	observe(src, /datum/notice/machinery_power_restored, src, then(PROC_REF(on_power_signal)))
	rel_set(src, nameof(assembly), new /obj/item/camera_assembly(src))
	assembly.state = 4
	LAZYOR(client_huds, GLOB.global_hud.whitense)

	if(!src.network || src.network.len < 1)
		if(loc)
			log_world("## ERROR [src.name] in [get_area(src)] (x:[src.x] y:[src.y] z:[src.z] has errored. [src.network?"Empty network list":"Null network list"]")
		else
			log_world("## ERROR [src.name] in [get_area(src)]has errored. [src.network?"Empty network list":"Null network list"]")
		ASSERT(src.network)
		ASSERT(src.network.len > 0)
	network = camera_network_intern(network)
	// Make mapping with cameras easier
	if(!c_tag)
		var/area/A = get_area(src)
		c_tag = "[A ? A.name : "Unknown"] #[rand(111,999)]"

	. = ..()

	if (dir == NORTH)
		layer = ABOVE_MOB_LAYER

	if(TYPE_TABLE_GET(src, camera_initial_emp_proof))
		upgradeEmpProof()
	if(TYPE_TABLE_GET(src, camera_initial_xray))
		upgradeXRay()
	if(TYPE_TABLE_GET(src, camera_initial_motion))
		upgradeMotion()

/// Cameras with the same network set share one list. Shared lists are
/// read-only: camera procs replace `network` rather than mutate it.
/proc/camera_network_intern(list/networks)
	var/static/list/interned = list()
	var/key = jointext(networks, "|")
	var/list/shared = interned[key]
	if(!shared)
		shared = networks.Copy()
		interned[key] = shared
	return shared


// alarm handlers release it, motion sensing stops and viewers are kicked out.
/obj/machinery/camera/on_destroy(force)
	for(var/datum/alarm_handler/handler as anything in all_alarm_handlers())
		handler.release_atom(src)
	if(isMotion())
		unsense_proximity(callback = TYPE_PROC_REF(/atom,HasProximity))
	deactivate(null, 0)
	..()

// A camera sleeps on one after() timer for its earliest deadline (EMP recovery, the motion alarm
// delay) and on signals from the mobs it tracks; it never polls.

/// The earliest pending deadline (world.time), or 0 for none.
/obj/machinery/camera/proc/next_camera_deadline()
	. = 0
	if(affected_by_emp_until > 0)
		. = affected_by_emp_until
	// The motion alarm waits for power (power_change() reschedules).
	if(detectTime > 0 && !(power_lost() || emp_held()))
		var/alarm_at = detectTime + alarm_delay + 1
		if(!. || alarm_at < .)
			. = alarm_at

/obj/machinery/camera/proc/schedule_camera_timer()
	var/deadline = next_camera_deadline()
	if(deadline == camera_timer_at && (after_pending(src, "camera_timer_token") || !deadline))
		return
	if(after_pending(src, "camera_timer_token"))
		cancel_after(src, "camera_timer_token")
	camera_timer_at = deadline
	if(deadline)
		sleep_audit_join(src)
		after(src, max(deadline - world.time, 0), PROC_REF(camera_timer_fired), key = "camera_timer_token")

/obj/machinery/camera/proc/camera_timer_fired()
	camera_timer_at = 0
	if(affected_by_emp_until && EXPIRY_EXPIRED(src, affected_by_emp_until, CLOCK_WORLD))
		affected_by_emp_until = 0
		release(src, STAT_OPERABLE, SRC_EMP)
		cancelCameraAlarm()
		changed(src)
		update_coverage()
	check_motion_alarm()
	schedule_camera_timer()

/obj/machinery/camera/sleep_violation()
	var/deadline = next_camera_deadline()
	if(deadline && (!after_pending(src, "camera_timer_token") || camera_timer_at > deadline))
		return "deadline [deadline] (now [world.time]) has no timer"
	return null

/// The area's channel change reaches cameras as the machinery power events.
/obj/machinery/camera/proc/on_power_signal(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	schedule_camera_timer()

/// An EMP may knock the camera out (camera_disrupt()).
/obj/machinery/camera/proc/camera_emp(datum/act/hit/emp/A)
	var/datum/damage_packet/packet = A.packet
	if(prob(100/packet.severity))
		camera_disrupt(packet.severity)
	return HOOK_DECLINE

/// Knocks the camera out for 90 seconds / severity (EMPs, laser pointers). EMP-proof cameras shrug it off.
/obj/machinery/camera/proc/camera_disrupt(severity)
	if(isEmpProof())
		return
	if(!affected_by_emp_until || EXPIRY_EXPIRED(src, affected_by_emp_until, CLOCK_WORLD))
		affected_by_emp_until = max(affected_by_emp_until, world.time + (90 SECONDS / severity))
		hold(src, STAT_OPERABLE, FALSE, SRC_EMP, max(affected_by_emp_until - world.time, 1))
		set_light(0)
		triggerCameraAlarm()
		changed(src)
		update_coverage()
		schedule_camera_timer()

/obj/machinery/camera/blob_act(obj/structure/blob/B)
	if((broken_now()) || (resistance_flags & BOMB_PROOF))
		return
	deal_damage(DAMAGE_BLUNT, max_integrity * (1 - integrity_failure) + DAMAGE_PRECISION, source = B)

/obj/machinery/camera/hitby(atom/movable/source, datum/thrownthing/throwingdatum)
	..()
	if (!isobj(source))
		return
	var/obj/item/O = source
	if(O.throwforce >= src.toughness)
		visible_message(span_boldwarning("[src] was hit by [O]."))

/obj/machinery/camera/proc/setViewRange(num = 7)
	src.view_range = num
	GLOB.cameranet.updateVisibility(src, 0)

/// Old attackby's unconditional first line, before any branch was tested. Always
/// runs first and declines, so the branches below (and the base attackby) still see it.
/obj/machinery/camera/proc/interaction_update_coverage(datum/act/op/A)
	update_coverage()
	return OP_DECLINE

/// Old attackby: hold a paper or PDA up to the camera.
/// Old attackby: bug or unbug the camera.
/obj/machinery/camera/proc/camera_can_use(mob/actor, atom/target, obj/item/held)
	return can_use()

/// Old attackby: bashing the camera with a damaging item.
/// Old attack_hand (never called ..()): a human who can shred slashes the camera.
/obj/machinery/camera/proc/actor_can_shred(mob/actor, atom/target, obj/item/held)
	if(!ishuman(actor))
		return FALSE
	var/mob/living/carbon/human/human_actor = actor
	return human_actor.species.can_shred(human_actor, FALSE, 11)

/obj/machinery/camera/proc/interaction_shred(datum/act/op/A)
	var/mob/user = A.actor
	set_status(0)
	user.do_attack_animation(src)
	user.setClickCooldown(user.get_attack_speed())
	act_message(user, src, others = span_warning("%U% slashes at %T%!"))
	play_sfx(src, SFX_WEAPONS_SLASH, 2)
	add_hiddenprint(user)
	deal_damage(DAMAGE_SHARP, max_integrity * (1 - integrity_failure) + DAMAGE_PRECISION, source = user, attacker = user)
	return OP_OK

/// A simple mob's (or a xeno's) generic hit on it, taken over (the hit/generic action): HOOK_DECLINE lets the default generic attack land.
/obj/machinery/camera/proc/smashed_by(datum/act/hit/generic/A)
	var/mob/user = A.attacker
	if(isanimal(user))
		var/mob/living/simple_mob/S = user
		set_status(0)
		S.do_attack_animation(src)
		S.setClickCooldown(user.get_attack_speed())
		act_message(user, src, others = span_warning("%U% [pick(S.attacktext)] %T%!"))
		playsound(src, S.attack_sound, 100, 1)
		add_hiddenprint(user)
		deal_damage(DAMAGE_BLUNT, max_integrity * (1 - integrity_failure) + DAMAGE_PRECISION, source = user, attacker = user)
		return OP_OK
	return OP_OK

/obj/machinery/camera/proc/screwdriver_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	update_coverage()
	set_panel_open(!panel_open)
	act_message(user, null, MSG_SELF(span_notice("You screw the camera's panel [panel_open ? "open" : "closed"].")), \
		MSG_OTHERS(span_warning("%U% screws the camera's panel [panel_open ? "open" : "closed"]!")))
	playsound(src, tool.usesound, 50, TRUE)
	return OP_OK

/// The wirecutters or a multitool: the coverage is refreshed, and behind the open panel the wires' window opens.
/obj/machinery/camera/proc/wire_tool_used(datum/act/op/A)
	update_coverage()
	if(panel_open)
		interact(A.actor)
	return OP_OK

/obj/machinery/camera/proc/welder_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	update_coverage()
	if(!wires_all_cut(src) && !broken_now())
		return OP_DECLINE
	if(!weld(tool, user, PROC_REF(welded_off), list(user, tool)))
		return OP_OK
	return OP_OK

/obj/machinery/camera/proc/welded_off(mob/user, obj/item/tool)
	if(assembly)
		assembly.forceMove(loc)
		assembly.set_anchored(TRUE)
		assembly.camera_name = c_tag
		assembly.camera_network = english_list(network, NETWORK_DEFAULT, ",", ",")
		assembly.update_icon()
		assembly.set_dir(dir)
		if(broken_now())
			assembly.state = 2
			to_chat(user, span_notice("You repaired \the [src] frame."))
		else
			assembly.state = 1
			to_chat(user, span_notice("You cut \the [src] free from the wall."))
			new /obj/item/stack/cable_coil(loc, 2)
		rel_take(src, nameof(assembly))
	spent(src, user)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/camera/proc/interaction_show_paper(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	update_coverage()
	var/mob/living/U = user
	var/obj/item/paper/X = null
	var/obj/item/pda/P = null

	var/itemname = ""
	var/info = ""
	if(istype(W, /obj/item/paper))
		X = W
		itemname = X.name
		info = X.info
	else
		P = W
		itemname = P.name
		var/datum/data/pda/app/notekeeper/N = P.find_program(/datum/data/pda/app/notekeeper)
		if(N)
			info = N.notehtml
	to_chat(U, "You hold \a [itemname] up to the camera ...")
	for(var/mob/living/silicon/ai/O in REGISTRY_MEMBERS(REGISTRY_LIVING_MOBS))
		if(!O.client)
			continue
		if(U.name == "Unknown")
			to_chat(O, span_infoplain(span_bold("[U]") + " holds \a [itemname] up to one of your cameras ..."))
		else
			to_chat(O, span_infoplain(span_bold("<a href='byond://?src=\ref[O];track2=\ref[O];track=\ref[U];trackname=[U.name]'>[U]</a>") + " holds \a [itemname] up to one of your cameras ..."))

		// structured TGUI AdminReport.
		dq_admin_report_html(O, itemname, "<TT>[info]</TT>")
	return OP_OK

/obj/machinery/camera/proc/paper_show_meant(mob/actor, atom/target, obj/item/held)
	return can_use() && isliving(actor)

/obj/machinery/camera/proc/interaction_toggle_bug(datum/act/op/A)
	var/mob/user = A.actor
	update_coverage()
	if(src.bugged)
		to_chat(user, span_notice("Camera bug removed."))
		src.bugged = 0
	else
		to_chat(user, span_notice("Camera bugged."))
		src.bugged = 1
	return OP_OK

/obj/machinery/camera/proc/interaction_bash(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	update_coverage()
	user.setClickCooldown(user.get_attack_speed(W))
	if (W.force >= src.toughness)
		user.do_attack_animation(src)
		act_message(src, user, others = span_boldwarning("%U% has been [LAZYLEN(W.attack_verb) ? pick(W.attack_verb) : "attacked"] with [W] by %T%!"))
		if (W.hitsound)
			playsound(src, W.hitsound, 50, 1, -1)
	receive_weapon_hit(W, user, silent = FALSE)
	return OP_OK

/obj/machinery/camera/proc/held_is_bashing(mob/actor, atom/target, obj/item/held)
	return held?.obj_damage_type()

/obj/machinery/camera/proc/deactivate(user as mob, choice = 1)
	// The only way for AI to reactivate cameras are malf abilities, this gives them different messages.
	if(isAI(user))
		user = null

	if(choice != 1)
		return

	set_status(!src.status)
	if (!(src.status))
		if(user)
			act_message(user, src, others = span_notice(" %U% has deactivated %T%!"))
			add_hiddenprint(user)
		else
			visible_message(span_notice(" [src] clicks and shuts down. "))
		play_sfx(src, SFX_ITEMS_WIRECUTTER)
		icon_state = "[initial(icon_state)]1"
	else
		if(user)
			act_message(user, src, others = span_notice(" %U% has reactivated %T%!"))
			add_hiddenprint(user)
		else
			visible_message(span_notice(" [src] clicks and reactivates itself. "))
		play_sfx(src, SFX_ITEMS_WIRECUTTER)
		icon_state = initial(icon_state)

/obj/machinery/camera/atom_break(damage_flag)
	. = ..()
	if(!.)
		return
	wires_cut_all(src)

	triggerCameraAlarm()
	update_coverage()

	//sparks
	fx_sparks(loc, 5, FALSE)
	play_sfx(src, SFX_SPARKS)

/obj/machinery/camera/atom_fix()
	. = ..()
	if(!.)
		return
	wires_mend_all(src)
	cancelCameraAlarm()
	update_coverage()

SETTER(/obj/machinery/camera, status)
/obj/machinery/camera/proc/set_status(newstatus)
	if (status != newstatus)
		status = newstatus
		tracked_changed(src, nameof(status))
		update_coverage()

/// The look (the draw sweep: from its template).
/obj/machinery/camera/draw(datum/look/look)
	..()
	look.state("[initial(icon_state)][appearance_suffix()]")

/// "1" when off or broken, "emp" while EMP-ed, else nothing.
/obj/machinery/camera/proc/appearance_suffix()
	if(!status || broken_now())
		return "1"
	if(emp_held())
		return "emp"
	return ""

/obj/machinery/camera/proc/triggerCameraAlarm(duration = 0)
	alarm_on = 1
	GLOB.camera_alarm.triggerAlarm(loc, src, duration)

/obj/machinery/camera/proc/cancelCameraAlarm()
	if(wire_is_cut(src, WIRE_CAM_ALARM))
		return

	alarm_on = 0
	GLOB.camera_alarm.clearAlarm(loc, src)

//if false, then the camera is listed as DEACTIVATED and cannot be used
/obj/machinery/camera/proc/can_use()
	if(!status)
		return 0
	if((emp_held() || broken_now()))
		return 0
	return 1

/obj/machinery/camera/proc/can_see()
	var/list/see = null
	var/turf/pos = get_turf(src)
	if(!pos)
		return list()

	if(isXRay())
		see = range(view_range, pos)
	else
		see = hear(view_range, pos)
	return see

/atom/proc/auto_turn()
	//Automatically turns based on nearby walls.
	var/turf/simulated/wall/T = null
	for(var/i = 1, i <= 8, i += i)
		T = get_ranged_target_turf(src, i, 1)
		if(istype(T))
			//If someone knows a better way to do this, let me know. -Giacom
			switch(i)
				if(NORTH)
					set_dir(SOUTH)
				if(SOUTH)
					set_dir(NORTH)
				if(WEST)
					set_dir(EAST)
				if(EAST)
					set_dir(WEST)
			break

//Return a working camera that can see a given mob
//or null if none
/proc/seen_by_camera(mob/M)
	for(var/obj/machinery/camera/C in oview(4, M))
		if(C.can_use())	// check if camera disabled
			return C
	return null

/proc/near_range_camera(mob/M)

	for(var/obj/machinery/camera/C in range(4, M))
		if(C.can_use())	// check if camera disabled
			return C

	return null

/// Welds (a timed tool job); `on_done` runs on src with `done_args` when it is done. 0 if busy or refused.
/obj/machinery/camera/proc/weld(obj/item/tool, mob/user, on_done, list/done_args)
	if(task_busy(src)) // a weld in progress claims it
		return 0
	var/result = use_tool(user, tool, src, delay = 10 SECONDS, quality = TOOL_WELDER, volume = 50, start_self = "You start to weld [src]..", receiver = src, on_done = PROC_REF(weld_finished), done_args = list(on_done, done_args), claims = TRUE)
	return result

/obj/machinery/camera/proc/weld_finished(on_done, list/done_args)
	if(on_done)
		call(src, on_done)(arglist(done_args))

/obj/machinery/camera/interact(mob/living/user as mob)
	if(!panel_open || isAI(user))
		return

	if(broken_now())
		to_chat(user, span_warning("\The [src] is broken."))
		return

	wires_open(src, user)

/obj/machinery/camera/proc/add_network(network_name)
	add_networks(list(network_name))

/obj/machinery/camera/proc/remove_network(network_name)
	remove_networks(list(network_name))

/obj/machinery/camera/proc/add_networks(list/networks)
	var/network_added
	network_added = 0
	for(var/network_name in networks)
		if(!(network_name in src.network))
			network = network + network_name
			network_added = 1

	if(network_added)
		update_coverage(1)

/obj/machinery/camera/proc/remove_networks(list/networks)
	var/network_removed
	network_removed = 0
	for(var/network_name in networks)
		if(network_name in src.network)
			network = network - network_name
			network_removed = 1

	if(network_removed)
		update_coverage(1)

/obj/machinery/camera/proc/replace_networks(list/networks)
	if(networks.len != network.len)
		network = networks
		update_coverage(1)
		return

	for(var/new_network in networks)
		if(!(new_network in network))
			network = networks
			update_coverage(1)
			return

/obj/machinery/camera/proc/clear_all_networks()
	if(network.len)
		network = list()
		update_coverage(1)

/obj/machinery/camera/proc/tgui_structure()
	var/cam[0]
	cam["name"] = sanitize(c_tag)
	cam["deact"] = !can_use()
	cam["camera"] = "\ref[src]"
	cam["omni"] = always_visible
	cam["x"] = x
	cam["y"] = y
	cam["z"] = z
	return cam

/obj/machinery/camera/proc/update_coverage(network_change = 0)
	if(network_change)
		var/list/open_networks = difflist(network, GLOB.restricted_camera_networks)
		// Add or remove camera from the camera net as necessary
		if(on_open_network && !open_networks.len)
			GLOB.cameranet.removeCamera(src)
		else if(!on_open_network && open_networks.len)
			on_open_network = 1
			GLOB.cameranet.addCamera(src)
	else
		GLOB.cameranet.updateVisibility(src, 0)

// Resets the camera's wires to fully operational state. Used by one of Malfunction abilities.
/obj/machinery/camera/proc/reset_wires()
	if(!wiring_of(src))
		return
	atom_fix() // Fix the camera
	wires_repair(src)
	changed(src)
	update_coverage()

// ---- the wires ----


/obj/machinery/camera/proc/wire_lights()
	return list(
		"The focus light is [(view_range == initial(view_range)) ? "on" : "off"].",
		"The power link light is [can_use() ? "on" : "off"].",
		"The camera light is [light_disabled ? "off" : "on"].",
		"The alarm light is [alarm_on ? "on" : "off"].")

/// The focus wire cut shortens the view; mended, it is back.
/obj/machinery/camera/proc/focus_wire_cut(datum/act/A)
	var/datum/notice/wire_cut/N = A
	setViewRange(N.mended ? initial(view_range) : short_range)

/obj/machinery/camera/proc/focus_wire_pulsed(datum/act/A)
	setViewRange(view_range == initial(view_range) ? short_range : initial(view_range))

/// The power wire cut switches the camera off; mended, back on.
/obj/machinery/camera/proc/power_wire_cut(datum/act/A)
	var/datum/notice/wire_cut/N = A
	if(status && !N.mended || !status && N.mended)
		deactivate(N.user, 1)

/obj/machinery/camera/proc/light_wire_cut(datum/act/A)
	var/datum/notice/wire_cut/N = A
	light_disabled = !N.mended

/obj/machinery/camera/proc/light_wire_pulsed(datum/act/A)
	light_disabled = !light_disabled

/obj/machinery/camera/proc/alarm_wire_cut(datum/act/A)
	var/datum/notice/wire_cut/N = A
	if(!N.mended)
		triggerCameraAlarm()
	else
		cancelCameraAlarm()

/obj/machinery/camera/proc/alarm_wire_pulsed(datum/act/A)
	visible_message("[icon2html(src, viewers(src))] *beep*", "[icon2html(src, viewers(src))] *beep*")

/obj/machinery/camera/proc/actor_can_shred_holds(datum/act/op/A)
	return actor_can_shred(A.actor, src, A.held)

/obj/machinery/camera/proc/paper_show_meant_holds(datum/act/op/A)
	return paper_show_meant(A.actor, src, A.held)

/obj/machinery/camera/proc/camera_can_use_holds(datum/act/op/A)
	return camera_can_use(A.actor, src, A.held)

/obj/machinery/camera/proc/held_is_bashing_holds(datum/act/op/A)
	return held_is_bashing(A.actor, src, A.held)
