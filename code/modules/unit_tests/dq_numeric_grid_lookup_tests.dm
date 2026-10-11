#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/datum/unit_test/dq_power_grid_public_reads/Run()
	var/id = power_test_grid(2500)
	TEST_ASSERT(id < 0, "detached test grid must have a negative identity")
	TEST_ASSERT_EQUAL(power_avail(id), 2500, "an empty grid loses available supply")
	TEST_ASSERT_EQUAL(power_load(id), 0, "an empty grid starts with load")
	TEST_ASSERT_EQUAL(length(power_grid_nodes(id)), 0, "an empty grid invents a machine")
	TEST_ASSERT_EQUAL(power_draw(id, 600), 600, "a detached grid failed to deliver available supply")
	TEST_ASSERT_EQUAL(power_load(id), 600, "draw did not book the actual grid load")
	TEST_ASSERT_EQUAL(power_netexcess(id), 1900, "surplus used a different grid ledger")
	power_test_set_brownout(id, TRUE)
	TEST_ASSERT(power_brownout(id), "brownout was not observable on an empty grid")
	power_set_material_warning(id, TRUE)
	TEST_ASSERT(power_problem(id), "material warning was not observable on an empty grid")
	power_set_material_warning(id, FALSE)
	TEST_ASSERT(!power_problem(id), "material warning did not clear")
	power_test_drop_grid(id)

/datum/unit_test/dq_power_grid_lookup_identity/Run()
	var/datum/power_grid_registry/registry = power_grid_registry()
	var/id = power_test_grid(1200)
	var/datum/power_grid/first = power_grid_lookup(id)
	TEST_ASSERT_NOTNULL(first, "explicit empty-grid creation has no lookup identity")
	TEST_ASSERT_EQUAL(registry.lookup(id), first, "public lookup and registry disagree")
	power_test_drop_grid(id)
	TEST_ASSERT(QDELETED(first), "dropping grid identity left the old owned datum alive")
	TEST_ASSERT_NULL(power_grid_lookup(id), "drop did not remove actual numeric lookup")
	TEST_ASSERT_EQUAL(power_avail(id), 0, "absent negative grid does not read as zero")
	TEST_ASSERT_NULL(power_grid_lookup(id), "pure absent-ID read silently recreated persistent state")
	var/datum/power_grid/second = power_grid(id)
	TEST_ASSERT_NOTNULL(second, "explicit recreation did not make a new grid")
	TEST_ASSERT(second != first, "recreated numeric identity reused the destroyed datum")
	TEST_ASSERT_EQUAL(power_grid_registry(), registry, "drop replaced the registry and orphaned identity readers")
	power_test_drop_grid(id)

/// A real Rust region can exist before (or without) a DM cache entry. Read-only
/// queries must preserve its ledger values without creating persistent state.
/datum/unit_test/dq_power_grid_uncached_native_read/Run()
	var/list/run = dq_power_test_run(3)
	TEST_ASSERT_NOTNULL(run, "a real cable run is required for native first-read coverage")
	if(!run)
		return
	var/list/cables = dq_power_test_line(run)
	var/obj/machinery/power/terminal/source = allocate(/obj/machinery/power/terminal, run[1])
	SSmachines.process_power()
	TEST_ASSERT(source.power_region > 0, "the real terminal did not bind a native region")
	source.set_power_supply(1400)
	vg_world_run_steps(1)
	SSmachines.process_power()
	var/id = source.power_region
	var/list/native_before = vg_power_region_read(id)
	TEST_ASSERT(islist(native_before) && native_before[1] > 0, "the real native ledger has no nonzero supply to preserve")
	power_grid_registry().drop(id)
	TEST_ASSERT_NULL(power_grid_lookup(id), "dropping DM custody did not leave a native-only region")
	TEST_ASSERT_EQUAL(power_avail(id), native_before[1], "pure first read silently zeroed an uncached native ledger")
	TEST_ASSERT_EQUAL(power_load(id), native_before[2], "pure first read silently zeroed uncached native load")
	TEST_ASSERT_EQUAL(power_brownout(id), !!native_before[3], "pure first read changed uncached native brownout")
	TEST_ASSERT_NULL(power_grid_lookup(id), "read-only native peek created persistent DM registry state")
	// Restore actual membership before fixture teardown; Rust ownership was never removed.
	power_grid_move_node(source, id, id)
	source.set_power_supply(0)
	for(var/obj/structure/cable/cable as anything in cables)
		END_SCOPE(cable)

