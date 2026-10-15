// A reference may create its first target without becoming its owner.
/datum/dq_decl_reference_target
	var/argument
	var/saw_first = FALSE
/datum/dq_decl_reference_target/New(obj/dq_decl_reference_holder/H, value)
	..()
	argument = value
	saw_first = value == "third" ? !!H?.fourth : !!H?.first

/obj/dq_decl_reference_holder
	var/datum/dq_decl_reference_target/first
	var/datum/dq_decl_reference_target/second
	var/datum/dq_decl_reference_target/third
	var/datum/dq_decl_reference_target/fourth
	var/datum/dq_decl_reference_target/plain
	var/obj/dq_decl_reference_rejected/rejected
	var/first_before_parent = FALSE

CAPABILITIES(/obj/dq_decl_reference_holder)
	ref_one(nameof(third), /datum/dq_decl_reference_target, starts = /datum/dq_decl_reference_target, starts_args = list("third"), starts_after = nameof(fourth))
	ref_one(nameof(fourth), /datum/dq_decl_reference_target, starts = /datum/dq_decl_reference_target, starts_args = list("fourth"))
	ref_one(nameof(second), /datum/dq_decl_reference_target, starts = /datum/dq_decl_reference_target, starts_args = list("second"), starts_after = nameof(first))
	ref_one(nameof(first), /datum/dq_decl_reference_target, starts = /datum/dq_decl_reference_target, starts_args = list("first"), early = TRUE)
	ref_one(nameof(plain), /datum/dq_decl_reference_target)
	ref_one(nameof(rejected), /obj/dq_decl_reference_rejected, starts = /obj/dq_decl_reference_rejected)

/obj/dq_decl_reference_holder/Initialize(mapload)
	first_before_parent = !!first
	return ..()

/obj/dq_decl_reference_rejected
CAPABILITIES(/obj/dq_decl_reference_rejected)
	keeps_if(FALSE)

/datum/unit_test/dq_decl_reference_starts
/datum/unit_test/dq_decl_reference_starts/Run()
	var/obj/dq_decl_reference_holder/H = allocate(/obj/dq_decl_reference_holder, test_floor())
	TEST_ASSERT(H.first_before_parent, "an early reference target exists before Initialize enters")
	TEST_ASSERT(istype(H.first) && istype(H.second), "both declared targets are constructed")
	var/first_had_owner = !!owner_of(H.first)
	var/second_had_owner = !!owner_of(H.second)
	own(H.first)
	own(H.second)
	own(H.third)
	own(H.fourth)
	TEST_ASSERT_EQUAL(H.first.argument, "first", "the early constructor receives its actual arguments")
	TEST_ASSERT_EQUAL(H.second.argument, "second", "the regular constructor receives its actual arguments")
	TEST_ASSERT(H.third.saw_first, "starts_after reorders reversed declarations within the same phase")
	TEST_ASSERT(H.second.saw_first, "starts_after observes the preceding constructed target")
	TEST_ASSERT_NULL(H.plain, "a plain reference without starts still allocates nothing")
	TEST_ASSERT_NULL(H.rejected, "a constructor rejected by keeps_if cannot fill the reference")
	TEST_ASSERT(!first_had_owner, "reference creation never stamps an owner")
	TEST_ASSERT(!second_had_owner, "the dependent reference remains non-owning")
	var/datum/dq_decl_reference_target/first = H.first
	var/datum/dq_decl_reference_target/second = H.second
	qdel(H)
	TEST_ASSERT(!QDELETED(first) && !QDELETED(second), "ending the referrer preserves independent targets")

/obj/dq_decl_parameter_setup
	var/payload
	var/list/trace
	var/datum/unit_test/dq_decl_parameter_setup/recorder
	var/parent_ready = FALSE
	var/refuse_creation = FALSE
	var/fail_setup = FALSE
CAPABILITIES(/obj/dq_decl_parameter_setup)
	param(nameof(payload), pos = 1, keep = FALSE)
	param(nameof(trace), pos = 2)
	param(nameof(recorder), pos = 3, keep = FALSE)
	ref_one(nameof(recorder), /datum/unit_test/dq_decl_parameter_setup)
	keeps_if(PROC_REF(creation_allowed))
	setup(PROC_REF(complete_constructor), with_params = TRUE)
	setup(PROC_REF(ordinary_setup))
/obj/dq_decl_parameter_setup/Initialize(mapload)
	. = ..()
	parent_ready = TRUE
/obj/dq_decl_parameter_setup/proc/creation_allowed()
	return !refuse_creation
/obj/dq_decl_parameter_setup/proc/complete_constructor()
	recorder?.capture_holder(src)
	add_trace("constructor:[payload]:[parent_ready]")
	if(fail_setup)
		CRASH("expected constructor-completion fixture fault")
/obj/dq_decl_parameter_setup/proc/ordinary_setup()
	add_trace("ordinary:[isnull(payload)]")
/obj/dq_decl_parameter_setup/rejected
	refuse_creation = TRUE
/obj/dq_decl_parameter_setup/fault
	fail_setup = TRUE

/datum/unit_test/dq_decl_parameter_setup
	var/obj/dq_decl_parameter_setup/captured_holder
CAPABILITIES(/datum/unit_test/dq_decl_parameter_setup)
	ref_one(nameof(captured_holder), /obj/dq_decl_parameter_setup)
/datum/unit_test/dq_decl_parameter_setup/proc/capture_holder(obj/dq_decl_parameter_setup/H)
	rel_set(src, nameof(captured_holder), H)

/datum/unit_test/dq_decl_parameter_setup/Run()
	var/list/trace = list()
	var/obj/dq_decl_parameter_setup/H = allocate(/obj/dq_decl_parameter_setup, test_floor(), 17, trace, src)
	TEST_ASSERT_EQUAL(H.trace[1], "constructor:17:1", "completion sees the transient input and the fully returned parent chain")
	TEST_ASSERT_EQUAL(H.trace[2], "ordinary:1", "ordinary setup still runs after the transient input is dropped")
	TEST_ASSERT_EQUAL(H.trace.len, 2, "each declared phase runs exactly once")
	TEST_ASSERT_NULL(H.payload, "constructor-only input is not retained")
	TEST_ASSERT(!(H in setup_pending), "completed setup leaves no pending holder")
	TEST_ASSERT(!(H in param_drop_pending), "completed params leave no pending holder")
	rel_clear(src, nameof(captured_holder))
	var/list/rejected = list()
	var/obj/dq_decl_parameter_setup/R = new /obj/dq_decl_parameter_setup/rejected(test_floor(), 23, rejected, src)
	if(R)
		own(R)
	TEST_ASSERT(QDELETED(R), "keeps_if still rejects construction")
	TEST_ASSERT_NULL(captured_holder, "rejected construction never enters completion setup")
	TEST_ASSERT(!rejected.len, "rejected construction runs neither setup phase")
	var/list/faulted = list()
	var/caught = FALSE
	try
		new /obj/dq_decl_parameter_setup/fault(test_floor(), 31, faulted, src)
	catch(var/exception/e)
		caught = TRUE
	var/obj/dq_decl_parameter_setup/F = captured_holder
	if(F)
		own(F)
	TEST_ASSERT(caught && F, "the real completion fault reaches its caller")
	TEST_ASSERT_NULL(F.payload, "a failed completion still releases transient inputs")
	TEST_ASSERT(!(F in setup_pending) && !(F in param_drop_pending), "a failed completion removes both pending indexes")
	TEST_ASSERT_EQUAL(F.trace.len, 1, "ordinary setup cannot run after failed completion")
