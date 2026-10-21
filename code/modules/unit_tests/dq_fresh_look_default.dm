// The default look of a type (doc/rewrite/proposals/change_graph.md section 7).
//
// The change graph stamps a type's default look on creation and queues no first draw. That is only right when a fresh instance's look
// is a function of its type and nothing else. This sweep makes two fresh instances of every creatable obj and mob type, each from the
// same world (the block emptied, the RNG reseeded from the type's path, the presentation lane settled), and compares their looks. The
// first instance's look is the type's default; a type whose second instance differs has an instance-dependent first draw (its
// Initialize() writes something a draw reads, or its look follows an order-dependent global), which is a type the stamp must not
// cover: it keeps a forced first draw until it is fixed. Such types are logged as forced-draw candidates; the test fails when one of them
// is covered by the default-look stamp (look_stamp.dm), which would spare it the first draw it needs.
//
// Sharded: dq_focused_test.sh runs it as DQ_SWEEP_SHARDS worlds (sweep_pins), each sweeping its slice through sweep_types().
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
	var/list/candidates = list()
	var/checked = 0
	for(var/type in sweep_types(types))
		checked++
		log_test("fresh look default: making [type]")
		var/list/first = dq_fresh_look_rows(type, T)
		var/list/second = dq_fresh_look_rows(type, T)
		if(jointext(first, "\n") != jointext(second, "\n"))
			var/row = "[type]: [dq_fresh_look_difference(first, second)]"
			candidates += row
			if(GLOB.type_look_stamp[type])
				bad += row // the stamp spares this type its first draw, but its fresh look is not its type's
	dq_fresh_look_reset(T)
	log_test("fresh look default: [checked] types, [length(candidates)] with an instance-dependent first look (they keep a forced first draw)")
	for(var/row in candidates)
		log_test("fresh look default: forced-draw candidate [row]")
	TEST_ASSERT(!length(bad), "a type the default-look stamp covers must draw its type's default when fresh; these differ from a second fresh instance:\n[jointext(bad, "\n")]")

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
			// dq_ types are unit-test fixtures (some crash on purpose); the sweep is about the game's own types.
			// The sleeving-cure pills hold a reagent that is commented out (latent_safe_types.dm): creating one runtimes, a medical fix.
			if(!is_abstract(type) && !(type in uncreatables) && !findtext("[type]", "/dq_") && !ispath(type, /obj/item/reagent_containers/pill/sleevingcure) && !ispath(type, /obj/item/storage/pill_bottle/sleevingcure))
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
				dq_fresh_look_delete(AM)

/// The block back to the state every unit starts from: its turfs reset, the lane settled.
/datum/unit_test/proc/dq_fresh_look_reset(turf/T)
	for(var/turf/B as anything in block_turfs(test_block))
		dq_fresh_look_drain(B)
		unit_test_block_reset_turf(B)
	dq_fresh_look_settle()

/// Whether `A`'s type refuses an unforced qdel() (LIFECYCLE_KEEP_*): asked with the refusal's own report switched off.
/datum/unit_test/proc/dq_fresh_look_keeps(datum/A)
	GLOB.lifecycle_keep_expected = TRUE // the question itself reports an unforced delete otherwise
	. = !!A.lifecycle_keep(FALSE)
	GLOB.lifecycle_keep_expected = FALSE

/// Deletes `A`; a type that refuses an unforced qdel() is deleted forced (the sweep made it, so it owns the end of it).
/datum/unit_test/proc/dq_fresh_look_delete(datum/A)
	qdel(A, dq_fresh_look_keeps(A))

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
		else if(dq_fresh_look_keeps(A))
			. = list("keeps itself (lifecycle_keep)") // a singleton or an owned part: not a look a type's instances share
			dq_fresh_look_delete(A)
		else
			dq_fresh_look_settle()
			. = dq_fresh_look_lines(A)
			dq_fresh_look_delete(A)
	catch(var/exception/e)
		. = list("runtime: [e.name]")
	dq_fresh_look_drain(T)

/// The first row that is in one look and not the other, for the report.
/datum/unit_test/proc/dq_fresh_look_difference(list/first, list/second)
	var/list/only_first = first - second
	var/list/only_second = second - first
	return "first only [json_encode(only_first)] second only [json_encode(only_second)]"
