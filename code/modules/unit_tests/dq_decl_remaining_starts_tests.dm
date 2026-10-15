// Construction assertions precede migration: real factories, no direct setup calls.
/datum/unit_test/dq_decl_starts
	abstract_type = /datum/unit_test/dq_decl_starts

/datum/unit_test/dq_decl_starts/New()
	..()
	dview(0, test_floor())
	status_policies()

/datum/unit_test/dq_decl_starts/proc/scope_fixture()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	set_global(nameof(GLOB.act_taken), GLOB.act_taken)

/obj/item/dq_decl_hidden_item
	init_hide_identity = TRUE

/datum/unit_test/dq_decl_starts/identity
/datum/unit_test/dq_decl_starts/identity/Run()
	scope_fixture()
	var/obj/item/hidden = allocate(/obj/item/dq_decl_hidden_item, test_floor())
	var/obj/item/plain = allocate(/obj/item, test_floor())
	TEST_ASSERT(istype(hidden.identity, /datum/identification), "a concealed item constructs its identification datum")
	TEST_ASSERT_EQUAL(owner_of(hidden.identity), hidden, "the item owns its identification")
	TEST_ASSERT_NULL(plain.identity, "an ordinary item does not allocate identification")
	var/datum/identification/I = hidden.identity
	qdel(hidden)
	TEST_ASSERT(QDELETED(I), "identification ends with the concealed item")

/datum/unit_test/dq_decl_starts/body
/datum/unit_test/dq_decl_starts/body/Run()
	scope_fixture()
	var/mob/living/simple_mob/M = allocate(/mob/living/simple_mob, test_floor())
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	TEST_ASSERT(istype(M.body, /datum/body/simple), "a simple mob receives its declared simple body")
	TEST_ASSERT_EQUAL(owner_of(M.body), M, "the simple mob owns its body")
	TEST_ASSERT_EQUAL(H.body.type, H.species.body_plan, "human species construction keeps the species body plan")
	TEST_ASSERT_EQUAL(owner_of(H.body), H, "the human keeps ownership of its species-created body")
	var/datum/body/B = M.body
	qdel(M)
	TEST_ASSERT(QDELETED(B), "the body ends with its mob")

/datum/unit_test/dq_decl_starts/frame
/datum/unit_test/dq_decl_starts/frame/Run()
	scope_fixture()
	var/datum/frame/frame_types/F = allocate(/datum/frame/frame_types/computer)
	var/obj/structure/frame/placed = allocate(/obj/structure/frame, test_floor(), SOUTH, TRUE, F)
	var/obj/structure/frame/empty = allocate(/obj/structure/frame, test_floor())
	TEST_ASSERT(placed.frame_type != F, "the placed frame owns a private copy of its definition")
	TEST_ASSERT_EQUAL(placed.frame_type.circuit, F.circuit, "the private definition retains its circuit type")
	if(F.circuit)
		TEST_ASSERT_EQUAL(placed.circuit.type, F.circuit, "the placed frame starts with its specified physical circuit")
		TEST_ASSERT_EQUAL(placed.circuit.loc, placed, "the starting circuit is inside the frame")
		TEST_ASSERT(!placed.need_circuit, "the starting circuit satisfies the construction step")
	TEST_ASSERT_NULL(empty.circuit, "an unbuilt frame does not create a circuit")
