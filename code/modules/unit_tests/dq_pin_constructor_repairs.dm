// Typed-reference declarations must preserve the constructors' absence cases.
/datum/unit_test/dq_pin_constructor_repairs
	abstract_type = /datum/unit_test/dq_pin_constructor_repairs

/datum/unit_test/dq_pin_constructor_repairs/New()
	..()
	dview(0, test_floor())
	status_policies()

/datum/unit_test/dq_pin_constructor_repairs/proc/scope_fixture()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	set_global(nameof(GLOB.act_taken), GLOB.act_taken)

/datum/unit_test/dq_pin_constructor_repairs/internal_storage
/datum/unit_test/dq_pin_constructor_repairs/internal_storage/Run()
	scope_fixture()
	var/turf/T = test_floor()
	var/obj/item/storage/internal/invalid = allocate(/obj/item/storage/internal, T)
	TEST_ASSERT(QDELETED(invalid), "a floor spawn is rejected without a typed-reference runtime")
	var/obj/item/owner = allocate(/obj/item/pen, T)
	var/obj/item/storage/internal/valid = allocate(/obj/item/storage/internal, owner)
	TEST_ASSERT(!QDELETED(valid), "an actual item owner is accepted")
	TEST_ASSERT_EQUAL(valid.loc, owner, "the internal storage stays inside its owner")
	TEST_ASSERT_EQUAL(valid.master_item(), owner, "the native setup links the exact supplied item")
	TEST_ASSERT_EQUAL(valid.name, owner.name, "construction copies the owner's name before returning")
	var/obj/item/storage/internal/gripper/pocket = allocate(/obj/item/storage/internal/gripper, owner)
	TEST_ASSERT_EQUAL(pocket.master_item(), owner, "the real gripper-pocket subtype inherits the same link")
	TEST_ASSERT_EQUAL(pocket.name, owner.name, "the gripper pocket is named before its creator resumes")
	qdel(valid)
	TEST_ASSERT(!QDELETED(owner), "the reference does not make its item owner an owned child")

/datum/unit_test/dq_pin_constructor_repairs/cloning_scanner
/datum/unit_test/dq_pin_constructor_repairs/cloning_scanner/Run()
	scope_fixture()
	var/turf/T = test_floor()
	var/obj/machinery/computer/cloning/C = allocate(/obj/machinery/computer/cloning, T)
	TEST_ASSERT(!QDELETED(C), "a console without a scanner survives its real constructor")
	TEST_ASSERT_NULL(C.findscanner(), "an absent scanner is null rather than numeric zero")
	TEST_ASSERT_NULL(C.scanner(), "the typed reference is empty without a scanner")
	var/obj/machinery/dna_scannernew/S = allocate(/obj/machinery/dna_scannernew, get_step(T, EAST))
	C.updatemodules()
	TEST_ASSERT_EQUAL(C.findscanner(), S, "the real lookup finds an adjacent scanner")
	TEST_ASSERT_EQUAL(C.scanner(), S, "module refresh links that exact scanner")
	qdel(S)
	C.updatemodules()
	TEST_ASSERT_NULL(C.scanner(), "refresh after scanner deletion preserves a valid empty relation")
