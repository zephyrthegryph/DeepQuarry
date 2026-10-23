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

// Binds that name a mixture by handle take the datum (or an id with its generation), never a bare number.

/datum/unit_test/dq_gas_handle_generation/proc/device_set_turf(device_id, port, turf_air)
	return vg_pipe_device_set_turf(device_id, port, turf_air)

/datum/unit_test/dq_gas_handle_generation/proc/pipe_upsert(port, mixture, volume)
	return vg_pipe_upsert(port, mixture, volume)

/datum/unit_test/dq_gas_handle_generation/proc/batch_transfer(list/operations)
	return vg_batch_transfer_hook(operations)

/datum/unit_test/dq_gas_handle_generation/pipe_device_turf_handle

/datum/unit_test/dq_gas_handle_generation/pipe_device_turf_handle/Run()
	var/list/run = dq_atmos_test_find_clear_pipe_run(1)
	TEST_ASSERT_NOTNULL(run, "no clear floor for the pipe device test")
	var/turf/simulated/floor/T = run[1]
	var/obj/machinery/atmospherics/unary/vent_pump/V = new(T)
	V.rust_register_pipe_topology()
	var/port = V.rust_pipe_port_ids[1]
	// The live turf air is accepted through the machine's own path.
	TEST_ASSERT(V.rust_set_turf_device(1, T.air), "a live turf air was refused as a device's turf side")
	V.rust_ensure_device_id()
	var/device = V.rust_device_id
	var/datum/result/live = safe_call(PROC_REF(device_set_turf), device, port, T.air)
	TEST_ASSERT(live.ok && live.value, "vg_pipe_device_set_turf refused the live turf air ([live.value])")
	// A bare handle number cannot say which mixture it was minted for.
	var/datum/result/bare = safe_call(PROC_REF(device_set_turf), device, port, T.air.arena_id())
	TEST_ASSERT(!bare.ok, "vg_pipe_device_set_turf accepted a bare handle number")
	// A leftover turf object's air after the cell changed hands.
	var/datum/gas_mixture/stale = new(CELL_VOLUME)
	vg_unregister_gasmixture_hook(stale)
	stale._extools_pointer_gasmixture = T.air._extools_pointer_gasmixture
	stale._extools_generation_gasmixture = T.air._extools_generation_gasmixture
	T.update_air_ref(-1)
	T.update_air_ref(0, T.air_block_mask())
	var/datum/result/refused = safe_call(PROC_REF(device_set_turf), device, port, stale)
	TEST_ASSERT(!refused.ok, "vg_pipe_device_set_turf accepted a turf air whose cell changed hands")
	stale._extools_pointer_gasmixture = null
	stale._extools_generation_gasmixture = null
	qdel(V)

/datum/unit_test/dq_gas_handle_generation/pipe_upsert_handle

/datum/unit_test/dq_gas_handle_generation/pipe_upsert_handle/Run()
	var/list/run = dq_atmos_test_find_clear_pipe_run(1)
	TEST_ASSERT_NOTNULL(run, "no clear floor for the pipe upsert test")
	var/turf/simulated/floor/T = run[1]
	var/obj/machinery/atmospherics/unary/vent_pump/V = new(T)
	V.rust_register_pipe_topology()
	var/port = V.rust_pipe_port_ids[1]
	var/datum/result/bare = safe_call(PROC_REF(pipe_upsert), port, T.air.arena_id(), 10)
	TEST_ASSERT(!bare.ok, "vg_pipe_upsert accepted a bare handle number")
	var/datum/gas_mixture/stale = new(CELL_VOLUME)
	vg_unregister_gasmixture_hook(stale)
	var/datum/gas_mixture/fresh = new(CELL_VOLUME)
	stale._extools_pointer_gasmixture = fresh._extools_pointer_gasmixture
	stale._extools_generation_gasmixture = null
	var/datum/result/refused = safe_call(PROC_REF(pipe_upsert), port, stale, 10)
	TEST_ASSERT(!refused.ok, "vg_pipe_upsert accepted a mixture with no valid generation")
	var/datum/result/empty = safe_call(PROC_REF(pipe_upsert), port, 0, 10)
	TEST_ASSERT(empty.ok, "vg_pipe_upsert refused an empty port (0)")
	stale._extools_pointer_gasmixture = null
	vg_unregister_gasmixture_hook(fresh)
	qdel(V)

/datum/unit_test/dq_gas_handle_generation/batch_transfer_generation

/datum/unit_test/dq_gas_handle_generation/batch_transfer_generation/Run()
	var/datum/gas_mixture/source = new(CELL_VOLUME)
	var/datum/gas_mixture/sink = new(CELL_VOLUME)
	source.set_moles(GAS_O2, 10)
	var/list/operations = list(source.arena_id(), source.arena_generation(), sink.arena_id(), sink.arena_generation(), 4)
	var/list/moved = vg_batch_transfer_hook(operations)
	TEST_ASSERT(moved[1] > 3.9, "a current id and generation moved no gas ([json_encode(moved)])")
	// The sink's slot is freed and reused by another mixture: its queued generation is stale.
	var/sink_id = sink.arena_id()
	var/sink_generation = sink.arena_generation()
	vg_unregister_gasmixture_hook(sink)
	var/datum/gas_mixture/other = new(CELL_VOLUME)
	TEST_ASSERT_EQUAL(other.arena_id(), sink_id, "the freed slot was not reused, so the test proves nothing")
	var/list/stale_ops = list(source.arena_id(), source.arena_generation(), sink_id, sink_generation, 4)
	var/list/refused = vg_batch_transfer_hook(stale_ops)
	TEST_ASSERT_EQUAL(refused[1], -1, "a queued transfer into a replaced mixture was not refused")
	TEST_ASSERT_EQUAL(other.get_moles(GAS_O2), 0, "gas reached the mixture that reused the slot")
	vg_unregister_gasmixture_hook(source)
	vg_unregister_gasmixture_hook(other)
