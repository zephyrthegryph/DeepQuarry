// Tests exercise real qdel() dispatch, not direct lifecycle-hook calls.
/datum/unit_test/dq_decl_cleanup_destroy
	abstract_type = /datum/unit_test/dq_decl_cleanup_destroy

/datum/unit_test/dq_decl_cleanup_destroy/New()
	..()
	dview(0, test_floor())
	status_policies()

/datum/unit_test/dq_decl_cleanup_destroy/proc/scope_fixture()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	set_global(nameof(GLOB.act_taken), GLOB.act_taken)
	set_global(nameof(GLOB.latency_last_ineligible), GLOB.latency_last_ineligible)
	set_global(nameof(GLOB.latency_last_pin_reason), GLOB.latency_last_pin_reason)
/mob/living/carbon/human/dq_decl_cleanup_subject
	var/perspective_resets = 0
	var/camera_cancels = 0
/mob/living/carbon/human/dq_decl_cleanup_subject/reset_perspective(atom/new_eye)
	perspective_resets++
	return ..()
/mob/living/carbon/human/dq_decl_cleanup_subject/cancel_camera()
	camera_cancels++
	return ..()
/obj/machinery/dq_decl_cleanup_holder
/obj/dq_decl_cleanup_micro_holder
	micro_target = TRUE

/obj/structure/micro_tunnel/dq_decl_cleanup_capture
	var/list/captured_messages
/obj/structure/micro_tunnel/dq_decl_cleanup_capture/visible_message(message, blind_message, list/exclude_mobs, range = world.view, runemessage = "<span style='font-size: 1.5em'>👁</span>")
	LAZYADD(captured_messages, message)
	return ..()

/obj/structure/gargoyle/dq_decl_cleanup_capture
	color = "#123456"
	var/list/captured_messages
/obj/structure/gargoyle/dq_decl_cleanup_capture/visible_message(message, blind_message, list/exclude_mobs, range = world.view, runemessage = "<span style='font-size: 1.5em'>👁</span>")
	LAZYADD(captured_messages, message)
	return ..()

/obj/item/telecube/dq_decl_cleanup_capture
	var/list/captured_messages
/obj/item/telecube/dq_decl_cleanup_capture/visible_message(message, blind_message, list/exclude_mobs, range = world.view, runemessage = "<span style='font-size: 1.5em'>👁</span>")
	LAZYADD(captured_messages, message)
	return ..()

/datum/unit_test/dq_decl_cleanup_destroy/machine
/datum/unit_test/dq_decl_cleanup_destroy/machine/Run()
	scope_fixture()
	var/turf/T = test_floor()
	var/obj/machinery/dq_decl_cleanup_holder/M = allocate(/obj/machinery/dq_decl_cleanup_holder, T)
	var/mob/living/carbon/human/dq_decl_cleanup_subject/H = allocate(/mob/living/carbon/human/dq_decl_cleanup_subject, T)
	H.forceMove(M)
	var/before = H.perspective_resets
	TEST_ASSERT_EQUAL(H.loc, M, "the machine actually contains a human")
	qdel(M)
	TEST_ASSERT(!QDELETED(H), "machine destruction releases its human alive")
	TEST_ASSERT_EQUAL(H.loc, T, "machine destruction puts its human on its turf")
	TEST_ASSERT(H.perspective_resets > before, "machine destruction resets the human view")

