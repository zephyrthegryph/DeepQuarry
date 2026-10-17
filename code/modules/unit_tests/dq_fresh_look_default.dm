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
	var/list/types = dq_fresh_look_universe()
	var/list/bad = list()
	var/checked = 0
	for(var/type in sweep_types(types))
		checked++
		log_test("fresh look default: making [type]")
		var/list/first = dq_fresh_look_rows(type, T)
		var/list/second = dq_fresh_look_rows(type, T)
		if(jointext(first, "
") != jointext(second, "
"))
			bad += "[type]: [dq_fresh_look_difference(first, second)]"
	dq_fresh_look_reset(T)
	log_test("fresh look default: [checked] types, [length(bad)] with an instance-dependent first look")
	TEST_ASSERT(!length(bad), "a fresh instance's look must be its type's default; these differ from a second fresh instance:
[jointext(bad, "
")]")

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

/// The creatable types the sweep makes, sorted by path text so every shard agrees. Items, machines, structures and mobs: the things a
/// player sees drawn. Effects and other roots are left out (an effect such as a light's visible mask refuses a plain qdel).
/datum/unit_test/proc/dq_fresh_look_universe()
	var/list/seen = list()
	for(var/root in list(/obj/item, /obj/machinery, /obj/structure, /mob))
		for(var/type in typesof(root))
			if(!is_abstract(type) && !(type in uncreatables))
				seen["[type]"] = type
	var/list/names = list()
	for(var/name in seen)
		names += name
	sortTim(names, GLOBAL_PROC_REF(cmp_text_asc))
	. = list()
	for(var/name in names)
		. += seen[name]

/// Lets the work that is already owed run the same way every time: the kernel stands on its injected clock and its deadline phase
/// runs the zero-delay work the last step queued until none is left.
/datum/unit_test/proc/dq_fresh_look_settle()
	kernel_test_begin()
	for(var/pass in 1 to 3)
		kernel_phase_run(KERNEL_PHASE_D)
	kernel_drain_now()

/// Deletes what a type left on `T` until nothing is left (deleting a thing can make more of them).
/datum/unit_test/proc/dq_fresh_look_drain(turf/T)
	for(var/pass in 1 to 30)
		var/list/left = list()
		for(var/atom/movable/AM as anything in contents_of(T))
			if(!QDELETED(AM) && !istype(AM, /obj/effect/landmark))
				left += AM
		if(!length(left))
			return
		for(var/atom/movable/AM as anything in left)
			if(!QDELETED(AM))
				qdel(AM)

/// The block back to the state every unit starts from: its turfs reset, the lane settled.
/datum/unit_test/proc/dq_fresh_look_reset(turf/T)
	for(var/turf/B as anything in block_turfs(test_block))
		dq_fresh_look_drain(B)
		unit_test_block_reset_turf(B)
	dq_fresh_look_settle()

/// The look of one atom as sorted rows: icon, state, dir, colour, alpha and every distinct overlay and underlay.
/proc/dq_fresh_look_lines(atom/target)
	. = list()
	. += "icon: [target.icon]"
	. += "state: [target.icon_state]"
	. += "dir: [target.dir]"
	if(!isnull(target.color))
		. += "color: [islist(target.color) ? jointext(target.color, ",") : target.color]"
	if(target.alpha != 255)
		. += "alpha: [target.alpha]"
	. += dq_fresh_look_layers("overlay", target.overlays)
	. += dq_fresh_look_layers("underlay", target.underlays)

/proc/dq_fresh_look_layers(kind, list/layers)
	var/list/counts = list()
	for(var/layer in layers)
		var/mutable_appearance/MA = new(layer)
		if(MA.icon == LIGHTING_ICON) // the lighting system's own darkness layer, present or not by boot timing; not part of a look
			continue
		var/row = "[kind]: [MA.icon]:[MA.icon_state]:[MA.plane]"
		if(!isnull(MA.color))
			row += ":[islist(MA.color) ? jointext(MA.color, ",") : MA.color]"
		counts[row] += 1
	. = list()
	for(var/row in counts)
		. += counts[row] > 1 ? "[row] x[counts[row]]" : row
	sortTim(., GLOBAL_PROC_REF(cmp_text_asc))

/// One fresh `type` made from a clean world (the RNG reseeded from its path), settled and read as look rows. A runtime is a row of
/// its own, so one broken type does not end the sweep; the instance is deleted and its tile drained.
/datum/unit_test/proc/dq_fresh_look_rows(type, turf/T)
	dq_fresh_look_reset(T)
	rand_seed(dq_test_seed_for("[type]"))
	try
		var/atom/A = dq_snapshot_allocate(type, T)
		if(QDELETED(A))
			. = list("deleted itself on creation")
		else
			dq_fresh_look_settle()
			. = dq_fresh_look_lines(A)
			qdel(A)
	catch(var/exception/e)
		. = list("runtime: [e.name]")
	dq_fresh_look_drain(T)

/// The first row that is in one look and not the other, for the report.
/datum/unit_test/proc/dq_fresh_look_difference(list/first, list/second)
	var/list/only_first = first - second
	var/list/only_second = second - first
	return "first only [json_encode(only_first)] second only [json_encode(only_second)]"
