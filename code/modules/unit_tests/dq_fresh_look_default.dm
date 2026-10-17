// The default look of a type (doc/rewrite/proposals/change_graph.md section 7).
//
// The change graph stamps a type's default look on creation and queues no first draw. That is only right when a fresh instance's look
// is a function of its type and nothing else. This sweep makes two fresh instances of every creatable obj and mob type, each from the
// same world (the block emptied, the RNG reseeded from the type's path, the presentation lane settled), and compares their looks. The
// first instance's look is the type's default; a type whose second instance differs has an instance-dependent first draw (its
// Initialize() writes something a draw reads, or its look follows an order-dependent global), which is a type the stamp must not
// cover: it keeps a forced first draw until it is fixed. Once the stamp lands (step 5) the same test compares the stamped look with a
// dry draw.
//
// Exhaustive: the whole-type sweep. Normal tier: dq_fresh_look_default/representative, a curated spread.

/datum/unit_test/dq_fresh_look_default
	tier = TEST_TIER_EXHAUSTIVE
	timeout = 3600
	is_sweep_test = TRUE

/datum/unit_test/dq_fresh_look_default/Run()
	var/turf/T = test_floor()
	// The roots the look pins cover: a type outside them (an effect whose lifecycle refuses a plain qdel) is not made by any look test.
	var/list/types = list()
	for(var/type in dq_look_universe(TRUE, FALSE))
		if(ispath(type, /obj) || ispath(type, /mob))
			types += type
	var/list/bad = list()
	var/checked = 0
	for(var/type in sweep_types(types))
		checked++
		log_test("fresh look default: making [type]")
		var/list/first = dq_fresh_look_rows(type, T)
		var/list/second = dq_fresh_look_rows(type, T)
		if(jointext(first, "\n") != jointext(second, "\n"))
			bad += "[type]: [dq_fresh_look_difference(first, second)]"
	dq_look_reset(T)
	log_test("fresh look default: [checked] types, [length(bad)] with an instance-dependent first look")
	TEST_ASSERT(!length(bad), "a fresh instance's look must be its type's default; these differ from a second fresh instance:\n[jointext(bad, "\n")]")

/// Normal tier: a curated spread of the sweep.
/datum/unit_test/dq_fresh_look_default/representative
	is_sweep_test = FALSE
	tier = TEST_TIER_NORMAL

/datum/unit_test/dq_fresh_look_default/representative/curated_types()
	return list(
		/obj/machinery/navbeacon,
		/obj/machinery/floodlight,
		/obj/machinery/door/airlock,
		/obj/item/storage/toolbox/mechanical,
		/obj/item/clothing/under/color/grey,
		/obj/structure/table,
		/obj/machinery/atmospherics/pipe/simple/visible,
		/obj/item/cell,
	)

/// One fresh `type` made from a clean world (the RNG reseeded from its path), settled and read as look rows. A runtime is a row of
/// its own, so one broken type does not end the sweep; the instance is deleted and its tile drained.
/datum/unit_test/proc/dq_fresh_look_rows(type, turf/T)
	dq_look_reset(T)
	rand_seed(dq_test_seed_for("[type]"))
	try
		var/atom/A = dq_snapshot_allocate(type, T)
		if(QDELETED(A))
			. = list("deleted itself on creation")
		else
			dq_look_settle()
			. = dq_look_pin_lines(A)
			qdel(A)
	catch(var/exception/e)
		. = list("runtime: [dq_look_state_error(e)]")
	dq_look_drain_turf(T)

/// The first row that is in one look and not the other, for the report.
/datum/unit_test/proc/dq_fresh_look_difference(list/first, list/second)
	var/list/only_first = first - second
	var/list/only_second = second - first
	return "first only [json_encode(only_first)] second only [json_encode(only_second)]"
