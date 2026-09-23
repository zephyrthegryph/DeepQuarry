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

	var/list/network = list(NETWORK_DEFAULT)
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
	var/busy = 0

	var/on_open_network = 0
	var/always_visible = FALSE //Visable from any map, good for entertainment network cameras

	var/affected_by_emp_until = 0
	/// The REACT_AT token for next_camera_deadline(), and the deadline it was set for.
	var/tmp/camera_timer_token
	var/tmp/camera_timer_at = 0

	var/client_huds = null

/obj/machinery/camera/Initialize(mapload)
	RegisterSignals(src, list(COMSIG_MACHINERY_POWER_LOST, COMSIG_MACHINERY_POWER_RESTORED), PROC_REF(on_power_signal))
	set_wires(new /datum/wires/camera(src))
	assembly = new(src)
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

/obj/machinery/camera/Destroy()
	// cancelCameraAlarm() intentionally respects a cut alarm wire, which is wrong
	// during destruction: every handler must release source and cached-camera refs.
	for(var/datum/alarm_handler/handler as anything in SSalarm.all_handlers)
		handler.release_atom(src)
	if(isMotion())
		unsense_proximity(callback = TYPE_PROC_REF(/atom,HasProximity))
	deactivate(null, 0) //kick anyone viewing out
	if(assembly)
		qdel(assembly)
		assembly = null
	qdel(wires)
	wires = null
	client_huds = null
	network = null
	return ..()

// A camera sleeps on one REACT_AT for its earliest deadline (EMP recovery, the motion alarm
// delay) and on signals from the mobs it tracks; it never polls (reactor.md §9).

/// The earliest pending deadline (world.time), or 0 for none.
/obj/machinery/camera/proc/next_camera_deadline()
	. = 0
	if((stat & EMPED) && affected_by_emp_until > 0)
		. = affected_by_emp_until
	// The motion alarm waits for power (power_change() reschedules).
	if(detectTime > 0 && !(stat & (NOPOWER|EMPED)))
		var/alarm_at = detectTime + alarm_delay + 1
		if(!. || alarm_at < .)
			. = alarm_at

/obj/machinery/camera/proc/schedule_camera_timer()
	var/deadline = next_camera_deadline()
	if(deadline == camera_timer_at && (!isnull(camera_timer_token) || !deadline))
		return
	if(!isnull(camera_timer_token))
		REACT_CANCEL(src, camera_timer_token)
		camera_timer_token = null
	camera_timer_at = deadline
	if(deadline)
		camera_timer_token = REACT_AT(src, deadline)

/obj/machinery/camera/on_react(reason, source, source_kind)
	. = ..()
	if(!(reason & REACT_REASON_TIMER))
		return
	camera_timer_token = null
	camera_timer_at = 0
	if((stat & EMPED) && world.time >= affected_by_emp_until)
		stat &= ~EMPED
		cancelCameraAlarm()
		update_icon()
		update_coverage()
	check_motion_alarm()
	schedule_camera_timer()

/obj/machinery/camera/react_sleep_violation()
	var/deadline = next_camera_deadline()
	if(deadline && (isnull(camera_timer_token) || camera_timer_at > deadline))
		return "deadline [deadline] (now [world.time]) has no timer"
	return null

/// The area's channel change reaches cameras as the machinery power signals.
/obj/machinery/camera/proc/on_power_signal(datum/source)
	SIGNAL_HANDLER
	schedule_camera_timer()

/obj/machinery/camera/emp_act(severity, recursive, forced)
	. = ..()
	if (. & EMP_PROTECT_SELF)
		return
	if(!isEmpProof() && (forced || prob(100/severity)))
		if(!affected_by_emp_until || (world.time > affected_by_emp_until))
			affected_by_emp_until = max(affected_by_emp_until, world.time + (90 SECONDS / severity))
			stat |= EMPED
			set_light(0)
			triggerCameraAlarm()
			update_icon()
			update_coverage()
			schedule_camera_timer()

/obj/machinery/camera/ex_act(severity)
	if(src.invuln)
		return

	return ..()

/obj/machinery/camera/blob_act(obj/structure/blob/B)
	if((stat & BROKEN) || invuln)
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

/obj/machinery/camera/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/camera_shred,
		/datum/interaction/machine_item/camera_update_coverage,
		/datum/interaction/machine_item/camera_paper_show,
		/datum/interaction/machine_item/camera_bug_toggle,
		/datum/interaction/machine_item/camera_bash,
	)
	..()

/// Old attackby's unconditional first line, before any branch was tested. Always
/// runs first and declines, so the branches below (and the base attackby) still see it.
/datum/interaction/machine_item/camera_update_coverage
	id = "camera_update_coverage"
	name = "Use"
	held_type = /obj/item
	consumes_input = FALSE
	effect = /obj/machinery/camera/proc/interaction_update_coverage

/obj/machinery/camera/proc/interaction_update_coverage(mob/user, obj/item/held, datum/interaction/interaction)
	update_coverage()
	return FALSE

