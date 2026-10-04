
/obj/item/gps
	name = "global positioning system"
	desc = "Triangulates the approximate co-ordinates using a nearby satellite network. Alt+click to toggle power."
	icon = 'icons/obj/gps.dmi'
	icon_state = "gps-gen"
	w_class = ITEMSIZE_TINY
	slot_flags = SLOT_BELT
	MATERIAL_BULK(MAT_STEEL, 500)

	var/gps_tag = "GEN0"
	/// Until when an EMP keeps the unit busted (EMP_DISABLE).
	EXPIRY_DECLARE(emp_until)
	var/long_range = FALSE		// If true, can see farther, depending on get_map_levels().
	var/local_mode = FALSE		// If true, only GPS signals of the same Z level are shown.
	var/hide_signal = FALSE		// If true, signal is not visible to other GPS devices.
	var/can_hide_signal = FALSE	// If it can toggle the above var.

	/// Will not show other signals or emit its own signal if false.
	var/tracking = FALSE
	/// The mob carrying it (a relation view).
	var/mob/holder = null
	/// An EMP has it down (its look follows; the expiry itself is emp_until).
	var/emp_busted = FALSE

	var/list/tracking_devices
	var/list/showing_tracked_names
	var/obj/compass_holder/compass
	var/theme
	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE

REGISTRY_MEMBERSHIP(/obj/item/gps, REGISTRY_GPS)
TRACKED(/obj/item/gps, tracking)
TRACKED(/obj/item/gps, emp_busted)

CAPABILITIES(/obj/item/gps)
	owns_one(nameof(compass), starts = /obj/compass_holder)
	ref_one(nameof(holder), /mob)
	interface("Gps", state = nameof(GLOB.tgui_inventory_state), input = in_hand())
	op("toggle_power", hand(), gesture(GESTURE_ALT), label("Toggle power"), then(PROC_REF(alt_toggled)))
	op("power", ui_act("power"), then(PROC_REF(ui_act_power)))
	op("rename", ui_act("rename", arg("value", schema_text(4096))), then(PROC_REF(ui_act_rename)))
	op("localMode", ui_act("localMode"), then(PROC_REF(ui_act_localmode)))
	op("hideSignal", ui_act("hideSignal"), then(PROC_REF(ui_act_hidesignal)))
	op("trackLabel", ui_act("trackLabel", arg("ref", schema_text(4096))), then(PROC_REF(ui_act_tracklabel)))
	op("stopTrack", ui_act("stopTrack", arg("ref", schema_text(4096))), then(PROC_REF(ui_act_stoptrack)))
	op("startTrack", ui_act("startTrack", arg("ref", schema_ref(/obj/item/gps))), then(PROC_REF(ui_act_starttrack)))
	op("trackColor", ui_act("trackColor", arg("color", schema_text(4096)), arg("ref", schema_ref(/obj/item/gps))), then(PROC_REF(ui_act_trackcolor)))
	// The compass refreshes while a carried GPS is tracking.
	every(2 SECONDS, then(PROC_REF(gps_step)), when = cond_all(nameof(tracking), nameof(holder)))

/obj/item/gps/Initialize(mapload)
	. = ..()
	name = "global positioning system ([gps_tag])"
	update_holder()
	update_icon()

/obj/item/gps/proc/check_visible_to_holder()
	. = (holder_ref() && (holder_ref().get_active_hand() == src || holder_ref().get_inactive_hand() == src))

/obj/item/gps/proc/update_holder()

	if(holder_ref() && loc != holder_ref())
		unobserve(holder_ref(), /datum/notice/movable_attempted_move, src)
		holder_ref().client?.screen -= compass
		rel_clear(src, nameof(holder))

	if(istype(loc, /mob))
		rel_set(src, nameof(holder), loc)
		observe(holder_ref(), /datum/notice/movable_attempted_move, src, then(PROC_REF(on_holder_moved)))
		dq_add_recursive_move(holder_ref())

	if(holder_ref() && tracking)
		if(holder_ref().client)
			if(check_visible_to_holder())
				holder_ref().client.screen |= compass
			else
				holder_ref().client.screen -= compass
	else
		if(holder_ref()?.client)
			holder_ref().client.screen -= compass

/obj/item/gps/pickup()
	. = ..()
	update_holder()

/obj/item/gps/equipped_robot()
	. = ..()
	update_holder()

