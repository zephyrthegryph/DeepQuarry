/obj/effect/map_effect/beam_point/end/dq_owned_beam_target
	id = "dq_owned_beam_plan"

/obj/effect/ebeam/dq_owned_beam_segment
/obj/effect/ebeam/dq_owned_beam_segment/on_drawn()
	var/datum/beam/B = owner()
	var/obj/effect/map_effect/beam_point/dq_owned_beam_source/S = B.origin()
	S.capture_child_state()
	return ..()

/obj/effect/dq_owned_beam_parent_observer
	var/beam_count
	var/cadence
	var/root_initialized
/obj/effect/dq_owned_beam_parent_observer/Initialize(mapload)
	var/obj/effect/map_effect/beam_point/S = loc
	beam_count = length(S.my_beams)
	cadence = S.next_beam_delay
	root_initialized = !!(S.flags & ATOM_INITIALIZED)
	return ..()

/obj/effect/map_effect/beam_point/dq_owned_beam_source
	id = "dq_owned_beam_plan"
	make_beams_on_init = TRUE
	max_beams = 31
	beam_type = /obj/effect/ebeam/dq_owned_beam_segment
	initial_delay = 2 SECONDS
	var/obj/effect/dq_owned_beam_parent_observer/parent_observer
	var/child_observed = FALSE
	var/child_root_initialized
	var/child_cadence
CAPABILITIES(/obj/effect/map_effect/beam_point/dq_owned_beam_source)
	owns_one(nameof(parent_observer), /obj/effect/dq_owned_beam_parent_observer, starts = /obj/effect/dq_owned_beam_parent_observer)
/obj/effect/map_effect/beam_point/dq_owned_beam_source/proc/capture_child_state()
	if(!child_observed)
		child_observed = TRUE
		child_root_initialized = !!(flags & ATOM_INITIALIZED)
		child_cadence = next_beam_delay

/datum/unit_test/dq_init_beam_owned_start
/datum/unit_test/dq_init_beam_owned_start/Run()
	dq_init_objects_fixture_scope()
	var/turf/T = test_floor()
	var/turf/target_turf = get_step(T, EAST)
	var/list/targets = list()
	for(var/i in 1 to 31)
		targets += allocate(/obj/effect/map_effect/beam_point/end/dq_owned_beam_target, target_turf)
	SSatoms.map_loader_begin("dq_init_beam_owned_start")
	var/obj/effect/map_effect/beam_point/dq_owned_beam_source/S = new(T)
	SSatoms.map_loader_stop("dq_init_beam_owned_start")
	own(S)
	TEST_ASSERT(vars_write(S, "next_beam_delay", 77), "mapper cadence is provided before true queued map init")
	TEST_ASSERT(vars_write(S, "initial_delay", 3 SECONDS), "map initial delay overrides compiled value")
	SSatoms.InitializeAtoms(list(S))
	TEST_ASSERT(S.child_observed, "actual beam Start draws a real segment child")
	TEST_ASSERT_EQUAL(S.child_root_initialized, FALSE, "real beam children observe pre-root emitter flags")
	TEST_ASSERT_EQUAL(S.child_cadence, 77, "beam children observe mapped pre-overwrite delay")
	TEST_ASSERT_EQUAL(length(S.my_beams), 31, "native take/re-adopt preserves more than REL_SCAN_MAX24 real beams")
	TEST_ASSERT_EQUAL(S.next_beam_delay, 3 SECONDS, "startup unconditionally overwrites mapped next delay with configured first cadence")
	TEST_ASSERT_EQUAL(S.parent_observer.beam_count, 31, "actual non-early owned child sees complete beamset at parent root")
	TEST_ASSERT_EQUAL(S.parent_observer.cadence, 3 SECONDS, "parent owned-child constructor sees cadence after real beam creation")
	TEST_ASSERT_EQUAL(S.parent_observer.root_initialized, TRUE, "parent observer is constructed at normal root phase")
	var/list/beams = S.my_beams.Copy()
	var/list/seen_targets = list()
	for(var/datum/beam/B as anything in beams)
		TEST_ASSERT_EQUAL(B.origin(), S, "every actual beam retains origin reference")
		TEST_ASSERT(!(B.target() in seen_targets), "real seek/has_active logic never duplicates a target")
		seen_targets += B.target()
		TEST_ASSERT(length(B.elements), "real Start produced owned visual segments")
	var/list/listeners = list()
	for(var/datum/beam/B as anything in beams)
		var/datum/dq_ending_detail/L = allocate(/datum/dq_ending_detail)
		listeners += L
		observe(B, /datum/notice/ended, L, then(TYPE_PROC_REF(/datum/dq_ending_detail, heard)))
	qdel(S)
	rx_drain()
	for(var/datum/dq_ending_detail/L as anything in listeners)
		TEST_ASSERT_EQUAL(L.cause, END_DESTROYED, "every real beam preserves destroyed cause, not generic owned cleanup")
	for(var/datum/beam/B as anything in beams)
		TEST_ASSERT(QDELETED(B), "origin deletion finalizes every real beam")
	for(var/obj/effect/map_effect/beam_point/P as anything in targets)
		TEST_ASSERT(!QDELETED(P), "borrowed endpoints survive origin deletion")

/obj/effect/map_effect/beam_point/timer/dq_owned_beam_cadence
	max_beams = 0
	initial_delay = 2 SECONDS

/datum/unit_test/dq_init_beam_owned_cadence
/datum/unit_test/dq_init_beam_owned_cadence/Run()
	dq_init_objects_fixture_scope()
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	SSatoms.map_loader_begin("dq_init_beam_owned_cadence")
	var/obj/effect/map_effect/beam_point/timer/dq_owned_beam_cadence/S = new(test_floor())
	SSatoms.map_loader_stop("dq_init_beam_owned_cadence")
	own(S)
	TEST_ASSERT(vars_write(S, "next_beam_delay", 77), "map supplied next delay is real pre-init state")
	TEST_ASSERT(vars_write(S, "initial_delay", 3 SECONDS), "map initial delay overrides compiled delay")
	SSatoms.InitializeAtoms(list(S))
	var/datum/viewer = allocate(/datum)
	hold(S, STAT_RELEVANCE, RELEVANCE_VISIBLE, viewer)
	TEST_ASSERT_EQUAL(S.next_beam_delay, 3 SECONDS, "empty real emitter plan still installs configured cadence")
	TEST_ASSERT_EQUAL(S.timer_on_index, 1, "native timer starts with first on index")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(S.timer_on_index, 1, "first tick cannot occur at zero or compiled two-second delay")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(S.timer_on_index, 2, "real native timer has run once at four seconds, after mapped three-second deadline")
	TEST_ASSERT_EQUAL(length(S.my_beams), 0, "max-zero timer never fabricates owned output")
	release(S, STAT_RELEVANCE, viewer)
	qdel(S)
	test_driver_end()
