// The slot admission engine (doc/rewrite/proposals/admission.md D2c, D2d, D2e, D2h, D2i, D2j, D8): accepts that mixes a type list with requirements, fits,
// the replace policies, the stated order of reasons, the actorless contract, the authority grant and the type-level or instance-level answer.
// Fixtures: code/tests/engine/adm_fixtures.dm.

/datum/unit_test/dq_slot_admission_accepts_mixes_types_and_requirements

/datum/unit_test/dq_slot_admission_accepts_mixes_types_and_requirements/Run()
	var/turf/T = test_floor()
	var/obj/adm_fixture/holder = allocate(/obj/adm_fixture, T)
	var/obj/item/flashlight/lamp = allocate(/obj/item/flashlight, T)
	var/obj/item/paper/page = allocate(/obj/item/paper, T)
	var/obj/item/storage/backpack/pack = allocate(/obj/item/storage/backpack, T)
	TEST_ASSERT_NULL(dq_ledger_refusal(lamp, holder, "adm_mixed", null), "a loose flashlight passes both the type list and the requirement")
	TEST_ASSERT_NULL(dq_ledger_refusal(page, holder, "adm_mixed", null), "so does a loose paper (the list is a set of types)")
	TEST_ASSERT_NOTNULL(dq_ledger_refusal(pack, holder, "adm_mixed", null), "a backpack is not one of the types")
	lamp.set_anchored(TRUE)
	var/why = dq_ledger_refusal(lamp, holder, "adm_mixed", null)
	TEST_ASSERT_NOTNULL(why, "an anchored flashlight is the right type but fails the requirement")
	TEST_ASSERT_EQUAL(why, reason_text(/datum/msg/slot/fastened_down), "and the reason is the requirement's, as text")

/datum/unit_test/dq_slot_admission_fits_comes_after_accepts

/datum/unit_test/dq_slot_admission_fits_comes_after_accepts/Run()
	var/turf/T = test_floor()
	var/obj/adm_fixture/holder = allocate(/obj/adm_fixture, T)
	var/obj/item/flashlight/lamp = allocate(/obj/item/flashlight, T)
	var/obj/item/storage/backpack/pack = allocate(/obj/item/storage/backpack, T)
	TEST_ASSERT_NULL(dq_ledger_refusal(lamp, holder, "adm_fits", null), "a small thing fits")
	TEST_ASSERT_NOTNULL(dq_ledger_refusal(pack, holder, "adm_fits", null), "a large one does not")
	var/datum/relation_definition/slot/def = dq_ledger(holder).def_by_id("adm_fits")
	TEST_ASSERT_EQUAL(def.accepts_level(), REQ_READS_TYPE, "a size class is type data: a pristine instance answers it (D8)")
	var/datum/relation_definition/slot/types = dq_ledger(holder).def_by_id("adm_types")
	TEST_ASSERT_EQUAL(types.accepts_level(), REQ_READS_TYPE, "a type list alone is type-level")
	var/datum/relation_definition/slot/mixed = dq_ledger(holder).def_by_id("adm_mixed")
	TEST_ASSERT_EQUAL(mixed.accepts_level(), REQ_READS_TYPE, "req_loose() is type-level for the items and structures latent holders keep (D8)")

/datum/unit_test/dq_slot_admission_replace_policies

/datum/unit_test/dq_slot_admission_replace_policies/Run()
	var/turf/T = test_floor()
	var/obj/adm_fixture/holder = allocate(/obj/adm_fixture, T)
	var/obj/item/flashlight/lamp = allocate(/obj/item/flashlight, T)
	var/obj/item/paper/page = allocate(/obj/item/paper, T)
	var/obj/item/storage/backpack/pack = allocate(/obj/item/storage/backpack, T)
	// REPLACE: a newcomer takes the place of the occupant, which goes to where the newcomer was.
	TEST_ASSERT(move_into(holder, "adm_swap", lamp), "the first thing fills the slot")
	TEST_ASSERT(move_into(holder, "adm_swap", page), "a second replaces it")
	TEST_ASSERT(page.loc == holder, "the newcomer is in")
	TEST_ASSERT(lamp.loc == T, "the occupant went to the floor the newcomer came from")
	TEST_ASSERT_EQUAL(length(holder.slot_contents("adm_swap")), 1, "one occupant")
	// REPLACE_IF_BETTER by w_class: only a bigger thing displaces.
	TEST_ASSERT(move_into(holder, "adm_best", lamp), "the flashlight goes in")
	TEST_ASSERT(move_into(holder, "adm_best", pack), "a bigger backpack displaces it")
	TEST_ASSERT(pack.loc == holder && lamp.loc == T, "the backpack is in, the flashlight is out")
	TEST_ASSERT(!move_into(holder, "adm_best", lamp), "the smaller flashlight no longer displaces the backpack")
	TEST_ASSERT(pack.loc == holder, "and the backpack stays")