#endif

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/obj/dq_lookup_grid_fixture
	var/grid_id = 0
	var/uses = 0
	var/edges = 0
	var/ticks = 0

TRACKED(/obj/dq_lookup_grid_fixture, grid_id)

CAPABILITIES(/obj/dq_lookup_grid_fixture)
	op("lookup_grid", menu(button = "Use grid"), needs(req(PROC_REF(grid_ready))), then(PROC_REF(use_grid)))
	op("lookup_wait", menu(button = "Wait on grid"), needs(req(PROC_REF(grid_ready))), wait(3 SECONDS), then(PROC_REF(use_grid)))
	on_change(PROC_REF(grid_has_supply), ENTER, then(PROC_REF(grid_edge)))
	every(1 SECOND, then(PROC_REF(grid_tick)), when = PROC_REF(grid_has_supply))
	contributes(STAT_DENSITY, PROC_REF(grid_has_supply), priority = PRIORITY_FORCE)

/obj/dq_lookup_grid_fixture/proc/grid_ready(datum/act/A)
	var/datum/power_grid/grid = power_grid_lookup(grid_id)
	return grid?.avail >= 100 ? null : "The grid has insufficient supply."

/obj/dq_lookup_grid_fixture/proc/grid_has_supply(datum/act/A)
	var/datum/power_grid/grid = power_grid_lookup(grid_id)
	return grid?.avail >= 100

/obj/dq_lookup_grid_fixture/proc/grid_edge(datum/act/A)
	edges++

/obj/dq_lookup_grid_fixture/proc/grid_tick(datum/act/A)
	ticks++

/obj/dq_lookup_grid_fixture/draw(datum/look/look)
	..()
	var/datum/power_grid/grid = power_grid_lookup(grid_id)
	look.state(grid?.avail >= 100 ? "grid-ready" : "grid-empty")

/obj/dq_lookup_grid_fixture/ui_data(datum/act/eval/A)
	var/datum/power_grid/grid = power_grid_lookup(grid_id)
	return list("available" = grid?.avail || 0)

/obj/dq_lookup_grid_fixture/proc/use_grid(datum/act/A)
	uses++

/datum/unit_test/dq_lookup_grid_binding_lifetime/Run()
	var/obj/dq_lookup_grid_fixture/holder = allocate(/obj/dq_lookup_grid_fixture)
	var/id = power_test_grid(250)
	holder.set_grid_id(id)
	var/list/specs = holder.generated_lookup_reads("grid_ready")
	TEST_ASSERT(length(specs), "the actual requirement's numeric lookup has no generated dependency")
	var/datum/power_grid/grid = power_grid_lookup(id)
	lookup_reads_prepare(holder)
	TEST_ASSERT(grid.rx?.observed?[nameof(grid.avail)] > 0, "holder lifecycle did not bind its actual selected grid field")
	END_SCOPE(holder)
	TEST_ASSERT(!(grid.rx?.observed?[nameof(grid.avail)]), "ending the holder leaked its selected grid-field watcher")
	power_test_drop_grid(id)

/datum/unit_test/dq_lookup_grid_menu_retarget/Run()
	test_driver_begin()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/dq_lookup_grid_fixture/holder = allocate(/obj/dq_lookup_grid_fixture, T)
	var/first_id = power_test_grid(250)
	var/second_id = power_test_grid(0)
	holder.set_grid_id(first_id)
	TEST_ASSERT(isnull(holder.grid_ready(null)), "actual first grid did not initially allow")
	var/list/first_menu = op_menu(actor, holder, null)
	var/list/first_row
	for(var/list/row as anything in first_menu)
		if(row["key"] == "lookup_grid")
			first_row = row
	TEST_ASSERT(first_row && first_row["enabled"], "the actual warmed menu omitted the allowed grid op")
	holder.set_grid_id(second_id)
	var/list/second_menu = op_menu(actor, holder, null)
	var/list/second_row
	for(var/list/row as anything in second_menu)
		if(row["key"] == "lookup_grid")
			second_row = row
	TEST_ASSERT(second_row && !second_row["enabled"], "retargeting to an empty grid kept the warm row enabled")
	var/datum/power_grid/first = power_grid_lookup(first_id)
	var/datum/power_grid/second = power_grid_lookup(second_id)
	TEST_ASSERT(!(first.rx?.observed?[nameof(first.avail)]), "retargeting retained the old grid subscription")
	TEST_ASSERT(second.rx?.observed?[nameof(second.avail)], "retargeting did not subscribe to the selected grid")
	second.set_avail(300)
	var/list/third_menu = op_menu(actor, holder, null)
	var/list/third_row
	for(var/list/row as anything in third_menu)
		if(row["key"] == "lookup_grid")
			third_row = row
	TEST_ASSERT(third_row && third_row["enabled"], "the selected empty grid's real field update did not invalidate its cached menu")
	op_menu_cache_clear()
	power_test_drop_grid(first_id)
	power_test_drop_grid(second_id)
	test_driver_end()