/datum/unit_test/dq_decl_cleanup_destroy/micro_holder
/datum/unit_test/dq_decl_cleanup_destroy/micro_holder/Run()
	scope_fixture()
	var/turf/T = test_floor()
	var/obj/dq_decl_cleanup_micro_holder/O = allocate(/obj/dq_decl_cleanup_micro_holder, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	H.forceMove(O)
	TEST_ASSERT_EQUAL(H.loc, O, "the micro holder actually contains its occupant")
	qdel(O)
	TEST_ASSERT(!QDELETED(H), "micro holder destruction preserves its occupant")
	TEST_ASSERT_EQUAL(H.loc, T, "micro holder destruction releases its occupant")

/datum/unit_test/dq_decl_cleanup_destroy/tunnel
/datum/unit_test/dq_decl_cleanup_destroy/tunnel/Run()
	scope_fixture()
	var/turf/T = test_floor()
	var/obj/structure/micro_tunnel/dq_decl_cleanup_capture/O = allocate(/obj/structure/micro_tunnel/dq_decl_cleanup_capture, T)
	var/list/messages = list()
	O.captured_messages = messages
	var/mob/living/carbon/human/dq_decl_cleanup_subject/H = allocate(/mob/living/carbon/human/dq_decl_cleanup_subject, T)
	H.forceMove(O)
	var/before = H.camera_cancels
	TEST_ASSERT_EQUAL(H.loc, O, "the tunnel contains the micro")
	qdel(O)
	TEST_ASSERT(!QDELETED(H), "tunnel destruction preserves the micro")
	TEST_ASSERT_EQUAL(H.loc, T, "tunnel collapse puts the micro on its turf")
	TEST_ASSERT(H.camera_cancels > before, "tunnel collapse cancels its camera")
	TEST_ASSERT(findtext(jointext(messages, "\n"), "tumbles out"), "the real collapse emits its tumble effect")

/datum/unit_test/dq_decl_cleanup_destroy/ventcrawler
/datum/unit_test/dq_decl_cleanup_destroy/ventcrawler/Run()
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

/datum/unit_test/dq_decl_cleanup_destroy/statue
/datum/unit_test/dq_decl_cleanup_destroy/statue/Run()
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
// Legacy destruction spills the subject before its late callback can release
// mute/stasis. This separate regression covers the native ending-phase repair.

/datum/unit_test/dq_decl_cleanup_destroy/statue_releases_stasis
/datum/unit_test/dq_decl_cleanup_destroy/statue_releases_stasis/Run()
	scope_fixture()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/structure/closet/statue/S = allocate(/obj/structure/closet/statue, T, H)
	TEST_ASSERT(H.sdisabilities & MUTE, "the real constructor installs petrification mute")
	TEST_ASSERT(act_wanted(H, /datum/act/injure), "the real constructor installs injury stasis")
	qdel(S)
	TEST_ASSERT(!(H.sdisabilities & MUTE), "statue destruction removes petrification mute")
	TEST_ASSERT(!act_wanted(H, /datum/act/injure), "statue destruction removes actual injury stasis")

/datum/unit_test/dq_decl_cleanup_destroy/belly
/datum/unit_test/dq_decl_cleanup_destroy/belly/Run()
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

/datum/unit_test/dq_decl_cleanup_destroy/gargoyle
/datum/unit_test/dq_decl_cleanup_destroy/gargoyle/Run()
	scope_fixture()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	H.set_dir(EAST)
	var/expected_integrity = H.vitality() * H.get_endurance() + 100
	var/obj/structure/gargoyle/dq_decl_cleanup_capture/S = allocate(/obj/structure/gargoyle/dq_decl_cleanup_capture, T, H, "canary", "granite", "solidifies", "#00FF00", FALSE, TRUE)
	var/list/messages = list()
	S.captured_messages = messages
	TEST_ASSERT_EQUAL(S.WR_gargoyle, H, "the real gargoyle constructor binds its subject")
	TEST_ASSERT(isnull(S.petrified), "constructor-only petrification input is dropped after initialization")
	TEST_ASSERT_EQUAL(H.loc, S, "the living subject occupies its statue before materialization returns")
	TEST_ASSERT_EQUAL(S.identifier, "canary", "the first param callback sees later constructor arguments")
	TEST_ASSERT_EQUAL(S.name, "canary of [H.name]", "the constructor builds the subject-specific appearance name")
	TEST_ASSERT_EQUAL(S.desc, "A very lifelike canary made of granite.", "the material override survives parent initialization")
	TEST_ASSERT_EQUAL(S.adjective, "solidifies", "the adjective override is bound before the subject is applied")
	TEST_ASSERT(!S.can_revert && S.discard_clothes, "the callback sees both later boolean constructor arguments")
	TEST_ASSERT_EQUAL(S.original_int, expected_integrity, "the subject-derived integrity survives the parent tail")
	TEST_ASSERT_EQUAL(S.max_integrity, H.get_endurance() + 100, "the base integrity initialization does not overwrite petrification")
	TEST_ASSERT(S.density, "an ordinary-sized subject produces a solid statue")
	TEST_ASSERT_EQUAL(S.dir, EAST, "the statue copies its subject orientation")
	TEST_ASSERT_EQUAL(S.layer, H.layer, "the statue copies its subject appearance layer")
	TEST_ASSERT_EQUAL(S.color, "#123456", "atom initialization preserves the statue fixture color")
	TEST_ASSERT(length(S.overlays), "petrification builds real human appearance overlays")
	qdel(S)
	TEST_ASSERT(findtext(jointext(messages, "\n"), "loses shape and crumbles"), "non-reverting gargoyle destruction emits the real crumble effect")

/datum/unit_test/dq_decl_cleanup_destroy/telecube
/datum/unit_test/dq_decl_cleanup_destroy/telecube/Run()
	scope_fixture()
	var/obj/item/telecube/C = allocate(/obj/item/telecube, test_floor())
	var/obj/item/telecube/dq_decl_cleanup_capture/M = allocate(/obj/item/telecube/dq_decl_cleanup_capture, test_floor())
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

/datum/unit_test/dq_decl_cleanup_destroy/crystal
/datum/unit_test/dq_decl_cleanup_destroy/crystal/Run()
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


/obj/dq_decl_cleanup_micro_holder/veto/lifecycle_keep(force)
	return !force

/datum/unit_test/dq_decl_cleanup_destroy/force_and_veto
/datum/unit_test/dq_decl_cleanup_destroy/force_and_veto/Run()
	scope_fixture()
	var/turf/T = test_floor()
	var/obj/dq_decl_cleanup_micro_holder/O = allocate(/obj/dq_decl_cleanup_micro_holder/veto, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	H.forceMove(O)
	qdel(O)
	TEST_ASSERT(!QDELETED(O), "the real lifecycle veto still preserves the holder")
	TEST_ASSERT_EQUAL(H.loc, O, "a vetoed ending cannot release occupants")
	qdel(O, TRUE)
	TEST_ASSERT(QDELETED(O), "forced deletion bypasses the native keep veto")
	TEST_ASSERT_EQUAL(H.loc, T, "the forced ending runs the same declared occupant release")
	TEST_ASSERT(!QDELETED(H), "forced release preserves the occupant")
