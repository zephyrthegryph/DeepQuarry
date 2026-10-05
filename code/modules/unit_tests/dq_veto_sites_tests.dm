// The sites that were om_hook() and became observe() on an action (doc/rewrite/codemod_rules.md "om_hook residue"): each test drives the real emit site of one
// group and checks that the hook vetoes, answers or adjusts what the legacy hook did. The engine form itself is dq_veto_tests.dm.

/// A listener for the plain acts a test observes: it counts what it was asked and answers `answer`.
/datum/dq_site_listener
	var/asked = 0
	var/answer
	var/blocking = TRUE

/datum/dq_site_listener/proc/blocks(datum/act/A)
	return blocking

/datum/dq_site_listener/proc/respond(datum/act/A)
	asked++
	return answer

// ---- injure: a stasis field (the statue) refuses it, a listener changes it in flight ----

/datum/unit_test/dq_veto_site_statue_stasis

/datum/unit_test/dq_veto_site_statue_stasis/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/structure/closet/statue/statue = allocate(/obj/structure/closet/statue, T, H)
	TEST_ASSERT_EQUAL(H.loc, statue, "the statue took the mob in")
	TEST_ASSERT_EQUAL(H.injure(INJURY_BLUNT, 20, BP_TORSO, flags = INJURE_SILENT), 0, "the stasis field refuses the injury: nothing lands")
	TEST_ASSERT(act_wanted(H, /datum/act/injure), "the statue's hook is on the mob's injure action")
	statue.release()
	TEST_ASSERT(!act_wanted(H, /datum/act/injure), "releasing the mob ends the hook")
	TEST_ASSERT(H.injure(INJURY_BLUNT, 20, BP_TORSO, flags = INJURE_SILENT) > 0, "and the injury lands again")

/datum/unit_test/dq_veto_site_injure_amount_in_flight

/datum/unit_test/dq_veto_site_injure_amount_in_flight/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/datum/dq_site_listener/listener = new
	var/before = H.injure(INJURY_BLUNT, 10, BP_TORSO, flags = INJURE_SILENT | INJURE_IGNORE_RESISTANCE)
	TEST_ASSERT(before > 0, "an injury lands")
	observe(H, /datum/act/injure, listener, adjusts("amount", scale = 0.5))
	var/halved = H.injure(INJURY_BLUNT, 10, BP_TORSO, flags = INJURE_SILENT | INJURE_IGNORE_RESISTANCE)
	TEST_ASSERT(halved < before, "an adjustment of the act's amount changes what lands ([halved] against [before])")
	unobserve(H, /datum/act/injure, listener)
	qdel(listener)

// ---- body_status: a dormant nanoform core is held alive, and answers a tool and an item used on it ----

/datum/unit_test/dq_veto_site_dormant_core

