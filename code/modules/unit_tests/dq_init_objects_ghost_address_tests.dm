// Observe the real protocol transaction without fabricating a client/key.
/datum/exonet_protocol/dq_init_ghost_address_capture
	var/address_input

/datum/exonet_protocol/dq_init_ghost_address_capture/make_address(string)
	address_input = string
	return ..()

/mob/observer/dead/dq_init_address_probe

CAPABILITIES(/mob/observer/dead/dq_init_address_probe)
	owns_one(nameof(exonet), /datum/exonet_protocol, starts = /datum/exonet_protocol/dq_init_ghost_address_capture)

/datum/unit_test/dq_init_objects_ghost_address

/datum/unit_test/dq_init_objects_ghost_address/Run()
	dq_init_objects_fixture_scope()
	var/mob/living/carbon/human/body = allocate(/mob/living/carbon/human, test_floor())
	var/mob/observer/dead/dq_init_address_probe/G = allocate(/mob/observer/dead/dq_init_address_probe, body)
	var/datum/exonet_protocol/dq_init_ghost_address_capture/P = G.exonet
	TEST_ASSERT(istype(P), "the actual ghost owns its real starting protocol datum")
	TEST_ASSERT_EQUAL(P.holder(), G, "the protocol's real holder is the ghost")
	TEST_ASSERT_EQUAL(P.address_input, "communicator-[G.key]-[G.real_name]", "the actual headless address transaction uses the ghost's final parent-initialized identity")
	TEST_ASSERT(length(P.address), "the constructor creates a real nonempty Exonet address")
	TEST_ASSERT_EQUAL(P.get_atom_from_address(P.address), G, "the real address registry resolves the exact ghost")
	TEST_ASSERT_EQUAL(G.loc, get_turf(body), "ghost setup does not disturb the parent body's final spawn location")
	TEST_ASSERT_EQUAL(G.visualnet, GLOB.ghostnet, "ghost setup preserves its real parent-initialized visibility network")
	var/address = P.address
	var/datum/exonet_protocol/lookup = allocate(/datum/exonet_protocol)
	qdel(G)
	TEST_ASSERT(QDELETED(P), "deleting the ghost still deletes its owned starting protocol")
	TEST_ASSERT_NULL(lookup.get_atom_from_address(address), "ghost destruction removes its actual address registration")
	TEST_ASSERT(!QDELETED(body), "the ghost does not own/delete the living body used for its appearance and spawn location")