/datum/unit_test/dq_lookup_grid_menu_identity/Run()
	test_driver_begin()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/dq_lookup_grid_fixture/holder = allocate(/obj/dq_lookup_grid_fixture, T)
	var/id = power_test_grid(250)
	holder.set_grid_id(id)
	op_menu(actor, holder, null)
	power_test_drop_grid(id)
	TEST_ASSERT_NOTNULL(holder.grid_ready(null), "a deleted selected grid still allows the real requirement")
	var/list/absent_menu = op_menu(actor, holder, null)
	var/list/absent_row
	for(var/list/row as anything in absent_menu)
		if(row["key"] == "lookup_grid")
			absent_row = row
	TEST_ASSERT(absent_row && !absent_row["enabled"], "numeric identity removal left a cached row allowed")
	var/datum/power_grid/recreated = power_grid(id)
	recreated.set_avail(500)
	var/list/restored_menu = op_menu(actor, holder, null)
	var/list/restored_row
	for(var/list/row as anything in restored_menu)
		if(row["key"] == "lookup_grid")
			restored_row = row
	TEST_ASSERT(restored_row && restored_row["enabled"], "creation at an absent watched numeric ID did not refresh the menu")
	op_menu_cache_clear()
	power_test_drop_grid(id)
	test_driver_end()

/datum/unit_test/dq_lookup_grid_pending_and_reactions/Run()
	test_driver_begin()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/dq_lookup_grid_fixture/holder = allocate(/obj/dq_lookup_grid_fixture, T)
	var/id = power_test_grid(250)
	holder.set_grid_id(id)
	var/datum/power_grid/grid = power_grid_lookup(id)
	test_time(1 SECOND)
	TEST_ASSERT(holder.ticks > 0, "the real periodic did not wake from its numeric grid read")
	TEST_ASSERT(holder.edges > 0, "the real edge callback did not wake from its numeric grid read")
	TEST_ASSERT(stat_value(holder, STAT_DENSITY), "the actual contribution did not read selected supply")
	test_menu(actor, holder, "lookup_wait")
	TEST_ASSERT_NOTNULL(op_pending_for(actor, "lookup_wait"), "the real op did not suspend at its timed step")
	grid.set_avail(0)
	TEST_ASSERT_NULL(op_pending_for(actor, "lookup_wait"), "a real selected-grid change did not cancel the pending requirement")
	TEST_ASSERT_EQUAL(holder.uses, 0, "the canceled wait still ran its effect")
	TEST_ASSERT(!stat_value(holder, STAT_DENSITY), "the stat contribution retained old selected-grid state")
	var/ticks = holder.ticks
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(holder.ticks, ticks, "the periodic kept running after its grid gate became false")
	grid.set_avail(250)
	test_time(1 SECOND)
	TEST_ASSERT(holder.ticks > ticks, "the parked periodic did not resume on actual supply publication")
	op_menu_cache_clear()
	power_test_drop_grid(id)
	test_driver_end()

