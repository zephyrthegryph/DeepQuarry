// A gas mixture handle is a plain slot or cell number; the generation next to it is what stops a datum that outlived its
// mixture from reading or writing whatever reuses the slot (verdigris/ffi/src/gas/mix.rs, "Generations").

/datum/unit_test/dq_gas_handle_generation
	abstract_type = /datum/unit_test/dq_gas_handle_generation

/datum/unit_test/dq_gas_handle_generation/proc/read_o2(datum/gas_mixture/mix)
	return mix.get_moles(GAS_O2)

/datum/unit_test/dq_gas_handle_generation/proc/write_o2(datum/gas_mixture/mix, moles)
	mix.set_moles(GAS_O2, moles)

/datum/unit_test/dq_gas_handle_generation/proc/id_of(datum/gas_mixture/mix)
	return mix.arena_id()

/// Asserts every entry point refuses `stale` and that `live_mix` kept its gas.
/datum/unit_test/dq_gas_handle_generation/proc/assert_refused(datum/gas_mixture/stale, datum/gas_mixture/live_mix, live_o2)
	var/datum/result/read = safe_call(PROC_REF(read_o2), stale)
	TEST_ASSERT(!read.ok, "a stale handle read a mixture it no longer names (got [read.value])")
	var/datum/result/write = safe_call(PROC_REF(write_o2), stale, 99)
	TEST_ASSERT(!write.ok, "a stale handle wrote a mixture it no longer names")
	var/datum/result/batch = safe_call(GLOBAL_PROC_REF(read_gas_mixtures), list(stale))
	TEST_ASSERT(!batch.ok, "a batched read zero-filled a stale handle instead of refusing it")
	var/datum/result/ident = safe_call(PROC_REF(id_of), stale)
	TEST_ASSERT(!ident.ok, "arena_id() handed out the id of a stale handle")
	TEST_ASSERT(abs(live_mix.get_moles(GAS_O2) - live_o2) < 0.001, "the stale write reached the live mixture ([live_mix.get_moles(GAS_O2)] oxygen, expected [live_o2])")

/datum/unit_test/dq_gas_handle_generation/main_slot_reuse

/datum/unit_test/dq_gas_handle_generation/main_slot_reuse/Run()
	var/datum/gas_mixture/stale = new(CELL_VOLUME)
	stale.set_moles(GAS_O2, 5)
	var/pointer = stale._extools_pointer_gasmixture
	var/generation = stale._extools_generation_gasmixture
	TEST_ASSERT_NOTNULL(generation, "a new mixture was not stamped with a generation")
	vg_unregister_gasmixture_hook(stale)
	TEST_ASSERT_NULL(stale._extools_pointer_gasmixture, "unbinding left the datum its handle")
	TEST_ASSERT_NULL(stale._extools_generation_gasmixture, "unbinding left the datum its generation")
	var/datum/gas_mixture/fresh = new(CELL_VOLUME)
	fresh.set_moles(GAS_O2, 3)
	TEST_ASSERT_EQUAL(fresh._extools_pointer_gasmixture, pointer, "the freed slot was not reused, so the test proves nothing")
	// The datum comes back holding what it held when it was freed.
	stale._extools_pointer_gasmixture = pointer
	stale._extools_generation_gasmixture = generation
	assert_refused(stale, fresh, 3)
	stale._extools_pointer_gasmixture = null
	stale._extools_generation_gasmixture = null
	vg_unregister_gasmixture_hook(fresh)

/datum/unit_test/dq_gas_handle_generation/turf_cell_new_owner

/datum/unit_test/dq_gas_handle_generation/turf_cell_new_owner/Run()
	var/list/run = dq_atmos_test_find_clear_pipe_run(1)
	TEST_ASSERT_NOTNULL(run, "no clear floor for the turf cell test")
	var/turf/simulated/floor/T = run[1]
	T.air.set_moles(GAS_O2, 21)
	var/datum/gas_mixture/stale = new(CELL_VOLUME)
	vg_unregister_gasmixture_hook(stale)
	// A leftover turf object's air: it holds the cell's handle and generation as the replaced turf did.
	stale._extools_pointer_gasmixture = T.air._extools_pointer_gasmixture
	stale._extools_generation_gasmixture = T.air._extools_generation_gasmixture
	TEST_ASSERT_EQUAL(stale.get_moles(GAS_O2), 21, "a handle of the current owner could not be read")
	// The cell changes hands (the turf is replaced and its successor registers).
	T.update_air_ref(-1)
	T.update_air_ref(0, T.air_block_mask())
	T.air.set_moles(GAS_O2, 8)
	assert_refused(stale, T.air, 8)
	TEST_ASSERT_EQUAL(T.air.get_moles(GAS_O2), 8, "the turf's own air stopped working after it re-registered")
	stale._extools_pointer_gasmixture = null
	stale._extools_generation_gasmixture = null