/datum/unit_test/dq_veto_site_dormant_core/Run()
	var/mob/living/carbon/human/H = make_protean_with_rig()
	var/datum/forms/protean/F = H.get_protean_forms()
	TEST_ASSERT(F.enter_rig(), "the protean should fold into its cluster")
	H.injure(INJURY_BLUNT, 1000, BP_TORSO, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	var/datum/affliction/core_dormancy/D = H.body.find_affliction(/datum/affliction/core_dormancy)
	TEST_ASSERT_NOTNULL(D, "the protean should be dormant")
	TEST_ASSERT(H.body.status_held(), "the dormant core takes the status question over: the body is held alive")
	qdel(F.rig)
	TEST_ASSERT(D.repaired_on_body(), "with no cluster the core is repaired on the body")
	var/mob/living/carbon/human/medic = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/tool/screwdriver/driver = allocate(/obj/item/tool/screwdriver)
	var/obj/item/stack/nanopaste/paste = allocate(/obj/item/stack/nanopaste)
	// A screwdriver on the sealed core is taken over by the affliction, which answers the interaction result.
	var/datum/act/tool_act/use = ACT_TRY(H, tool_act, TOOL_SCREWDRIVER, FALSE, medic, driver)
	TEST_ASSERT_NULL(use, "a screwdriver on the sealed core is taken over")
	TEST_ASSERT(ACT_TAKEN_OVER, "taken over, not refused")
	TEST_ASSERT_EQUAL(ACT_REPLY, ITEM_INTERACT_SUCCESS, "and the answer is the interaction result")
	// A secondary use, or another tool, is left alone.
	use = ACT_TRY(H, tool_act, TOOL_SCREWDRIVER, TRUE, medic, driver)
	TEST_ASSERT_NOTNULL(use, "a secondary use is not the affliction's")
	act_cancel(use)
	// Nanopaste is not the item of the first step.
	var/datum/act/attackby/hit = ACT_TRY(H, attackby, paste, medic, null)
	TEST_ASSERT_NOTNULL(hit, "nanopaste is not the item of the sealed step: the use goes on")
	act_cancel(hit)
	H.mend(TREAT_CALIBRATION, 1)
	D.open_panel()
	D.revival_step = DORMANCY_PROGRAMMED
	hit = ACT_TRY(H, attackby, paste, medic, null)
	TEST_ASSERT_NULL(hit, "nanopaste at the programmed step is taken over")
	TEST_ASSERT(ACT_TAKEN_OVER, "taken over")
	TEST_ASSERT_EQUAL(ACT_REPLY, TRUE, "and answered")
	if(hit)
		act_cancel(hit)
	// Reviving ends dormancy and its hooks.
	H.revive()
	TEST_ASSERT(!act_wanted(H, /datum/act/tool_act), "the hooks end with the dormancy")

// ---- names: a phase-shifted shadekin answers for its voice, its alt name and its visible name ----

/datum/unit_test/dq_veto_site_shadekin_names

/datum/unit_test/dq_veto_site_shadekin_names/Run()
	var/mob/living/carbon/human/H = dq_phase_test_human()
	var/datum/shadekin/SK = H.get_shadekin_state()
	var/visible = H.get_visible_name()
	TEST_ASSERT(visible != "Something", "in realspace the name is the mob's own")
	SK.in_phase = TRUE
	SK.hide_voice_in_phase = TRUE
	TEST_ASSERT_EQUAL(H.GetVoice(), "Something", "in phase the voice is hidden")
	TEST_ASSERT_EQUAL(H.get_visible_name(), "Something", "and so is the visible name")
	TEST_ASSERT_EQUAL(H.GetAltName(), "", "and there is no alt name")
	SK.hide_voice_in_phase = FALSE
	TEST_ASSERT(H.GetVoice() != "Something", "a shadekin who does not hide its voice speaks as itself")
	TEST_ASSERT_EQUAL(H.get_visible_name(), visible, "and is named as itself")
	for(var/obj/effect/temp_visual/V in get_turf(H))
		own(V)

// ---- the yes/no gates: the HUD, the health icon, the radiation tick, the geiger scan, movement relay ----

/datum/unit_test/dq_veto_site_hud_and_relay_gates

/datum/unit_test/dq_veto_site_hud_and_relay_gates/Run()
	var/mob/living/simple_mob/animal/passive/mouse/H = allocate(/mob/living/simple_mob/animal/passive/mouse, test_floor())
	var/datum/dq_site_listener/listener = new
	TEST_ASSERT(H.life_hud_health_icons(), "the default draws the health icon")
	TEST_ASSERT(!act_wanted(H, /datum/act/draw_hud), "nobody hooks the HUD")
	observe(H, /datum/act/draw_health_icon, listener, instead(then(TYPE_PROC_REF(/datum/dq_site_listener, respond))))
	observe(H, /datum/act/draw_hud, listener, instead(when(TYPE_PROC_REF(/datum/dq_site_listener, blocks))))
	TEST_ASSERT(act_wanted(H, /datum/act/draw_hud), "a hook on the HUD is asked about")
	TEST_ASSERT(!H.life_hud_health_icons(), "a hook that takes the health icon over leaves the default undrawn")
	TEST_ASSERT_EQUAL(listener.asked, 1, "it was asked once")
	listener.blocking = FALSE
	var/datum/act/draw_hud/hud = ACT_TRY(H, draw_hud)
	TEST_ASSERT_NOTNULL(hud, "a gate that does not hold lets the HUD go on")
	act_cancel(hud)
	unobserve_all(listener)
	TEST_ASSERT(H.life_hud_health_icons(), "with the hooks gone the default draws it again")
	qdel(listener)

/datum/unit_test/dq_veto_site_radiation_effects

/datum/unit_test/dq_veto_site_radiation_effects/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/geiger/counter = allocate(/obj/item/geiger, test_floor())
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, test_floor())
	H.add_radiation(50)
	TEST_ASSERT(H.radiation > 0, "the mob is irradiated")
	var/datum/trait_state/radiation_effects/state = H.add_trait_state(/datum/trait_state/radiation_effects/promethean)
	TEST_ASSERT_NOTNULL(state, "a promethean radiation state attaches")
	var/before = H.radiation
	var/datum/act/live_radiation/tick = ACT_TRY(H, live_radiation)
	TEST_ASSERT_NULL(tick, "an immune body takes the radiation tick over (the default decay does not run)")
	TEST_ASSERT(ACT_TAKEN_OVER, "taken over")
	if(tick)
		act_cancel(tick)
	TEST_ASSERT(H.radiation < before, "and the state purged some of it itself ([H.radiation] of [before])")
	var/datum/act/geiger_scan/scan = ACT_TRY(H, geiger_scan, user, counter)
	TEST_ASSERT_NULL(scan, "an irradiated subject answers the geiger scan itself")
	if(scan)
		act_cancel(scan)
	qdel(state)
	TEST_ASSERT(!act_wanted(H, /datum/act/live_radiation), "detaching the state ends its hooks")
	scan = ACT_TRY(H, geiger_scan, user, counter)
	TEST_ASSERT_EQUAL(scan, ACT_PASS, "and the scan is the counter's own again")
	act_cancel(scan)