/// Old attackby: hold a paper or PDA up to the camera.
/datum/interaction/machine_item/camera_paper_show
	id = "camera_paper_show"
	name = "Show to camera"
	held_type = list(/obj/item/paper, /obj/item/pda)
	offered_when = list(REQ_ON(PRED_TARGET, /obj/machinery/camera/proc/paper_show_meant, null))
	effect = /obj/machinery/camera/proc/interaction_show_paper

/// Old attackby: bug or unbug the camera.
/datum/interaction/machine_item/camera_bug_toggle
	id = "camera_bug_toggle"
	name = "Bug camera"
	held_type = /obj/item/camera_bug
	requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_TARGET, /obj/machinery/camera/proc/camera_can_use, "camera non-functional"))
	effect = /obj/machinery/camera/proc/interaction_toggle_bug

/obj/machinery/camera/proc/camera_can_use(mob/actor, atom/target, obj/item/held)
	return can_use()

/// Old attackby: bashing the camera with a damaging item.
/datum/interaction/machine_item/camera_bash
	id = "camera_bash"
	name = "Attack"
	category = INTERACTION_CAT_ATTACK
	tags = list(INTERACTION_TAG_HOSTILE)
	held_type = /obj/item
	offered_when = list(REQ_ON(PRED_HELD, /obj/machinery/camera/proc/held_is_bashing, null))
	effect = /obj/machinery/camera/proc/interaction_bash

/// Old attack_hand (never called ..()): a human who can shred slashes the camera.
/datum/interaction/machine_hand/ungated/camera_shred
	id = "camera_shred"
	name = "Slash"
	category = INTERACTION_CAT_ATTACK
	tags = list(INTERACTION_TAG_HOSTILE)
	offered_when = list(REQ_ON(PRED_ACTOR, /obj/machinery/camera/proc/actor_can_shred, null))
	effect = /obj/machinery/camera/proc/interaction_shred

/obj/machinery/camera/proc/actor_can_shred(mob/actor, atom/target, obj/item/held)
	if(!ishuman(actor))
		return FALSE
	var/mob/living/carbon/human/human_actor = actor
	return human_actor.species.can_shred(human_actor, FALSE, 11)

/obj/machinery/camera/proc/interaction_shred(mob/user, obj/item/held, datum/interaction/interaction)
	set_status(0)
	user.do_attack_animation(src)
	user.setClickCooldown(user.get_attack_speed())
	visible_message(span_warning("\The [user] slashes at [src]!"))
	playsound(src, 'sound/weapons/slash.ogg', 100, 1)
	add_hiddenprint(user)
	deal_damage(DAMAGE_SHARP, max_integrity * (1 - integrity_failure) + DAMAGE_PRECISION, source = user, attacker = user)
	return TRUE

/obj/machinery/camera/attack_generic(mob/user as mob)
	if(isanimal(user))
		var/mob/living/simple_mob/S = user
		set_status(0)
		S.do_attack_animation(src)
		S.setClickCooldown(user.get_attack_speed())
		visible_message(span_warning("\The [user] [pick(S.attacktext)] \the [src]!"))
		playsound(src, S.attack_sound, 100, 1)
		add_hiddenprint(user)
		deal_damage(DAMAGE_BLUNT, max_integrity * (1 - integrity_failure) + DAMAGE_PRECISION, source = user, attacker = user)
		return 1
	return 0

/obj/machinery/camera/screwdriver_act(mob/user, obj/item/tool)
	update_coverage()
	panel_open = !panel_open
	user.visible_message(span_warning("[user] screws the camera's panel [panel_open ? "open" : "closed"]!"), span_notice("You screw the camera's panel [panel_open ? "open" : "closed"]."))
	playsound(src, tool.usesound, 50, TRUE)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/camera/wirecutter_act(mob/user, obj/item/tool)
	update_coverage()
	if(!panel_open)
		return ITEM_INTERACT_BLOCKING
	interact(user)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/camera/multitool_act(mob/user, obj/item/tool)
	return wirecutter_act(user, tool)

/obj/machinery/camera/welder_act(mob/user, obj/item/tool)
	update_coverage()
	if(!wires.is_all_cut() && !(stat & BROKEN))
		return ..()
	if(!weld(tool, user))
		return ITEM_INTERACT_BLOCKING
	if(assembly)
		assembly.forceMove(loc)
		assembly.anchored = TRUE
		assembly.camera_name = c_tag
		assembly.camera_network = english_list(network, NETWORK_DEFAULT, ",", ",")
		assembly.update_icon()
		assembly.set_dir(dir)
		if(stat & BROKEN)
			assembly.state = 2
			to_chat(user, span_notice("You repaired \the [src] frame."))
		else
			assembly.state = 1
			to_chat(user, span_notice("You cut \the [src] free from the wall."))
			new /obj/item/stack/cable_coil(loc, 2)
		assembly = null
	qdel(src)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/camera/proc/interaction_show_paper(mob/user, obj/item/W, datum/interaction/interaction)
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
	for(var/mob/living/silicon/ai/O in GLOB.living_mob_list)
		if(!O.client)
			continue
		if(U.name == "Unknown")
			to_chat(O, span_infoplain(span_bold("[U]") + " holds \a [itemname] up to one of your cameras ..."))
		else
			to_chat(O, span_infoplain(span_bold("<a href='byond://?src=\ref[O];track2=\ref[O];track=\ref[U];trackname=[U.name]'>[U]</a>") + " holds \a [itemname] up to one of your cameras ..."))

		// structured TGUI AdminReport.
		dq_admin_report_html(O, itemname, "<TT>[info]</TT>")
	return TRUE

