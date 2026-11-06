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
	var/old_text = "[old_handle]"
	var/id = slot_of(old)
	TEST_ASSERT_EQUAL(handle_get(old_handle), old, "a handle resolves while its datum lives")
	TEST_ASSERT_EQUAL(handle_get(old_text), old, "and so does its text")
	qdel(old)
	TEST_ASSERT_NULL(handle_get(old_handle), "a handle to a deleted datum resolves to nothing")
	var/datum/slot_probe/fresh = new
	TEST_ASSERT_EQUAL(slot_of(fresh), id, "the freed slot is the next one handed out")
	TEST_ASSERT_NULL(handle_get(old_handle), "the datum in the reused slot is not what the old handle names")
	TEST_ASSERT_NULL(handle_get(old_text), "nor the old text")
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
	TEST_ASSERT_EQUAL(handle_get("[handle_text(handle_of(D))]"), D, "handle_get reads the number's text form too")
	var/turf/T = run_loc_floor_bottom_left
	TEST_ASSERT(istext(handle_of(T)), "a turf's handle is its text")
	TEST_ASSERT_EQUAL(handle_get(handle_of(T)), T, "and resolves")
	TEST_ASSERT_NULL(handle_of(null), "nothing has no handle")
	qdel(D)
	TEST_ASSERT_NULL(handle_of(D), "a deleted datum has none")

/// Names a datum (it takes a slot) and drops it with no qdel(): only the slot table holds it when this returns.
/proc/slot_test_leak_one()
	var/datum/slot_probe/dropped = new
	slot_of(dropped)

/// A datum something names that is dropped without qdel() is a leak: the table still holds it, and the report counts it by type. One that is
/// still referenced, or that was qdel()ed, is not.
/datum/unit_test/dq_slots_leak_reported/Run()
	var/datum/slot_probe/held = new
	var/held_slot = slot_of(held)
	var/datum/slot_probe/deleted = new
	slot_of(deleted)
	qdel(deleted)
	var/before = slot_leak_report(log = FALSE)["/datum/slot_probe"] || 0
	slot_test_leak_one()
	var/list/leaks = slot_leaks()
	var/after = slot_leak_report(log = FALSE)["/datum/slot_probe"] || 0
	TEST_ASSERT_EQUAL(after, before + 1, "the dropped datum is reported by type, and only it")
	TEST_ASSERT(!(held_slot in leaks), "a datum something still references is not a leak")
	// Clean up what this test leaked on purpose: the datum goes free, the slot with it.
	for(var/id in leaks)
		if(id != held_slot && handle_types[id] == /datum/slot_probe)
			var/datum/dropped = handle_data[id]
			dropped.handle_slot = 0
			dropped = null
			slot_free(id)
	TEST_ASSERT_EQUAL(slot_leak_report(log = FALSE)["/datum/slot_probe"] || 0, before, "and once released it is no longer reported")
	qdel(held)

/// A handle from 1e6 on keeps every digit as text: "[h]" would give "1.04858e+06", handle_text() the whole number, and handle_get() reads it back.
/datum/unit_test/dq_slots_handle_text_high/Run()
	var/datum/slot_probe/D = new
	var/id = slot_of(D)
	handle_gens[id] = 3 // a slot in its fourth life: 3 * SLOT_SPAN + id is above 1.5 million
	var/h = handle_of(D)
	TEST_ASSERT(h > 1048577, "the handle is above 1048577: [h]")
	var/text = handle_text(h)
	TEST_ASSERT(istext(text) && !findtext(text, "e+") && !findtext(text, "."), "its text is whole digits: [text]")
	TEST_ASSERT_EQUAL(text2num(text), h, "and reads back as the same number")
	TEST_ASSERT_EQUAL(handle_get(text), D, "handle_get resolves the text")
	TEST_ASSERT_EQUAL(handle_get(h), D, "and the number")
	TEST_ASSERT_EQUAL(handle_text(handle_of(D)), text, "the helper wraps handle_of directly")
	var/list/by_key = list()
	by_key[handle_text(handle_of(D))] = TRUE // a text-keyed table, as the tracked lists that cannot be alists are
	TEST_ASSERT(by_key[text], "a text key made again finds the same entry")
	var/turf/T = run_loc_floor_bottom_left
	TEST_ASSERT_EQUAL(handle_text(handle_of(T)), handle_of(T), "a turf's text handle passes through unchanged")
	TEST_ASSERT_NULL(handle_text(null), "nothing is nothing")
	qdel(D)
	TEST_ASSERT_NULL(handle_get(text), "and the text stops resolving once the datum is deleted")

/// A handle stored in a var or a table and made into text later (a log key built from a token, an actor total keyed by a handle) keeps every digit too.
/datum/unit_test/dq_slots_stored_handle_text_high/Run()
	var/datum/slot_probe/D = new
	var/id = slot_of(D)
	handle_gens[id] = 3
	var/stored = handle_of(D) // kept in a var, read back by a proc that only gets the number
	TEST_ASSERT(stored > 1048577, "the stored handle is above 1048577: [stored]")
	set_global("dq_rule_recording", TRUE)
	GLOB.dq_rule_fire_log.Cut()
	var/datum/rule/rule = new /datum/rule/heat_behaviour/rag_ignites
	dq_rule_record_fire(D, rule)
	TEST_ASSERT_EQUAL(dq_rule_fire_count_of(stored, rule), 1, "a fire log read by the stored handle finds the entry written from the datum")
	TEST_ASSERT_EQUAL(dq_rule_fire_count(D, rule), 1, "and by the datum")
	set_global("dq_rule_recording", FALSE)
	GLOB.dq_rule_fire_log.Cut()
	var/list/totals = list()
	var/datum/slot_probe/E = new
	var/id_b = slot_of(E)
	handle_gens[id_b] = 3
	var/other = handle_of(E)
	totals["[handle_text(stored)]"] = 1
	totals["[handle_text(other)]"] = 2
	TEST_ASSERT_EQUAL(length(totals), 2, "two high handles stay two keys (6-digit text would merge neighbours)")
	qdel(E)
	qdel(D)
	qdel(rule)
