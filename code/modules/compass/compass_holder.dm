/obj/compass_holder
	name = null
	icon = null
	icon_state = null
	screen_loc = "CENTER,CENTER"

	var/show_heading = FALSE
	var/numeric_directions = FALSE

	var/image/compass_heading_marker
	var/list/compass_static_labels
	var/list/compass_waypoints
	var/list/compass_waypoint_markers

	var/static/list/angle_step_to_dir = list(
		"N",
		"NE",
		"E",
		"SE",
		"S",
		"SW",
		"W",
		"NW",
		"N"
	)
TRACKED(/obj/compass_holder, compass_heading_marker)
TRACKED(/obj/compass_holder, compass_waypoint_markers)

CAPABILITIES(/obj/compass_holder)
	owns_many(nameof(compass_waypoints))

/obj/compass_holder/Initialize(mapload, ...)
	. = ..()
	if(show_heading)
		set_compass_heading_marker(new /image/compass_marker)
		compass_heading_marker.maptext = "<center>" + span_normal(span_cyan(span_bold("△"))) + "</center>"
		compass_heading_marker.filters = filter(type="drop_shadow", color = "#00ffffaa", size = 2, offset = 1,x = 0, y = 0)
		compass_heading_marker.layer = LAYER_HUD_UNDER
		compass_heading_marker.plane = PLANE_PLAYER_HUD

	for(var/i in 0 to (360/(COMPASS_PERIOD))-1)
		var/image/I = new /image/compass_marker
		image_anchor(I, src)
		var/str
		var/str_col
		if(i % COMPASS_INTERVAL == 0)
			var/angle = (i * COMPASS_PERIOD)
			if(numeric_directions)
				str = "[angle]"
			else
				str = angle_step_to_dir[CLAMP(round(angle/45)+1, 1, length(angle_step_to_dir))]
			str_col = "#ffffffaa"
		else
			str = "〡"
			str_col = "#aaaaaa88"
		I.maptext = "<center><font color = '[str_col]' size = '1px'>" + span_bold("[str]") + "</font></center>"
		var/matrix/M = matrix()
		M.Translate(0, COMPASS_LABEL_OFFSET)
		M.Turn(COMPASS_PERIOD * i)
		I.transform = M
		I.filters = filter(type="drop_shadow", color = "#77777777", size = 2, offset = 1,x = 0, y = 0)
		I.layer = LAYER_HUD_UNDER
		I.plane = PLANE_PLAYER_HUD
		LAZYADD(compass_static_labels, I)

	rebuild_overlay_lists()


/obj/compass_holder/proc/get_heading()
	var/atom/A = loc?.loc // is there a get_holder_recursive() equivalent on Polaris?
	if(istype(A))
		. = dir2angle(A.dir)
	else
		. = 0

/obj/compass_holder/draw(datum/look/look)
	..()
	var/set_overlays = (compass_static_labels | compass_waypoint_markers)
	if(show_heading)
		set_overlays |= compass_heading_marker
	look.overlay(set_overlays)// ???

/obj/compass_holder/proc/clear_waypoint(id)
	rel_add(src, nameof(compass_waypoints), null, id) // removes and disposes of it
	rebuild_overlay_lists()

/obj/compass_holder/proc/set_waypoint(id, label, heading_x, heading_y, heading_z, label_color)
	var/datum/compass_waypoint/wp = LAZYACCESS(compass_waypoints, id)
	if(!wp)
		wp = new /datum/compass_waypoint()
	wp.set_values(label, heading_x, heading_y, heading_z, label_color)
	rel_add(src, nameof(compass_waypoints), wp, id)
	rebuild_overlay_lists()

/// Turns the heading marker to the holder's facing. The marker is a fresh copy each time, so the tracked setter sees a new value and the
/// look (whose key names the marker's transform and maptext) redraws.
/obj/compass_holder/proc/recalculate_heading()
	if(show_heading)
		var/matrix/M = matrix()
		M.Translate(0, round(COMPASS_LABEL_OFFSET - 35))
		M.Turn(get_heading())
		var/image/turned = image(compass_heading_marker)
		turned.transform = M
		set_compass_heading_marker(turned)

/obj/compass_holder/proc/show_waypoint(id)
	var/datum/compass_waypoint/wp = compass_waypoints[id]
	wp.hidden = FALSE

/obj/compass_holder/proc/hide_waypoint(id)
	var/datum/compass_waypoint/wp = compass_waypoints[id]
	wp.hidden = TRUE

/obj/compass_holder/proc/hide_waypoints(rebuild_overlays = FALSE)
	for(var/id in compass_waypoints)
		hide_waypoint(id)
	if(rebuild_overlays)
		rebuild_overlay_lists()

/// Recomputes where every shown waypoint points and the heading, and publishes the new marker list through its tracked setter (a fresh list each
/// time, so the draw runs); the look key names each marker's transform and maptext, so only a marker that changed is applied again.
/obj/compass_holder/proc/rebuild_overlay_lists()
	var/list/markers
	var/turf/T = get_turf(src)
	if(istype(T))
		for(var/id in compass_waypoints)
			var/datum/compass_waypoint/wp = compass_waypoints[id]
			if(!wp.hidden)
				wp.recalculate_heading(T.x, T.y)
				LAZYADD(markers, wp.compass_overlay)
	set_compass_waypoint_markers(markers)
	recalculate_heading()

