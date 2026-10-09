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

	var/image/panel = null

	var/original_zLevel = 1	// zLevel on which the station map was initialized.
	var/offsets_settled_flag = FALSE
	var/bogus = TRUE		// set to 0 when you initialize the station map on a zLevel that has its own icon formatted for use by station holomaps.
	var/datum/station_holomap/holomap_datum

TRACKED(/obj/machinery/station_map, bogus)
TRACKED(/obj/machinery/station_map, offsets_settled_flag)

CAPABILITIES(/obj/machinery/station_map)
	ref_one(nameof(watching_mob))
	started_work(step = PROC_REF(work_step), starts = TRUE, when = nameof(watching_mob), wakes_on = list(nameof(watching_mob)))
	on_notice(/datum/notice/bumped, then(PROC_REF(bumped_into)))
	owns_one(nameof(holomap_datum), starts = /datum/station_holomap)
	op("watch", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 1), label("Watch"), needs(req_is(nameof(watching_mob), FALSE, because = MSG(station_map/watched)), req_on_holder_turf(because = MSG(station_map/stand_in_front))), then(PROC_REF(interaction_watch)))
	op("fingerprint", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Touch"), then(TYPE_PROC_REF(/atom, op_fingerprint)))

/// The mob looking at the map (startWatching()/stopWatching()); it checks on them while set.
/obj/machinery/station_map/var/mob/watching_mob
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
	var/turf/T = get_turf(src)
	original_zLevel = T.z
	if(!("[HOLOMAP_EXTRA_STATIONMAP]_[original_zLevel]" in SSholomaps.extraMiniMaps))
		set_bogus(TRUE)
		holomap_datum.initialize_holomap_bogus()
		return

	holomap_datum.initialize_holomap(T, reinit = TRUE)
	set_bogus(FALSE)

	after(src, 0.1 SECONDS, PROC_REF(offsets_settled)) //When built from frames, need to allow time for it to set pixel_x and pixel_y

/// The pixel offset of a machine built from a frame is set a moment after init: the floor markings (which cancel it) draw once it has settled.
/obj/machinery/station_map/proc/offsets_settled()
	set_offsets_settled_flag(TRUE)

MSG_DEF_SELF(station_map/watched, "someone else is currently watching the holomap")
MSG_DEF_SELF(station_map/stand_in_front, "you need to stand in front of %T%")


/obj/machinery/station_map/proc/interaction_watch(datum/act/op/A)
	var/mob/user = A.actor
	if(watching_mob())
		return OP_OK
	startWatching(user)
	return OP_OK

// Let people bump up against it to watch
/// Something walked into it (the bump action's notice).
/obj/machinery/station_map/proc/bumped_into(datum/act/A)
	var/datum/notice/bumped/N = A
	var/atom/movable/AM = N.bumper
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

			rel_set(src, nameof(watching_mob), user)
			dq_add_recursive_move(watching_mob())
			observe(watching_mob(), /datum/notice/movable_attempted_move, src, then(PROC_REF(checkPosition)))
			observe(watching_mob(), /datum/notice/qdeleting, src, then(PROC_REF(on_watcher_deleted)))
			set_use_power(USE_POWER_ACTIVE)

			if(bogus)
				to_chat(user, span_warning("The holomap failed to initialize. This area of space cannot be mapped."))
			else
				to_chat(user, span_notice("A hologram of the station appears before your eyes."))

// TODO - Implement for AI ~Leshana
// user.station_holomap.toggleHolomap(user, isAI(user))

/obj/machinery/station_map/proc/work_step(datum/act/timer/A)
	if((!operable()) || !anchored || !watching_mob())
		stopWatching()

/obj/machinery/station_map/proc/checkPosition(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	if(!watching_mob() || (watching_mob().loc != loc) || (dir != watching_mob().dir))
		stopWatching()

/obj/machinery/station_map/proc/on_watcher_deleted(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/source = A.target
	// watching_mob() already reads null for a watcher mid-delete: hand it over.
	if((watching_mob == source))
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
				after(watcher, 0.5 SECONDS, GLOBAL_PROC_REF(remove_client_image), with = list(watcher, holomap_datum.station_map)) //we give it time to fade out
		unobserve(watcher, /datum/notice/movable_attempted_move, src)
		unobserve(watcher, /datum/notice/qdeleting, src)
	rel_clear(src, nameof(watching_mob))
	set_use_power(USE_POWER_IDLE)

/obj/machinery/station_map/power_change()
	. = ..()
	if(power_lost())
		stopWatching()
	// TODO - Port use_auto_lights from /vg - For now implement it manually here
	if(power_lost())
		set_light(0)
	else
		set_light(light_range_on, light_power_on)

/obj/machinery/station_map/draw(datum/look/look)
	..()
	if(!holomap_datum)
		return

	if(broken_now())
		look.state("station_mapb")
	else if((power_lost()) || !anchored)
		look.state("station_map0")
	else
		look.state("station_map")
		if(!bogus)
			look.overlay(look_overlay_image(SSholomaps.extraMiniMaps["[HOLOMAP_EXTRA_STATIONMAPSMALL]_[original_zLevel]"], null, dir = dir))

	// Put the little "map" overlay down where it looks nice
	if(!bogus && offsets_settled_flag)
		look.overlay(look_overlay_image('icons/obj/machines/stationmap.dmi', "decal_station_map", pixel_x = -pixel_x, pixel_y = -pixel_y, dir = dir))

	look.overlay("station_map-panel", when = panel_open)

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

/// The watching_mob this refers to (a relation view: null once that is deleted).
/obj/machinery/station_map/proc/watching_mob() as /mob
	return watching_mob