/obj/item/gps/equipped()
	. = ..()
	update_holder()

/obj/item/gps/dropped(mob/user, equipping, slot)
	. = ..()
	update_holder()

/obj/item/gps/proc/gps_step(datum/act/timer/A)
	update_holder()
	if(holder_ref())
		update_compass(src, TRUE)

// the GPS leaves its holder's tracking.
/obj/item/gps/on_destroy(force)
	update_holder()
	..()

/obj/item/gps/proc/can_track(obj/item/gps/other, reachable_z_levels)
	if(!other.tracking || EXPIRY_ACTIVE(other, emp_until, CLOCK_WORLD) || other.hide_signal || is_vore_jammed(other))
		return FALSE
	var/turf/origin = get_turf(src)
	var/turf/target = get_turf(other)
	if(!istype(origin) || !istype(target))
		return FALSE
	if(origin.z == target.z)
		return TRUE
	if(local_mode)
		return FALSE
	reachable_z_levels = reachable_z_levels || using_map.get_map_levels(origin.z, long_range)
	return (target.z in reachable_z_levels)

/// Hooked on the holder's movement.
/obj/item/gps/proc/on_holder_moved(datum/act/notice/A)
	var/atom/movable/source = A.target
	update_compass(source)

/obj/item/gps/proc/update_compass(atom/movable/source, update_compass_icon)
	SHOULD_NOT_SLEEP(TRUE)
	compass.hide_waypoints(FALSE)
	var/turf/my_turf = get_turf(src)
	for(var/thing in tracking_devices)
		var/obj/item/gps/gps = locate(thing)
		if(!istype(gps) || QDELETED(gps))
			LAZYREMOVE(tracking_devices, thing)
			LAZYREMOVE(showing_tracked_names, thing)
			continue
		var/turf/gps_turf = get_turf(gps)
		var/gps_tag = LAZYACCESS(showing_tracked_names, thing) ? gps.gps_tag : null
		if(istype(gps_turf))
			compass.set_waypoint("\ref[gps]", gps_tag, gps_turf.x, gps_turf.y, gps_turf.z, LAZYACCESS(tracking_devices, "\ref[gps]"))
		else
			compass.set_waypoint("\ref[gps]", gps_tag, 0, 0, 0, LAZYACCESS(tracking_devices, "\ref[gps]"))
		if(can_track(gps) && gps_turf && my_turf && gps_turf.z == my_turf.z)
			compass.show_waypoint("\ref[gps]")
	compass.rebuild_overlay_lists(update_compass_icon)

/// The empty-hand alt-click: switch the unit on or off.
/obj/item/gps/proc/alt_toggled(datum/act/op/A)
	var/mob/user = A.actor
	toggletracking(user)
	return OP_OK

/obj/item/gps/proc/toggletracking(mob/living/user)
	if(!istype(user))
		return
	if(EXPIRY_ACTIVE(src, emp_until, CLOCK_WORLD))
		to_chat(user, "It's busted!")
		return

	toggle_tracking()
	if(tracking)
		to_chat(user, "[src] is now tracking, and visible to other GPS devices.") // purdev Fixed an issue where the if/else argument was written backwards
	else // purdev Fixed an issue where the if/else argument was written backwards
		to_chat(user, "[src] is no longer tracking, or visible to other GPS devices.") // purdev Fixed an issue where the if/else argument was written backwards

/obj/item/gps/proc/toggle_tracking()
	set_tracking(!tracking)
	if(tracking)
		update_compass(src, TRUE)
	else
		update_compass(src)
	update_holder()
	update_icon()

CAPABILITY(/obj/item/gps, emp_disable(5 MINUTES))

/obj/item/gps/emp_disable_changed(disabled)
	..()
	set_emp_busted(disabled)
	if(!disabled)
		visible_message("\The [src] appears to be functional again.")

/// A busted unit shows it; a running one shows its light.
/obj/item/gps/draw(datum/look/look)
	..()
	if(emp_busted)
		look.overlay("emp")
	else if(tracking)
		look.overlay("working")

/obj/item/gps/tgui_static_data(mob/user)
	. = ..()
	var/robot_theme
	if(isrobot(loc))
		var/mob/living/silicon/robot/robot_owner = loc
		robot_theme = robot_owner.get_ui_theme()
	.["theme"] = theme || robot_theme

