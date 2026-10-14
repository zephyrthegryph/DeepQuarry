// Tests exercise real qdel() dispatch, not direct lifecycle-hook calls.
/datum/unit_test/dq_cleanup_destroy
	abstract_type = /datum/unit_test/dq_cleanup_destroy

/datum/unit_test/dq_cleanup_destroy/New()
	..()
	dview(0, test_floor())
	status_policies()

/datum/unit_test/dq_cleanup_destroy/proc/scope_fixture()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	set_global(nameof(GLOB.act_taken), GLOB.act_taken)
	set_global(nameof(GLOB.latency_last_ineligible), GLOB.latency_last_ineligible)
	set_global(nameof(GLOB.latency_last_pin_reason), GLOB.latency_last_pin_reason)
/mob/living/carbon/human/dq_cleanup_subject
	var/perspective_resets = 0
	var/camera_cancels = 0
/mob/living/carbon/human/dq_cleanup_subject/reset_perspective(atom/new_eye)
	perspective_resets++
	return ..()
/mob/living/carbon/human/dq_cleanup_subject/cancel_camera()
	camera_cancels++
	return ..()
/obj/machinery/dq_cleanup_holder
/obj/dq_cleanup_micro_holder
	micro_target = TRUE

/obj/structure/micro_tunnel/dq_cleanup_capture
	var/list/captured_messages
/obj/structure/micro_tunnel/dq_cleanup_capture/visible_message(message, blind_message, list/exclude_mobs, range = world.view, runemessage = "<span style='font-size: 1.5em'>👁</span>")
	LAZYADD(captured_messages, message)
	return ..()

/obj/structure/gargoyle/dq_cleanup_capture
	var/list/captured_messages
/obj/structure/gargoyle/dq_cleanup_capture/visible_message(message, blind_message, list/exclude_mobs, range = world.view, runemessage = "<span style='font-size: 1.5em'>👁</span>")
	LAZYADD(captured_messages, message)
	return ..()

/obj/item/telecube/dq_cleanup_capture
	var/list/captured_messages
/obj/item/telecube/dq_cleanup_capture/visible_message(message, blind_message, list/exclude_mobs, range = world.view, runemessage = "<span style='font-size: 1.5em'>👁</span>")
	LAZYADD(captured_messages, message)
	return ..()

/datum/unit_test/dq_cleanup_destroy/machine
/datum/unit_test/dq_cleanup_destroy/machine/Run()
	scope_fixture()
	var/turf/T = test_floor()
	var/obj/machinery/dq_cleanup_holder/M = allocate(/obj/machinery/dq_cleanup_holder, T)
	var/mob/living/carbon/human/dq_cleanup_subject/H = allocate(/mob/living/carbon/human/dq_cleanup_subject, T)
	H.forceMove(M)
	var/before = H.perspective_resets
	TEST_ASSERT_EQUAL(H.loc, M, "the machine actually contains a human")
	qdel(M)
	TEST_ASSERT(!QDELETED(H), "machine destruction releases its human alive")
	TEST_ASSERT_EQUAL(H.loc, T, "machine destruction puts its human on its turf")
	TEST_ASSERT(H.perspective_resets > before, "machine destruction resets the human view")