// ---- disposal: the connection takes the flush and the arrival over ----

/datum/unit_test/dq_veto_site_disposal_connection

/datum/unit_test/dq_veto_site_disposal_connection/Run()
	var/obj/structure/toilet/toilet = allocate(/obj/structure/toilet, test_floor())
	var/datum/disposal_system_connection/original = toilet.disposal_connection
	TEST_ASSERT_NOTNULL(original, "the real toilet constructor creates its original disposal connection")
	TEST_ASSERT(!QDELETED(original), "the original constructor-created connection is alive before replacement")
	var/datum/disposal_system_connection/connection = toilet.add_disposal_connection()
	TEST_ASSERT_NOTNULL(connection, "the toilet has a disposal connection")
	TEST_ASSERT(connection != original, "the real helper supplies a distinct replacement connection")
	TEST_ASSERT(QDELETED(original), "replacement retires the exact constructor-created owned connection")
	TEST_ASSERT(act_wanted(toilet, /datum/act/flush_disposal), "the connection hooks the flush")
	// Not linked to a trunk: the connection declines, the flush goes on as if nobody hooked it.
	var/list/items = list()
	var/datum/gas_mixture/gas = new(1)
	var/datum/act/flush_disposal/flush = ACT_TRY(toilet, flush_disposal, items, gas)
	TEST_ASSERT_NOTNULL(flush, "with no trunk linked the connection leaves the flush alone")
	act_cancel(flush)
	qdel(connection)
	TEST_ASSERT(!act_wanted(toilet, /datum/act/flush_disposal), "deleting the connection ends its hook")

// ---- materials and artifacts: an item used on the holder is taken over, a shot or a blast is answered ----

/datum/unit_test/dq_veto_site_material_insert

/datum/unit_test/dq_veto_site_material_insert/Run()
	var/obj/machinery/ore_silo/silo = allocate(/obj/machinery/ore_silo, test_floor())
	var/datum/material_container/container = silo.materials
	TEST_ASSERT_NOTNULL(container, "the silo has a material container")
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, test_floor())
	TEST_ASSERT(act_wanted(silo, /datum/act/attackby), "the container hooks item use on its owner")
	var/obj/item/stack/material/steel/sheets = allocate(/obj/item/stack/material/steel, test_floor(), 5)
	var/before = container.total_amount()
	var/datum/act/attackby/use = ACT_TRY(silo, attackby, sheets, user, null)
	TEST_ASSERT_NULL(use, "steel sheets are taken over: the container takes them in")
	TEST_ASSERT(ACT_TAKEN_OVER, "taken over")
	if(use)
		act_cancel(use)
	TEST_ASSERT(container.total_amount() > before, "and the silo holds more steel than it did")

/datum/unit_test/dq_veto_site_emp_protection_combines

/datum/unit_test/dq_veto_site_emp_protection_combines/Run()
	var/obj/item/cell/cell = allocate(/obj/item/cell, test_floor())
	var/datum/dq_site_listener/listener = new
	var/datum/act/emp/pulse = ACT_TRY(cell, emp, 1, 0)
	TEST_ASSERT_EQUAL(pulse, ACT_PASS, "nothing hooks the pulse")
	observe(cell, /datum/act/emp, listener, adjusts_with(TYPE_PROC_REF(/datum/dq_site_listener, add_protection)))
	pulse = ACT_TRY(cell, emp, 1, EMP_PROTECT_WIRES)
	TEST_ASSERT_NOTNULL(pulse, "an adjustment does not take the pulse over")
	TEST_ASSERT_EQUAL(ACT_FINAL(pulse, protection, 0), EMP_PROTECT_WIRES | EMP_PROTECT_SELF, "the listener's shield combines with the atom's own flags")
	act_done(pulse)
	qdel(listener)