/datum/unit_test/dq_slot_admission_actorless_checks

/datum/unit_test/dq_slot_admission_actorless_checks/Run()
	var/turf/T = test_floor()
	var/obj/adm_fixture/holder = allocate(/obj/adm_fixture, T)
	var/obj/item/flashlight/lamp = allocate(/obj/item/flashlight, T)
	// No actor means a system mover (a conveyor, Cross): the actor-gated parts hold.
	var/list/gated = list(req_capable(), req_adjacent(), req_self(), req_access(), req_conscious(), req_alive())
	var/datum/act/op/A = take(/datum/act/op)
	A.holder = holder
	A.target = lamp
	for(var/datum/entry/part/req/R as anything in gated)
		TEST_ASSERT(R.reads_actor, "[R.part_name] declares that it reads the actor")
		TEST_ASSERT(R.holds(A), "[R.part_name] holds with no actor")
	A.release()

/datum/unit_test/dq_slot_admission_authority_grant

/datum/unit_test/dq_slot_admission_authority_grant/Run()
	var/turf/T = test_floor()
	var/obj/adm_fixture/from = allocate(/obj/adm_fixture, T)
	var/obj/adm_fixture/to = allocate(/obj/adm_fixture, T)
	var/obj/item/flashlight/lamp = allocate(/obj/item/flashlight, T)
	TEST_ASSERT(move_into(from, "adm_types", lamp), "the flashlight is in the first holder")
	TEST_ASSERT(!from.slot_transfer(lamp, to, "adm_papers", null), "the papers slot refuses a flashlight")
	var/datum/authority_grant/granted = admin_authority(null, "unit test")
	TEST_ASSERT(from.slot_transfer(lamp, to, "adm_papers", null, authority = granted), "a granted admin authority forces it")
	TEST_ASSERT(lamp.loc == to, "and it landed")

/datum/unit_test/dq_slot_admission_equip_action

/datum/unit_test/dq_slot_admission_equip_action/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/wearer = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/dresser = allocate(/mob/living/carbon/human, T)
	var/obj/item/clothing/head/soft/adm_fixture/hat = allocate(/obj/item/clothing/head/soft/adm_fixture, T)
	// The item's extend(/datum/act/equip, needs(...)) runs last, with the real actor (a stripper is judged as himself, not as the victim).
	TEST_ASSERT_NULL(hat.equip_refusal(wearer, SLOT_ID_HEAD, TRUE), "the wearer may put the hat on")
	TEST_ASSERT_EQUAL(hat.equip_refusal(wearer, SLOT_ID_HEAD, TRUE, actor = dresser), reason_text(/datum/msg/adm/dress_yourself), "someone else putting it on is refused by the hat's own rule")
	TEST_ASSERT(!wearer.equip_to_slot_if_possible(hat, SLOT_ID_HEAD, disable_warning = TRUE, actor = dresser), "the strip-equip path passes the dresser")
	TEST_ASSERT(wearer.equip_to_slot_if_possible(hat, SLOT_ID_HEAD, disable_warning = TRUE), "the wearer dresses himself")
	TEST_ASSERT_EQUAL(wearer.get_equipped_item(SLOT_ID_HEAD), hat, "and wears it")

/datum/unit_test/dq_slot_admission_req_removable

