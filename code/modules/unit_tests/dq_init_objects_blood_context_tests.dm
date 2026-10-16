// Actual constructor/mapload transactions, never manual calls to the capability hook.
/obj/effect/decal/cleanable/blood/splatter/animated/init_discard_fixture
	delete_me = TRUE

/datum/unit_test/dq_init_objects_blood_context

/datum/unit_test/dq_init_objects_blood_context/Run()
	dq_init_objects_fixture_scope()
	var/turf/T = test_floor()
	var/obj/effect/decal/cleanable/blood/first = allocate(/obj/effect/decal/cleanable/blood, T)
	first.init_forensic_data().merge_blooddna(null, list("first donor" = "O+"))
	var/obj/effect/decal/cleanable/blood/second = allocate(/obj/effect/decal/cleanable/blood, T)
	TEST_ASSERT(QDELETED(first), "a new runtime plain puddle consumes the initialized older puddle")
	TEST_ASSERT_EQUAL(second.forensic_data.get_blooddna()["first donor"], "O+", "actual donor evidence survives coalescing")
	TEST_ASSERT_EQUAL(second.dry_delay, 5 MINUTES * (second.amount + 1), "runtime drying uses actual initial depth")
	var/obj/effect/decal/cleanable/blood/splatter/S = allocate(/obj/effect/decal/cleanable/blood/splatter, T)
	TEST_ASSERT(!QDELETED(second) && !QDELETED(S), "nonplain splatters do not coalesce existing plain puddles")
	TEST_ASSERT_EQUAL(S.dry_delay, 5 MINUTES * (S.amount + 1), "a real subtype's amount controls drying")

/datum/unit_test/dq_init_objects_blood_context/mapload_and_discard

/datum/unit_test/dq_init_objects_blood_context/mapload_and_discard/Run()
	dq_init_objects_fixture_scope()
	var/turf/T = test_floor()
	SSatoms.map_loader_begin("dq_initial_blood")
	var/obj/effect/decal/cleanable/blood/first = new(T)
	var/obj/effect/decal/cleanable/blood/second = new(T)
	first.init_forensic_data().merge_blooddna(null, list("first donor" = "A+"))
	second.init_forensic_data().merge_blooddna(null, list("second donor" = "B-"))
	SSatoms.map_loader_stop("dq_initial_blood")
	own(first)
	own(second)
	SSatoms.InitializeAtoms(list(first, second))
	TEST_ASSERT(!QDELETED(first) && QDELETED(second), "the first mapped puddle marks its not-yet-initialized peer for deferred discard")
	TEST_ASSERT_EQUAL(first.forensic_data.get_blooddna()["first donor"], "A+", "mapped coalescing preserves the survivor's evidence")
	TEST_ASSERT_EQUAL(first.forensic_data.get_blooddna()["second donor"], "B-", "mapped coalescing merges the discarded peer's evidence")
	TEST_ASSERT_EQUAL(first.dry_delay, 0, "mapped blood does not acquire runtime drying delay")
	SSatoms.map_loader_begin("dq_initial_blood_discard")
	var/obj/effect/decal/cleanable/blood/splatter/animated/init_discard_fixture/discarded = new(T)
	SSatoms.map_loader_stop("dq_initial_blood_discard")
	own(discarded)
	SSatoms.InitializeAtoms(list(discarded))
	TEST_ASSERT(QDELETED(discarded), "the real keep condition discards an initially marked subtype")
	TEST_ASSERT_EQUAL(discarded.loc_last_process, T, "the actual animated descendant's post-parent tail still ran before discard")
	TEST_ASSERT(!(discarded in SSpersistence.tracking_values[/datum/persistent/filth]), "discard forgets the registration inherited from cleanable init")