/datum/dq_site_listener/proc/add_protection(datum/act/emp/pulse)
	pulse.protection |= EMP_PROTECT_SELF

// ---- the cheap range observer ----

/// What the range watcher told it.
/datum/dq_range_probe
	var/entered = 0
	var/exited = 0
	var/created = 0
	var/atom/movable/last_entered
	var/atom/movable/last_exited

/datum/dq_range_probe/proc/on_enter(turf/T, atom/movable/thing, atom/old_loc)
	entered++
	last_entered = thing

/datum/dq_range_probe/proc/on_exit(turf/T, atom/movable/thing, atom/new_loc)
	exited++
	last_exited = thing

/datum/dq_range_probe/proc/on_create(turf/T, atom/movable/thing, mapload)
	created++

/datum/unit_test/dq_range_watcher_follows_its_atom

/datum/unit_test/dq_range_watcher_follows_its_atom/Run()
	var/turf/start = run_loc_floor_bottom_left
	var/turf/near = locate(start.x + 3, start.y, start.z)
	var/turf/far = locate(start.x + 24, start.y, start.z)
	TEST_ASSERT(isturf(near) && isturf(far), "the test map has room east of the origin")
	var/obj/dq_hook_hand_receiver/host = allocate(/obj/dq_hook_hand_receiver, start)
	var/datum/dq_range_probe/probe = new
	var/watching_before = GLOB.range_watch_count
	var/datum/connect_range/watcher = new(probe, host, list(RANGE_ENTERED = TYPE_PROC_REF(/datum/dq_range_probe, on_enter), RANGE_EXITED = TYPE_PROC_REF(/datum/dq_range_probe, on_exit), RANGE_INITIALIZED = TYPE_PROC_REF(/datum/dq_range_probe, on_create)), 10)
	TEST_ASSERT_EQUAL(GLOB.range_watch_count, watching_before + 1, "one watcher in the grid")
	TEST_ASSERT(length(watcher.buckets) <= 9, "a range-10 watcher is in at most nine buckets, not 441 turfs ([length(watcher.buckets)])")
	var/obj/item/pen/mover = allocate(/obj/item/pen, far)
	TEST_ASSERT_EQUAL(probe.entered, 0, "something moving about far away is not heard")
	mover.forceMove(near)
	TEST_ASSERT_EQUAL(probe.entered, 1, "something entering a turf in range is heard")
	TEST_ASSERT_EQUAL(probe.last_entered, mover, "with what entered")
	mover.forceMove(far)
	TEST_ASSERT_EQUAL(probe.exited, 1, "something leaving a turf in range is heard")
	TEST_ASSERT_EQUAL(probe.last_exited, mover, "with what left")
	// The watcher moves with its atom: the old surroundings fall silent and the new ones are heard.
	probe.entered = 0
	host.forceMove(far)
	mover.forceMove(near)
	TEST_ASSERT_EQUAL(probe.entered, 0, "the old surroundings are no longer watched")
	mover.forceMove(locate(far.x + 2, far.y, far.z))
	TEST_ASSERT_EQUAL(probe.entered, 1, "the new ones are")
	// Deleting what it tracks ends it.
	qdel(host)
	TEST_ASSERT(QDELETED(watcher), "the watcher goes with what it tracks")
	TEST_ASSERT_EQUAL(GLOB.range_watch_count, watching_before, "and leaves the grid")
	qdel(probe)

/datum/unit_test/dq_range_watcher_proximity_monitor

/datum/unit_test/dq_range_watcher_proximity_monitor/Run()
	var/turf/start = run_loc_floor_bottom_left
	var/turf/near = locate(start.x + 2, start.y, start.z)
	var/turf/far = locate(start.x + 24, start.y, start.z)
	var/obj/dq_hook_hand_receiver/host = allocate(/obj/dq_hook_hand_receiver, start)
	var/datum/proximity_monitor/monitor = new(host, 3)
	var/obj/item/pen/mover = allocate(/obj/item/pen, far)
	var/before = host.prox_calls
	mover.forceMove(near)
	TEST_ASSERT(host.prox_calls > before, "something coming within range of a proximity monitor reaches its receiver")
	before = host.prox_calls
	mover.forceMove(far)
	TEST_ASSERT_EQUAL(host.prox_calls, before, "leaving does not call HasProximity")
	qdel(monitor)
	before = host.prox_calls
	mover.forceMove(near)
	TEST_ASSERT_EQUAL(host.prox_calls, before, "a deleted monitor is not told anything")
