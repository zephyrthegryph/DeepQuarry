#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

// Two real gas producers whose combined pressure must remain admissible during a transfer.
/obj/gas_numeric_fixture
	abstract_type = /obj/gas_numeric_fixture
	var/datum/gas_mixture/first
	var/datum/gas_mixture/second
	var/baseline_pressure = 0
	var/completed = FALSE

TRACKED(/obj/gas_numeric_fixture, baseline_pressure)
TRACKED(/obj/gas_numeric_fixture, completed)

CAPABILITIES(/obj/gas_numeric_fixture)
	ref_one(nameof(first), /datum/gas_mixture)
	ref_one(nameof(second), /datum/gas_mixture)
	gas_numeric_read(air = nameof(first))
	gas_numeric_read(air = nameof(second))
	op("wait", menu(), needs(req(PROC_REF(conserved_pressure))), wait(1 SECOND), then(PROC_REF(finished)))

/obj/gas_numeric_fixture/proc/conserved_pressure(datum/act/op/A)
	return abs(gas_numeric_pressure(first) + gas_numeric_pressure(second) - baseline_pressure) < 0.001 ? null : "The combined pressure changed."

/obj/gas_numeric_fixture/proc/finished(datum/act/op/A)
	set_completed(TRUE)
	return OP_OK

/obj/gas_numeric_fixture/proc/recycle_native(datum/gas_mixture/mixture)
	var/volume = mixture.return_volume()
	var/temperature = mixture.return_temperature()
	var/moles = mixture.get_moles(GAS_OXYGEN)
	vg_unregister_gasmixture_hook(mixture)
	vg_register_gasmixture_hook(mixture)
	mixture.set_volume(volume)
	mixture.set_temperature(temperature)
	mixture.set_moles(GAS_OXYGEN, moles)

