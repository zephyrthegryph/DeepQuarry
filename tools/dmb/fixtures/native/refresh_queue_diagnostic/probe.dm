#if defined(UNIT_TESTS)
// Included only by the owned diagnostic manifest; no permanent game include.
// Diagnostic only: no flush, mutation, or assertion of queue-size parity.
/datum/unit_test/dq_refresh_queue_diagnostic
	priority = -100000

/datum/unit_test/dq_refresh_queue_diagnostic/Run()
	var/list/queue = GLOB.refresh_queue
	var/list/seen = list()
	var/list/types = list()
	var/list/masks = list()
	var/list/locations = list()
	var/duplicates = 0
	var/nulls = 0
	var/deleted = 0
	var/zero_pending = 0
	var/visited = 0
	var/queue_length = length(queue)
	var/captured_time = world.time
	var/captured_drained = GLOB.refresh_bench_drained
	for(var/datum/D as anything in queue)
		if(++visited > 100000)
			break
		if(isnull(D))
			nulls++
			continue
		if(seen[D])
			duplicates++
		seen[D] = TRUE
		if(QDELETED(D))
			deleted++
		if(!D.refresh_queued)
			zero_pending++
		var/type_key = "[D.type]"
		types[type_key] = (types[type_key] || 0) + 1
		var/mask_key = "[D.refresh_queued]"
		masks[mask_key] = (masks[mask_key] || 0) + 1
		var/location_key = "datum"
		if(isatom(D))
			var/atom/A = D
			location_key = "z=[A.z];loc=[isnull(A.loc) ? "null" : "[A.loc.type]"]"
		locations[location_key] = (locations[location_key] || 0) + 1
	var/atoms = 0
	var/turfs = 0
	var/map_complete = TRUE
	for(var/atom/A in world)
		if(++atoms > 250000)
			map_complete = FALSE
			break
		if(isturf(A))
			turfs++
	var/list/report = list("schema" = 1, "diagnostic_only" = TRUE, "world_time" = captured_time, "drained" = captured_drained,
		"queue_length" = queue_length, "queue_scan_complete" = queue_length <= 100000, "distinct" = length(seen),
		"duplicates" = duplicates, "nulls" = nulls, "deleted" = deleted, "zero_pending" = zero_pending,
		"types" = types, "masks" = masks, "locations" = locations, "world_atoms" = atoms, "world_turfs" = turfs,
		"map_scan_complete" = map_complete, "map_maxx" = world.maxx, "map_maxy" = world.maxy, "map_maxz" = world.maxz)
	text2file(json_encode(report), world.params["refresh-diagnostic-file"])
#endif
