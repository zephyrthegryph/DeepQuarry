// LINDA atmospherics rewrite (commit 6fdac16ef1). gas_mixture var accesses (e.g. mix.total_moles) converted to proc calls (mix.total_moles()) for the LINDA engine API. Bulk rewrite by tools/verdigris/linda_rewrite_chomp_atmos.py.
// Bracketed at file-header rather than per-hunk because the
// edits are mechanical and span the whole file; the commit SHA
// is the source of truth for per-line diff context.

//
// This event chooses a random canister on player levels and breaks it, releasing its contents!
//

/datum/event2/meta/canister_leak
	name = "canister leak"
	departments = list(DEPARTMENT_ENGINEERING)
	chaos = 10
	chaotic_threshold = EVENT_CHAOS_THRESHOLD_LOW_IMPACT
	reusable = TRUE
	event_type = /datum/event2/event/canister_leak

/datum/event2/meta/canister_leak/get_weight()
	return GLOB.metric.count_people_in_department(DEPARTMENT_ENGINEERING) * 30

/datum/event2/event/canister_leak/start()
	// List of all non-destroyed canisters on station levels
	var/list/all_canisters = list()
	for(var/obj/machinery/portable_atmospherics/canister/C in GLOB.machines)
		if(!C.destroyed && (C.z in using_map.station_levels) && C.air_contents.total_moles() >= MOLES_CELLSTANDARD)
			all_canisters += C
	if(!length(all_canisters))
		return
	var/obj/machinery/portable_atmospherics/canister/C = pick(all_canisters)
	log_game("canister_leak event: Canister [C] ([C.x],[C.y],[C.z]) destroyed.")
	C.health = 0
	C.healthcheck()
