//
// Wall mounted holomap of the station
//
/obj/machinery/station_map
	name = "station holomap"
	silicon_use = NONE // Silicons can't use it yet (TODO: implement for AI).
	desc = "A virtual map of the surrounding station."
	icon = 'icons/obj/machines/stationmap.dmi'
	icon_state = "station_map"
	layer = ABOVE_WINDOW_LAYER
	maintenance_flags = MACHINE_MAINT_STANDARD
	anchored = TRUE
	density = FALSE
	use_power = USE_POWER_IDLE
	idle_power_usage = 10
	active_power_usage = 500
	circuit = /obj/item/circuitboard/station_map
	vis_flags = VIS_HIDE // They have an emissive that looks bad in openspace due to their wall-mounted nature
	flags = ON_BORDER|WALL_ITEM
	integrity_failure = 0.5

	// TODO - Port use_auto_lights from /vg - for now declare here
	var/use_auto_lights = 1
	var/light_power_on = 1
	var/light_range_on = 2
	light_color = "#64C864"

	var/image/small_station_map = null
	var/image/floor_markings = null
	var/image/panel = null

	var/original_zLevel = 1	// zLevel on which the station map was initialized.
	var/bogus = TRUE		// set to 0 when you initialize the station map on a zLevel that has its own icon formatted for use by station holomaps.
	var/datum/station_holomap/holomap_datum

DECLARE_DEFAULT_CHILD(/obj/machinery/station_map, "holomap_datum", /datum/station_holomap)

/// OM handle of the mob looking at the map (startWatching()/stopWatching()); it checks on them while set.
OM_FIELD_TYPED(/obj/machinery/station_map, tmp, watching_mob_handle, null, CHANGE_MACHINE_SETTINGS)
DECLARE_PERIODIC_WHILE(/obj/machinery/station_map, MACHINE_PIPELINE, "watching_mob_handle")

/obj/machinery/station_map/Initialize(mapload)
	. = ..()
	original_zLevel = loc.z
	SSholomaps.station_holomaps += src
	if(SSholomaps.holomaps_initialized)
		setup_holomap()

/// Phase 2: leaves the holomap index and stops watching.
/obj/machinery/station_map/lifecycle_dematerialize()
	. = ..()
	SSholomaps.station_holomaps -= src
	stopWatching()

/obj/machinery/station_map/proc/setup_holomap()
	bogus = FALSE
	var/turf/T = get_turf(src)
	original_zLevel = T.z
	if(!("[HOLOMAP_EXTRA_STATIONMAP]_[original_zLevel]" in SSholomaps.extraMiniMaps))
		bogus = TRUE
		holomap_datum.initialize_holomap_bogus()
		update_icon()
		return

	holomap_datum.initialize_holomap(T, reinit = TRUE)

	small_station_map = image(SSholomaps.extraMiniMaps["[HOLOMAP_EXTRA_STATIONMAPSMALL]_[original_zLevel]"], dir = dir)

	floor_markings = image('icons/obj/machines/stationmap.dmi', "decal_station_map")
	floor_markings.dir = src.dir

	om_after(src, 1, TYPE_PROC_REF(/atom, update_icon)) //When built from frames, need to allow time for it to set pixel_x and pixel_y

/obj/machinery/station_map/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/station_map_watch,
		/datum/interaction/machine_item/station_map_fingerprint,
	)
	..()

/// Old attack_hand: never called ..(), so ungated.
/datum/interaction/machine_hand/ungated/station_map_watch
	id = "station_map_watch"
	name = "Watch"
	effect = /obj/machinery/station_map/proc/interaction_watch

/obj/machinery/station_map/proc/interaction_watch(mob/user, obj/item/held, datum/interaction/interaction)
	if(watching_mob() && (watching_mob() != user))
		to_chat(user, span_warning("Someone else is currently watching the holomap."))
		return TRUE
	if(user.loc != loc)
		to_chat(user, span_warning("You need to stand in front of \the [src]."))
		return TRUE
	if(watching_mob())
		return TRUE
	startWatching(user)
	return TRUE

// Let people bump up against it to watch
/obj/machinery/station_map/Bumped(atom/movable/AM)
	if(!watching_mob() && isliving(AM) && AM.loc == loc)
		startWatching(AM)

/obj/machinery/station_map/Uncross(atom/movable/mover, turf/target)
	if(get_dir(mover, target) == GLOB.reverse_dir[dir])
		return FALSE
	return TRUE
/obj/machinery/station_map/proc/startWatching(mob/user)
	// Okay, does this belong on a screen thing or what?
	// One argument is that this is an "in game" object becuase its in the world.
	// But I think it actually isn't.  The map isn't holo projected into the whole room, (maybe strat one is!)
	// But for this, the on screen object just represents you leaning in and looking at it closely.
	// So it SHOULD be a screen object.
	// But it is not QUITE a hud either.  So I think it shouldn't go in /datum/hud
	// Okay? Yeah.  Lets use screen objects but manage them manually here in the item.
	// That might be a mistake... I'd rather they be managed by some central hud management system.
	// But the /vg code, while the screen obj is managed, its still adding and removing image, so this is
	// just as good.

	// EH JUST HACK IT FOR NOW SO WE CAN SEE HOW IT LOOKS! STOP OBSESSING, ITS BEEN AN HOUR NOW!

	// TODO - This part!! ~Leshana
	if(isliving(user) && anchored && operable())
		if(user.client)
			image_anchor(holomap_datum.station_map, GLOB.global_hud.holomap) // Put the image on the holomap hud
			holomap_datum.station_map.alpha = 0 // Set to transparent so we can fade in
			animate(holomap_datum.station_map, alpha = 255, time = 5, easing = LINEAR_EASING)
			flick("station_map_activate", src)
			// Wait, if wea re not modifying the holomap_obj... can't it be part of the global hud?
			user.client.screen |= GLOB.global_hud.holomap // TODO - HACK! This should be there permenently really.
			user.client.images |= holomap_datum.station_map

			set_watching_mob_handle(om_handle(user))
			dq_add_recursive_move(watching_mob())
			om_hook(watching_mob(), /datum/om/event/movable_attempted_move, src, PROC_REF(checkPosition))
			om_hook(watching_mob(), /datum/om/event/qdeleting, src, PROC_REF(on_watcher_deleted))
			set_use_power(USE_POWER_ACTIVE)

			if(bogus)
				to_chat(user, span_warning("The holomap failed to initialize. This area of space cannot be mapped."))
			else
				to_chat(user, span_notice("A hologram of the station appears before your eyes."))

