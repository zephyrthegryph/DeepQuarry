// Behaviour-preservation tests for the APC domain (phase 2): they pin what a player, an AI or a borg can observe of an area power
// controller through public inputs (clicks, window buttons, damage entry points, time), so the same file passes before and after the
// APC moves from the capability library to the engine forms.
//
// Rules the tests keep:
//   - Input goes through test_click(), the window adapter p2_apc_ui() and the damage entry points; never an op key.
//   - State is read through the small adapter block below (the only place that names today's accessors) and plain vars.
//   - Every input is followed by p2_settle() (10 seconds of kernel time), because tool waits differ between the two implementations.
//     A test that cares about elapsed time asserts state at explicit times with test_time().
//   - Nothing here depends on message text, on an op key or on a click result being non-null.

// ---------------------------------------------------------------------------------------------------------------------
// Adapters: today's accessors, wrapped. After the conversion only these bodies change.
// ---------------------------------------------------------------------------------------------------------------------

/// The cover is open.
/proc/p2_apc_cover_open(obj/machinery/power/apc/A)
	return !!cover_open(A, null)

/// The cover has been knocked off (a broken APC's cover, which also leaves it open).
/proc/p2_apc_cover_removed(obj/machinery/power/apc/A)
	return !!cover_removed(A, null)

/// The wire panel is open.
/proc/p2_apc_panel_open(obj/machinery/power/apc/A)
	return !!panel_open(A, null)

/// The ID lock is engaged.
/proc/p2_apc_locked(obj/machinery/power/apc/A)
	return !!lock_locked(A, null)

/// The APC's interface was subverted by an emag.
/proc/p2_apc_emagged(obj/machinery/power/apc/A)
	return !!emag_emagged(A, null)

/// How far the frame is built: "frame", "board", "wired" or "secured".
/proc/p2_apc_stage(obj/machinery/power/apc/A)
	switch(graph_current(A))
		if(STAGE_APC_FRAME)
			return "frame"
		if(STAGE_APC_BOARD)
			return "board"
		if(STAGE_APC_WIRED)
			return "wired"
		if(STAGE_APC_SECURED)
			return "secured"
	return null

/// The wire controller of the APC (cut(), pulse(), is_cut(), cut_all(), interactable()).
/proc/p2_apc_wires(obj/machinery/power/apc/A)
	return new /datum/wires_test_adapter(A)

/// The APC's interface is subverted, as an emag leaves it: subverted and unlocked.
/proc/p2_apc_subvert(obj/machinery/power/apc/A)
	key_set(A, EMAG_EMAGGED, TRUE)
	key_set(A, LOCK_LOCKED, FALSE)

/// Somebody opens the APC's window (the touch of a hand or a silicon).
/proc/p2_apc_open_interface(obj/machinery/power/apc/A, mob/user)
	if(issilicon(user))
		A.tgui_interact(user) // a silicon's interface: what the remote() binding of the open op does
		return
	test_click(user, A, null)
	test_time(1 SECOND)

/// The lights of the area the APC powers.
/proc/p2_apc_area_lights(obj/machinery/power/apc/A)
	return A.area_lights()

/// Presses a window button as the actor: the engine's op if the APC has one for the action, else today's tgui_act().
/proc/p2_apc_ui(mob/actor, obj/machinery/power/apc/A, action, list/args)
	var/datum/op_result/result = test_ui(actor, A, action, args)
	if(result)
		return result
	var/datum/tgui/ui = new(actor, A, "APC")
	ui.status = STATUS_INTERACTIVE
	. = A.tgui_act(action, args || list(), ui)
	qdel(ui)

/// The APC's window was opened for `user` (a test mob has no client, so the type records the open).
/proc/p2_apc_interface_opened(obj/machinery/power/apc/A, mob/user)
	var/obj/machinery/power/apc/p2_test/P = A
	return istype(P) && (user in P.p2_opened)

/// After a change a test made to the cell or the channels, the power domain is told once (the Rust copy, the area's channels).
/proc/p2_apc_resync(obj/machinery/power/apc/A)
	A.seat_cell_charge(TRUE)
	native_write(A, NATIVE_APC_CHANNELS, A.equipment, 0)
	native_write(A, NATIVE_APC_CHANNELS, A.lighting, 1)
	native_write(A, NATIVE_APC_CHANNELS, A.environ, 2)
	A.apply_area_power()
	A.push_to_rust() // the test rewrote the area's requires_power, which the APC never sees change in a round
	refresh_flush()

/// The area takes `watts` more static load on the equipment channel (negative: gives it back).
/proc/p2_apc_load(obj/machinery/power/apc/A, watts)
	dq_area_load(get_turf(A), watts, EQUIP)

/// One power step as the game runs it.
/proc/p2_apc_power_step()
	refresh_flush()
	dq_power_test_step()

/// The channel `index` of the area is powered (0 equipment, 1 lighting, 2 environment).
/proc/p2_apc_area_powered(obj/machinery/power/apc/A, index)
	return !!(index == 0 ? A.area.power_equip : (index == 1 ? A.area.power_light : A.area.power_environ))

/// The APC's output is down for a while (an EMP, an overload event, a supermatter shutdown): its power failure is on.
/proc/p2_apc_failed(obj/machinery/power/apc/A)
	return A.failure_left() > 0

/// The frame is not finished (its electronics are not fastened): it does not run.
/proc/p2_apc_unfinished(obj/machinery/power/apc/A)
	return !built(A, STAGE_APC_SECURED)

/// A power failure of `seconds` (what the electrical fault event and the supermatter do).
/proc/p2_apc_energy_fail(obj/machinery/power/apc/A, seconds)
	A.energy_fail(seconds SECONDS / MACHINE_SERVICE_INTERVAL)

/// The station night shift turns on or off (the night-shift system's command).
/proc/p2_apc_station_night(night)
	SSnightshift.update_nightshift(night, FALSE, forced = TRUE)

/// The APC's wires, recording who reached their window (a test mob has no client to open it for).
/proc/p2_apc_record_wire_window(obj/machinery/power/apc/A)
	GLOB.wires_test_opened -= A
	return new /datum/wires_test_adapter(A)

/// The wire window was reached by `user`.
/proc/p2_apc_wire_window_opened(datum/wires_test_adapter/W, mob/user)
	return user in W.opened_for()

/// The test APC: a real APC, except that a test mob has no client (can_use() asks for one) and the type records who opened its window.
/obj/machinery/power/apc/p2_test
	var/list/p2_opened

/obj/machinery/power/apc/p2_test/critical
	is_critical = 1

/obj/machinery/power/apc/p2_test/tgui_interact(mob/user, datum/tgui/ui, datum/tgui/parent_ui, custom_state)
	LAZYADD(p2_opened, user)
	return ..()

// ---------------------------------------------------------------------------------------------------------------------
// The base: the kernel on its injected clock around the test, the area as it was after.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_apc
	abstract_type = /datum/unit_test/dq_p2_apc
	var/list/p2_apcs
	var/area/p2_area
	var/p2_area_requires
	var/p2_area_light
	var/p2_area_equip
	var/p2_area_environ
	var/datum/decl/flooring/p2_flooring
	var/list/p2_cables

/datum/unit_test/dq_p2_apc/Run()
	test_driver_begin()
	test_rng(1)
	p2_area = get_area(run_loc_floor_bottom_left)
	p2_area_requires = p2_area.requires_power
	p2_area_light = p2_area.power_light
	p2_area_equip = p2_area.power_equip
	p2_area_environ = p2_area.power_environ
	var/turf/simulated/floor/F = run_loc_floor_bottom_left
	p2_flooring = F.flooring
	run_gate()
	for(var/obj/machinery/power/apc/A as anything in p2_apcs)
		if(!QDELETED(A))
			qdel(A)
	for(var/obj/structure/cable/C as anything in p2_cables)
		if(!QDELETED(C))
			qdel(C)
	own_turf_contents(run_loc_floor_bottom_left)
	own_turf_contents(run_loc_floor_top_right)
	if(F.flooring != p2_flooring)
		F.set_flooring(p2_flooring)
	p2_area.requires_power = p2_area_requires
	p2_area.power_light = p2_area_light
	p2_area.power_equip = p2_area_equip
	p2_area.power_environ = p2_area_environ
	test_driver_end()

/datum/unit_test/dq_p2_apc/proc/run_gate()
	return

/// A conscious person with hands, who cannot be knocked out by the test's passing time.
/datum/unit_test/dq_p2_apc/proc/p2_actor(turf/T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T || run_loc_floor_bottom_left)
	H.enable_godmode()
	return H

/// A cyborg (a silicon's touch is the interface route, and it works a locked APC).
/datum/unit_test/dq_p2_apc/proc/p2_borg(turf/T)
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, T || run_loc_floor_bottom_left)
	R.enable_godmode()
	return R

/// A finished APC as a map places it: locked, cover shut, a 90% cell, breaker on.
/datum/unit_test/dq_p2_apc/proc/p2_apc(turf/T, type = /obj/machinery/power/apc/p2_test)
	var/obj/machinery/power/apc/A = allocate(type, T || run_loc_floor_bottom_left)
	LAZYADD(p2_apcs, A)
	return A

/// A cable end under the APC's terminal, so the terminal has a network to join.
/datum/unit_test/dq_p2_apc/proc/p2_cable(turf/T)
	var/obj/structure/cable/C = dq_power_test_cable(T || run_loc_floor_bottom_left, 0, EAST)
	LAZYADD(p2_cables, C)
	return C

/// A bare frame as a builder leaves it: no cell, no board, the cover open, the breaker off.
/datum/unit_test/dq_p2_apc/proc/p2_frame(turf/T)
	var/obj/machinery/power/apc/A = allocate(/obj/machinery/power/apc/p2_test, T || run_loc_floor_bottom_left, SOUTH, TRUE)
	LAZYADD(p2_apcs, A)
	return A

/// Time for any wait a tool or a window press may start.
/datum/unit_test/dq_p2_apc/proc/p2_settle()
	test_time(10 SECONDS)
	if(GLOB.op_pure_depth)
		Fail("ZDEBUG pure depth [GLOB.op_pure_depth] after settle")
		GLOB.op_pure_depth = 0