/datum/unit_test/dq_lookup_grid_outputs/Run()
	test_driver_begin()
	var/obj/dq_lookup_grid_fixture/holder = allocate(/obj/dq_lookup_grid_fixture, test_floor())
	var/id = power_test_grid(0)
	holder.set_grid_id(id)
	refresh_flush()
	TEST_ASSERT_EQUAL(holder.icon_state, "grid-empty", "the real initial draw did not reflect empty supply")
	var/list/before = list()
	present_tgui_data(holder, null, before)
	TEST_ASSERT_EQUAL(before["available"], 0, "initial window output invented available supply")
	var/datum/power_grid/grid = power_grid_lookup(id)
	grid.set_avail(300)
	TEST_ASSERT(holder.refresh_queued & DEP_DRAW, "a selected grid publication did not mark the declared draw dependency")
	TEST_ASSERT(holder.refresh_queued & DEP_UI, "a selected grid publication did not mark the declared UI dependency")
	refresh_flush()
	TEST_ASSERT_EQUAL(holder.icon_state, "grid-ready", "the real coalesced draw kept its stale numeric lookup")
	var/list/after = list()
	present_tgui_data(holder, null, after)
	TEST_ASSERT_EQUAL(after["available"], 300, "actual window output kept old selected grid state")
	power_test_drop_grid(id)
	test_driver_end()

/mob/living/carbon/human/dq_lookup_actor
	var/grid_id = 0

TRACKED(/mob/living/carbon/human/dq_lookup_actor, grid_id)

/obj/dq_lookup_grid_fixture/contextual

CAPABILITIES(/obj/dq_lookup_grid_fixture/contextual)
	op("actor_grid", menu(button = "Use actor grid"), needs(req(PROC_REF(actor_grid_ready))), then(PROC_REF(use_grid)))
	op("actor_wait", menu(button = "Wait on actor grid"), needs(req(PROC_REF(actor_grid_ready))), wait(3 SECONDS), then(PROC_REF(use_grid)))

/obj/dq_lookup_grid_fixture/contextual/proc/actor_grid_ready(datum/act/action/A)
	var/mob/living/carbon/human/dq_lookup_actor/actor = A.actor
	if(!istype(actor))
		return "The actor has no grid."
	var/datum/power_grid/grid = power_grid_lookup(actor.grid_id)
	return grid?.avail >= 100 ? null : "The actor grid has insufficient supply."

/datum/unit_test/dq_lookup_grid_actor_context/Run()
	test_driver_begin()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/dq_lookup_actor/first = allocate(/mob/living/carbon/human/dq_lookup_actor, T)
	var/mob/living/carbon/human/dq_lookup_actor/second = allocate(/mob/living/carbon/human/dq_lookup_actor, T)
	var/obj/dq_lookup_grid_fixture/contextual/holder = allocate(/obj/dq_lookup_grid_fixture/contextual, T)
	var/first_id = power_test_grid(250)
	var/second_id = power_test_grid(0)
	first.set_grid_id(first_id)
	second.set_grid_id(second_id)
	var/list/first_row
	for(var/list/row as anything in op_menu(first, holder, null))
		if(row["key"] == "actor_grid")
			first_row = row
	var/list/second_row
	for(var/list/row as anything in op_menu(second, holder, null))
		if(row["key"] == "actor_grid")
			second_row = row
	TEST_ASSERT(first_row && first_row["enabled"], "the actor's real grid was replaced by the holder's absent grid")
	TEST_ASSERT(second_row && !second_row["enabled"], "the second actor inherited the first actor's cached admission")
	var/datum/power_grid/second_grid = power_grid_lookup(second_id)
	second_grid.set_avail(250)
	var/list/repaired_row
	for(var/list/row as anything in op_menu(second, holder, null))
		if(row["key"] == "actor_grid")
			repaired_row = row
	TEST_ASSERT(repaired_row && repaired_row["enabled"], "the actual contextual producer did not refresh its actor's menu")
	END_SCOPE(first)
	END_SCOPE(second)
	TEST_ASSERT(!(second_grid.rx?.observed?[nameof(second_grid.avail)]), "deleted actors left contextual cache bindings alive")
	op_menu_cache_clear()
	power_test_drop_grid(first_id)
	power_test_drop_grid(second_id)
	test_driver_end()

