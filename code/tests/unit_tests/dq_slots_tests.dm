// Slots and numeric handles (code/engine/refs/slots.dm): a slot is a whole number, a handle is slot + SLOT_SPAN * generation, and a handle taken before a
// datum was deleted never names whatever reuses its slot.

/datum/slot_probe

/// A datum's slot is stable and nonzero, and slot_datum() gives the datum back.
/datum/unit_test/dq_slots_identity/Run()
	var/datum/slot_probe/D = new
	var/id = slot_of(D)
	TEST_ASSERT(id > 0, "a datum takes a slot")
	TEST_ASSERT_EQUAL(slot_of(D), id, "and keeps it")
	TEST_ASSERT_EQUAL(slot_datum(id), D, "the slot names the datum back")
	var/datum/slot_probe/other = new
	TEST_ASSERT(slot_of(other) != id, "two live datums never share a slot")
	qdel(D)
	qdel(other)

/// A turf's slot is its position, negative, and needs no table.
/datum/unit_test/dq_slots_turf/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/id = slot_of(T)
	TEST_ASSERT(id < 0, "a turf's slot is negative")
	TEST_ASSERT_EQUAL(slot_datum(id), T, "and names the turf")
	TEST_ASSERT_EQUAL(slot_of(T), id, "stably")
	var/turf/next = get_step(T, EAST)
	TEST_ASSERT(isturf(next) && slot_of(next) != id, "and a neighbour has another")

/// The ABA case: a handle taken to a datum that was deleted never resolves to the datum that took its slot.
/datum/unit_test/dq_slots_aba/Run()
	var/datum/slot_probe/old = new
	var/old_handle = handle_of(old)
	var/old_text = ref_token(old)
	var/id = slot_of(old)
	TEST_ASSERT_EQUAL(handle_get(old_handle), old, "a handle resolves while its datum lives")
	TEST_ASSERT_EQUAL(resolve_token(old_text), old, "and so does its text")
	qdel(old)
	TEST_ASSERT_NULL(handle_get(old_handle), "a handle to a deleted datum resolves to nothing")
	var/datum/slot_probe/fresh = new
	TEST_ASSERT_EQUAL(slot_of(fresh), id, "the freed slot is the next one handed out")
	TEST_ASSERT_NULL(handle_get(old_handle), "the datum in the reused slot is not what the old handle names")
	TEST_ASSERT_NULL(resolve_token(old_text), "nor the old text")
	TEST_ASSERT_EQUAL(handle_get(handle_of(fresh)), fresh, "its own handle resolves")
	TEST_ASSERT(handle_of(fresh) != old_handle, "and differs from the old one")
	qdel(fresh)

/// A slot retires after its generation reaches SLOT_GEN_MAX: it is never handed out again, so a generation never wraps and no old handle can match it.
/datum/unit_test/dq_slots_retire/Run()
	var/datum/slot_probe/last = new
	var/id = slot_of(last)
	handle_gens[id] = SLOT_GEN_MAX // its 32nd life
	var/last_handle = handle_of(last)
	TEST_ASSERT(last_handle < 16777216, "the highest handle stays exact (under 2^24): [last_handle]")
	TEST_ASSERT_EQUAL(handle_get(last_handle), last, "and resolves")
	var/retired_before = slots_retired()
	qdel(last)
	TEST_ASSERT_EQUAL(slots_retired(), retired_before + 1, "freeing the slot at the last generation retires it")
	TEST_ASSERT(!(id in handle_free), "a retired slot is not offered for reuse")
	TEST_ASSERT_NULL(handle_get(last_handle), "and its last handle stops resolving")
	var/datum/slot_probe/next = new
	TEST_ASSERT(slot_of(next) != id, "the next datum takes another slot")
	qdel(next)

/// The numbers and the texts name the same datum, and a turf or client handle stays text.
/datum/unit_test/dq_slots_handle_forms/Run()
	var/datum/slot_probe/D = new
	var/h = handle_of(D)
	TEST_ASSERT(isnum(h), "a datum's handle is a number")
	TEST_ASSERT_EQUAL(handle_get(ref_token(D)), D, "handle_get reads the text form too")
	var/turf/T = run_loc_floor_bottom_left
	TEST_ASSERT(istext(handle_of(T)), "a turf's handle is its text")
	TEST_ASSERT_EQUAL(handle_get(handle_of(T)), T, "and resolves")
	TEST_ASSERT_NULL(handle_of(null), "nothing has no handle")
	qdel(D)
	TEST_ASSERT_NULL(handle_of(D), "a deleted datum has none")