/// The actor puts `held` in the active hand (an empty hand when null), clicks the target and waits.
/datum/unit_test/dq_p2_apc/proc/touch(mob/living/carbon/human/H, atom/target, obj/item/held)
	H.drop_item()
	if(held)
		H.put_in_active_hand(held)
	test_click(H, target, held)
	if(GLOB.op_pure_depth)
		Fail("ZDEBUG pure depth [GLOB.op_pure_depth] right after click on [target] with [held]")
		GLOB.op_pure_depth = 0
	p2_settle()

/// The actor presses a window button and waits.
/datum/unit_test/dq_p2_apc/proc/press(mob/actor, obj/machinery/power/apc/A, action, list/args)
	p2_apc_ui(actor, A, action, args)
	p2_settle()

/// A tool with no speed penalty.
/datum/unit_test/dq_p2_apc/proc/tool(path)
	return dq_fast_tool(path, run_loc_floor_bottom_left)

/// An ID card with engineering access (or none).
/datum/unit_test/dq_p2_apc/proc/id_card(has_access = TRUE)
	var/obj/item/card/id/card = allocate(/obj/item/card/id, run_loc_floor_bottom_left)
	card.access = has_access ? list(ACCESS_ENGINE_EQUIP) : list()
	return card

/// Opens the cover of a finished APC: the cover lock off, then the crowbar.
/datum/unit_test/dq_p2_apc/proc/open_cover(mob/living/carbon/human/H, obj/machinery/power/apc/A)
	A.coverlocked = FALSE
	touch(H, A, tool(/obj/item/tool/crowbar))

/// The wire panel open (the screwdriver, with the cover shut).
/datum/unit_test/dq_p2_apc/proc/open_panel(mob/living/carbon/human/H, obj/machinery/power/apc/A)
	touch(H, A, tool(/obj/item/tool/screwdriver))

/// Unlocks the APC with an engineering ID in the actor's hand.
/datum/unit_test/dq_p2_apc/proc/unlock(mob/living/carbon/human/H, obj/machinery/power/apc/A)
	touch(H, A, id_card())

/// The floor the APC stands on, bared to the plating.
/datum/unit_test/dq_p2_apc/proc/bare_floor()
	var/turf/simulated/floor/F = run_loc_floor_bottom_left
	F.make_plating()

// ---------------------------------------------------------------------------------------------------------------------
// A mapped APC
// ---------------------------------------------------------------------------------------------------------------------

/// A finished APC with its cell spawns locked, shut, powered and serving its area.
/datum/unit_test/dq_p2_apc/mapped_apc_spawns_locked_closed_and_works

/datum/unit_test/dq_p2_apc/mapped_apc_spawns_locked_closed_and_works/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	p2_settle()
	TEST_ASSERT(p2_apc_locked(A), "the ID lock starts engaged")
	TEST_ASSERT(!p2_apc_cover_open(A), "the cover starts shut")
	TEST_ASSERT(!p2_apc_panel_open(A), "the wire panel starts shut")
	TEST_ASSERT(!p2_apc_emagged(A), "not subverted")
	TEST_ASSERT_EQUAL(p2_apc_stage(A), "secured", "a finished frame")
	TEST_ASSERT(A.coverlocked, "the cover lock starts on")
	TEST_ASSERT_NOTNULL(A.cell, "it starts with a cell")
	TEST_ASSERT_EQUAL(round(A.cell.percent()), 90, "charged to the start level")
	TEST_ASSERT_NOTNULL(A.terminal, "it has a terminal")
	TEST_ASSERT_EQUAL(A.terminal.master, A, "which answers to the APC")
	TEST_ASSERT(A.operating, "the breaker is on")
	TEST_ASSERT_EQUAL(A.equipment, POWERCHAN_ON_AUTO, "equipment on auto")
	TEST_ASSERT_EQUAL(A.lighting, POWERCHAN_ON_AUTO, "lighting on auto")
	TEST_ASSERT_EQUAL(A.environ, POWERCHAN_ON_AUTO, "environment on auto")
	TEST_ASSERT(!A.shorted && !p2_apc_failed(A), "neither shorted nor failed")
	TEST_ASSERT(!A.has_stat(BROKEN) && !p2_apc_unfinished(A), "neither broken nor under maintenance")
	TEST_ASSERT(A.operable(), "it works")
	TEST_ASSERT_EQUAL(A.get_integrity(), A.max_integrity, "undamaged")
	for(var/index in 0 to 2)
		TEST_ASSERT(p2_apc_area_powered(A, index), "channel [index] of the area is powered")

/// The area it stands in lists it, and the lights of the area are the ones it reads.
/datum/unit_test/dq_p2_apc/area_membership_and_lights

/datum/unit_test/dq_p2_apc/area_membership_and_lights/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	TEST_ASSERT_EQUAL(A.area, get_area(A), "the APC serves the area it stands in")
	TEST_ASSERT_EQUAL(A.area.apc, A, "and the area names it")
	var/obj/machinery/light/L = allocate(/obj/machinery/light, run_loc_floor_bottom_left)
	TEST_ASSERT(L in p2_apc_area_lights(A), "a light of the area is one of its lights")
	qdel(L)
	TEST_ASSERT(!(L in p2_apc_area_lights(A)), "a deleted light leaves the list")

/// The area's lights follow the APC's lighting channel: the breaker off darkens them, on lights them again.
/datum/unit_test/dq_p2_apc/area_lights_follow_the_channels

/datum/unit_test/dq_p2_apc/area_lights_follow_the_channels/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/carbon/human/H = p2_actor()
	p2_area.requires_power = TRUE
	var/obj/machinery/light/L = allocate(/obj/machinery/light, run_loc_floor_bottom_left)
	p2_apc_resync(A)
	p2_settle()
	TEST_ASSERT(L.has_power(), "powered while the APC serves the lighting channel")
	unlock(H, A)
	press(H, A, "breaker", list())
	TEST_ASSERT(!A.operating, "the breaker is off")
	TEST_ASSERT(!L.has_power(), "the light lost its power")
	press(H, A, "breaker", list())
	TEST_ASSERT(A.operating, "the breaker is on again")
	TEST_ASSERT(L.has_power(), "the light has power again")

// ---------------------------------------------------------------------------------------------------------------------
// The ID lock
// ---------------------------------------------------------------------------------------------------------------------

/// An engineering ID in the hand toggles the lock, both ways.
/datum/unit_test/dq_p2_apc/id_lock_toggles_with_an_allowed_id

/datum/unit_test/dq_p2_apc/id_lock_toggles_with_an_allowed_id/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/item/card/id/card = id_card()
	TEST_ASSERT(p2_apc_locked(A), "locked to start")
	touch(H, A, card)
	TEST_ASSERT(!p2_apc_locked(A), "the ID unlocked it")
	touch(H, A, card)
	TEST_ASSERT(p2_apc_locked(A), "the same ID locked it again")

/// An ID without the access does nothing.
/datum/unit_test/dq_p2_apc/id_lock_refused_without_access

/datum/unit_test/dq_p2_apc/id_lock_refused_without_access/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/carbon/human/H = p2_actor()
	touch(H, A, id_card(FALSE))
	TEST_ASSERT(p2_apc_locked(A), "an ID with no access leaves it locked")
	unlock(H, A)
	TEST_ASSERT(!p2_apc_locked(A), "the right ID unlocks it")
	touch(H, A, id_card(FALSE))
	TEST_ASSERT(!p2_apc_locked(A), "and the wrong one does not lock it")

/// A cut ID scan wire or a subverted interface refuses the ID.
/datum/unit_test/dq_p2_apc/id_lock_refused_when_wire_cut_or_subverted

/datum/unit_test/dq_p2_apc/id_lock_refused_when_wire_cut_or_subverted/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/carbon/human/H = p2_actor()
	var/datum/wires_test_adapter/W = p2_apc_wires(A)
	W.cut(WIRE_IDSCAN)
	touch(H, A, id_card())
	TEST_ASSERT(p2_apc_locked(A), "a cut ID scan wire: the ID does nothing")
	W.cut(WIRE_IDSCAN) // cut() toggles: mended
	touch(H, A, id_card())
	TEST_ASSERT(!p2_apc_locked(A), "the wire mended, the ID works")
	touch(H, A, id_card()) // locked again
	TEST_ASSERT(p2_apc_locked(A), "locked again")
	p2_apc_subvert(A)
	TEST_ASSERT(p2_apc_emagged(A), "subverted")
	touch(H, A, id_card())
	TEST_ASSERT(!p2_apc_locked(A), "a subverted panel stays unlocked")
	touch(H, A, id_card())
	TEST_ASSERT(!p2_apc_locked(A), "and does not take the ID's lock")

/// With the cover or the wire panel open the ID is not offered.
/datum/unit_test/dq_p2_apc/id_lock_refused_with_cover_or_panel_open

/datum/unit_test/dq_p2_apc/id_lock_refused_with_cover_or_panel_open/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/item/card/id/card = id_card()
	open_cover(H, A)
	TEST_ASSERT(p2_apc_cover_open(A), "the cover is open")
	touch(H, A, card)
	TEST_ASSERT(p2_apc_locked(A), "no swipe with the cover open")
	touch(H, A, tool(/obj/item/tool/crowbar))
	TEST_ASSERT(!p2_apc_cover_open(A), "the cover is shut again")
	open_panel(H, A)
	TEST_ASSERT(p2_apc_panel_open(A), "the wire panel is open")
	touch(H, A, card)
	TEST_ASSERT(p2_apc_locked(A), "no swipe with the panel open")

// ---------------------------------------------------------------------------------------------------------------------
// The cover
// ---------------------------------------------------------------------------------------------------------------------

/// The cover lock holds the cover against the crowbar while the cell is charged.
/datum/unit_test/dq_p2_apc/cover_lock_holds_with_a_charged_cell