/datum/unit_test/dq_lookup_grid_actor_pending/Run()
	test_driver_begin()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/dq_lookup_actor/actor = allocate(/mob/living/carbon/human/dq_lookup_actor, T)
	var/obj/dq_lookup_grid_fixture/contextual/holder = allocate(/obj/dq_lookup_grid_fixture/contextual, T)
	var/actor_id = power_test_grid(250)
	var/holder_id = power_test_grid(250)
	actor.set_grid_id(actor_id)
	holder.set_grid_id(holder_id)
	test_menu(actor, holder, "actor_wait")
	var/datum/pending_op/pending = op_pending_for(actor, "actor_wait")
	TEST_ASSERT_NOTNULL(pending, "the actual contextual requirement did not start a pending wait")
	var/datum/power_grid/actor_grid = power_grid_lookup(actor_id)
	var/datum/power_grid/holder_grid = power_grid_lookup(holder_id)
	holder_grid.set_avail(0)
	TEST_ASSERT_EQUAL(op_pending_for(actor, "actor_wait"), pending, "contextual binding substituted the holder for the real actor")
	actor_grid.set_avail(0)
	TEST_ASSERT_NULL(op_pending_for(actor, "actor_wait"), "the real actor grid did not cancel its pending admission")
	TEST_ASSERT_EQUAL(holder.uses, 0, "contextual cancellation allowed the wait effect")
	TEST_ASSERT(!(actor_grid.rx?.observed?[nameof(actor_grid.avail)]), "a finished contextual wait leaked its producer subscription")
	power_test_drop_grid(actor_id)
	power_test_drop_grid(holder_id)
	test_driver_end()

/obj/dq_lookup_grid_fixture/contextual/ui_data(datum/act/eval/A)
	var/mob/living/carbon/human/dq_lookup_actor/actor = A.actor
	if(!istype(actor))
		return list("actor_available" = 0)
	var/datum/power_grid/grid = power_grid_lookup(actor.grid_id)
	return list("actor_available" = grid?.avail || 0)

/datum/unit_test/dq_lookup_grid_window_lifetime/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/dq_lookup_actor/actor = allocate(/mob/living/carbon/human/dq_lookup_actor, T)
	var/obj/dq_lookup_grid_fixture/contextual/holder = allocate(/obj/dq_lookup_grid_fixture/contextual, T)
	var/id = power_test_grid(250)
	actor.set_grid_id(id)
	var/datum/tgui/ui = new(actor, holder, "LookupProbe")
	ui.prepare_lookup_reads()
	var/datum/power_grid/grid = power_grid_lookup(id)
	TEST_ASSERT(grid.rx?.observed?[nameof(grid.avail)] > 0, "actual window preparation did not follow its viewer's numeric grid")
	var/list/data = list()
	present_tgui_data(holder, actor, data, lookup_scope = ui.lookup_scope)
	TEST_ASSERT_EQUAL(data["actor_available"], 250, "actual contextual window data substituted holder state for viewer state")
	ui.close(FALSE)
	TEST_ASSERT(!(grid.rx?.observed?[nameof(grid.avail)]), "closing the actual window retained contextual producer watchers")
	power_test_drop_grid(id)

/obj/item/dq_lookup_probe
	var/grid_id = 0

TRACKED(/obj/item/dq_lookup_probe, grid_id)

CAPABILITIES(/obj/item/dq_lookup_probe)
	op("target_grid", at_target(/obj/dq_lookup_grid_fixture), label("Use target grid"), needs(req(PROC_REF(target_ready))), then(PROC_REF(used)))
	op("held_grid", at_target(/obj/dq_lookup_grid_fixture), label("Use held grid"), needs(req(PROC_REF(held_ready))), then(PROC_REF(used)))

/obj/item/dq_lookup_probe/proc/target_ready(datum/act/action/A)
	var/obj/dq_lookup_grid_fixture/target = A.target
	var/datum/power_grid/grid = power_grid_lookup(target.grid_id)
	return grid?.avail >= 100 ? null : "The target grid has insufficient supply."

/obj/item/dq_lookup_probe/proc/held_ready(datum/act/action/A)
	var/obj/item/dq_lookup_probe/held = A.held
	var/datum/power_grid/grid = power_grid_lookup(held.grid_id)
	return grid?.avail >= 100 ? null : "The held grid has insufficient supply."

/obj/item/dq_lookup_probe/proc/used(datum/act/A)
	return OP_OK