/datum/unit_test/dq_slot_admission_req_removable/Run()
	var/turf/T = test_floor()
	var/obj/item/clothing/head/soft/cap = allocate(/obj/item/clothing/head/soft, T)
	var/datum/entry/part/req/take_off = req_removable()
	var/datum/entry/part/req/strip_off = req_removable(strip = TRUE)
	var/datum/act/op/A = take(/datum/act/op)
	A.held = cap
	TEST_ASSERT(take_off.holds(A), "an ordinary cap comes off")
	cap.flags |= NOSTRIP
	TEST_ASSERT(take_off.holds(A), "NOSTRIP does not stop its wearer")
	TEST_ASSERT(!strip_off.holds(A), "but it stops a stripper")
	TEST_ASSERT_EQUAL(strip_off.refusal(A), /datum/msg/slot/not_strippable, "with the strip reason")
	cap.set_canremove(FALSE)
	TEST_ASSERT(!take_off.holds(A), "canremove = FALSE keeps it on")
	TEST_ASSERT_EQUAL(take_off.refusal(A), /datum/msg/slot/not_removable, "with the removal reason")
	A.release()

/datum/unit_test/dq_slot_admission_with_reason

/datum/unit_test/dq_slot_admission_with_reason/Run()
	// A variadic proc refuses a named argument it does not declare ("bad arg name"), so any_of(..., because =) cannot exist: with_reason() gives a
	// combinator its reason.
	var/datum/entry/part/req/R = with_reason(any_of(req_self_held(), req_empty_hand()), MSG(slot/too_big_for_pocket))
	var/datum/act/op/A = take(/datum/act/op)
	var/obj/item/flashlight/lamp = allocate(/obj/item/flashlight, test_floor())
	A.held = lamp
	A.target = test_floor()
	TEST_ASSERT(!R.holds(A), "neither member holds")
	TEST_ASSERT_EQUAL(R.refusal(A), /datum/msg/slot/too_big_for_pocket, "the wrapper's reason replaces the joined ones")
	A.target = lamp
	TEST_ASSERT(R.holds(A), "a member holds, so the wrapper holds")
	A.release()

/datum/unit_test/dq_slot_admission_message_instance

/datum/unit_test/dq_slot_admission_message_instance/Run()
	var/datum/msg/instance/M = msg_reason("the gloves are in the way")
	TEST_ASSERT_EQUAL(reason_text(M), "the gloves are in the way", "an instance reads as its text")
	TEST_ASSERT_EQUAL(req_refusal_value(M), M, "a requirement may return an instance")

/datum/unit_test/dq_slot_admission_requirement_reason

/datum/unit_test/dq_slot_admission_requirement_reason/Run()
	var/obj/adm_fixture/holder = allocate(/obj/adm_fixture, test_floor())
	var/datum/entry/part/req/R = req(TYPE_PROC_REF(/obj/adm_fixture, takes_paper_type))
	TEST_ASSERT_NULL(requirement_reason(R, holder, /obj/item/paper), "a type path is asked without making the thing")
	TEST_ASSERT_EQUAL(requirement_reason(R, holder, /obj/item/flashlight), /datum/msg/adm/papers_only, "and refused with the requirement's reason")
	var/obj/item/paper/page = allocate(/obj/item/paper, test_floor())
	TEST_ASSERT_NULL(requirement_reason(R, holder, page), "an instance is asked the same way")

/// D8: a holder that keeps latent contents admits by type: every slot of the latent holder roots answers from type data alone.
/datum/unit_test/dq_slot_admission_latent_holders_type_level

/datum/unit_test/dq_slot_admission_latent_holders_type_level/Run()
	var/list/holders = list(/obj/structure/closet, /obj/item/storage/box, /obj/machinery/vending)
	for(var/path in holders)
		var/atom/H = allocate(path, test_floor())
		TEST_ASSERT(H.latent_contents_enabled(), "[path] keeps latent contents")
		for(var/datum/relation_definition/slot/def as anything in dq_slot_defs_for(H))
			TEST_ASSERT(def.accepts_level() <= REQ_READS_TYPE, "[path] slot [def.slot_id] admits by type, so latent entries are judged without making them")