/datum/unit_test/dq_p2_apc/cover_lock_holds_with_a_charged_cell/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/carbon/human/H = p2_actor()
	touch(H, A, tool(/obj/item/tool/crowbar))
	TEST_ASSERT(!p2_apc_cover_open(A), "the cover lock holds with a charged cell")

/// A nearly flat cell lets the crowbar pry the cover open although the cover lock is on.
/datum/unit_test/dq_p2_apc/flat_cell_lets_the_cover_open

/datum/unit_test/dq_p2_apc/flat_cell_lets_the_cover_open/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/carbon/human/H = p2_actor()
	A.cell.charge = A.cell.maxcharge * (CELL_BAY_LOW_PERCENT - 5) / 100
	TEST_ASSERT(A.coverlocked, "the cover lock is on")
	touch(H, A, tool(/obj/item/tool/crowbar))
	TEST_ASSERT(p2_apc_cover_open(A), "a nearly flat cell lets the cover go")

/// With the cover lock off the crowbar opens the cover although the cell is charged, and shuts it once the cell is out.
/datum/unit_test/dq_p2_apc/crowbar_opens_and_closes_the_cover

/datum/unit_test/dq_p2_apc/crowbar_opens_and_closes_the_cover/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/item/tool/crowbar/bar = tool(/obj/item/tool/crowbar)
	A.coverlocked = FALSE
	touch(H, A, bar)
	TEST_ASSERT(p2_apc_cover_open(A), "with the cover lock off a charged cell does not hold it")
	touch(H, A, null)
	TEST_ASSERT_NULL(A.cell, "the cell is out")
	touch(H, A, bar)
	TEST_ASSERT(!p2_apc_cover_open(A), "and the crowbar shuts it")
	touch(H, A, bar)
	TEST_ASSERT(p2_apc_cover_open(A), "and opens it again")

/// A broken APC's cover can't be pried open, and the cover lock does not stop shutting.
/datum/unit_test/dq_p2_apc/broken_apc_cover_stays_shut

/datum/unit_test/dq_p2_apc/broken_apc_cover_stays_shut/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/carbon/human/H = p2_actor()
	A.coverlocked = FALSE
	A.take_damage(A.max_integrity * 0.75)
	p2_settle()
	TEST_ASSERT(A.has_stat(BROKEN), "three quarters of its integrity gone: broken")
	touch(H, A, tool(/obj/item/tool/crowbar))
	TEST_ASSERT(!p2_apc_cover_open(A), "a broken APC's cover can't be pried open")

/// A hard hit on a broken APC eventually knocks the cover off; a light one, or a hit on a whole APC, never does.
/datum/unit_test/dq_p2_apc/cover_knocked_off_by_force_on_a_broken_apc

/datum/unit_test/dq_p2_apc/cover_knocked_off_by_force_on_a_broken_apc/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/item/bat = allocate(/obj/item, run_loc_floor_bottom_left)
	bat.force = 10
	bat.w_class = ITEMSIZE_NORMAL
	var/obj/item/twig = allocate(/obj/item, run_loc_floor_bottom_left)
	twig.force = 1
	twig.w_class = ITEMSIZE_TINY
	for(var/i in 1 to 40)
		A.attackby(bat, H)
	TEST_ASSERT(!p2_apc_cover_removed(A), "a whole APC keeps its cover")
	A.take_damage(A.max_integrity * 0.75)
	p2_settle()
	TEST_ASSERT(A.has_stat(BROKEN), "broken")
	for(var/i in 1 to 40)
		A.attackby(twig, H)
	TEST_ASSERT(!p2_apc_cover_removed(A), "a light tap never knocks the cover off")
	for(var/i in 1 to 200)
		if(p2_apc_cover_removed(A))
			break
		A.attackby(bat, H)
	TEST_ASSERT(p2_apc_cover_removed(A), "a heavy hit on a broken APC knocks the cover off")
	TEST_ASSERT(p2_apc_cover_open(A), "and leaves it open")

/// A new APC frame replaces a knocked-off cover once the cell is out: the APC is whole again.
/datum/unit_test/dq_p2_apc/knocked_off_cover_is_replaced_with_a_frame

/datum/unit_test/dq_p2_apc/knocked_off_cover_is_replaced_with_a_frame/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/item/bat = allocate(/obj/item, run_loc_floor_bottom_left)
	bat.force = 10
	bat.w_class = ITEMSIZE_NORMAL
	var/obj/item/frame/apc/frame = allocate(/obj/item/frame/apc, run_loc_floor_bottom_left)
	var/obj/item/tool/crowbar/bar = tool(/obj/item/tool/crowbar)
	A.coverlocked = FALSE
	touch(H, A, bar)
	touch(H, A, null)
	TEST_ASSERT_NULL(A.cell, "the cell is out")
	touch(H, A, bar)
	TEST_ASSERT(!p2_apc_cover_open(A), "the cover is shut over the empty bay")
	A.take_damage(A.max_integrity * 0.75)
	p2_settle()
	TEST_ASSERT(A.has_stat(BROKEN), "broken")
	for(var/i in 1 to 200)
		if(p2_apc_cover_removed(A))
			break
		A.attackby(bat, H)
	TEST_ASSERT(p2_apc_cover_removed(A), "the cover is off")
	touch(H, A, frame)
	TEST_ASSERT(!p2_apc_cover_removed(A), "a new cover goes on")
	TEST_ASSERT(!A.has_stat(BROKEN), "the APC is whole again")
	TEST_ASSERT(QDELETED(frame), "the frame was used up")

/// With the cell still in, a new frame does not replace the knocked-off cover and is not used up.
/datum/unit_test/dq_p2_apc/cover_replacement_refused_with_a_cell_in

/datum/unit_test/dq_p2_apc/cover_replacement_refused_with_a_cell_in/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/item/bat = allocate(/obj/item, run_loc_floor_bottom_left)
	bat.force = 10
	bat.w_class = ITEMSIZE_NORMAL
	var/obj/item/frame/apc/frame = allocate(/obj/item/frame/apc, run_loc_floor_bottom_left)
	A.take_damage(A.max_integrity * 0.75)
	for(var/i in 1 to 200)
		if(p2_apc_cover_removed(A))
			break
		A.attackby(bat, H)
	TEST_ASSERT(p2_apc_cover_removed(A), "the cover is off")
	touch(H, A, frame)
	TEST_ASSERT(p2_apc_cover_removed(A), "the cover is still off")
	TEST_ASSERT(A.has_stat(BROKEN), "and the APC still broken")
	TEST_ASSERT(!QDELETED(frame), "the frame is not used up")

// ---------------------------------------------------------------------------------------------------------------------
// The wire panel and the wires
// ---------------------------------------------------------------------------------------------------------------------

/// A screwdriver opens and shuts the panel, but not with the cover open.
/datum/unit_test/dq_p2_apc/screwdriver_panel_needs_the_cover_closed

/datum/unit_test/dq_p2_apc/screwdriver_panel_needs_the_cover_closed/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/item/tool/screwdriver/driver = tool(/obj/item/tool/screwdriver)
	touch(H, A, driver)
	TEST_ASSERT(p2_apc_panel_open(A), "the screwdriver opens the panel")
	touch(H, A, driver)
	TEST_ASSERT(!p2_apc_panel_open(A), "and shuts it")
	open_cover(H, A)
	TEST_ASSERT(p2_apc_cover_open(A), "cover open")
	touch(H, A, driver)
	TEST_ASSERT(!p2_apc_panel_open(A), "no panel with the cover open")

/// The power wires short the APC; mending both clears it.
/datum/unit_test/dq_p2_apc/power_wires_short_the_apc

/datum/unit_test/dq_p2_apc/power_wires_short_the_apc/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/carbon/human/H = p2_actor()
	var/datum/wires_test_adapter/W = p2_apc_wires(A)
	W.cut(WIRE_MAIN_POWER1, H)
	p2_settle()
	TEST_ASSERT(A.shorted, "one power wire cut: shorted")
	W.cut(WIRE_MAIN_POWER2, H)
	W.cut(WIRE_MAIN_POWER1, H)
	p2_settle()
	TEST_ASSERT(A.shorted, "one wire mended, the other still cut: shorted")
	W.cut(WIRE_MAIN_POWER2, H)
	p2_settle()
	TEST_ASSERT(!A.shorted, "both mended")

/// Pulsing the power wire shorts the APC for two minutes; the AI wire turns off AI control for a second, cutting it for good.
/datum/unit_test/dq_p2_apc/pulsed_wires_have_timed_effects

/datum/unit_test/dq_p2_apc/pulsed_wires_have_timed_effects/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/datum/wires_test_adapter/W = p2_apc_wires(A)
	W.pulse(WIRE_MAIN_POWER1)
	TEST_ASSERT(A.shorted, "a pulse on the power wire shorts it")
	test_time(1 MINUTES)
	TEST_ASSERT(A.shorted, "still shorted a minute on")
	test_time(70 SECONDS)
	TEST_ASSERT(!A.shorted, "and clear after two minutes")
	W.pulse(WIRE_AI_CONTROL)
	TEST_ASSERT(A.aidisabled, "a pulse on the AI wire disables AI control")
	test_time(3 SECONDS)
	TEST_ASSERT(!A.aidisabled, "for a moment only")
	W.cut(WIRE_AI_CONTROL)
	TEST_ASSERT(A.aidisabled, "cut, it stays disabled")
	test_time(1 MINUTES)
	TEST_ASSERT(A.aidisabled, "for good")
	W.cut(WIRE_AI_CONTROL)
	TEST_ASSERT(!A.aidisabled, "mended, it is back")

/// Pulsing the ID scan wire unlocks the APC and it locks itself again after thirty seconds.
/datum/unit_test/dq_p2_apc/id_scan_pulse_unlocks_for_a_while

/datum/unit_test/dq_p2_apc/id_scan_pulse_unlocks_for_a_while/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/datum/wires_test_adapter/W = p2_apc_wires(A)
	TEST_ASSERT(p2_apc_locked(A), "locked to start")
	W.pulse(WIRE_IDSCAN)
	TEST_ASSERT(!p2_apc_locked(A), "the pulse unlocked it")
	test_time(20 SECONDS)
	TEST_ASSERT(!p2_apc_locked(A), "still open after twenty seconds")
	test_time(15 SECONDS)
	TEST_ASSERT(p2_apc_locked(A), "locked again after thirty")

