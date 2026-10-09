// Map object.
/obj/turbolift_map_holder
	name = "turbolift map placeholder"
	icon = 'icons/obj/turbolift_preview_3x3.dmi'
	dir = SOUTH			// Direction of the holder determines the placement of the lift control panel and doors.
	var/depth = 1		// Number of floors to generate, including the initial floor.
	var/lift_size_x = 2 // Number of turfs on each axis to generate in addition to the first
	var/lift_size_y = 2 // ie. a 3x3 lift would have a value of 2 in each of these variables.

	// Various turf and door types used when generating the turbolift floors.
	var/wall_type = /turf/simulated/wall/elevator
	var/floor_type = /turf/simulated/floor/tiled/dark
	var/door_type =  /obj/machinery/door/airlock/lift
	var/firedoor_type = /obj/machinery/door/firedoor/glass //for adding a firedoor to the exterior door

	var/list/areas_to_use

// Resolved at map time: the lift is built once the load is in place, and the holder never lives.
CAPABILITIES(/obj/turbolift_map_holder)
	map_resolver(
		GLOBAL_PROC_REF(resolve_turbolift_holder),
		vars = list("depth", "door_type", "firedoor_type", "floor_type", "lift_size_x", "lift_size_y", "wall_type", "areas_to_use"))

/// The map resolver of turbolift holders. The per-type area list is a list var, which only an
/// instance carries: placed by the map reader (no instance yet) the holder is made and resolved
/// when it initializes.
/proc/resolve_turbolift_holder(atom/loc, path, list/varedits)
	if(!varedits || !islist(varedits["areas_to_use"]))
		return FALSE
	map_resolve_later(GLOBAL_PROC_REF(turbolift_build), get_turf(loc), path, varedits)
	return TRUE