/datum/unit_test/dq_lookup_grid_target_held_context/Run()
	test_driver_begin()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/dq_lookup_grid_fixture/target = allocate(/obj/dq_lookup_grid_fixture, T)
	var/obj/item/dq_lookup_probe/probe = allocate(/obj/item/dq_lookup_probe, T)
	var/target_id = power_test_grid(250)
	var/held_id = power_test_grid(0)
	target.set_grid_id(target_id)
	probe.set_grid_id(held_id)
	actor.put_in_hands(probe)
	TEST_ASSERT_EQUAL(actor.held_for_ops(), probe, "the real actor did not hold the item supplying target-bound ops")
	var/list/target_row
	var/list/held_row
	for(var/list/row as anything in op_menu(actor, target, probe))
		if(row["key"] == "target_grid")
			target_row = row
		if(row["key"] == "held_grid")
			held_row = row
	TEST_ASSERT(target_row && target_row["enabled"], "actual target-root lookup was replaced by its held provider")
	TEST_ASSERT(held_row && !held_row["enabled"], "actual held-root lookup was replaced by the target")
	var/datum/power_grid/held_grid = power_grid_lookup(held_id)
	held_grid.set_avail(250)
	var/list/updated_row
	for(var/list/row as anything in op_menu(actor, target, probe))
		if(row["key"] == "held_grid")
			updated_row = row
	TEST_ASSERT(updated_row && updated_row["enabled"], "the actual held producer failed to invalidate the warmed menu")
	op_menu_cache_clear()
	power_test_drop_grid(target_id)
	power_test_drop_grid(held_id)
	test_driver_end()

/obj/dq_lookup_grid_fixture/public_read

/obj/dq_lookup_grid_fixture/public_read/grid_ready(datum/act/A)
	return power_avail(grid_id) >= 100 ? null : "The grid has insufficient supply."

/datum/unit_test/dq_lookup_grid_uncached_native_menu/Run()
	test_driver_begin()
	var/list/run = dq_power_test_run(3)
	TEST_ASSERT_NOTNULL(run, "a real cable run is required for warmed native-only dependency coverage")
	if(!run)
		return
	var/list/cables = dq_power_test_line(run)
	var/obj/machinery/power/terminal/source = allocate(/obj/machinery/power/terminal, run[1])
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, run[1])
	var/obj/dq_lookup_grid_fixture/public_read/holder = allocate(/obj/dq_lookup_grid_fixture/public_read, run[1])
	SSmachines.process_power()
	TEST_ASSERT(source.power_region > 0, "the real terminal did not bind a native region")
	source.set_power_supply(1400)
	vg_world_run_steps(1)
	SSmachines.process_power()
	var/id = source.power_region
	power_grid_registry().drop(id)
	holder.set_grid_id(id)
	TEST_ASSERT_NULL(power_grid_lookup(id), "warming native-only coverage unexpectedly adopted DM state")
	var/list/warm_row
	for(var/list/row as anything in op_menu(actor, holder, null))
		if(row["key"] == "lookup_grid")
			warm_row = row
	TEST_ASSERT(warm_row && warm_row["enabled"], "the warmed real public requirement did not preserve native nonzero supply")
	TEST_ASSERT_NULL(power_grid_lookup(id), "the menu's pure read registered persistent grid custody")
	source.set_power_supply(0)
	vg_world_run_steps(1)
	SSmachines.process_power()
	TEST_ASSERT_NOTNULL(power_grid_lookup(id), "the system's write step did not adopt the actual watched native identity")
	TEST_ASSERT(source in power_grid_nodes(id), "system adoption lost an actual bound machine's membership")
	var/list/empty_row
	for(var/list/row as anything in op_menu(actor, holder, null))
		if(row["key"] == "lookup_grid")
			empty_row = row
	TEST_ASSERT(empty_row && !empty_row["enabled"], "a warmed native-only menu stayed enabled after real native supply changed")
	source.set_power_supply(1400)
	vg_world_run_steps(1)
	SSmachines.process_power()
	var/list/restored_row
	for(var/list/row as anything in op_menu(actor, holder, null))
		if(row["key"] == "lookup_grid")
			restored_row = row
	TEST_ASSERT(restored_row && restored_row["enabled"], "the adopted real grid did not publish later tracked supply updates")
	source.set_power_supply(0)
	op_menu_cache_clear()
	for(var/obj/structure/cable/cable as anything in cables)
		END_SCOPE(cable)
	test_driver_end()

#endif