/// The wires answer only behind the open panel with the cover shut.
/datum/unit_test/dq_p2_apc/wires_reachable_only_behind_the_open_panel

/datum/unit_test/dq_p2_apc/wires_reachable_only_behind_the_open_panel/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/carbon/human/H = p2_actor()
	var/datum/wires_test_adapter/W = p2_apc_wires(A)
	TEST_ASSERT(!W.interactable(H), "shut: not reachable")
	open_panel(H, A)
	TEST_ASSERT(W.interactable(H), "the panel open: reachable")
	touch(H, A, tool(/obj/item/tool/screwdriver))
	open_cover(H, A)
	TEST_ASSERT(p2_apc_cover_open(A), "cover open")
	TEST_ASSERT(!W.interactable(H), "behind the open cover: not reachable")

// ---------------------------------------------------------------------------------------------------------------------
// The emag and the multitool reset
// ---------------------------------------------------------------------------------------------------------------------

/// A subverted APC stays unlocked and does not take the ID's lock.
/datum/unit_test/dq_p2_apc/subverted_apc_stays_unlocked

/datum/unit_test/dq_p2_apc/subverted_apc_stays_unlocked/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/carbon/human/H = p2_actor()
	p2_apc_subvert(A)
	TEST_ASSERT(p2_apc_emagged(A), "subverted")
	TEST_ASSERT(!p2_apc_locked(A), "and unlocked")
	touch(H, A, id_card())
	TEST_ASSERT(!p2_apc_locked(A), "the ID cannot lock it")
	TEST_ASSERT(p2_apc_emagged(A), "and does not clear the subversion")

/// The multitool resets a subverted APC (cell out, cover open): the subversion is gone.
/datum/unit_test/dq_p2_apc/multitool_reset_clears_subversion

/datum/unit_test/dq_p2_apc/multitool_reset_clears_subversion/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/item/multitool/multi = allocate(/obj/item/multitool, run_loc_floor_bottom_left)
	p2_apc_subvert(A)
	TEST_ASSERT(p2_apc_emagged(A), "subverted")
	open_cover(H, A)
	TEST_ASSERT(p2_apc_cover_open(A), "cover open")
	touch(H, A, multi)
	TEST_ASSERT(p2_apc_emagged(A), "with the cell in, the reset is refused")
	touch(H, A, null)
	TEST_ASSERT_NULL(A.cell, "the cell is out")
	touch(H, A, multi)
	TEST_ASSERT(!p2_apc_emagged(A), "the multitool reset it")
	TEST_ASSERT(!A.operating, "a reset leaves the breaker off")
	TEST_ASSERT_EQUAL(A.lighting, POWERCHAN_ON_AUTO, "and the channels on auto")

/// The multitool is not offered on an APC nobody subverted.
/datum/unit_test/dq_p2_apc/multitool_does_nothing_on_a_sound_apc

/datum/unit_test/dq_p2_apc/multitool_does_nothing_on_a_sound_apc/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/item/multitool/multi = allocate(/obj/item/multitool, run_loc_floor_bottom_left)
	A.operating = TRUE
	open_cover(H, A)
	touch(H, A, null)
	TEST_ASSERT_NULL(A.cell, "cell out")
	touch(H, A, multi)
	TEST_ASSERT(A.operating, "no reset: the breaker is as it was")

// ---------------------------------------------------------------------------------------------------------------------
// The cell bay and the interface
// ---------------------------------------------------------------------------------------------------------------------

/// With the cover open an empty hand takes the cell, and the cell in hand goes back in.
/datum/unit_test/dq_p2_apc/cell_take_and_insert_with_the_cover_open

/datum/unit_test/dq_p2_apc/cell_take_and_insert_with_the_cover_open/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/item/cell/original = A.cell
	open_cover(H, A)
	TEST_ASSERT(p2_apc_cover_open(A), "cover open")
	touch(H, A, null)
	TEST_ASSERT_NULL(A.cell, "the empty hand took the cell")
	TEST_ASSERT(H.is_in_hands(original), "into the hand")
	touch(H, A, original)
	TEST_ASSERT_EQUAL(A.cell, original, "the cell in hand goes back in")
	TEST_ASSERT_EQUAL(original.loc, A, "inside the APC")

/// A closed cover keeps the bay out of reach: a hand cannot take the cell.
/datum/unit_test/dq_p2_apc/closed_cover_keeps_the_cell_out_of_reach

/datum/unit_test/dq_p2_apc/closed_cover_keeps_the_cell_out_of_reach/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/item/cell/original = A.cell
	touch(H, A, null)
	TEST_ASSERT_EQUAL(A.cell, original, "the cell stays in a closed APC")

/// A device cell is too small for the bay.
/datum/unit_test/dq_p2_apc/small_cell_does_not_fit

/datum/unit_test/dq_p2_apc/small_cell_does_not_fit/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/item/cell/small = allocate(/obj/item/cell/device, run_loc_floor_bottom_left)
	open_cover(H, A)
	touch(H, A, null)
	TEST_ASSERT_NULL(A.cell, "bay empty")
	touch(H, A, small)
	TEST_ASSERT_NULL(A.cell, "a device cell does not fit")

/// With an ID worn, an empty hand on the closed APC toggles the lock by the wearer's own access.
/datum/unit_test/dq_p2_apc/empty_hand_with_a_worn_id_toggles_the_lock

/datum/unit_test/dq_p2_apc/empty_hand_with_a_worn_id_toggles_the_lock/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/item/card/id/card = id_card()
	H.equip_to_slot_or_del(allocate(/obj/item/clothing/under/color/grey, run_loc_floor_bottom_left), SLOT_ID_UNIFORM)
	H.equip_to_slot_or_del(card, SLOT_ID_ID)
	TEST_ASSERT_EQUAL(H.get_equipped_item(SLOT_ID_ID), card, "the ID is worn")
	touch(H, A, null)
	TEST_ASSERT(!p2_apc_locked(A), "the wearer's access unlocked it")
	touch(H, A, null)
	TEST_ASSERT(p2_apc_locked(A), "and locked it again")

/// The touch of a hand or a silicon opens the window; a person at an APC with its wire panel open sees the wires instead.
/datum/unit_test/dq_p2_apc/touch_opens_the_interface_window

/datum/unit_test/dq_p2_apc/touch_opens_the_interface_window/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/carbon/human/H = p2_actor()
	var/mob/living/silicon/robot/R = p2_borg()
	p2_apc_open_interface(A, H)
	TEST_ASSERT(p2_apc_interface_opened(A, H), "a person's touch opens the window")
	p2_apc_open_interface(A, R)
	TEST_ASSERT(p2_apc_interface_opened(A, R), "so does a cyborg's")
	open_panel(H, A)
	TEST_ASSERT(p2_apc_panel_open(A), "panel open")
	var/mob/living/carbon/human/other = p2_actor()
	p2_apc_open_interface(A, other)
	TEST_ASSERT(!p2_apc_interface_opened(A, other), "with the panel open a person sees the wires, not the window")
	p2_apc_open_interface(A, R)
	TEST_ASSERT(p2_apc_interface_opened(A, R), "a cyborg still gets the window")

// ---------------------------------------------------------------------------------------------------------------------
// The window's buttons
// ---------------------------------------------------------------------------------------------------------------------

/// Once the lock is off a person can flip the breaker, the charge mode, the cover lock and set the channels.
/datum/unit_test/dq_p2_apc/ui_buttons_work_on_an_unlocked_apc

/datum/unit_test/dq_p2_apc/ui_buttons_work_on_an_unlocked_apc/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/carbon/human/H = p2_actor()
	unlock(H, A)
	TEST_ASSERT(!p2_apc_locked(A), "unlocked")
	press(H, A, "breaker", list())
	TEST_ASSERT(!A.operating, "the breaker flipped off")
	press(H, A, "breaker", list())
	TEST_ASSERT(A.operating, "and on")
	var/charge_mode = A.chargemode
	press(H, A, "charge", list())
	TEST_ASSERT_EQUAL(A.chargemode, !charge_mode, "the charge mode flipped")
	press(H, A, "charge", list())
	TEST_ASSERT_EQUAL(A.chargemode, charge_mode, "and back")
	var/cover_lock = A.coverlocked
	press(H, A, "cover", list())
	TEST_ASSERT_EQUAL(!!A.coverlocked, !cover_lock, "the cover lock flipped")
	press(H, A, "cover", list())
	TEST_ASSERT_EQUAL(!!A.coverlocked, !!cover_lock, "and back")
	press(H, A, "nightshift", list("nightshift" = NIGHTSHIFT_ALWAYS))
	TEST_ASSERT_EQUAL(A.nightshift_setting, NIGHTSHIFT_ALWAYS, "the night shift setting changed")

/// The channel buttons set each channel's mode; a bad channel is refused; with a charged cell "off auto" means off.
/datum/unit_test/dq_p2_apc/ui_channel_modes

/datum/unit_test/dq_p2_apc/ui_channel_modes/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/carbon/human/H = p2_actor()
	unlock(H, A)
	press(H, A, "channel", list("channel" = POWER_CHANNEL_LIGHTING, "mode" = POWERCHAN_OFF_AUTO))
	TEST_ASSERT_EQUAL(A.lighting, POWERCHAN_OFF, "a charged cell: the off button means off")
	TEST_ASSERT(!p2_apc_area_powered(A, 1), "and the area's lighting is off")
	press(H, A, "channel", list("channel" = POWER_CHANNEL_LIGHTING, "mode" = POWERCHAN_ON_AUTO))
	TEST_ASSERT_EQUAL(A.lighting, POWERCHAN_ON_AUTO, "lighting back on auto")
	TEST_ASSERT(p2_apc_area_powered(A, 1), "and powered")
	press(H, A, "channel", list("channel" = POWER_CHANNEL_EQUIPMENT, "mode" = POWERCHAN_ON))
	TEST_ASSERT_EQUAL(A.equipment, POWERCHAN_ON, "equipment on")
	press(H, A, "channel", list("channel" = POWER_CHANNEL_ENVIRON, "mode" = POWERCHAN_OFF))
	TEST_ASSERT_EQUAL(A.environ, POWERCHAN_OFF, "environment off")
	TEST_ASSERT(!p2_apc_area_powered(A, 2), "and its area channel")
	press(H, A, "channel", list("channel" = "nonsense", "mode" = POWERCHAN_OFF))
	TEST_ASSERT_EQUAL(A.equipment, POWERCHAN_ON, "a bad channel changes nothing")
	TEST_ASSERT_EQUAL(A.lighting, POWERCHAN_ON_AUTO, "not the others either")

