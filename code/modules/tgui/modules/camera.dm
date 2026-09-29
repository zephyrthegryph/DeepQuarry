#define DEFAULT_MAP_SIZE 15

/atom/movable/screen/map_view_tg/camera
	var/atom/movable/screen/background/cam_background
	var/atom/movable/screen/background/cam_foreground
	var/atom/movable/screen/skybox/local_skybox


/atom/movable/screen/map_view_tg/camera/generate_view(map_key)
	. = ..()
	own_set(src, "cam_background", new /atom/movable/screen/background())
	cam_background.del_on_map_removal = FALSE
	cam_background.assigned_map = assigned_map

	own_set(src, "local_skybox", new /atom/movable/screen/skybox())
	local_skybox.del_on_map_removal = FALSE
	local_skybox.assigned_map = assigned_map

	// FG
	own_set(src, "cam_foreground", new /atom/movable/screen/background)
	cam_foreground.del_on_map_removal = FALSE
	cam_foreground.assigned_map = assigned_map

	var/mutable_appearance/scanlines = mutable_appearance('icons/effects/static.dmi', "scanlines")
	scanlines.alpha = 50
	scanlines.layer = FULLSCREEN_LAYER

	var/mutable_appearance/noise = mutable_appearance('icons/effects/static.dmi', "1 light")
	noise.layer = FULLSCREEN_LAYER

	cam_foreground.plane = PLANE_FULLSCREEN
	cam_foreground.add_overlay(scanlines)
	cam_foreground.add_overlay(noise)

/atom/movable/screen/map_view_tg/camera/display_to_client(client/show_to)
	show_to.register_map_obj(cam_background)
	show_to.register_map_obj(cam_foreground)
	show_to.register_map_obj(local_skybox)
	. = ..()

/atom/movable/screen/map_view_tg/camera/proc/show_camera(list/visible_turfs, turf/newturf, size_x, size_y)
	vis_contents = visible_turfs
	cam_background.icon_state = "clear"
	cam_background.fill_rect(1, 1, size_x, size_y)

	cam_foreground.fill_rect(1, 1, size_x, size_y)

	local_skybox.cut_overlays()
	local_skybox.add_overlay(skybox_service().get_skybox(get_z(newturf)))
	local_skybox.scale_to_view(size_x)
	local_skybox.set_position("CENTER", "CENTER", (world.maxx>>1) - newturf.x, (world.maxy>>1) - newturf.y)

/atom/movable/screen/map_view_tg/camera/proc/show_camera_static()
	vis_contents.Cut()
	cam_background.icon_state = "scanline2"
	cam_background.fill_rect(1, 1, DEFAULT_MAP_SIZE, DEFAULT_MAP_SIZE)
	local_skybox.cut_overlays()

/datum/tgui_module/camera
	name = "Security Cameras"
	tgui_id = "CameraConsole"

	var/access_based = FALSE
	var/list/network = list() // ALLOW(instance_list): d: camera console network filter; many call sites
	var/list/additional_networks

	var/tmp/obj/machinery/camera/active_camera
	var/list/concurrent_users

	// Stuff needed to render the map
	var/map_name

	var/atom/movable/screen/map_view_tg/camera/cam_screen_tg

	// Stuff for moving cameras
	var/tmp/turf/last_camera_turf

/datum/tgui_module/camera/New(host, list/network_computer)
	. = ..()
	if(!LAZYLEN(network_computer))
		access_based = TRUE
	else
		network = network_computer
	map_name = "camera_console_[REF(src)]_map"

	// Initialize map objects
	own_set(src, "cam_screen_tg", new /atom/movable/screen/map_view_tg/camera)
	cam_screen_tg.generate_view(map_name)


/datum/tgui_module/camera/ui_prepare(mob/user, datum/tgui/ui)
	if(!user.client)
		return FALSE
	// Update the camera, showing static if necessary and updating data if the location has moved.
	update_active_camera_screen()
	return TRUE

/datum/tgui_module/camera/ui_opening(mob/user, datum/tgui/ui)
	..()
	var/user_ref = REF(user)
	var/is_living = isliving(user)
	// Ghosts shouldn't count towards concurrent users, which produces
	// an audible terminal_on click.
	if(is_living)
		LAZYADD(concurrent_users, user_ref)
	// Turn on the console
	if(length(concurrent_users) == 1 && is_living)
		play_sfx(tgui_host(), SFX_MACHINES_TERMINAL_ON, 0.5, vary = FALSE)