/obj/machinery/camera/proc/paper_show_meant(mob/actor, atom/target, obj/item/held)
	return can_use() && isliving(actor)

/obj/machinery/camera/proc/interaction_toggle_bug(mob/user, obj/item/held, datum/interaction/interaction)
	update_coverage()
	if(src.bugged)
		to_chat(user, span_notice("Camera bug removed."))
		src.bugged = 0
	else
		to_chat(user, span_notice("Camera bugged."))
		src.bugged = 1
	return TRUE

/obj/machinery/camera/proc/interaction_bash(mob/user, obj/item/W, datum/interaction/interaction)
	update_coverage()
	user.setClickCooldown(user.get_attack_speed(W))
	if (W.force >= src.toughness)
		user.do_attack_animation(src)
		visible_message(span_boldwarning("[src] has been [LAZYLEN(W.attack_verb) ? pick(W.attack_verb) : "attacked"] with [W] by [user]!"))
		if (W.hitsound)
			playsound(src, W.hitsound, 50, 1, -1)
	receive_weapon_hit(W, user, silent = FALSE)
	return TRUE

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
			visible_message(span_notice(" [user] has deactivated [src]!"))
			add_hiddenprint(user)
		else
			visible_message(span_notice(" [src] clicks and shuts down. "))
		playsound(src, 'sound/items/Wirecutter.ogg', 100, 1)
		icon_state = "[initial(icon_state)]1"
	else
		if(user)
			visible_message(span_notice(" [user] has reactivated [src]!"))
			add_hiddenprint(user)
		else
			visible_message(span_notice(" [src] clicks and reactivates itself. "))
		playsound(src, 'sound/items/Wirecutter.ogg', 100, 1)
		icon_state = initial(icon_state)

/obj/machinery/camera/atom_break(damage_flag)
	. = ..()
	if(!.)
		return
	wires.cut_all()

	triggerCameraAlarm()
	update_coverage()

	//sparks
	var/datum/effect/effect/system/spark_spread/spark_system = new /datum/effect/effect/system/spark_spread()
	spark_system.set_up(5, 0, loc)
	spark_system.start()
	playsound(src, "sparks", 50, 1)

/obj/machinery/camera/atom_fix()
	. = ..()
	if(!.)
		return
	wires.mend_all()
	cancelCameraAlarm()
	update_coverage()

/obj/machinery/camera/proc/set_status(newstatus)
	if (status != newstatus)
		status = newstatus
		update_coverage()

/obj/machinery/camera/update_icon()
	if (!status || (stat & BROKEN))
		icon_state = "[initial(icon_state)]1"
	else if (stat & EMPED)
		icon_state = "[initial(icon_state)]emp"
	else
		icon_state = initial(icon_state)

/obj/machinery/camera/proc/triggerCameraAlarm(duration = 0)
	alarm_on = 1
	GLOB.camera_alarm.triggerAlarm(loc, src, duration)

/obj/machinery/camera/proc/cancelCameraAlarm()
	if(wires.is_cut(WIRE_CAM_ALARM))
		return

	alarm_on = 0
	GLOB.camera_alarm.clearAlarm(loc, src)

//if false, then the camera is listed as DEACTIVATED and cannot be used
/obj/machinery/camera/proc/can_use()
	if(!status)
		return 0
	if(stat & (EMPED|BROKEN))
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
					src.set_dir(SOUTH)
				if(SOUTH)
					src.set_dir(NORTH)
				if(WEST)
					src.set_dir(EAST)
				if(EAST)
					src.set_dir(WEST)
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

/obj/machinery/camera/proc/weld(obj/item/tool, mob/user)
	if(busy)
		return 0
	busy = 1
	var/result = use_tool(user, tool, src, delay = 10 SECONDS, quality = TOOL_WELDER, volume = 50, message_self = "You start to weld [src]..")
	busy = 0
	return result

/obj/machinery/camera/interact(mob/living/user as mob)
	if(!panel_open || isAI(user))
		return

	if(stat & BROKEN)
		to_chat(user, span_warning("\The [src] is broken."))
		return

	wires.Interact(user)

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
	if(!wires)
		return
	atom_fix() // Fix the camera
	wires.repair()
	update_icon()
	update_coverage()
