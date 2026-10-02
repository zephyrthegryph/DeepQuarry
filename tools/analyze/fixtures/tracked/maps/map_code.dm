// maps/ is read too (dm_files() walks code and maps).
TRACKED(/obj/machinery/pump, map_declared)

/obj/machinery/pump/proc/map_writes(obj/machinery/pump/P)
	target_pressure = 1
	P.open = 1
	map_declared = 2
	map_declared = 3 // ALLOW(tracked): the fixture keeps this map write on purpose