/datum/tgui_module/camera/ui_opened(mob/user, datum/tgui/ui)
	..()
	// Register map objects
	cam_screen_tg.display_to(user, ui.window())

UI_DATA_REPLACE(/datum/tgui_module/camera, "merge:ui_data_datum_tgui_module_camera{activeCamera:list}")

/// The computed part of /datum/tgui_module/camera's window data (declared on its UI_DATA row).
/datum/tgui_module/camera/proc/ui_data_datum_tgui_module_camera(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["activeCamera"] = null
	if(active_camera())
		data["activeCamera"] = list(
			name = active_camera().c_tag,
			status = active_camera().status,
		)
	return data

/datum/tgui_module/camera/tgui_static_data(mob/user)
	var/list/data = ..()
	data["mapRef"] = map_name
	var/list/cameras = get_available_cameras(user)
	data["cameras"] = list()
	data["allNetworks"] = list()
	for(var/i in cameras)
		var/obj/machinery/camera/C = cameras[i]
		data["cameras"] += list(list(
			name = C.c_tag,
			networks = C.network
		))
		data["allNetworks"] |= C.network
	return data

/datum/tgui_module/camera/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(action && !issilicon(ui.user))
		play_sfx(tgui_host(), SFX_TERMINAL_TYPE)
	return TRUE

UI_ACT(/datum/tgui_module/camera, "switch_camera", ui_act_switch_camera, UI_ARG_TEXT("name"))
UI_ACT_PROC(/datum/tgui_module/camera, ui_act_switch_camera)
	var/c_tag = params["name"]
	var/list/cameras = get_available_cameras(ui.user)
	var/obj/machinery/camera/C = cameras["[ckey(c_tag)]"]
	if(active_camera())
		om_unhook(active_camera(), /datum/om/event/movable_attempted_move, src)
	if(C)
		rel_set(src, "active_camera", C)
		dq_add_recursive_move(active_camera())
		om_hook(active_camera(), /datum/om/event/movable_attempted_move, src, PROC_REF(on_active_camera_moved_event))
	playsound(tgui_host(), get_sfx(SFX_TERMINAL_TYPE), 25, FALSE)
	update_active_camera_screen()
	return TRUE

UI_ACT(/datum/tgui_module/camera, "pan", ui_act_pan, UI_ARG_NUM("dir"))
UI_ACT_PROC(/datum/tgui_module/camera, ui_act_pan)
	var/dir = params["dir"]
	var/turf/T = get_turf(active_camera())
	for(var/i in 1 to 10)
		T = get_step(T, dir)
	if(T)
		var/obj/machinery/camera/target
		var/best_dist = INFINITY

		var/list/possible_cameras = get_available_cameras(ui.user)
		for(var/obj/machinery/camera/C in get_area(T))
			if(!possible_cameras["[ckey(C.c_tag)]"])
				continue
			var/dist = get_dist(C, T)
			if(dist < best_dist)
				best_dist = dist
				target = C

		if(target)
			if(active_camera())
				om_unhook(active_camera(), /datum/om/event/movable_attempted_move, src)
			rel_set(src, "active_camera", target)
			dq_add_recursive_move(active_camera())
			om_hook(active_camera(), /datum/om/event/movable_attempted_move, src, PROC_REF(on_active_camera_moved_event))
			playsound(tgui_host(), get_sfx(SFX_TERMINAL_TYPE), 25, FALSE)
			update_active_camera_screen()
			. = TRUE

/// Event wrapper: the watched camera (or something carrying it) moved.
/datum/tgui_module/camera/proc/on_active_camera_moved_event(datum/source, datum/om/event/movable_attempted_move/event)
	EVENT_HANDLER
	update_active_camera_screen()

/datum/tgui_module/camera/proc/update_active_camera_screen()
	if(!active_camera()?.can_use())
		cam_screen_tg.show_camera_static()
		return TRUE

	var/turf/newturf = get_turf(active_camera())
	var/area/B = newturf?.loc // No cam tracking in dorms!
	// Show static if can't use the camera
	if(B?.flag_check(AREA_BLOCK_TRACKING))
		cam_screen_tg.show_camera_static()
		return TRUE

	// If we're not forcing an update for some reason and the cameras are in the same location,
	// we don't need to update anything.
	// Most security cameras will end here as they're not moving.
	if(newturf == last_camera_turf())
		return

	// Cameras that get here are moving, and are likely attached to some moving atom such as cyborgs.
	rel_set(src, "last_camera_turf", newturf)

	var/list/visible_turfs = list()
	for(var/turf/T in (active_camera().isXRay() \
			? range(active_camera().view_range, newturf) \
			: view(active_camera().view_range, newturf)))
		visible_turfs += T

	var/list/bbox = get_bbox_of_atoms(visible_turfs)
	var/size_x = bbox[3] - bbox[1] + 1
	var/size_y = bbox[4] - bbox[2] + 1

	cam_screen_tg.show_camera(visible_turfs, newturf, size_x, size_y)

// Returns the list of cameras accessible from this computer
// This proc operates in two distinct ways depending on the context in which the module is created.
// It can either return a list of cameras sharing the same the internal `network` variable, or
// It can scan all station networks and determine what cameras to show based on the access of the user.
/datum/tgui_module/camera/proc/get_available_cameras(mob/user)
	var/list/all_networks = list()
	// Access Based
	if(access_based)
		for(var/network in using_map.station_networks)
			if(can_ACCESS_NETWORK(user, get_camera_access(network), 1))
				all_networks.Add(network)
		for(var/network in using_map.secondary_networks)
			if(can_ACCESS_NETWORK(user, get_camera_access(network), 0))
				all_networks.Add(network)
	// Network Based
	else
		all_networks = network.Copy()

	if(additional_networks)
		if(length(additional_networks)) all_networks += additional_networks

	var/list/D = list()
	for(var/obj/machinery/camera/C in REGISTRY_MEMBERS(REGISTRY_CAMERAS))
		if(!C.network)
			stack_trace("Camera in a cameranet has no camera network")
			continue
		if(!(islist(C.network)))
			stack_trace("Camera in a cameranet has a non-list camera network")
			continue
		var/list/tempnetwork = C.network & all_networks
		if(tempnetwork.len)
			D["[ckey(C.c_tag)]"] = C
	return D

/datum/tgui_module/camera/proc/can_ACCESS_NETWORK(mob/user, network_access, station_network = 0)
	// No access passed, or 0 which is considered no access requirement. Allow it.
	if(!network_access)
		return 1

	if(station_network)
		return check_access(user, network_access) || check_access(user, ACCESS_SECURITY) || check_access(user, ACCESS_HEADS)
	else
		return check_access(user, network_access)

/datum/tgui_module/camera/tgui_close(mob/user)
	. = ..()
	var/user_ref = REF(user)
	var/is_living = isliving(user)
	// living creature or not, we remove you anyway.
	LAZYREMOVE(concurrent_users, user_ref)
	// Unregister map objects
	cam_screen_tg?.hide_from(user)
	// Turn off the console
	if(length(concurrent_users) == 0 && is_living)
		if(active_camera())
			om_unhook(active_camera(), /datum/om/event/movable_attempted_move, src)
		rel_clear(src, "active_camera")
		rel_clear(src, "last_camera_turf")
		play_sfx(tgui_host(), SFX_MACHINES_TERMINAL_OFF, 0.5, vary = FALSE)

// NTOS Version
// Please note, this isn't a very good replacement for converting modular computers 100% to TGUI
// If/when that is done, just move all the PC_ specific data and stuff to the modular computers themselves
// instead of copying this approach here.
/datum/tgui_module/camera/ntos
	ntos = TRUE

// ERT Version provides some additional networks.
/datum/tgui_module/camera/ntos/ert
	additional_networks = list(NETWORK_ERT, NETWORK_CRESCENT)

// Hacked version also provides some additional networks,
// but we want it to show *all* the networks 24/7, so we convert it into a non-access-based UI.
/datum/tgui_module/camera/ntos/hacked
	additional_networks = list(NETWORK_MERCENARY, NETWORK_ERT, NETWORK_CRESCENT)

/datum/tgui_module/camera/ntos/hacked/New(host)
	. = ..(host, using_map.station_networks.Copy())

/datum/tgui_module/camera/bigscreen

DECLARE_UI_STATE(/datum/tgui_module/camera/bigscreen, GLOB.tgui_physical_state_bigscreen)

/datum/tgui_module/camera/virtual

DECLARE_UI_STATE(/datum/tgui_module/camera/virtual, GLOB.tgui_camera_view)

#undef DEFAULT_MAP_SIZE

/// The active_camera this refers to (a relation view: null once that is deleted).
/datum/tgui_module/camera/proc/active_camera() as /obj/machinery/camera
	return active_camera

/// The last_camera_turf this refers to (a relation view: null once that is deleted).
/datum/tgui_module/camera/proc/last_camera_turf() as /turf
	return last_camera_turf