// Compiles all the data not available directly from the GPS
// Like the positions and directions to all other GPS units
/obj/item/gps/ui_data(datum/act/eval/A)
	var/turf/curr = get_turf(src)
	var/area/my_area = get_area(src)

	var/list/data = list(
		"currentArea" = strip_improper(my_area.name),
		"power" = tracking,
		"tag" = gps_tag,
		"localMode" = local_mode,
		"currentCoords" = "[curr.x], [curr.y], [curr.z]",
		"currentZName" = strip_improper(using_map.get_zlevel_name(curr.z)),
		"canHide" = can_hide_signal,
		"isHidden" = hide_signal
	)

	var/z_level_det = using_map.get_map_levels(curr.z, long_range)
	var/list/gps_list = list()
	for(var/obj/item/gps/current_gps in REGISTRY_MEMBERS(REGISTRY_GPS) - src)

		if(!can_track(current_gps, z_level_det))
			continue

		var/area/gps_area = get_area(current_gps)
		var/turf/gps_turf = get_turf(current_gps)

		var/is_local = (curr.z == gps_turf.z)
		var/dist = get_dist(curr, gps_turf)
		var/is_poi = istype(current_gps, /obj/item/gps/internal/poi)

		if(is_poi && is_local)
			dist = round(dist, 10)

		var/list/gps_data = list(
			"ref" = "\ref[current_gps]",
			"gpsTag" = current_gps.gps_tag,
			"areaName" = strip_improper(gps_area.get_name()),
			"zName" = strip_improper(using_map.get_zlevel_name(gps_turf.z)),
			"local" = is_local,
			"trackingColor" = LAZYACCESS(tracking_devices, "\ref[current_gps]"),
			"trackingName" = LAZYACCESS(showing_tracked_names, "\ref[current_gps]"),
		)

		if(!is_poi || is_local)
			gps_data["degrees"] = round(Get_Angle(curr, gps_turf))
			gps_data["coords"] = "[gps_turf.x], [gps_turf.y], [gps_turf.z]"
			gps_data["dist"] = dist

		UNTYPED_LIST_ADD(gps_list, gps_data)

	data["signals"] = gps_list

	return data

/obj/item/gps/proc/ui_act_power(datum/act/op/A)
	toggle_tracking()
	return OP_OK

/obj/item/gps/proc/ui_act_rename(datum/act/op/A, value)
	var/new_name = sanitize(value, 11)
	if(!new_name)
		return OP_DECLINE
	gps_tag = uppertext(new_name)
	name = "global positioning system ([gps_tag])"
	return OP_OK

/obj/item/gps/proc/ui_act_localmode(datum/act/op/A)
	local_mode = !local_mode
	return OP_OK

/obj/item/gps/proc/ui_act_hidesignal(datum/act/op/A)
	if(!can_hide_signal)
		return OP_DECLINE
	hide_signal = !hide_signal
	return OP_OK

/obj/item/gps/proc/ui_act_tracklabel(datum/act/op/A, ref)
	var/gps_ref = ref
	if(!gps_ref)
		return OP_DECLINE
	// Only a tracked device's label can be shown.
	if(LAZYACCESS(tracking_devices, gps_ref) && !LAZYACCESS(showing_tracked_names, gps_ref))
		LAZYSET(showing_tracked_names, gps_ref, TRUE)
	else
		LAZYREMOVE(showing_tracked_names, gps_ref)
	return OP_OK

/obj/item/gps/proc/ui_act_stoptrack(datum/act/op/A, ref)
	var/gps_ref = ref
	if(!gps_ref)
		return OP_DECLINE
	compass.clear_waypoint(gps_ref)
	LAZYREMOVE(tracking_devices, gps_ref)
	LAZYREMOVE(showing_tracked_names, gps_ref)
	update_compass(src, TRUE)
	return OP_OK

/obj/item/gps/proc/ui_act_starttrack(datum/act/op/A, obj/item/gps/ref)
	var/obj/item/gps/gps = ref
	if(!gps)
		return OP_DECLINE
	var/gps_ref = REF(gps)
	LAZYSET(tracking_devices, gps_ref, "#00ffff")
	LAZYSET(showing_tracked_names, gps_ref, TRUE)
	update_compass(src, TRUE)
	return OP_OK