/// The night shift setting is set from the window, and it is the one button a locked APC allows anyone.
/datum/unit_test/dq_p2_apc/ui_nightshift_setting_even_when_locked

/datum/unit_test/dq_p2_apc/ui_nightshift_setting_even_when_locked/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/carbon/human/H = p2_actor()
	TEST_ASSERT(p2_apc_locked(A), "locked")
	TEST_ASSERT_EQUAL(A.nightshift_setting, NIGHTSHIFT_AUTO, "automatic to start")
	press(H, A, "nightshift", list("nightshift" = NIGHTSHIFT_NEVER))
	TEST_ASSERT_EQUAL(A.nightshift_setting, NIGHTSHIFT_NEVER, "set to never although locked")

/// A locked APC refuses every button but the night shift to a person with no way past the lock.
/datum/unit_test/dq_p2_apc/ui_buttons_refused_while_locked

/datum/unit_test/dq_p2_apc/ui_buttons_refused_while_locked/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/carbon/human/H = p2_actor()
	TEST_ASSERT(p2_apc_locked(A), "locked")
	press(H, A, "breaker", list())
	TEST_ASSERT(A.operating, "the breaker stays on")
	press(H, A, "charge", list())
	TEST_ASSERT(A.chargemode, "the charge mode stays")
	press(H, A, "cover", list())
	TEST_ASSERT(A.coverlocked, "the cover lock stays")
	press(H, A, "channel", list("channel" = POWER_CHANNEL_LIGHTING, "mode" = POWERCHAN_OFF))
	TEST_ASSERT_EQUAL(A.lighting, POWERCHAN_ON_AUTO, "the channels stay")
	press(H, A, "emergency_lighting", list())
	TEST_ASSERT(!A.emergency_lights, "the emergency lighting stays")
	press(H, A, "lock", list())
	TEST_ASSERT(p2_apc_locked(A), "a person cannot press the lock button")
	press(H, A, "overload", list())
	TEST_ASSERT(A.cell.charge >= A.cell.maxcharge * 0.9 - 1, "and cannot overload the lights")

/// A cyborg works a locked APC's buttons, including the lock itself; a person cannot press the lock button even unlocked.
/datum/unit_test/dq_p2_apc/ui_silicon_works_a_locked_apc

/datum/unit_test/dq_p2_apc/ui_silicon_works_a_locked_apc/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/silicon/robot/R = p2_borg()
	var/mob/living/carbon/human/H = p2_actor()
	TEST_ASSERT(p2_apc_locked(A), "locked")
	press(R, A, "breaker", list())
	TEST_ASSERT(!A.operating, "the cyborg flipped the breaker of a locked APC")
	press(R, A, "lock", list())
	TEST_ASSERT(!p2_apc_locked(A), "and unlocked it")
	press(H, A, "lock", list())
	TEST_ASSERT(!p2_apc_locked(A), "a person cannot lock it with the button, even unlocked")
	press(R, A, "lock", list())
	TEST_ASSERT(p2_apc_locked(A), "the cyborg locks it again")

/// The lock button is refused on a subverted or unfinished APC.
/datum/unit_test/dq_p2_apc/ui_lock_button_refused_when_subverted

/datum/unit_test/dq_p2_apc/ui_lock_button_refused_when_subverted/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/silicon/robot/R = p2_borg()
	p2_apc_subvert(A)
	TEST_ASSERT(p2_apc_emagged(A), "subverted")
	TEST_ASSERT(!p2_apc_locked(A), "unlocked by the subversion")
	press(R, A, "lock", list())
	TEST_ASSERT(!p2_apc_locked(A), "the lock button does nothing on a subverted APC")

/// The reboot button ends a power failure; the emergency lighting button toggles the area's emergency lights.
/datum/unit_test/dq_p2_apc/ui_reboot_and_emergency_lighting

/datum/unit_test/dq_p2_apc/ui_reboot_and_emergency_lighting/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/carbon/human/H = p2_actor()
	unlock(H, A)
	A.emp_act(1)
	p2_settle()
	TEST_ASSERT(p2_apc_failed(A), "the pulse failed it")
	press(H, A, "reboot", list())
	TEST_ASSERT(!p2_apc_failed(A), "the reboot ended the failure")
	test_time(15 MINUTES)
	TEST_ASSERT(!p2_apc_failed(A), "and it does not come back")
	var/was = A.emergency_lights
	press(H, A, "emergency_lighting", list())
	TEST_ASSERT_EQUAL(A.emergency_lights, !was, "the emergency lighting flipped")
	press(H, A, "emergency_lighting", list())
	TEST_ASSERT_EQUAL(A.emergency_lights, was, "and back")

/// The window offers each actor what the lock lets them: a person at an unlocked APC, nothing at a locked one but the night shift.
/datum/unit_test/dq_p2_apc/ui_refused_for_an_actor_out_of_reach

/datum/unit_test/dq_p2_apc/ui_refused_for_an_actor_out_of_reach/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/carbon/human/H = p2_actor()
	var/mob/living/carbon/human/far = p2_actor(run_loc_floor_top_right)
	unlock(H, A)
	press(far, A, "breaker", list())
	TEST_ASSERT(A.operating, "a person across the room cannot press the breaker")
	press(H, A, "breaker", list())
	TEST_ASSERT(!A.operating, "a person beside it can")

// ---------------------------------------------------------------------------------------------------------------------
// Power
// ---------------------------------------------------------------------------------------------------------------------

/// The breaker off darkens every channel of the area; on lights them again.
/datum/unit_test/dq_p2_apc/breaker_off_kills_the_area_channels

/datum/unit_test/dq_p2_apc/breaker_off_kills_the_area_channels/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/carbon/human/H = p2_actor()
	unlock(H, A)
	for(var/index in 0 to 2)
		TEST_ASSERT(p2_apc_area_powered(A, index), "channel [index] powered to start")
	press(H, A, "breaker", list())
	for(var/index in 0 to 2)
		TEST_ASSERT(!p2_apc_area_powered(A, index), "channel [index] dark with the breaker off")
	press(H, A, "breaker", list())
	for(var/index in 0 to 2)
		TEST_ASSERT(p2_apc_area_powered(A, index), "channel [index] powered again")

/// A pulse fails the APC for minutes; the area is dark meanwhile and recovers by itself.
/datum/unit_test/dq_p2_apc/emp_fails_the_apc_for_a_while_then_it_recovers

/datum/unit_test/dq_p2_apc/emp_fails_the_apc_for_a_while_then_it_recovers/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	A.emp_act(1)
	p2_settle()
	TEST_ASSERT(p2_apc_failed(A), "failed by the pulse")
	TEST_ASSERT(!p2_apc_area_powered(A, 1), "the area is dark")
	test_time(3 MINUTES)
	TEST_ASSERT(p2_apc_failed(A), "still failed minutes on")
	test_time(11 MINUTES)
	TEST_ASSERT(!p2_apc_failed(A), "recovered by itself")
	TEST_ASSERT(p2_apc_area_powered(A, 1) || A.shorted, "the area is lit again unless a wire the pulse hit still holds it")

/// A critical APC shrugs most of a pulse off: its failure is over in about a minute.
/datum/unit_test/dq_p2_apc/emp_on_a_critical_apc_is_brief

/datum/unit_test/dq_p2_apc/emp_on_a_critical_apc_is_brief/run_gate()
	var/obj/machinery/power/apc/A = p2_apc(null, /obj/machinery/power/apc/p2_test/critical)
	A.emp_act(1)
	p2_settle()
	TEST_ASSERT(p2_apc_failed(A), "failed")
	test_time(100 SECONDS)
	TEST_ASSERT(!p2_apc_failed(A), "a critical APC recovers within two minutes")

/// A lighter pulse costs less time than a hard one.
/datum/unit_test/dq_p2_apc/emp_severity_scales_the_failure

/datum/unit_test/dq_p2_apc/emp_severity_scales_the_failure/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	A.emp_act(2)
	p2_settle()
	TEST_ASSERT(p2_apc_failed(A), "failed by a light pulse")
	test_time(8 MINUTES)
	TEST_ASSERT(!p2_apc_failed(A), "a light pulse is over within eight minutes")

/// A damage that breaks the APC shuts it down: broken, the breaker off and the area dark.
/datum/unit_test/dq_p2_apc/damage_breaks_the_apc_and_darkens_the_area

/datum/unit_test/dq_p2_apc/damage_breaks_the_apc_and_darkens_the_area/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	A.take_damage(A.max_integrity * 0.3)
	p2_settle()
	TEST_ASSERT(!A.has_stat(BROKEN), "a third of its integrity: still working")
	TEST_ASSERT(A.operating, "breaker on")
	A.take_damage(A.max_integrity * 0.4)
	p2_settle()
	TEST_ASSERT(A.has_stat(BROKEN), "past half: broken")
	TEST_ASSERT(!A.operating, "the breaker is off")
	TEST_ASSERT(!A.operable(), "it does not work")
	TEST_ASSERT(!p2_apc_area_powered(A, 0) && !p2_apc_area_powered(A, 1) && !p2_apc_area_powered(A, 2), "the area is dark")

/// An explosion damages it (the severity's share of its integrity) or destroys it.
/datum/unit_test/dq_p2_apc/explosion_damages_the_apc

