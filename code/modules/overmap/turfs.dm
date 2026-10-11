//Dimension of overmap (squares 4 lyfe)
GLOBAL_LIST_EMPTY(map_sectors)

/area/overmap
	name = "System Map"
	icon_state = "start"
	requires_power = 0
	base_turf = /turf/unsimulated/map

/turf/unsimulated/map
	icon = 'icons/turf/space.dmi'
	icon_state = "map"
	alpha = 200
	vis_flags = VIS_INHERIT_ID // disable VIS_INHERIT_PLANE
	init_from_table = FALSE

/turf/unsimulated/map/edge
	opacity = 1
	density = TRUE
	alpha = 255
	var/map_is_to_my
	var/tmp/turf/unsimulated/map/edge/wrap_buddy

CAPABILITIES(/turf/unsimulated/map/edge)
	after_init(0, then(PROC_REF(find_wrap)))

/// Finds the map it wraps to, once the overmap exists.
/turf/unsimulated/map/edge/proc/find_wrap(datum/act/timer/A)
	//This could be done by using the using_map.overmap_size much faster, HOWEVER, doing it programatically to 'find'
	//  the edges this way allows for 'sub overmaps' elsewhere and whatnot.
	for(var/side in GLOB.alldirs) //The order of this list is relevant: It should definitely break on finding a GLOB.cardinal FIRST.
		var/turf/T = get_step(src, side)
		if(T?.type == /turf/unsimulated/map) //Not a wall, not something else, EXACTLY a flat map turf.
			map_is_to_my = side
			break

	if(map_is_to_my)
		var/turf/T = get_step(src, map_is_to_my) //Should be a normal map turf
		while(istype(T, /turf/unsimulated/map))
			T = get_step(T, map_is_to_my) //Could be a wall if the map is only 1 turf big
			if(istype(T, /turf/unsimulated/map/edge))
				rel_set(src, nameof(wrap_buddy), T)
				break

/turf/unsimulated/map/edge/Bumped(atom/movable/AM)
	if(wrap_buddy()?.map_is_to_my)
		AM.forceMove(get_step(wrap_buddy(), wrap_buddy().map_is_to_my))
	else
		. = ..()

// ALLOW(init/INSTANCE_STATE): names and numbers itself from its overmap coordinates
/turf/unsimulated/map/Initialize(mapload)
	name = "[x]-[y]"
	var/list/numbers = list()
	coord_marks = list()

	if(x == 1 || x == using_map.overmap_size)
		numbers += list("[round(y/10)]","[round(y%10)]")
		if(y == 1 || y == using_map.overmap_size)
			numbers += "-"
	if(y == 1 || y == using_map.overmap_size)
		numbers += list("[round(x/10)]","[round(x%10)]")

	for(var/i = 1 to numbers.len)
		var/px = 5*i - 2
		var/py = world.icon_size/2 - 3
		if(y == 1)
			py = 3
			px = 5*i + 4
		if(y == using_map.overmap_size)
			py = world.icon_size - 9
			px = 5*i + 4
		if(x == 1)
			px = 5*i - 2
		if(x == using_map.overmap_size)
			px = 5*i + 2
		coord_marks += list(list(numbers[i], px, py))
	. = ..()
	make_z_transparent()

/turf/unsimulated/map/Entered(atom/movable/O, atom/oldloc)
	..()
	if(istype(O, /obj/effect/overmap/visitable/ship))
		GLOB.overmap_event_handler.on_turf_entered(src, O, oldloc)

/turf/unsimulated/map/Exited(atom/movable/O, atom/newloc)
	..()
	if(istype(O, /obj/effect/overmap/visitable/ship))
		GLOB.overmap_event_handler.on_turf_exited(src, O, newloc)

/// Accessor for the wrap_buddy var.
/turf/unsimulated/map/edge/proc/wrap_buddy() as /turf/unsimulated/map/edge
	return wrap_buddy

/// The coordinate digits an edge tile shows: list(list(state, pixel_x, pixel_y), ...), worked out at init from where it lies.
/turf/unsimulated/map/var/list/coord_marks

/// An edge tile of the map shows its coordinates.
/turf/unsimulated/map/draw(datum/look/look)
	..()
	for(var/list/mark in coord_marks)
		look.overlay(look_overlay_image('icons/effects/numbers.dmi', mark[1], pixel_x = mark[2], pixel_y = mark[3]))