/obj/item/gps/proc/ui_act_trackcolor(datum/act/op/A, color, obj/item/gps/ref)
	var/obj/item/gps/gps = ref
	if(!gps)
		return OP_DECLINE
	var/gps_ref = REF(gps)
	var/new_colour = sanitize_hexcolor(color)
	if(!new_colour)
		return OP_DECLINE
	LAZYSET(tracking_devices, gps_ref, new_colour)
	update_compass(src, TRUE)
	return OP_OK

/obj/item/gps/on // Defaults to off to avoid polluting the signal list with a bunch of GPSes without owners. If you need to spawn active ones, use these.
	tracking = TRUE

/obj/item/gps/command
	icon_state = "gps-com"
	gps_tag = "COM0"

/obj/item/gps/command/on
	tracking = TRUE

/obj/item/gps/security
	icon_state = "gps-sec"
	gps_tag = "SEC0"

/obj/item/gps/security/on
	tracking = TRUE

/obj/item/gps/security/hos
	icon_state = "gps-sec-hos"
	gps_tag = "HOS0"

/obj/item/gps/security/hos/on
	tracking = TRUE

/obj/item/gps/medical
	icon_state = "gps-med"
	gps_tag = "MED0"

/obj/item/gps/medical/on
	tracking = TRUE

/obj/item/gps/medical/cmo
	icon_state = "gps-med-cmo"
	gps_tag = "CMO0"

/obj/item/gps/medical/cmo/on
	tracking = TRUE

/obj/item/gps/science
	icon_state = "gps-sci"
	gps_tag = "SCI0"

/obj/item/gps/science/on
	tracking = TRUE

/obj/item/gps/science/rd
	icon_state = "gps-sci-rd"
	gps_tag = "RD0"

/obj/item/gps/science/rd/on
	tracking = TRUE

/obj/item/gps/engineering
	icon_state = "gps-eng"
	gps_tag = "ENG0"

/obj/item/gps/engineering/on
	tracking = TRUE

/obj/item/gps/engineering/atmos
	icon_state = "gps-eng-atm"
	gps_tag = "ATM0"

/obj/item/gps/engineering/atmos/on
	tracking = TRUE

/obj/item/gps/engineering/ce
	icon_state = "gps-eng-ce"
	gps_tag = "CE0"

/obj/item/gps/engineering/ce/on
	tracking = TRUE

/obj/item/gps/mining
	icon_state = "gps-mine"
	gps_tag = "MINE0"
	desc = "A positioning system helpful for rescuing trapped or injured miners, keeping one on you at all times while mining might just save your life. Alt+click to toggle power."

/obj/item/gps/mining/on
	tracking = TRUE

/obj/item/gps/explorer
	icon_state = "gps-exp"
	gps_tag = "EXP0"
	desc = "A positioning system helpful for rescuing trapped or injured explorers, keeping one on you at all times while exploring might just save your life. Alt+click to toggle power."

/obj/item/gps/explorer/on
	tracking = TRUE

/obj/item/gps/robot
	icon_state = "gps-borg"
	gps_tag = "SYNTH0"
	desc = "A synthetic internal positioning system. Used as a recovery beacon for damaged synthetic assets, or a collaboration tool for mining or exploration teams. \
	Alt+click to toggle power."
	tracking = TRUE // On by default.

/obj/item/gps/internal // Base type for immobile/internal GPS units.
	icon_state = "internal"
	gps_tag = "Eerie Signal"
	desc = "Report to a coder immediately."
	invisibility = INVISIBILITY_MAXIMUM
	tracking = TRUE // Meant to point to a location, so it needs to be on.
	anchored = TRUE

/obj/item/gps/internal/base
	gps_tag = "NT_BASE"
	desc = "A homing signal from NanoTrasen's outpost."

/obj/item/gps/internal/poi
	gps_tag = "Unidentified Signal"
	desc = "A signal that seems forboding."

/obj/item/gps/syndie
	icon_state = "gps-syndie"
	gps_tag = "NULL"
	desc = "A positioning system that has extended range and can detect other GPS device signals without revealing its own. How that works is best left a mystery. Alt+click to toggle power."
	long_range = TRUE
	hide_signal = TRUE
	can_hide_signal = TRUE
	theme = "syndicate"


/// Relation view: holder (reads null once it is gone).
/obj/item/gps/proc/holder_ref() as /mob
	return holder