/datum/unit_test/dq_p2_apc/explosion_damages_the_apc/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	A.ex_act(3)
	p2_settle()
	TEST_ASSERT(QDELETED(A) || A.get_integrity() < A.max_integrity, "a light blast hurt it")

/// A blob tears the wires out and opens the panel without hurting the frame.
/datum/unit_test/dq_p2_apc/blob_tears_the_wires_and_opens_the_panel

/datum/unit_test/dq_p2_apc/blob_tears_the_wires_and_opens_the_panel/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/datum/wires_test_adapter/W = p2_apc_wires(A)
	TEST_ASSERT(!p2_apc_panel_open(A), "panel shut to start")
	A.blob_act(null)
	p2_settle()
	TEST_ASSERT(p2_apc_panel_open(A), "the blob opened the panel")
	TEST_ASSERT(W.is_cut(WIRE_MAIN_POWER1) && W.is_cut(WIRE_MAIN_POWER2) && W.is_cut(WIRE_IDSCAN) && W.is_cut(WIRE_AI_CONTROL), "and cut every wire")
	TEST_ASSERT(A.shorted, "the APC is shorted")
	TEST_ASSERT_EQUAL(A.get_integrity(), A.max_integrity, "the frame took no damage")

/// Claws: the first slashes only count; then the panel springs open; the next slash shreds the wires and shorts the APC.
/datum/unit_test/dq_p2_apc/claws_spring_the_panel_and_shred_the_wires

/datum/unit_test/dq_p2_apc/claws_spring_the_panel_and_shred_the_wires/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/carbon/human/H = p2_actor()
	H.set_species(SPECIES_XENOMORPH_HYBRID)
	H.combat_mode = TRUE
	var/datum/wires_test_adapter/W = p2_apc_wires(A)
	touch(H, A, null)
	TEST_ASSERT(!p2_apc_panel_open(A), "one slash does not open it")
	for(var/i in 1 to 8)
		if(p2_apc_panel_open(A))
			break
		touch(H, A, null)
	TEST_ASSERT(p2_apc_panel_open(A), "a few slashes spring the panel open")
	TEST_ASSERT(!W.is_cut(WIRE_MAIN_POWER1), "the wires are not yet cut")
	for(var/i in 1 to 4)
		if(W.is_cut(WIRE_MAIN_POWER1))
			break
		touch(H, A, null)
	TEST_ASSERT(W.is_cut(WIRE_MAIN_POWER1) && W.is_cut(WIRE_MAIN_POWER2), "the next slash shreds the power wires")
	TEST_ASSERT(A.shorted, "shorted")

// ---------------------------------------------------------------------------------------------------------------------
// Cell, charging and the power step
// ---------------------------------------------------------------------------------------------------------------------

/// A flat cell and a load: the area browns out after some steps. With supply the cell charges, the APC reads good power and the area is lit.
/datum/unit_test/dq_p2_apc/cell_drains_without_supply_and_charges_with_it

/datum/unit_test/dq_p2_apc/cell_drains_without_supply_and_charges_with_it/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/obj/machinery/power/terminal/Tm = A.terminal
	p2_cable(run_loc_floor_bottom_left)
	p2_area.requires_power = TRUE
	A.operating = TRUE
	A.chargemode = TRUE
	A.equipment = POWERCHAN_ON_AUTO
	A.lighting = POWERCHAN_ON_AUTO
	A.environ = POWERCHAN_ON_AUTO
	p2_apc_load(A, 2000)
	A.cell.charge = A.cell.maxcharge * 0.001
	p2_apc_resync(A)
	var/drained = FALSE
	for(var/i in 1 to 20)
		p2_apc_power_step()
		if(!p2_apc_area_powered(A, 0))
			drained = TRUE
			break
	TEST_ASSERT(drained, "an empty cell under load browns the area out")
	TEST_ASSERT_EQUAL(A.charging, 0, "an unsupplied APC is not charging")
	var/low = A.cell.charge
	A.connect_to_network()
	Tm.set_power_supply(1000000)
	var/restored = FALSE
	for(var/i in 1 to 80)
		p2_apc_power_step()
		if(p2_apc_area_powered(A, 0) && A.charging)
			restored = TRUE
			break
	TEST_ASSERT(restored, "with supply the area comes back and the cell charges")
	p2_apc_power_step()
	TEST_ASSERT(A.cell.charge > low, "the cell took charge")
	TEST_ASSERT_EQUAL(A.main_status, APC_EXTERNAL_POWER_GOOD, "external power reads good")
	Tm.set_power_supply(0)
	p2_apc_load(A, -2000)
	A.cell.charge = A.cell.maxcharge
	p2_apc_resync(A)

/// A shorted APC gives its area no power once the power domain has run a step; mending the wires gives it back.
/datum/unit_test/dq_p2_apc/shorted_apc_darkens_the_area_after_a_power_step

/datum/unit_test/dq_p2_apc/shorted_apc_darkens_the_area_after_a_power_step/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/obj/machinery/power/terminal/Tm = A.terminal
	var/datum/wires_test_adapter/W = p2_apc_wires(A)
	p2_cable(run_loc_floor_bottom_left)
	p2_area.requires_power = TRUE
	A.connect_to_network()
	Tm.set_power_supply(1000000)
	p2_apc_resync(A)
	for(var/i in 1 to 10)
		p2_apc_power_step()
	TEST_ASSERT(p2_apc_area_powered(A, 0) && p2_apc_area_powered(A, 1) && p2_apc_area_powered(A, 2), "a supplied APC powers its area")
	W.cut(WIRE_MAIN_POWER1)
	var/dark = FALSE
	for(var/i in 1 to 20)
		p2_apc_power_step()
		if(!p2_apc_area_powered(A, 0))
			dark = TRUE
			break
	TEST_ASSERT(dark, "a shorted APC leaves its area dark")
	W.cut(WIRE_MAIN_POWER1)
	TEST_ASSERT(!A.shorted, "mended")
	var/lit = FALSE
	for(var/i in 1 to 40)
		p2_apc_power_step()
		if(p2_apc_area_powered(A, 0))
			lit = TRUE
			break
	TEST_ASSERT(lit, "and the area is powered again")
	Tm.set_power_supply(0)

/// Turning charging off stops the cell taking charge although supply is good.
/datum/unit_test/dq_p2_apc/charge_mode_off_stops_charging

/datum/unit_test/dq_p2_apc/charge_mode_off_stops_charging/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/obj/machinery/power/terminal/Tm = A.terminal
	var/mob/living/carbon/human/H = p2_actor()
	p2_cable(run_loc_floor_bottom_left)
	p2_area.requires_power = TRUE
	A.connect_to_network()
	Tm.set_power_supply(1000000)
	A.cell.charge = A.cell.maxcharge * 0.5
	p2_apc_resync(A)
	unlock(H, A)
	press(H, A, "charge", list())
	TEST_ASSERT(!A.chargemode, "charging switched off")
	var/before = A.cell.charge
	for(var/i in 1 to 10)
		p2_apc_power_step()
	TEST_ASSERT(A.cell.charge <= before, "the cell takes no charge")
	TEST_ASSERT_EQUAL(A.charging, 0, "and the APC says it is not charging")
	press(H, A, "charge", list())
	TEST_ASSERT(A.chargemode, "charging back on")
	for(var/i in 1 to 40)
		p2_apc_power_step()
	TEST_ASSERT(A.cell.charge > before, "the cell charges again")
	Tm.set_power_supply(0)

/// A shorted APC raises the power alarm once the power domain has stepped; mending it clears the alarm.
/datum/unit_test/dq_p2_apc/power_alarm_follows_the_state_of_the_apc

/datum/unit_test/dq_p2_apc/power_alarm_follows_the_state_of_the_apc/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/obj/machinery/power/terminal/Tm = A.terminal
	var/datum/wires_test_adapter/W = p2_apc_wires(A)
	p2_cable(run_loc_floor_bottom_left)
	p2_area.requires_power = TRUE
	A.connect_to_network()
	Tm.set_power_supply(1000000)
	p2_apc_resync(A)
	for(var/i in 1 to 20)
		p2_apc_power_step()
	TEST_ASSERT(!A.power_alarm_raised, "a supplied APC raises no alarm")
	W.cut(WIRE_MAIN_POWER1)
	var/raised = FALSE
	for(var/i in 1 to 20)
		p2_apc_power_step()
		if(A.power_alarm_raised)
			raised = TRUE
			break
	TEST_ASSERT(raised, "a shorted APC raises the power alarm")
	W.cut(WIRE_MAIN_POWER1)
	var/cleared = FALSE
	for(var/i in 1 to 60)
		p2_apc_power_step()
		if(!A.power_alarm_raised)
			cleared = TRUE
			break
	TEST_ASSERT(cleared, "mended, the alarm clears")
	Tm.set_power_supply(0)

// ---------------------------------------------------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------------------------------------------------

/// A builder's frame starts open, off and without a cell, and goes frame, board, wired, secured; each step has its tool.
/datum/unit_test/dq_p2_apc/frame_builds_up_to_a_working_apc

/datum/unit_test/dq_p2_apc/frame_builds_up_to_a_working_apc/run_gate()
	var/obj/machinery/power/apc/A = p2_frame()
	var/mob/living/carbon/human/H = p2_actor()
	TEST_ASSERT_EQUAL(p2_apc_stage(A), "frame", "a bare frame")
	TEST_ASSERT(p2_apc_cover_open(A), "the cover is open")
	TEST_ASSERT(!A.operating, "the breaker is off")
	TEST_ASSERT_NULL(A.cell, "there is no cell")
	TEST_ASSERT(p2_apc_unfinished(A), "it is under maintenance")
	bare_floor()
	touch(H, A, allocate(/obj/item/module/power_control, run_loc_floor_bottom_left))
	TEST_ASSERT_EQUAL(p2_apc_stage(A), "board", "the board is in")
	var/obj/item/stack/cable_coil/coil = allocate(/obj/item/stack/cable_coil, run_loc_floor_bottom_left, 10)
	touch(H, A, coil)
	TEST_ASSERT_EQUAL(p2_apc_stage(A), "wired", "ten lengths of cable")
	TEST_ASSERT_NOTNULL(A.terminal, "the terminal was made")
	TEST_ASSERT_EQUAL(A.terminal.master, A, "and answers to the APC")
	touch(H, A, tool(/obj/item/tool/screwdriver))
	TEST_ASSERT_EQUAL(p2_apc_stage(A), "secured", "the electronics are fastened")
	TEST_ASSERT(!p2_apc_unfinished(A), "the APC works")