/datum/unit_test/dq_cleanup_destroy/micro_holder
/datum/unit_test/dq_cleanup_destroy/micro_holder/Run()
	scope_fixture()
	var/turf/T = test_floor()
	var/obj/dq_cleanup_micro_holder/O = allocate(/obj/dq_cleanup_micro_holder, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	H.forceMove(O)
	TEST_ASSERT_EQUAL(H.loc, O, "the micro holder actually contains its occupant")
	qdel(O)
	TEST_ASSERT(!QDELETED(H), "micro holder destruction preserves its occupant")
	TEST_ASSERT_EQUAL(H.loc, T, "micro holder destruction releases its occupant")

/datum/unit_test/dq_cleanup_destroy/tunnel
/datum/unit_test/dq_cleanup_destroy/tunnel/Run()
	scope_fixture()
	var/turf/T = test_floor()
	var/obj/structure/micro_tunnel/dq_cleanup_capture/O = allocate(/obj/structure/micro_tunnel/dq_cleanup_capture, T)
	var/list/messages = list()
	O.captured_messages = messages
	var/mob/living/carbon/human/dq_cleanup_subject/H = allocate(/mob/living/carbon/human/dq_cleanup_subject, T)
	H.forceMove(O)
	var/before = H.camera_cancels
	TEST_ASSERT_EQUAL(H.loc, O, "the tunnel contains the micro")
	qdel(O)
	TEST_ASSERT(!QDELETED(H), "tunnel destruction preserves the micro")
	TEST_ASSERT_EQUAL(H.loc, T, "tunnel collapse puts the micro on its turf")
	TEST_ASSERT(H.camera_cancels > before, "tunnel collapse cancels its camera")
	TEST_ASSERT(findtext(jointext(messages, "\n"), "tumbles out"), "the real collapse emits its tumble effect")

/datum/unit_test/dq_cleanup_destroy/ventcrawler
/datum/unit_test/dq_cleanup_destroy/ventcrawler/Run()
	scope_fixture()
	var/turf/T = test_floor()
	var/obj/machinery/atmospherics/pipe/simple/P = allocate(/obj/machinery/atmospherics/pipe/simple, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	H.forceMove(P)
	set_var(H, nameof(H.is_ventcrawling), TRUE)
	TEST_ASSERT_EQUAL(H.loc, P, "the ventcrawler starts in the pipe")
	qdel(P)
	TEST_ASSERT(!QDELETED(H), "pipe destruction preserves the ventcrawler")
	TEST_ASSERT_EQUAL(H.loc, T, "pipe destruction releases its ventcrawler")
	TEST_ASSERT(!H.is_ventcrawling, "pipe destruction clears actual ventcrawl state")

/datum/unit_test/dq_cleanup_destroy/statue
/datum/unit_test/dq_cleanup_destroy/statue/Run()
	scope_fixture()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/structure/closet/statue/S = allocate(/obj/structure/closet/statue, T, H)
	TEST_ASSERT(!QDELETED(S), "the real statue constructor accepts its subject")
	TEST_ASSERT_EQUAL(H.loc, S, "the subject is actually encased")
	TEST_ASSERT(H.sdisabilities & MUTE, "the encased subject is muted")
	TEST_ASSERT(act_wanted(H, /datum/act/injure), "the statue installs actual injury stasis")
	qdel(S)
	TEST_ASSERT(!QDELETED(H), "statue destruction preserves its subject")
	TEST_ASSERT_EQUAL(H.loc, T, "statue destruction releases its subject")
	TEST_ASSERT(!(H.sdisabilities & MUTE), "statue destruction removes petrification mute")
	TEST_ASSERT(!act_wanted(H, /datum/act/injure), "statue destruction removes actual injury stasis")

/datum/unit_test/dq_cleanup_destroy/belly
/datum/unit_test/dq_cleanup_destroy/belly/Run()
	scope_fixture()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/belly/B = allocate(/obj/belly, H)
	rel_set(B, nameof(B.owner), H)
	var/mob/observer/G = allocate(/mob/observer, T)
	G.forceMove(B)
	TEST_ASSERT_EQUAL(G.loc, B, "the ghost actually starts in the belly")
	qdel(B)
	TEST_ASSERT(!QDELETED(G), "belly destruction preserves its ghost")
	TEST_ASSERT_EQUAL(G.loc, T, "belly destruction releases its ghost on the owner's turf")

/datum/unit_test/dq_cleanup_destroy/gargoyle
/datum/unit_test/dq_cleanup_destroy/gargoyle/Run()
	scope_fixture()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/structure/gargoyle/dq_cleanup_capture/S = allocate(/obj/structure/gargoyle/dq_cleanup_capture, T, H)
	var/list/messages = list()
	S.captured_messages = messages
	set_var(S, nameof(S.can_revert), FALSE)
	TEST_ASSERT_EQUAL(S.WR_gargoyle, H, "the real gargoyle setup binds its subject")
	qdel(S)
	TEST_ASSERT(findtext(jointext(messages, "\n"), "loses shape and crumbles"), "non-reverting gargoyle destruction emits the real crumble effect")

/datum/unit_test/dq_cleanup_destroy/telecube
/datum/unit_test/dq_cleanup_destroy/telecube/Run()
	scope_fixture()
	var/obj/item/telecube/C = allocate(/obj/item/telecube, test_floor())
	var/obj/item/telecube/dq_cleanup_capture/M = allocate(/obj/item/telecube/dq_cleanup_capture, test_floor())
	// Nullspace tests the actual mate message/unlink without submitting a
	// map-wide explosion epoch to other fixtures.
	M.moveToNullspace()
	var/list/messages = list()
	M.captured_messages = messages
	TEST_ASSERT(C.pair_cube(M), "the cube pairs to its mate")
	TEST_ASSERT(M.pair_cube(C), "the mate pairs back")
	qdel(C)
	TEST_ASSERT(!QDELETED(M), "the real collapse hook preserves its mate")
	TEST_ASSERT_NULL(M.mate(), "the real collapse hook clears the reverse link")
	TEST_ASSERT(findtext(jointext(messages, "\n"), "collapses into itself"), "the mate receives the actual collapse effect")

/datum/unit_test/dq_cleanup_destroy/crystal
/datum/unit_test/dq_cleanup_destroy/crystal/Run()
	scope_fixture()
	var/turf/T = test_floor()
	var/list/existing_shards = list()
	for(var/obj/item/material/shard/S in contents_of(T))
		existing_shards += S
	var/shards = 0
	var/phoron_shards = 0
	// The runner seeds RNG. Multiple real shatters exercise both probabilistic
	// products without replacing the probability function or destroy hook.
	for(var/i in 1 to 20)
		var/obj/structure/crystal/C = allocate(/obj/structure/crystal, T)
		qdel(C)
	for(var/obj/item/material/shard/S in contents_of(T))
		if(S in existing_shards)
			continue
		own(S)
		shards++
		if(istype(S, /obj/item/material/shard/phoron))
			phoron_shards++
	TEST_ASSERT(phoron_shards > 0, "real crystal destruction produces phoron shards")
	TEST_ASSERT(shards > phoron_shards, "real crystal destruction also produces ordinary shards")

