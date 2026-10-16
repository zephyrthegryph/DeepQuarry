// Existing trait alias, no raw damage_wear var or new test-only entry engine.
/obj/effect/dq_trait_roll_probe
	var/next_value = 0
	var/gate_open = TRUE
	var/seen_before_parent
CAPABILITIES(/obj/effect/dq_trait_roll_probe)
	configure(damage_profile(wear = "unrolled"))
	rolls("damage_wear", range_of(1, 1000000), when = nameof(gate_open))
	rolls(nameof(next_value), range_of(1, 1000000), from = list("damage_wear"))
/obj/effect/dq_trait_roll_probe/Initialize(mapload)
	seen_before_parent = damage_profile_of(src).wear
	return ..()

/datum/unit_test/dq_roll_trait_alias_phase_and_stream
/datum/unit_test/dq_roll_trait_alias_phase_and_stream/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	set_global(nameof(GLOB.coalesce_absorbed), GLOB.coalesce_absorbed)
	set_global(nameof(GLOB.act_taken), GLOB.act_taken)
	var/datum/roller/creator = allocate(/datum/roller, "trait-alias-proof")
	set_global(nameof(GLOB.roll_creators), list(creator))
	var/obj/effect/dq_trait_roll_probe/P = allocate(/obj/effect/dq_trait_roll_probe, null)
	var/datum/roller/replay = allocate(/datum/roller, "trait-alias-proof/1")
	TEST_ASSERT_EQUAL(damage_profile_of(P).wear, replay.number(1, 1000000), "alias roll consumes the same first stream draw")
	TEST_ASSERT_EQUAL(P.seen_before_parent, damage_profile_of(P).wear, "subtype pre-parent Initialize observes the completed native roll")
	TEST_ASSERT_EQUAL(P.next_value, replay.number(1, 1000000), "raw dependent target follows alias without an extra RNG draw")
	TEST_ASSERT_EQUAL(damage_profile_of_type(P.type).wear, "unrolled", "rolled private value never mutates compiled initial")
	TEST_ASSERT(!("damage_wear" in P.vars), "registered alias does not create a physical shadow")
	var/obj/effect/dq_trait_roll_probe/peer = allocate(/obj/effect/dq_trait_roll_probe, null)
	var/datum/roller/replay_peer = allocate(/datum/roller, "trait-alias-proof/2")
	TEST_ASSERT_EQUAL(damage_profile_of(peer).wear, replay_peer.number(1, 1000000), "second holder keeps its independent child stream")

/datum/unit_test/dq_roll_trait_alias_map_precedence
/datum/unit_test/dq_roll_trait_alias_map_precedence/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	set_global(nameof(GLOB.coalesce_absorbed), GLOB.coalesce_absorbed)
	set_global(nameof(GLOB.act_taken), GLOB.act_taken)
	var/datum/roller/creator = allocate(/datum/roller, "trait-alias-map")
	set_global(nameof(GLOB.roll_creators), list(creator))
	defer_cleanup(SSatoms, TYPE_PROC_REF(/datum/system/atoms, map_loader_stop), "dq_roll_trait_map")
	for(var/value in list(0, null, "mapped", "unrolled"))
		SSatoms.map_loader_begin("dq_roll_trait_map")
		var/obj/effect/dq_trait_roll_probe/P = new(test_floor())
		SSatoms.map_loader_stop("dq_roll_trait_map")
		own(P)
		TEST_ASSERT(vars_write(P, "damage_wear", value), "historical alias is applied before real init")
		SSatoms.InitializeAtoms(list(P))
		var/datum/roller/replay = allocate(/datum/roller, "trait-alias-map/[creator.children]")
		if(value == "unrolled")
			TEST_ASSERT_EQUAL(damage_profile_of(P).wear, replay.number(1, 1000000), "explicit compiled-default value still rolls, matching raw targets")
		else
			TEST_ASSERT_EQUAL(damage_profile_of(P).wear, value, "nondefault map value, including0/null, suppresses alias roll")
		TEST_ASSERT_EQUAL(P.next_value, replay.number(1, 1000000), "skipped alias consumes no draw; ordinary next target retains exact stream position")
		TEST_ASSERT_EQUAL(P.seen_before_parent, damage_profile_of(P).wear, "map-precedence decision completes before subtype Initialize")

/obj/effect/dq_trait_roll_probe/gated
	gate_open = FALSE

/datum/unit_test/dq_roll_trait_alias_gate
/datum/unit_test/dq_roll_trait_alias_gate/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	set_global(nameof(GLOB.coalesce_absorbed), GLOB.coalesce_absorbed)
	set_global(nameof(GLOB.act_taken), GLOB.act_taken)
	var/datum/roller/creator = allocate(/datum/roller, "trait-alias-gated")
	set_global(nameof(GLOB.roll_creators), list(creator))
	var/obj/effect/dq_trait_roll_probe/gated/P = allocate(/obj/effect/dq_trait_roll_probe/gated, null)
	var/datum/roller/replay = allocate(/datum/roller, "trait-alias-gated/1")
	TEST_ASSERT_EQUAL(damage_profile_of(P).wear, "unrolled", "false ordinary condition leaves native alias unchanged")
	TEST_ASSERT_EQUAL(P.next_value, replay.number(1, 1000000), "a gated alias consumes no random draw")
	TEST_ASSERT(!roll_target_untouched(P, "unregistered_target"), "unknown names still have no writable roll target")
	TEST_ASSERT(roll_target_untouched(P, "@damage_profile.wear"), "canonical native field name shares compiled-initial comparison")
