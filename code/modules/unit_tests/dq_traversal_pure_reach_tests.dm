// Approved pure per-call reach exemption: no policy mutation during a query.
/obj/machinery/door/dq_traversal_reach
/obj/machinery/door/dq_traversal_reach/proc/reach_reason(datum/act/op/A)
	return Adjacent(A.actor) ? null : "The door is out of reach."

/obj/dq_traversal_border_blocker
	flags = ON_BORDER
	density = TRUE
	dir = EAST

/datum/unit_test/dq_traversal_pure_door_reach
/datum/unit_test/dq_traversal_pure_door_reach/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	set_global(nameof(GLOB.coalesce_absorbed), GLOB.coalesce_absorbed)
	set_global(nameof(GLOB.act_taken), GLOB.act_taken)
	var/turf/T = test_floor()
	var/turf/W = get_step(T, WEST)
	var/turf/SW = get_step(W, SOUTH)
	var/turf/S = get_step(T, SOUTH)
	TEST_ASSERT(W && SW && S, "real orthogonal and diagonal reach fixture has four tiles")
	var/obj/machinery/door/dq_traversal_reach/D = allocate(/obj/machinery/door/dq_traversal_reach, T)
	var/obj/machinery/door/firedoor/border_only/F = allocate(/obj/machinery/door/firedoor/border_only, T)
	F.set_density(TRUE)
	F.set_dir(WEST)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, W)
	var/datum/act/op/A = allocate(/datum/act/op)
	A.holder = D
	A.target_atom = D
	A.actor = H
	var/datum/entry/part/req/R = req(TYPE_PROC_REF(/obj/machinery/door/dq_traversal_reach, reach_reason), of = ON_HOLDER)
	var/datum/dq_b4_key_probe/P = dq_b4_probe(F, TRAVERSAL_POLICY_KEY)
	var/obj/machinery/door/firedoor/border_only/peer = allocate(/obj/machinery/door/firedoor/border_only, S)
	peer.set_throwpass(0)
	peer.set_density(FALSE)
	for(var/value in list(0, 1, null, "configured passthrough"))
		TEST_ASSERT(vars_write(F, "throwpass", value), "historical mapper/admin alias accepts exact value")
		rx_drain()
		var/prior = P.hits
		TEST_ASSERT_NULL(R.check(A), "real requirement permits the door behind its border shutter")
		TEST_ASSERT(D.Adjacent(H), "direct door query agrees with requirement")
		rx_drain()
		TEST_ASSERT_EQUAL(P.hits, prior, "reach preview publishes no native policy writes")
		TEST_ASSERT_EQUAL(traversal_policy_of(F).throwpass, value, "reach preview preserves exact configured value, including null")
		TEST_ASSERT_EQUAL(traversal_policy_of(peer).throwpass, 0, "query exemption never changes an independent peer")
	H.forceMove(SW)
	TEST_ASSERT_NULL(R.check(A), "diagonal path also carries border-firedoor exemption")
	var/obj/first = allocate(/obj, W)
	var/obj/second = allocate(/obj, S)
	first.set_density(TRUE)
	second.set_density(TRUE)
	TEST_ASSERT_NOTNULL(R.check(A), "two unrelated dense intermediate obstacles still block diagonal reach")
	first.set_density(FALSE)
	TEST_ASSERT_NULL(R.check(A), "one clear intermediate path is sufficient")
	var/obj/edge = allocate(/obj/dq_traversal_border_blocker, W)
	TEST_ASSERT_NOTNULL(R.check(A), "a border on the remaining diagonal route still blocks its corner")
	edge.set_density(FALSE)
	TEST_ASSERT_NULL(R.check(A), "clearing that border restores the same diagonal route")
	H.forceMove(W)
	// The historical fourth positional mover remains ignored, not an obstacle exemption.
	F.set_throwpass(0)
	TEST_ASSERT_EQUAL(T.ClickCross(WEST, TRUE, null, F), 0, "old fourth argument is not reinterpreted as ignored obstacle")
	TEST_ASSERT_EQUAL(T.ClickCross(WEST, TRUE, null, null, F), 1, "new explicit fifth argument ignores only the requested shutter")
	edge.set_density(TRUE)
	TEST_ASSERT(edge.flags & ON_BORDER, "the real extra blocker is a border object")
	TEST_ASSERT_NOTNULL(R.check(A), "another border blocker still refuses orthogonal door reach")

/datum/unit_test/dq_traversal_mapper_query
/datum/unit_test/dq_traversal_mapper_query/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	set_global(nameof(GLOB.coalesce_absorbed), GLOB.coalesce_absorbed)
	set_global(nameof(GLOB.act_taken), GLOB.act_taken)
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, get_step(T, WEST))
	var/obj/machinery/door/dq_traversal_reach/D = allocate(/obj/machinery/door/dq_traversal_reach, T)
	defer_cleanup(SSatoms, TYPE_PROC_REF(/datum/system/atoms, map_loader_stop), "dq_traversal_mapper")
	SSatoms.map_loader_begin("dq_traversal_mapper")
	var/obj/machinery/door/firedoor/border_only/F = new(T)
	SSatoms.map_loader_stop("dq_traversal_mapper")
	own(F)
	TEST_ASSERT(vars_write(F, "throwpass", "mapped passthrough"), "real delayed map atom accepts historical value before initialization")
	SSatoms.InitializeAtoms(list(F))
	F.set_density(TRUE)
	F.set_dir(WEST)
	TEST_ASSERT_EQUAL(traversal_policy_of(F).throwpass, "mapped passthrough", "actual atom initialization preserves mapper policy")
	TEST_ASSERT(D.Adjacent(H), "real door remains reachable with mapped border policy")
	TEST_ASSERT_EQUAL(traversal_policy_of(F).throwpass, "mapped passthrough", "pure query no longer resets mapper value")