// TODO - Implement for AI ~Leshana
// user.station_holomap.toggleHolomap(user, isAI(user))

/obj/machinery/station_map/machine_step()
	if((!operable()) || !anchored || !watching_mob())
		stopWatching()

/obj/machinery/station_map/proc/checkPosition()
	SHOULD_NOT_SLEEP(TRUE)
	if(!watching_mob() || (watching_mob().loc != loc) || (dir != watching_mob().dir))
		stopWatching()

/obj/machinery/station_map/proc/on_watcher_deleted(datum/source, datum/om/event/qdeleting/event)
	EVENT_HANDLER
	// watching_mob() already reads null for a watcher mid-delete: hand it over.
	if(om_handle_is(watching_mob_handle, source))
		stopWatching(source)

/// `watcher` defaults to watching_mob(); pass it for a watcher that is being deleted.
/obj/machinery/station_map/proc/stopWatching(mob/watcher = watching_mob())
	SHOULD_NOT_SLEEP(TRUE)
	if(watcher)
		if(watcher.client)
			animate(holomap_datum.station_map, alpha = 0, time = 5, easing = LINEAR_EASING)
			if(QDELETED(watcher))
				watcher.client.images -= holomap_datum.station_map // no timer on a dying mob
			else
				om_after(watcher, 5, /proc/remove_client_image, watcher, holomap_datum.station_map) //we give it time to fade out
		om_unhook(watcher, list(/datum/om/event/movable_attempted_move, /datum/om/event/qdeleting), src)
	set_watching_mob_handle(null)
	set_use_power(USE_POWER_IDLE)

/obj/machinery/station_map/power_change()
	. = ..()
	if(has_stat(NOPOWER))
		stopWatching()
	update_icon()
	// TODO - Port use_auto_lights from /vg - For now implement it manually here
	if(has_stat(NOPOWER))
		set_light(0)
	else
		set_light(light_range_on, light_power_on)

/obj/machinery/station_map/update_icon()
	if(!holomap_datum)
		return //Not yet.

	cut_overlays()
	if(has_stat(BROKEN))
		icon_state = "station_mapb"
	else if((has_stat(NOPOWER)) || !anchored)
		icon_state = "station_map0"
	else
		icon_state = "station_map"

		if(bogus)
			holomap_datum.initialize_holomap_bogus()
		else
			small_station_map = image(SSholomaps.extraMiniMaps["[HOLOMAP_EXTRA_STATIONMAPSMALL]_[original_zLevel]"], dir = src.dir)
			add_overlay(small_station_map)
			holomap_datum.initialize_holomap(get_turf(src))

	// Put the little "map" overlay down where it looks nice
	if(floor_markings)
		floor_markings.dir = src.dir
		floor_markings.pixel_x = -src.pixel_x
		floor_markings.pixel_y = -src.pixel_y
		add_overlay(floor_markings)

	if(panel_open)
		add_overlay("station_map-panel")
	else
		cut_overlay("station_map-panel")

/// Old attackby: fingerprinted, then always fell through to ..().
/datum/interaction/machine_item/station_map_fingerprint
	id = "station_map_fingerprint"
	name = "Touch"
	held_type = /obj/item
	effect = /atom/proc/interaction_fingerprint

/datum/frame/frame_types/station_map
	name = "Station Map Frame"
	frame_class = "display"
	frame_size = 3
	frame_style = "wall"
	x_offset = WORLD_ICON_SIZE
	y_offset = WORLD_ICON_SIZE
	circuit = /obj/item/circuitboard/station_map
	icon_override = 'icons/obj/machines/stationmap.dmi'

/datum/frame/frame_types/station_map/get_icon_state(state)
	return "station_map_frame_[state]"

/obj/structure/frame
	layer = ABOVE_WINDOW_LAYER

/obj/item/circuitboard/station_map
	name = T_BOARD("Station Map")
	board_type = new /datum/frame/frame_types/station_map
	build_path = /obj/machinery/station_map
	req_components = list()

/datum/holomap_marker
	var/x
	var/y
	var/z
	var/offset_x = -8
	var/offset_y = -8
	var/filter
	var/id // used for icon_state of the marker on maps
	var/icon = 'icons/holomap_markers.dmi'
	var/color //used by path rune markers

DECLARE_REF(/obj/machinery/station_map, "small_station_map", OWNED, null)
DECLARE_REF(/obj/machinery/station_map, "floor_markings", OWNED, null)
DECLARE_REF(/obj/machinery/station_map, "panel", OWNED, null)
DECLARE_REF(/obj/machinery/station_map, "holomap_datum", OWNED, null)

/// LC-refs: the watching_mob this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/machinery/station_map/proc/watching_mob() as /mob
	return om_resolve(watching_mob_handle)
