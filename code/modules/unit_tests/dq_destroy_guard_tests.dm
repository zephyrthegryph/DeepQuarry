// The teardown guard (code/datums/ownership/guard.dm) and the destroy transaction's declared
// step sequence (GLOB.destroy_step_sequence, code/datums/lifecycle/transaction.dm).

/datum/guard_test_holder
	var/datum/guard_test_child/child
	var/list/kids
	var/list/values
	var/datum/guard_test_child/view
	var/list/views
	var/datum/species/species
	var/datum/species/shared_species
	var/fired = 0

CAPABILITIES(/datum/guard_test_holder)
	owns_one(nameof(child))
	owns_many(nameof(kids))
	owns_many(nameof(values))

/datum/guard_test_holder/ownership()
	. = ..()
	. += rel_one(nameof(species), kind = RELK_OWNED, policy = OWN_PRIVATE_COPY)

/datum/guard_test_holder/proc/on_tick()
	fired++

/datum/guard_test_holder/proc/on_event()
	return

/datum/guard_test_child

/// Every acquiring accessor refuses when the holder or the target is being destroyed: nothing is
/// written, with a stack trace outside a destroy transaction and silently inside one.
/datum/unit_test/ownership_teardown_guard

/datum/unit_test/ownership_teardown_guard/Run()
	contents_case(FALSE)
	contents_case(TRUE)
	contents_phase_case()

/obj/item/storage/box/empty_guard_test
	starts_with = null

/datum/unit_test/ownership_teardown_guard/proc/contents_case(inside)
	for(var/dying_end in list("holder", "target"))
		var/obj/item/storage/box/holder = allocate(/obj/item/storage/box/empty_guard_test, run_loc_floor_bottom_left)
		var/obj/item/tool/wrench/thing = allocate(/obj/item/tool/wrench, run_loc_floor_bottom_left)
		TEST_ASSERT_NOTNULL(dq_ledger(holder), "the box keeps a ledger")
		var/datum/dying = dying_end == "holder" ? holder : thing
		var/list/capture = list()
		set_global("dq_lifecycle_report_capture", capture)
		dying.destroy_phase = LIFECYCLE_PHASE_LINKS
		if(inside)
			GLOB.destroy_transaction_depth++
		thing.forceMove(holder)
		var/adopted = holder.containment_ledger()?.entries[thing] ? TRUE : FALSE
		if(inside)
			GLOB.destroy_transaction_depth--
		dying.destroy_phase = 0
		set_global("dq_lifecycle_report_capture", null)
		thing.forceMove(run_loc_floor_bottom_left)
		TEST_ASSERT(!adopted, "contents adoption with the [dying_end] dying ([inside ? "inside" : "outside"] a transaction) took a slot")
		if(inside)
			TEST_ASSERT(!length(capture), "a teardown refusal of contents adoption is silent: [json_encode(capture)]")
		else
			TEST_ASSERT(length(capture), "a refusal of contents adoption outside a teardown is reported")

/// A holder in its own contents step (phase 3) still adopts: it materializes latent entries
/// into its slots to resolve them by policy. From its links phase on it refuses (above).
/datum/unit_test/ownership_teardown_guard/proc/contents_phase_case()
	var/obj/item/storage/box/holder = allocate(/obj/item/storage/box/empty_guard_test, run_loc_floor_bottom_left)
	var/obj/item/tool/wrench/thing = allocate(/obj/item/tool/wrench, run_loc_floor_bottom_left)
	TEST_ASSERT_NOTNULL(dq_ledger(holder), "the box keeps a ledger")
	holder.destroy_phase = LIFECYCLE_PHASE_CONTENTS
	GLOB.destroy_transaction_depth++
	thing.forceMove(holder)
	var/adopted = holder.containment_ledger()?.entries[thing] ? TRUE : FALSE
	GLOB.destroy_transaction_depth--
	holder.destroy_phase = 0
	thing.forceMove(run_loc_floor_bottom_left)
	TEST_ASSERT(adopted, "a holder in its contents step adopts what it materializes")

/obj/item/storage/box/empty_guard_test
	starts_with = null

/// The destroy transaction runs one declared sequence: every step once, phases never going
/// backwards (except the effects' second half after Destroy()), and the contents release check
/// right after the contents steps, before links dispose of the ledger.

/// The destroy transaction runs one declared sequence: every step once, phases never going
/// backwards (except the effects' second half after Destroy()), and the contents release check
/// right after the contents steps, before links dispose of the ledger.
/datum/unit_test/destroy_step_sequence

/datum/unit_test/destroy_step_sequence/Run()
	var/list/sequence = GLOB.destroy_step_sequence
	TEST_ASSERT_EQUAL(length(sequence), DESTROY_STEP_COUNT, "every step is declared once")
	for(var/step in 1 to DESTROY_STEP_COUNT)
		TEST_ASSERT_EQUAL(count_in(sequence, step), 1, "step [DESTROY_STEP_NAME(step)] appears exactly once")
	var/last_phase = 0
	for(var/step in sequence)
		var/phase = DESTROY_STEP_PHASE(step)
		if(step != DESTROY_STEP_EFFECTS_AFTER)
			TEST_ASSERT(phase >= last_phase, "step [DESTROY_STEP_NAME(step)] (phase [phase]) runs before a later phase ([last_phase])")
			last_phase = phase
	var/resolve = sequence.Find(DESTROY_STEP_CONTENTS_RESOLVE)
	var/spill = sequence.Find(DESTROY_STEP_CONTENTS_SPILL)
	var/check = sequence.Find(DESTROY_STEP_CONTENTS_CHECK_RELEASED)
	var/links = sequence.Find(DESTROY_STEP_LINKS)
	TEST_ASSERT(spill == resolve + 1 && check == spill + 1, "the release check follows the contents steps directly")
	TEST_ASSERT(check < links, "the release check runs before links dispose of the ledger")
	TEST_ASSERT(sequence.Find(DESTROY_STEP_GUARD) == 1, "the guard step runs first")
	// A real destroy walks the whole sequence.
	var/obj/item/storage/box/box = allocate(/obj/item/storage/box, run_loc_floor_bottom_left)
	qdel(box)
	TEST_ASSERT_EQUAL(box.destroy_phase, LIFECYCLE_PHASE_SCRUB, "a finished destroy transaction reached the scrub phase")

/datum/unit_test/destroy_step_sequence/proc/count_in(list/L, value)
	. = 0
	for(var/item in L)
		if(item == value)
			.++
