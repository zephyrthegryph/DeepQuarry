// Surface elevator anchor: a landmark placed at the center of the surface
// elevator room on the entrance .dmm. On Initialize, it tells SSquarry's
// elevator datum which 3x3 of floor tiles around it constitute the surface
// bay. Door positions on the surface map are also discovered from the
// same scan.

/obj/effect/landmark/quarry_elevator_anchor
	name = "quarry elevator anchor"
	desc = "Marks the center of the surface elevator bay."

/obj/effect/landmark/quarry_elevator_anchor/Initialize(mapload)
	. = ..()
	if(!SSquarry || !SSquarry.elevator)
		return
	var/turf/center = get_turf(src)
	if(!isturf(center))
		return

	// Collect the 3x3 of turfs centered on this landmark, in row-major
	// order (top row first, left to right). Both the layer carver and this
	// proc use the same ordering so travel_to() can pair tiles by index.
	var/list/bay = list()
	for(var/dy in -1 to 1)
		for(var/dx in -1 to 1)
			var/turf/T = locate(center.x + dx, center.y + dy, center.z)
			if(isturf(T))
				bay += T
	SSquarry.elevator.surface_bay = bay

	// Find any lift doors adjacent to the bay; cache them under depth 0.
	var/list/surface_doors = list()
	for(var/turf/T as anything in bay)
		for(var/dir in GLOB.cardinal)
			var/turf/neighbor = get_step(T, dir)
			for(var/obj/machinery/door/airlock/lift/D in neighbor)
				if(!(D in surface_doors))
					surface_doors += D
	SSquarry.elevator.doors["0"] = surface_doors