/// The cable step needs the floor plating off.
/datum/unit_test/dq_p2_apc/wiring_needs_the_plating_bared

/datum/unit_test/dq_p2_apc/wiring_needs_the_plating_bared/run_gate()
	var/obj/machinery/power/apc/A = p2_frame()
	var/mob/living/carbon/human/H = p2_actor()
	touch(H, A, allocate(/obj/item/module/power_control, run_loc_floor_bottom_left))
	var/obj/item/stack/cable_coil/coil = allocate(/obj/item/stack/cable_coil, run_loc_floor_bottom_left, 10)
	touch(H, A, coil)
	TEST_ASSERT_EQUAL(p2_apc_stage(A), "board", "with the floor tile on, no wiring")
	TEST_ASSERT_NULL(A.terminal, "and no terminal")
	bare_floor()
	touch(H, A, coil)
	TEST_ASSERT_EQUAL(p2_apc_stage(A), "wired", "with the plating bared, the cable goes in")

/// Each step undoes with its tool: the screwdriver unfastens (cell out), the wirecutters cut the cable (the terminal goes), a hand takes the board.
/datum/unit_test/dq_p2_apc/construction_steps_undo

/datum/unit_test/dq_p2_apc/construction_steps_undo/run_gate()
	var/obj/machinery/power/apc/A = p2_frame()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/item/module/power_control/board = allocate(/obj/item/module/power_control, run_loc_floor_bottom_left)
	bare_floor()
	touch(H, A, board)
	touch(H, A, allocate(/obj/item/stack/cable_coil, run_loc_floor_bottom_left, 10))
	touch(H, A, tool(/obj/item/tool/screwdriver))
	TEST_ASSERT_EQUAL(p2_apc_stage(A), "secured", "built")
	touch(H, A, tool(/obj/item/tool/screwdriver))
	TEST_ASSERT_EQUAL(p2_apc_stage(A), "wired", "the screwdriver unfastened it")
	TEST_ASSERT(p2_apc_unfinished(A), "under maintenance again")
	touch(H, A, tool(/obj/item/tool/wirecutters))
	TEST_ASSERT_EQUAL(p2_apc_stage(A), "board", "the wirecutters cut the cable out")
	TEST_ASSERT_NULL(A.terminal, "the terminal is gone")
	var/coil_units = 0
	for(var/obj/item/stack/cable_coil/C in run_loc_floor_bottom_left)
		coil_units += C.amount
	TEST_ASSERT_EQUAL(coil_units, 10, "all ten lengths came back")
	touch(H, A, null)
	TEST_ASSERT_EQUAL(p2_apc_stage(A), "frame", "a hand takes the board out")
	var/obj/item/module/power_control/loose = locate() in run_loc_floor_bottom_left
	TEST_ASSERT(H.is_in_hands(board) || loose, "the board came out, into the hand or onto the floor")

/// The electronics can only be unfastened with the cell out; and the cell goes in only once they are fastened.
/datum/unit_test/dq_p2_apc/cell_and_electronics_exclude_each_other

/datum/unit_test/dq_p2_apc/cell_and_electronics_exclude_each_other/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/item/cell/original = A.cell
	open_cover(H, A)
	touch(H, A, tool(/obj/item/tool/screwdriver))
	TEST_ASSERT_EQUAL(p2_apc_stage(A), "secured", "with the cell in the screwdriver cannot unfasten it")
	touch(H, A, null)
	TEST_ASSERT_NULL(A.cell, "the cell is out")
	touch(H, A, tool(/obj/item/tool/screwdriver))
	TEST_ASSERT_EQUAL(p2_apc_stage(A), "wired", "now it unfastens")
	touch(H, A, original)
	TEST_ASSERT_NULL(A.cell, "unfastened electronics refuse the cell")
	touch(H, A, tool(/obj/item/tool/screwdriver))
	TEST_ASSERT_EQUAL(p2_apc_stage(A), "secured", "fastened again")
	touch(H, A, original)
	TEST_ASSERT_EQUAL(A.cell, original, "the cell goes back in")

/// The cover will not shut on a board that is not fastened, on either unfinished step.
/datum/unit_test/dq_p2_apc/cover_will_not_shut_on_an_unfastened_board

/datum/unit_test/dq_p2_apc/cover_will_not_shut_on_an_unfastened_board/run_gate()
	var/obj/machinery/power/apc/A = p2_frame()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/item/tool/crowbar/bar = tool(/obj/item/tool/crowbar)
	bare_floor()
	touch(H, A, bar)
	TEST_ASSERT(!p2_apc_cover_open(A), "a bare frame's cover shuts")
	touch(H, A, bar)
	TEST_ASSERT(p2_apc_cover_open(A), "and opens again")
	touch(H, A, allocate(/obj/item/module/power_control, run_loc_floor_bottom_left))
	touch(H, A, bar)
	TEST_ASSERT(p2_apc_cover_open(A), "the cover will not shut on the loose board")
	touch(H, A, allocate(/obj/item/stack/cable_coil, run_loc_floor_bottom_left, 10))
	touch(H, A, bar)
	TEST_ASSERT(p2_apc_cover_open(A), "nor on the wired frame")
	touch(H, A, tool(/obj/item/tool/screwdriver))
	TEST_ASSERT_EQUAL(p2_apc_stage(A), "secured", "secured")
	touch(H, A, bar)
	TEST_ASSERT(!p2_apc_cover_open(A), "the finished APC's cover shuts")

/// A welder cuts a whole frame off the wall into a reusable frame, the APC with it.
/datum/unit_test/dq_p2_apc/welder_dismantles_into_a_frame

/datum/unit_test/dq_p2_apc/welder_dismantles_into_a_frame/run_gate()
	var/obj/machinery/power/apc/A = p2_frame()
	var/mob/living/carbon/human/H = p2_actor()
	touch(H, A, dq_fueled_welder(run_loc_floor_bottom_left))
	TEST_ASSERT(QDELETED(A), "the APC is gone")
	var/obj/item/frame/apc/frame = locate() in run_loc_floor_bottom_left
	TEST_ASSERT_NOTNULL(frame, "a reusable APC frame is on the floor")

/// A ruined frame (emagged, broken or its cover gone) comes apart into scrap steel instead.
/datum/unit_test/dq_p2_apc/welder_dismantles_a_ruined_frame_into_scrap

/datum/unit_test/dq_p2_apc/welder_dismantles_a_ruined_frame_into_scrap/run_gate()
	var/obj/machinery/power/apc/A = p2_frame()
	var/mob/living/carbon/human/H = p2_actor()
	A.take_damage(A.max_integrity * 0.9)
	p2_settle()
	TEST_ASSERT(A.has_stat(BROKEN), "broken")
	touch(H, A, dq_fueled_welder(run_loc_floor_bottom_left))
	TEST_ASSERT(QDELETED(A), "the APC is gone")
	var/obj/item/stack/material/steel/scrap = locate() in run_loc_floor_bottom_left
	TEST_ASSERT_NOTNULL(scrap, "scrap steel is on the floor")
	TEST_ASSERT_NULL(locate(/obj/item/frame/apc) in run_loc_floor_bottom_left, "and no usable frame")

/// A subverted frame is a ruined one: scrap steel, not a reusable frame.
/datum/unit_test/dq_p2_apc/welder_dismantles_a_subverted_frame_into_scrap

/datum/unit_test/dq_p2_apc/welder_dismantles_a_subverted_frame_into_scrap/run_gate()
	var/obj/machinery/power/apc/A = p2_frame()
	var/mob/living/carbon/human/H = p2_actor()
	p2_apc_subvert(A)
	touch(H, A, dq_fueled_welder(run_loc_floor_bottom_left))
	TEST_ASSERT(QDELETED(A), "the APC is gone")
	TEST_ASSERT_NOTNULL(locate(/obj/item/stack/material/steel) in run_loc_floor_bottom_left, "scrap steel is on the floor")
	TEST_ASSERT_NULL(locate(/obj/item/frame/apc) in run_loc_floor_bottom_left, "and no usable frame")

/// The welder does nothing to a frame that has its board in: the ladder is taken apart first.
/datum/unit_test/dq_p2_apc/welder_refused_on_a_built_frame

/datum/unit_test/dq_p2_apc/welder_refused_on_a_built_frame/run_gate()
	var/obj/machinery/power/apc/A = p2_frame()
	var/mob/living/carbon/human/H = p2_actor()
	touch(H, A, allocate(/obj/item/module/power_control, run_loc_floor_bottom_left))
	TEST_ASSERT_EQUAL(p2_apc_stage(A), "board", "the board is in")
	touch(H, A, dq_fueled_welder(run_loc_floor_bottom_left))
	TEST_ASSERT(!QDELETED(A), "the APC is still there")

// ---------------------------------------------------------------------------------------------------------------------
// The recorder
// ---------------------------------------------------------------------------------------------------------------------

/// The recorder sees a cell taken out and put back in: the state moves as recorded and no engine-internal key leaks into the rows.
/datum/unit_test/dq_p2_apc/recorder_cell_take_insert