/// Builds the lift whose holder of type `path` sat on `origin` (bottom left of the shaft).
/proc/turbolift_build(turf/origin, path, list/varedits)
	if(!origin)
		return
	var/obj/turbolift_map_holder/P = path
	var/name = MAP_VAR(P, varedits, name)
	var/depth = MAP_VAR(P, varedits, depth)
	var/lift_size_x = MAP_VAR(P, varedits, lift_size_x)
	var/lift_size_y = MAP_VAR(P, varedits, lift_size_y)
	var/wall_type = MAP_VAR(P, varedits, wall_type)
	var/floor_type = MAP_VAR(P, varedits, floor_type)
	var/door_type = MAP_VAR(P, varedits, door_type)
	var/firedoor_type = MAP_VAR(P, varedits, firedoor_type)
	var/list/areas_to_use = varedits["areas_to_use"]

	// Create our system controller.
	var/datum/turbolift/lift = new()

	var/ux = origin.x
	var/uy = origin.y
	var/uz = origin.z
	var/udir = MAP_VAR(P, varedits, dir)

	// These modifiers are used in relation to the origin
	// to place the system control panels and doors.
	var/make_walls = isnull(wall_type) ? FALSE : TRUE // addition: Wall-less elevator
	var/int_panel_x
	var/int_panel_y
	var/ext_panel_x
	var/ext_panel_y
	var/door_x1
	var/door_y1
	var/door_x2
	var/door_y2
	var/light_x1
	var/light_x2
	var/light_y1
	var/light_y2

	var/az = 1
	var/ex = (ux+lift_size_x)
	var/ey = (uy+lift_size_y)
	var/ez = (uz+(depth-1))

	switch(udir)

		if(NORTH)

			int_panel_x = ux + FLOOR(lift_size_x/2, 1)
			int_panel_y = uy + (make_walls ? 1 : 0) // Wall-less elevator
			ext_panel_x = ux
			ext_panel_y = ey + 2

			door_x1 = ux + 1
			door_y1 = ey + (make_walls ? 0 : 1) // Wall-less elevator
			door_x2 = ex - 1
			door_y2 = ey + 1

			light_x1 = ux + (make_walls ? 1 : 0) // Wall-less elevator
			light_y1 = uy + (make_walls ? 2 : 1) // Wall-less elevator //CHOMPFixy
			light_x2 = ex - (make_walls ? 1 : 0) // Wall-less elevator //CHOMPFixy
			light_y2 = uy + (make_walls ? 2 : 1) // Wall-less elevator //CHOMPFixy

		if(SOUTH)

			int_panel_x = ux + FLOOR(lift_size_x/2, 1)
			int_panel_y = ey - (make_walls ? 1 : 0) // Wall-less elevator
			ext_panel_x = ex
			ext_panel_y = uy - 2

			door_x1 = ux + 1
			door_y1 = uy - 1
			door_x2 = ex - 1
			door_y2 = uy - (make_walls ? 0 : 1) // Wall-less elevator

			light_x1 = ux + (make_walls ? 1 : 0) // Wall-less elevator
			light_y1 = uy + (make_walls ? 2 : 1) // Wall-less elevator
			light_x2 = ex - (make_walls ? 1 : 0) // Wall-less elevator //CHOMPFixy
			light_y2 = uy + (make_walls ? 2 : 1) // Wall-less elevator //CHOMPFixy

		if(EAST)

			int_panel_x = ux + (make_walls ? 1 : 0) // Wall-less elevator
			int_panel_y = uy + FLOOR(lift_size_y/2, 1)
			ext_panel_x = ex + 2
			ext_panel_y = ey

			door_x1 = ex + (make_walls ? 0 : 1) // Wall-less elevator
			door_y1 = uy + 1
			door_x2 = ex + 1
			door_y2 = ey - 1

			light_x1 = ux + (make_walls ? 2 : 1) // Wall-less elevator //CHOMPFixy
			light_y1 = uy + (make_walls ? 1 : 0) // Wall-less elevator
			light_x2 = ux + (make_walls ? 2 : 1) // Wall-less elevator //CHOMPFixy
			light_y2 = ey - (make_walls ? 1 : 0) // Wall-less elevator //CHOMPFixy

		if(WEST)

			int_panel_x = ex - (make_walls ? 1 : 0) // Wall-less elevator
			int_panel_y = uy + FLOOR(lift_size_y/2, 1)
			ext_panel_x = ux - 2
			ext_panel_y = uy

			door_x1 = ux - 1
			door_y1 = uy + 1
			door_x2 = ux - (make_walls ? 0 : 1) // Wall-less elevator
			door_y2 = ey - 1

			light_x1 = ex - (make_walls ? 2 : 1) // Wall-less elevator //CHOMPFixy
			light_y1 = uy + (make_walls ? 1 : 0) // Wall-less elevator
			light_x2 = ex - (make_walls ? 2 : 1) // Wall-less elevator //CHOMPFixy
			light_y2 = ey - (make_walls ? 1 : 0) // Wall-less elevator //CHOMPFixy

	// Generate each floor and store it in the controller datum.
	for(var/cz = uz;cz<=ez;cz++)

		var/datum/turbolift_floor/cfloor = new()
		rel_add(lift, nameof(lift.floors), cfloor)

		var/list/floor_turfs = list()
		// Update the appropriate turfs.
		for(var/tx = ux to ex)
			for(var/ty = uy to ey)

				var/turf/checking = locate(tx,ty,cz)

				if(!istype(checking))
					log_mapping("[name] cannot find a component turf at [tx],[ty] on floor [cz]. Aborting.")
					return

				// Update path appropriately if needed.
				var/swap_to = /turf/simulated/open
				if(cz == uz)																	   // Elevator.
					if(wall_type && (tx == ux || ty == uy || tx == ex || ty == ey) && !(tx >= door_x1 && tx <= door_x2 && ty >= door_y1 && ty <= door_y2)) // Wall-less elevator
						swap_to = wall_type
					else
						swap_to = floor_type

				if(checking.type != swap_to)
					checking.ChangeTurf(swap_to)
					// Let's make absolutely sure that we have the right turf.
					checking = locate(tx,ty,cz)

				// Clear out contents.
				for(var/atom/movable/thing in turf_contents_of_type(checking, /atom/movable))
					if(thing.simulated)
						spent(thing)

				if(tx >= ux && tx <= ex && ty >= uy && ty <= ey)
					floor_turfs += checking

		// Place exterior doors.
		for(var/tx = door_x1 to door_x2)
			for(var/ty = door_y1 to door_y2)
				var/turf/checking = locate(tx,ty,cz)
				var/internal = 1
				if(!(checking in floor_turfs))
					internal = 0
					if(checking.type != floor_type)
						checking.ChangeTurf(floor_type)
						checking = locate(tx,ty,cz)
					for(var/atom/movable/thing in turf_contents_of_type(checking, /atom/movable))
						if(thing.simulated)
							spent(thing)
				if(checking.type == floor_type) // Don't build over empty space on lower levels.
					var/obj/machinery/door/airlock/lift/newdoor = new door_type(checking)
					var/obj/machinery/door/firedoor/glass/firedoor = new firedoor_type(checking) //ition for fire doors
					if(internal)
						rel_set(newdoor, nameof(newdoor.lift), lift) // REL_PAIR: adds it to lift.doors too
					else
						rel_add(cfloor, nameof(cfloor.doors), newdoor)
						rel_set(newdoor, nameof(newdoor.floor), cfloor)
						rel_add(cfloor, nameof(cfloor.doors), firedoor) //ition for fire doors
						rel_set(firedoor, nameof(firedoor.turbolift_floor), cfloor)
						firedoor.glass = cfloor //ition for fire doors

		// Place exterior control panel.
		var/turf/placing = locate(ext_panel_x, ext_panel_y, cz)
		var/obj/structure/lift/button/panel_ext = new(placing, lift)
		rel_set(panel_ext, nameof(panel_ext.floor), cfloor) // REL_PAIR: sets cfloor.ext_panel too
		panel_ext.set_dir(udir)


		// Place lights
		var/turf/placing1 = locate(light_x1, light_y1, cz)
		var/turf/placing2 = locate(light_x2, light_y2, cz)
		var/obj/machinery/light/light1 = new(placing1)
		var/obj/machinery/light/light2 = new(placing2)
		if(udir == NORTH || udir == SOUTH)
			light1.set_dir(WEST)
			light2.set_dir(EAST)
		else
			light1.set_dir(SOUTH)
			light2.set_dir(NORTH)

		// Update area.
		if(az > length(areas_to_use))
			log_mapping("[name] at [ux],[uy],[uz] requires [depth] floor areas but has [length(areas_to_use)]; failed while creating z=[cz]. Aborting.")
			return

		var/area_path = LAZYACCESS(areas_to_use, az)
		for(var/thing in floor_turfs)
			new area_path(thing)
		var/area/A = locate(area_path)
		cfloor.set_area_ref("\ref[A]")
		az++

	// Place lift panel.
	var/turf/T = locate(int_panel_x, int_panel_y, uz)
	rel_set(lift, nameof(lift.control_panel_interior), make(/obj/structure/lift/panel, at = T, lift = lift))
	lift.control_panel_interior.set_dir(udir)
	rel_set(lift, nameof(lift.current_floor), lift.floors[1])

	lift.open_doors()
