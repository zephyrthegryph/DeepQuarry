// Construction assertions precede migration: real factories, no direct setup calls.
/datum/unit_test/dq_decl_remaining
	abstract_type = /datum/unit_test/dq_decl_remaining

/datum/unit_test/dq_decl_remaining/New()
	..()
	dview(0, test_floor())
	status_policies()

/datum/unit_test/dq_decl_remaining/proc/scope_fixture()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	set_global(nameof(GLOB.act_taken), GLOB.act_taken)

/obj/item/dq_decl_hidden_item
	init_hide_identity = TRUE

/datum/unit_test/dq_decl_remaining/identity
/datum/unit_test/dq_decl_remaining/identity/Run()
	scope_fixture()
	var/obj/item/hidden = allocate(/obj/item/dq_decl_hidden_item, test_floor())
	var/obj/item/plain = allocate(/obj/item, test_floor())
	TEST_ASSERT(istype(hidden.identity, /datum/identification), "a concealed item constructs its identification datum")
	TEST_ASSERT_EQUAL(owner_of(hidden.identity), hidden, "the item owns its identification")
	TEST_ASSERT_NULL(plain.identity, "an ordinary item does not allocate identification")
	var/datum/identification/I = hidden.identity
	qdel(hidden)
	TEST_ASSERT(QDELETED(I), "identification ends with the concealed item")

/datum/unit_test/dq_decl_remaining/body
/datum/unit_test/dq_decl_remaining/body/Run()
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

/datum/frame/frame_types/computer/dq_decl_supplied
	circuit = /obj/item/circuitboard/teleporter

/datum/unit_test/dq_decl_remaining/frame
/datum/unit_test/dq_decl_remaining/frame/Run()
	scope_fixture()
	var/datum/frame/frame_types/F = allocate(/datum/frame/frame_types/computer/dq_decl_supplied)
	var/obj/structure/frame/placed = allocate(/obj/structure/frame, test_floor(), SOUTH, TRUE, F)
	var/obj/structure/frame/empty = allocate(/obj/structure/frame, test_floor())
	TEST_ASSERT(placed.frame_type != F, "the placed frame owns a private copy of its definition")
	TEST_ASSERT_EQUAL(placed.frame_type.circuit, F.circuit, "the private definition retains its circuit type")
	TEST_ASSERT_EQUAL(placed.circuit.type, F.circuit, "the placed frame starts with its specified physical circuit")
	TEST_ASSERT_EQUAL(placed.circuit.loc, placed, "the starting circuit is inside the frame")
	TEST_ASSERT(!placed.need_circuit, "the starting circuit satisfies the construction step")
	TEST_ASSERT_NULL(empty.circuit, "an unbuilt frame does not create a circuit")

/obj/item/gun/energy/dq_decl_no_cell
	cell_type = null
/obj/item/gun/energy/dq_decl_self_recharging
	cell_type = null
	self_recharge = TRUE
/obj/item/gun/energy/dq_decl_random_charge
	random_start_ammo = TRUE

/datum/unit_test/dq_decl_remaining/energy
/datum/unit_test/dq_decl_remaining/energy/Run()
	scope_fixture()
	var/obj/item/gun/energy/normal = allocate(/obj/item/gun/energy, test_floor())
	var/obj/item/gun/energy/absent = allocate(/obj/item/gun/energy/dq_decl_no_cell, test_floor())
	var/obj/item/gun/energy/recharging = allocate(/obj/item/gun/energy/dq_decl_self_recharging, test_floor())
	var/obj/item/gun/energy/rolled = allocate(/obj/item/gun/energy/dq_decl_random_charge, test_floor())
	TEST_ASSERT(istype(normal.power_supply, /obj/item/cell/device/weapon), "an ordinary energy gun gets its declared cell")
	TEST_ASSERT_EQUAL(normal.power_supply.loc, normal, "the cell is a real spatial child")
	TEST_ASSERT_NULL(absent.power_supply, "a gun without a cell type starts empty")
	TEST_ASSERT(istype(recharging.power_supply, /obj/item/cell/device/weapon), "self recharge supplies the standard cell even when cell_type is null")
	TEST_ASSERT(rolled.power_supply.charge >= 0 && rolled.power_supply.charge <= rolled.power_supply.maxcharge, "random starting charge is bounded by the actual cell")
	TEST_ASSERT_EQUAL(rolled.power_supply.charge % rolled.charge_cost, 0, "starting charge is rolled in complete shots")
	var/obj/item/cell/C = normal.power_supply
	qdel(normal)
	TEST_ASSERT(QDELETED(C), "the gun's spatial contents dispose of its starting cell")

