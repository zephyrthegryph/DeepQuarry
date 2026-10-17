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
	TEST_ASSERT(findtext("[why]", "fastened down"), "and the reason is the requirement's: [why]")

/datum/unit_test/dq_slot_admission_fits_comes_after_accepts

/datum/unit_test/dq_slot_admission_fits_comes_after_accepts/Run()
	var/turf/T = test_floor()
	var/obj/adm_fixture/holder = allocate(/obj/adm_fixture, T)
	var/obj/item/flashlight/lamp = allocate(/obj/item/flashlight, T)
	var/obj/item/storage/backpack/pack = allocate(/obj/item/storage/backpack, T)
	TEST_ASSERT_NULL(dq_ledger_refusal(lamp, holder, "adm_fits", null), "a small thing fits")
	TEST_ASSERT_NOTNULL(dq_ledger_refusal(pack, holder, "adm_fits", null), "a large one does not")
	var/datum/relation_definition/slot/def = dq_ledger(holder).def_by_id("adm_fits")
	TEST_ASSERT_EQUAL(def.accepts_level(), REQ_READS_INSTANCE, "a size reads the candidate's own state: instance-level")
	var/datum/relation_definition/slot/types = dq_ledger(holder).def_by_id("adm_types")
	TEST_ASSERT_EQUAL(types.accepts_level(), REQ_READS_TYPE, "a type list alone is type-level")
	var/datum/relation_definition/slot/mixed = dq_ledger(holder).def_by_id("adm_mixed")
	TEST_ASSERT_EQUAL(mixed.accepts_level(), REQ_READS_INSTANCE, "a requirement that reads anchored makes the slot instance-level")

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