/datum/unit_test/dq_p2_apc/recorder_cell_take_insert/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/item/cell/original = A.cell
	open_cover(H, A)
	test_record(H, A, original)
	touch(H, A, null)
	TEST_ASSERT_NULL(A.cell, "the cell is out")
	touch(H, A, original)
	TEST_ASSERT_EQUAL(A.cell, original, "the cell is back in")
	var/list/events = test_recorded()
	// The cell's own moves record under the bay's slot name; the hand it passes through records its own rows (hand_r), which are not the bay's.
	var/transfers = test_events_count(events, TEST_EVENT_TRANSFER, "cell")
	var/list/dump = list()
	for(var/datum/test_event/event in events)
		dump += "[event.kind]:[event.key]"
	TEST_ASSERT(transfers == 0 || transfers == 2, "a take and an insert make two bay transfer rows or none: [jointext(dump, " ")]")
	var/committed = 0
	for(var/datum/test_event/event in events)
		if(event.kind == TEST_EVENT_OUTCOME)
			TEST_ASSERT_EQUAL(event.to_value, ACT_COMMITTED, "every op outcome of the take and the insert is a commit")
			committed++
	TEST_ASSERT_EQUAL(committed, 2, "two ops ran: the take and the insert")
	for(var/datum/test_event/event in events)
		if(event.kind == TEST_EVENT_TRANSFER)
			TEST_ASSERT_EQUAL(event.entity, original, "a transfer row is about the cell")
			TEST_ASSERT(!findtext("[event.key]", ":"), "its slot is a plain name, not an op key: [event.key]")
	TEST_ASSERT_EQUAL(test_events_count(events, TEST_EVENT_SPILL), 0, "nothing spilled")

// ---------------------------------------------------------------------------------------------------------------------
// Outages: EMPs, the overload events and the reboot (pinned before the outage became a hold on the APC's operability)
// ---------------------------------------------------------------------------------------------------------------------

/// A hard pulse during a lighter pulse's outage lengthens it; a light pulse during a hard pulse's outage never shortens it.
/datum/unit_test/dq_p2_apc/emp_during_an_outage_keeps_the_longer_failure

/datum/unit_test/dq_p2_apc/emp_during_an_outage_keeps_the_longer_failure/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	A.emp_act(2)
	p2_settle()
	TEST_ASSERT(p2_apc_failed(A), "a light pulse fails it (four to six minutes)")
	A.emp_act(1)
	p2_settle()
	test_time(7 MINUTES)
	TEST_ASSERT(p2_apc_failed(A), "the hard pulse that followed holds it past the light pulse's end")
	test_time(6 MINUTES)
	TEST_ASSERT(!p2_apc_failed(A), "and it ends when the hard pulse's outage ends")
	var/obj/machinery/power/apc/B = p2_apc(run_loc_floor_top_right)
	B.emp_act(1)
	p2_settle()
	B.emp_act(2)
	p2_settle()
	test_time(7 MINUTES)
	TEST_ASSERT(p2_apc_failed(B), "a light pulse during a hard pulse's outage does not shorten it")

/// An event's power failure (the electrical fault, the supermatter's shutdown) darkens the area for its duration; the reboot button ends it early.
/datum/unit_test/dq_p2_apc/event_power_failure_lasts_its_duration

/datum/unit_test/dq_p2_apc/event_power_failure_lasts_its_duration/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/silicon/robot/R = p2_borg()
	p2_apc_energy_fail(A, 60)
	p2_settle()
	TEST_ASSERT(p2_apc_failed(A), "the failure is on")
	TEST_ASSERT(!p2_apc_area_powered(A, 0) && !p2_apc_area_powered(A, 1) && !p2_apc_area_powered(A, 2), "the area is dark")
	TEST_ASSERT(A.operating, "the breaker is untouched")
	test_time(30 SECONDS)
	TEST_ASSERT(p2_apc_failed(A), "still failed half a minute on")
	test_time(30 SECONDS)
	TEST_ASSERT(!p2_apc_failed(A), "over after its minute")
	TEST_ASSERT(p2_apc_area_powered(A, 0) && p2_apc_area_powered(A, 1) && p2_apc_area_powered(A, 2), "the area is lit again")
	A.emp_act(1)
	p2_settle()
	p2_apc_energy_fail(A, 30)
	test_time(1 MINUTE)
	TEST_ASSERT(p2_apc_failed(A), "a shorter failure during a pulse's outage does not end it")
	press(R, A, "reboot", list())
	TEST_ASSERT(!p2_apc_failed(A), "the reboot button ends any failure at once")

/// The overload button (a silicon's) spends 20 of the cell's charge and bursts the area's lights.
/datum/unit_test/dq_p2_apc/ui_overload_bursts_the_area_lights

/datum/unit_test/dq_p2_apc/ui_overload_bursts_the_area_lights/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/silicon/robot/R = p2_borg()
	var/obj/machinery/light/L = allocate(/obj/machinery/light, run_loc_floor_top_right)
	if(L.status != LIGHT_OK)
		L.fix()
	p2_settle()
	TEST_ASSERT(L in p2_apc_area_lights(A), "the light is one of the area's")
	var/charge = A.cell.charge
	press(R, A, "overload", list())
	TEST_ASSERT(A.cell.charge <= charge - 19, "the overload spent the cell's charge")
	TEST_ASSERT_EQUAL(L.status, LIGHT_BROKEN, "and burst the light")
	TEST_ASSERT(!p2_apc_failed(A), "it does not fail the APC")

/// A surge from the grid never fails an APC's output, and a critical APC ignores it altogether.
/datum/unit_test/dq_p2_apc/grid_surge_never_fails_the_apc

/datum/unit_test/dq_p2_apc/grid_surge_never_fails_the_apc/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	for(var/i in 1 to 30)
		A.overload(null)
		TEST_ASSERT(!p2_apc_failed(A), "a surge does not fail the APC")
	var/obj/machinery/power/apc/C = p2_apc(run_loc_floor_top_right, /obj/machinery/power/apc/p2_test/critical)
	var/charge = C.cell.charge
	for(var/i in 1 to 30)
		C.overload(null)
	p2_settle()
	TEST_ASSERT(!p2_apc_failed(C), "a critical APC is not failed")
	TEST_ASSERT(!p2_apc_emagged(C) && p2_apc_locked(C), "nor subverted")
	TEST_ASSERT_EQUAL(C.cell.charge, charge, "nor its cell touched")
	TEST_ASSERT(!C.has_stat(BROKEN), "nor broken")

// ---------------------------------------------------------------------------------------------------------------------
// Signallers and silicons (pinned before they became their own bindings)
// ---------------------------------------------------------------------------------------------------------------------

/// A signaller held to the open wire panel (the cover shut) reaches the wire window, where it can be attached; with the panel shut it does nothing.
/datum/unit_test/dq_p2_apc/signaler_at_the_open_panel_reaches_the_wires

/datum/unit_test/dq_p2_apc/signaler_at_the_open_panel_reaches_the_wires/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/carbon/human/H = p2_actor()
	var/datum/wires_test_adapter/W = p2_apc_record_wire_window(A)
	var/obj/item/assembly/signaler/S = allocate(/obj/item/assembly/signaler, run_loc_floor_bottom_left)
	touch(H, A, S)
	TEST_ASSERT(!p2_apc_wire_window_opened(W, H), "the panel shut: the wires are out of reach")
	TEST_ASSERT_EQUAL(A.get_integrity(), A.max_integrity, "and the APC is not hurt")
	open_panel(H, A)
	touch(H, A, S)
	TEST_ASSERT(p2_apc_wire_window_opened(W, H), "the panel open: the signaller reaches the wire window")
	TEST_ASSERT_EQUAL(A.get_integrity(), A.max_integrity, "the APC is not hurt")

/// An AI's click opens the window from across the room.
/datum/unit_test/dq_p2_apc/silicon_click_opens_the_window

/datum/unit_test/dq_p2_apc/silicon_click_opens_the_window/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/silicon/ai/AI = allocate(/mob/living/silicon/ai, run_loc_floor_top_right, null, null, null, TRUE)
	test_click(AI, A, null)
	p2_settle()
	TEST_ASSERT(p2_apc_interface_opened(A, AI), "an AI's click opens the window")

/// A cyborg using a module that means nothing to the APC opens the window instead of hitting it.
/datum/unit_test/dq_p2_apc/cyborg_module_opens_the_window

/datum/unit_test/dq_p2_apc/cyborg_module_opens_the_window/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/silicon/robot/R = p2_borg()
	var/obj/item/module = allocate(/obj/item/pen, run_loc_floor_bottom_left)
	test_click(R, A, module)
	p2_settle()
	TEST_ASSERT(p2_apc_interface_opened(A, R), "a module with no use here opens the window")
	TEST_ASSERT_EQUAL(A.get_integrity(), A.max_integrity, "and does not hit the APC")

// ---------------------------------------------------------------------------------------------------------------------
// Night shift (pinned before the night-shift system stopped calling every APC)
// ---------------------------------------------------------------------------------------------------------------------

/// On "automatic" an APC on a station level dims its area for the station's night; "never" keeps it bright; "always" dims it by day.
/datum/unit_test/dq_p2_apc/night_shift_follows_the_station_night_on_automatic

/datum/unit_test/dq_p2_apc/night_shift_follows_the_station_night_on_automatic/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/list/levels = using_map.station_levels.Copy()
	var/was_night = SSnightshift.nightshift_active
	if(!(A.z in using_map.station_levels))
		using_map.station_levels += A.z
	p2_apc_station_night(FALSE)
	p2_settle()
	TEST_ASSERT(!A.area.lights_nightshift, "by day the area is bright")
	p2_apc_station_night(TRUE)
	p2_settle()
	TEST_ASSERT(A.area.lights_nightshift, "at night an automatic APC dims its area")
	A.set_nightshift_setting(NIGHTSHIFT_NEVER)
	p2_settle()
	TEST_ASSERT(!A.area.lights_nightshift, "an APC set to never keeps it bright at night")
	A.set_nightshift_setting(NIGHTSHIFT_AUTO)
	p2_settle()
	TEST_ASSERT(A.area.lights_nightshift, "back on automatic it dims again")
	p2_apc_station_night(FALSE)
	p2_settle()
	TEST_ASSERT(!A.area.lights_nightshift, "the morning brightens it")
	A.set_nightshift_setting(NIGHTSHIFT_ALWAYS)
	p2_settle()
	TEST_ASSERT(A.area.lights_nightshift, "an APC set to always dims it by day")
	A.set_nightshift_setting(NIGHTSHIFT_AUTO)
	using_map.station_levels = levels
	p2_apc_station_night(was_night)
	p2_settle()