/// Real pAI teardown may damage its card and emit sparks; own those actual
/// products before the fixture's general object cleanup, including on assertion failure.
/datum/unit_test/dq_decl_remaining/proc/clean_flipper(obj/item/paicard/flipper/F, turf/T, list/prior)
	if(!QDELETED(F))
		if(!QDELETED(F.pai))
			qdel(F.pai)
		qdel(F)
	for(var/obj/effect/effect/sparks/S in range(3, T))
		if(!(S in prior))
			own(S)

/datum/unit_test/dq_decl_remaining/flipper
/datum/unit_test/dq_decl_remaining/flipper/Run()
	scope_fixture()
	var/turf/T = test_floor()
	var/list/prior = list()
	for(var/obj/effect/effect/sparks/S in range(3, T))
		prior += S
	var/obj/item/paicard/flipper/F = allocate(/obj/item/paicard/flipper, T)
	defer_cleanup(src, TYPE_PROC_REF(/datum/unit_test/dq_decl_remaining, clean_flipper), F, T, prior)
	for(var/obj/effect/effect/sparks/S in T)
		if(!(S in prior))
			own(S)
	TEST_ASSERT(istype(F.pai, /mob/living/silicon/pai/flipper), "the real flipper card creates its special pAI")
	own(F.pai)
	TEST_ASSERT_EQUAL(F.pai.card, F, "the child binds the supplied card instead of making another")
	TEST_ASSERT(!F.emagged, "the pre-passenger emag attempt declines without subverting the card")
	TEST_ASSERT(!is_emagged(F), "the declined attempt does not publish native emag state")
	TEST_ASSERT_EQUAL(F.current_emotion, 16, "the inherited zero-delay card policy settles after the flipper initialization emotion")

/datum/unit_test/dq_decl_remaining/telecube
/datum/unit_test/dq_decl_remaining/telecube/Run()
	scope_fixture()
	var/turf/T = test_floor()
	var/obj/item/telecube/C = allocate(/obj/item/telecube/precursor/mated/mirrorcolor, T)
	defer_cleanup(C, TYPE_PROC_REF(/atom/movable, moveToNullspace))
	var/obj/item/telecube/M = C.mate()
	if(M)
		defer_cleanup(M, TYPE_PROC_REF(/atom/movable, moveToNullspace))
	TEST_ASSERT(istype(M), "the mated subtype creates a real peer")
	own(M)
	TEST_ASSERT_EQUAL(M.loc, T, "the peer is placed beside the original, not inside it")
	TEST_ASSERT_EQUAL(M.mate(), C, "the constructed peer pairs back")
	TEST_ASSERT_EQUAL(lowertext(M.glow_color), lowertext(C.color), "mirror mode swaps the glow with the original surface")
	TEST_ASSERT_EQUAL(lowertext(M.color), lowertext(C.glow_color), "mirror mode swaps the surface with the original glow")
	M.moveToNullspace()
	qdel(C)
	TEST_ASSERT(!QDELETED(M), "an independent peer survives the original ending")
	TEST_ASSERT_NULL(M.mate(), "ending the original clears the reverse peer link")

/datum/unit_test/dq_decl_remaining/mmi
/datum/unit_test/dq_decl_remaining/mmi/Run()
	scope_fixture()
	var/obj/item/organ/internal/mmi_holder/loose = allocate(/obj/item/organ/internal/mmi_holder, test_floor())
	TEST_ASSERT_NULL(loose.stored_mmi, "an ownerless organ does not allocate a brain")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/organ/internal/brain/old = H.organ_in(O_BRAIN)
	old?.removed()
	qdel(old)
	var/obj/item/mmi/M = allocate(/obj/item/mmi, test_floor())
	var/obj/item/organ/internal/mmi_holder/holder = install_mmi_holder(H, M)
	TEST_ASSERT_EQUAL(H.organ_in(O_BRAIN), holder, "the real organ attachment completes before adopting the MMI")
	TEST_ASSERT_EQUAL(holder.stored_mmi, M, "the supplied MMI is adopted instead of replaced")
	TEST_ASSERT_EQUAL(M.loc, holder, "the supplied MMI moves inside its holder")
	TEST_ASSERT_NULL(holder.installed_mmi, "the transient MMI argument is dropped after completion")
	var/count = 0
	for(var/obj/item/mmi/brain in contents_of(holder))
		count++
	TEST_ASSERT_EQUAL(count, 1, "adoption does not allocate a duplicate brain")