/datum/unit_test/dq_gas_numeric_immediate_ui/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/machinery/disposal/D = allocate(/obj/machinery/disposal, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	D.air_contents.clear()
	D.air_contents.set_volume(70)
	D.air_contents.set_temperature(T20C)
	D.air_contents.set_moles(GAS_OXYGEN, 0.08)
	var/before = gauge(D, H)
	D.air_contents.set_temperature(T20C * 2)
	var/after_temperature = gauge(D, H)
	TEST_ASSERT(after_temperature > before, "A warmed real UI immediately reflects a native temperature-only write without a frame drain")
	D.air_contents.set_volume(35)
	var/after_volume = gauge(D, H)
	TEST_ASSERT(after_volume > after_temperature, "A warmed real UI immediately reflects a native volume-only write")
	D.air_contents.set_moles(GAS_OXYGEN, 0.24)
	TEST_ASSERT(gauge(D, H) > after_volume, "A warmed real UI immediately reflects a native composition-only write")
	test_driver_end()

/datum/unit_test/dq_gas_numeric_immediate_ui/proc/gauge(obj/machinery/disposal/D, mob/H)
	var/list/data = D.tgui_data(H, null, GLOB.tgui_always_state)
	var/expected = round(clamp(100 * D.air_contents.return_pressure() / (ONE_ATMOSPHERE + 0.05), 0, 100), 1)
	TEST_ASSERT_EQUAL(data["pressure"], expected, "The actual UI percentage matches the committed native getter")
	TEST_ASSERT_EQUAL(gas_numeric_pressure(D.air_contents), D.air_contents.return_pressure(), "The prepared numeric producer carries actual committed kPa")
	return data["pressure"]

/datum/unit_test/dq_gas_numeric_transfer_atomic/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/gas_numeric_fixture/F = allocate(/obj/gas_numeric_fixture, T)
	var/datum/gas_mixture/a = allocate(/datum/gas_mixture, 70)
	var/datum/gas_mixture/b = allocate(/datum/gas_mixture, 70)
	a.set_temperature(T20C)
	b.set_temperature(T20C)
	a.set_moles(GAS_OXYGEN, 0.3)
	b.set_moles(GAS_OXYGEN, 0.1)
	rel_set(F, nameof(F.first), a)
	rel_set(F, nameof(F.second), b)
	F.set_baseline_pressure(a.return_pressure() + b.return_pressure())
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/datum/op_result/started = test_menu(H, F, "wait")
	TEST_ASSERT_NOTNULL(started, "The real conserved-pressure operation returns a result record")
	TEST_ASSERT_NULL(started.outcome, "The real operation waits before the transfer")
	var/datum/pending_op/pending = op_pending_for(H, "wait")
	TEST_ASSERT(pending?.active, "The conservation requirement has a real pending subscriber")
	TEST_ASSERT(a.transfer_to(b, 0.1), "The real native transfer succeeds")
	TEST_ASSERT_EQUAL(gas_numeric_pressure(a), a.return_pressure(), "The first participant is immediately committed")
	TEST_ASSERT_EQUAL(gas_numeric_pressure(b), b.return_pressure(), "The second participant is immediately committed")
	TEST_ASSERT(pending.active, "The completed transfer preserves admission without an intermediate cancellation")
	test_time(1 SECOND)
	TEST_ASSERT(F.completed, "An atomic two-mixture update does not cancel a still-admissible pending operation")
	TEST_ASSERT_EQUAL(started.outcome, ACT_COMMITTED, "The waiting operation commits after the unchanged final requirement")
	test_driver_end()

/datum/unit_test/dq_gas_numeric_retarget_and_teardown/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/gas_numeric_fixture/F = allocate(/obj/gas_numeric_fixture, T)
	var/datum/gas_mixture/a = allocate(/datum/gas_mixture, 70)
	var/datum/gas_mixture/b = allocate(/datum/gas_mixture, 70)
	a.set_moles(GAS_OXYGEN, 0.1)
	b.set_moles(GAS_OXYGEN, 0.3)
	rel_set(F, nameof(F.first), a)
	var/datum/gas_numeric_source/old_source = gas_numeric_lookup(a.arena_id())
	var/datum/native_watch/gas_numeric/old_watch = old_source.watch
	var/old_id = a.arena_id()
	var/old_token = old_watch.handle
	var/old_pressure = a.return_pressure()
	rel_set(F, nameof(F.first), b)
	TEST_ASSERT_EQUAL(gas_numeric_pressure(b), b.return_pressure(), "Relation replacement prepares the new producer before an immediate pure read")
	TEST_ASSERT(QDELETED(old_watch), "The old subscription detaches synchronously when its final consumer leaves")
	TEST_ASSERT_NULL(gas_numeric_lookup(old_id), "The prior numeric source no longer occupies the registry")
	kernel_native_native_dispatch(old_token, list(old_id, TRUE, old_pressure))
	var/datum/gas_numeric_source/replacement_source = gas_numeric_lookup(b.arena_id())
	kernel_native_native_dispatch(replacement_source.watch.handle, list(old_id, TRUE, old_pressure))
	TEST_ASSERT_EQUAL(gas_numeric_pressure(b), b.return_pressure(), "A delayed prior-token or mismatched-identity observation cannot change the replacement")
	a.set_temperature(T20C * 2)
	TEST_ASSERT_EQUAL(gas_numeric_pressure(b), b.return_pressure(), "A retired mixture mutation cannot overwrite the new producer")
	var/active_id = b.arena_id()
	qdel(F)
	TEST_ASSERT_NULL(gas_numeric_lookup(active_id), "Destroying the holder drops its last numeric consumer")
	test_driver_end()

/datum/unit_test/dq_gas_numeric_live_identity_reuse/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/machinery/disposal/D = allocate(/obj/machinery/disposal, T)
	var/obj/gas_numeric_fixture/F = allocate(/obj/gas_numeric_fixture, T)
	var/datum/gas_mixture/a = D.air_contents
	var/datum/gas_mixture/b = allocate(/datum/gas_mixture, 70)
	a.clear()
	a.set_temperature(T20C)
	a.set_moles(GAS_OXYGEN, 0.1)
	rel_set(F, nameof(F.first), a)
	rel_set(F, nameof(F.second), b)
	F.set_baseline_pressure(a.return_pressure() + b.return_pressure())
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/list/before = D.tgui_data(H, null, GLOB.tgui_always_state)
	var/id = a.arena_id()
	var/datum/gas_numeric_source/old_source = gas_numeric_lookup(id)
	var/datum/op_result/result = test_menu(H, F, "wait")
	TEST_ASSERT_NOTNULL(result, "The shared-producer operation returns a real result")
	TEST_ASSERT_NULL(result.outcome, "The shared-producer operation waits")
	var/datum/pending_op/pending = op_pending_for(H, "wait")
	TEST_ASSERT(pending?.active, "The initial producer has a live waiting consumer")
	state_batch(F, TYPE_PROC_REF(/obj/gas_numeric_fixture, recycle_native), list(a))
	TEST_ASSERT_EQUAL(a.arena_id(), id, "The actual native free list reused the same numeric slot")
	var/datum/gas_numeric_source/replacement = gas_numeric_lookup(id)
	TEST_ASSERT_NOTNULL(replacement, "Native retirement was drained before same-number identity rearm")
	TEST_ASSERT(replacement != old_source && QDELETED(old_source), "The registry contains a new live producer, not the retired record")
	TEST_ASSERT_EQUAL(gas_numeric_pressure(a), a.return_pressure(), "The replacement producer has the final committed pressure")
	var/list/after = D.tgui_data(H, null, GLOB.tgui_always_state)
	TEST_ASSERT_EQUAL(after["pressure"], before["pressure"], "The live warmed disposal UI remains correct after actual identity reuse")
	TEST_ASSERT(pending.active, "The completed identity replacement never exposes its intermediate retirement to admission")
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(result.outcome, ACT_COMMITTED, "The waiting consumer commits after the final equal-pressure replacement")
	test_driver_end()

// A transformed numeric argument proves the runtime executes the validated getter.
/datum/dq_numeric_argument_fixture
	var/raw_id = 0

TRACKED(/datum/dq_numeric_argument_fixture, raw_id)
READ_LOOKUP_ARGUMENT(/datum/dq_numeric_argument_fixture/proc/decoded_id, reads = list(nameof(raw_id)))

/datum/dq_numeric_argument_fixture/proc/decoded_id()
	return raw_id + 1

/obj/dq_numeric_provider_fixture
	abstract_type = /obj/dq_numeric_provider_fixture
	var/datum/dq_numeric_argument_fixture/argument

CAPABILITIES(/obj/dq_numeric_provider_fixture)
	ref_one(nameof(argument), /datum/dq_numeric_argument_fixture)
	op("decoded_grid", menu(button = "Use decoded grid"), needs(req(PROC_REF(ready))), then(PROC_REF(use_grid)))

/obj/dq_numeric_provider_fixture/proc/ready(datum/act/A)
	var/datum/power_grid/grid = power_grid_lookup(argument.decoded_id())
	return grid?.avail >= 100 ? null : "The decoded grid has insufficient supply."

/obj/dq_numeric_provider_fixture/proc/use_grid(datum/act/A)
	return OP_OK

/datum/unit_test/dq_lookup_argument_provider_runtime/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	test_driver_begin()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/dq_numeric_provider_fixture/holder = allocate(/obj/dq_numeric_provider_fixture, T)
	var/datum/dq_numeric_argument_fixture/argument = allocate(/datum/dq_numeric_argument_fixture)
	var/first_id = power_test_grid(250)
	var/second_id = power_test_grid(0)
	argument.set_raw_id(first_id - 1)
	rel_set(holder, nameof(holder.argument), argument)
	var/list/first = row(actor, holder)
	TEST_ASSERT(first && first["enabled"], "A real warmed menu must use the transformed getter, not its raw tracked argument")
	argument.set_raw_id(second_id - 1)
	var/list/second = row(actor, holder)
	TEST_ASSERT(second && !second["enabled"], "Publishing the actual getter input must retarget the warmed menu to the second grid")
	TEST_ASSERT_EQUAL(second?["reason"], "The decoded grid has insufficient supply.", "The actual selected producer's refusal is preserved")
	var/datum/power_grid/old_grid = power_grid_lookup(first_id)
	old_grid.set_avail(500)
	TEST_ASSERT(!row(actor, holder)?["enabled"], "The old selected grid must not replace the current argument")
	lifeform_end(holder, END_SCOPE)
	power_test_drop_grid(first_id)
	power_test_drop_grid(second_id)
	test_driver_end()

/datum/unit_test/dq_lookup_argument_provider_runtime/proc/row(mob/actor, obj/holder)
	for(var/list/entry as anything in action_options(actor, holder, null))
		if(entry["key"] == "decoded_grid")
			return entry
	return null
CAPABILITY_TYPE(gas_numeric_throwing_preparer, CAP_GAS_NUMERIC_THROWING_PREPARER, /datum/capability/gas_numeric_throwing_preparer, key = NONE)
CAPABILITY_TYPE(gas_numeric_following_preparer, CAP_GAS_NUMERIC_FOLLOWING_PREPARER, /datum/capability/gas_numeric_following_preparer, key = NONE)

/datum/gas_numeric_throwing_holder
	var/context_ref
	var/seen_relation
	var/datum/target
	var/following_runs = 0
	var/notifications = 0

CAPABILITIES(/datum/gas_numeric_throwing_holder)
	gas_numeric_throwing_preparer()
	gas_numeric_following_preparer()
	ref_one(nameof(target), /datum)
	on_change(nameof(target), ANY, then(PROC_REF(notified)))

/datum/gas_numeric_throwing_holder/proc/notified(datum/act/A)
	notifications++

/datum/capability/gas_numeric_following_preparer
	holder_hooks = HOLDER_HOOK_RELATION

/datum/capability/gas_numeric_following_preparer/on_holder_relation_changed(datum/act/eval/A, relation_var)
	var/datum/gas_numeric_throwing_holder/holder = A.holder
	if(relation_var == nameof(holder.target) && holder.target)
		holder.following_runs++

/datum/capability/gas_numeric_throwing_preparer
	holder_hooks = HOLDER_HOOK_RELATION

/datum/capability/gas_numeric_throwing_preparer/on_holder_relation_changed(datum/act/eval/A, relation_var)
	var/datum/gas_numeric_throwing_holder/holder = A.holder
	if(relation_var != nameof(holder.target) || !holder.target)
		return
	holder.context_ref = REF(A)
	holder.seen_relation = relation_var
	throw EXCEPTION("numeric relation preparer test failure")

/datum/unit_test/dq_gas_numeric_relation_hook_exception/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	test_driver_begin()
	var/datum/gas_numeric_throwing_holder/holder = allocate(/datum/gas_numeric_throwing_holder)
	var/datum/target = allocate(/datum)
	// Seed the actual eval pool so its outstanding lease count can be compared.
	var/datum/act/eval/seed = take(/datum/act/eval)
	seed.release()
	var/datum/object_pool/pool = GLOB.object_pools[/datum/act/eval]
	var/before_out = pool.out
	var/before_released = pool.released
	var/exception/caught
	try
		rel_set(holder, nameof(holder.target), target)
	catch(var/exception/fault)
		caught = fault
	TEST_ASSERT_NOTNULL(caught, "The actual declared relation preparer must throw through its caller")
	TEST_ASSERT_EQUAL(caught?.name, "numeric relation preparer test failure", "Cleanup must preserve the original exception")
	TEST_ASSERT_EQUAL(holder.target, target, "The actual relation write committed before its preparer failed")
	TEST_ASSERT_EQUAL(holder.seen_relation, nameof(holder.target), "The engine must dispatch the actual relation key")
	TEST_ASSERT_EQUAL(holder.following_runs, 1, "A failing preparer must not prevent the following preparer from preparing the committed relation")
	var/datum/act/eval/released_context = locate(holder.context_ref)
	TEST_ASSERT_NOTNULL(released_context, "The hook must have received a real pooled evaluation context")
	TEST_ASSERT_EQUAL(pool.out, before_out, "A throwing relation hook must return its eval lease to the actual pool")
	TEST_ASSERT_EQUAL(pool.released, before_released + 2, "Both relation preparers must release exactly once before reaction delivery")
	TEST_ASSERT(released_context?.pool_state != POOL_STATE_TAKEN, "The failing hook's actual context must no longer be checked out")
	TEST_ASSERT_NULL(released_context?.holder, "Release must reset the borrowed holder reference")
	TEST_ASSERT_NULL(released_context?.cap, "Release must reset the borrowed capability reference")
	TEST_ASSERT_EQUAL(holder.notifications, 0, "The on_change consequence has not run before the driver drains")
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(holder.notifications, 1, "The committed relation must publish exactly once despite the preparer exception")
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(holder.notifications, 1, "Preparation failure must not duplicate relation publication")
	test_driver_end()
#endif
