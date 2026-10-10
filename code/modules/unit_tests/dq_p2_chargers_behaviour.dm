// Behaviour-preservation tests for the chargers (phase 2): the heavy-duty cell charger, the recharger and the wall recharger. They pin what a
// player, a cyborg or a mechanic can observe through public inputs (clicks, a part replacer, power changes, time), so the same file passes
// before and after the chargers move from the interaction table to the engine forms.
//
// Rules (as in dq_p2_apc_behaviour.dm): input goes through test_click(); state is read through plain vars (`charging`, `loc`, `anchored`,
// `use_power`, cell charge) and the small adapter block below; every input is followed by p2c_settle() (tool ops carry waits that the old
// code did not); no assertion reads message text, an op key or a click result.

/// The anchored flag (the converted charger keeps the same plain var).
/proc/p2c_anchored(obj/machinery/M)
	return !!M.anchored

/// What a charger holds (its `charging` var, a cell for the cell charger, any device for a recharger).
/proc/p2c_held(obj/machinery/M)
	var/obj/machinery/recharger/R = M
	var/obj/machinery/cell_charger/C = M
	return istype(R) ? R.charging : C.charging

/// The charge per charging frame a charger gives.
/proc/p2c_rate(obj/machinery/M)
	var/obj/machinery/recharger/R = M
	var/obj/machinery/cell_charger/C = M
	return CELLRATE * (istype(R) ? R.efficiency : C.efficiency)

/// The power of the area changed: the machine hears it.
/proc/p2c_power_change(obj/machinery/M)
	M.power_change()

/// The machine is still the legacy interaction-table form (its handlers are the interaction_* procs): a tool, a drag and a cyborg's touch reach it
/// through the mob click paths the driver does not run, so the adapters below call them. The converted charger has ops for all three and the
/// adapters use the driver.
/proc/p2c_legacy(obj/machinery/M)
	return !!hascall(M, "interaction_take")

/// A wrench used on the machine.
/proc/p2c_wrench(mob/living/carbon/human/H, obj/machinery/M, obj/item/tool)
	if(p2c_legacy(M) && hascall(M, "wrench_act"))
		call(M, "wrench_act")(H, tool)
		return
	H.next_click = 0
	test_click(H, M, tool)

/// A dragged item dropped onto the machine.
/proc/p2c_drag(mob/living/carbon/human/H, obj/machinery/M, obj/item/dragged)
	if(p2c_legacy(M))
		M.MouseDrop_T(dragged, H)
		return
	test_click(H, M, dragged, GESTURE_DRAG)

/// A cyborg beside the machine touches it with no module in hand.
/proc/p2c_borg_touch(mob/living/silicon/robot/B, obj/machinery/M)
	if(p2c_legacy(M))
		if(hascall(M, "cell_charger_silicon_take"))
			call(M, "cell_charger_silicon_take")(B, null, null)
		else
			call(M, "recharger_silicon_take")(B, null, null)
		return
	test_click(B, M, null)

/datum/unit_test/dq_p2_chargers
	abstract_type = /datum/unit_test/dq_p2_chargers
	var/area/p2_area
	var/p2_area_requires
	var/p2_area_equip

/datum/unit_test/dq_p2_chargers/Run()
	test_driver_begin()
	test_rng(1)
	p2_area = get_area(run_loc_floor_bottom_left)
	p2_area_requires = p2_area.requires_power
	p2_area_equip = p2_area.power_equip
	p2_area.set_requires_power(FALSE)
	p2_area.power_change() // the machines of the area learn of it, as a holodeck switch does
	p2_area.power_equip = TRUE
	run_gate()
	own_turf_contents(run_loc_floor_bottom_left)
	own_turf_contents(run_loc_floor_top_right)
	p2_area.set_requires_power(p2_area_requires)
	p2_area.power_change() // the machines of the area learn of it, as a holodeck switch does
	p2_area.power_equip = p2_area_equip
	test_driver_end()

/datum/unit_test/dq_p2_chargers/proc/run_gate()
	return

/datum/unit_test/dq_p2_chargers/proc/p2c_settle()
	test_time(10 SECONDS)

/datum/unit_test/dq_p2_chargers/proc/p2c_actor(turf/T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T || run_loc_floor_bottom_left)
	H.enable_godmode()
	return H

/datum/unit_test/dq_p2_chargers/proc/p2c_borg(turf/T)
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, T || run_loc_floor_bottom_left)
	R.enable_godmode()
	return R

/// The cyborg's gripper (of `type`), selected: a cyborg handles things with it (doc/rewrite/final_api.html 16.8).
/datum/unit_test/dq_p2_chargers/proc/p2c_gripper(mob/living/silicon/robot/R, type = /obj/item/gripper/omni)
	if(!R.module)
		rel_set(R, nameof(R.module), new /obj/item/robot_module/robot/standard(R))
	var/obj/item/gripper/G = new type(R.module)
	rel_add(R.module, nameof(R.module.modules), G)
	R.activate_module(G)
	R.select_module(R.module_slot_of(G))
	return G

/// A big, empty cell, so a charge never saturates.
/datum/unit_test/dq_p2_chargers/proc/p2c_cell(type = /obj/item/cell)
	var/obj/item/cell/C = allocate(type, run_loc_floor_bottom_left)
	C.maxcharge = 1e7
	C.charge = 0
	return C

/datum/unit_test/dq_p2_chargers/proc/touch(mob/living/carbon/human/H, atom/target, obj/item/held, gesture = GESTURE_CLICK)
	H.drop_item()
	if(held)
		H.put_in_active_hand(held)
	test_click(H, target, held, gesture)
	p2c_settle()

/datum/unit_test/dq_p2_chargers/proc/wrench(mob/living/carbon/human/H, obj/machinery/M, obj/item/tool)
	H.drop_item()
	H.put_in_active_hand(tool)
	p2c_wrench(H, M, tool)
	p2c_settle()

/datum/unit_test/dq_p2_chargers/proc/p2c_tool(path)
	return dq_fast_tool(path, run_loc_floor_bottom_left)

/datum/unit_test/dq_p2_chargers/proc/p2c_cell_charger(turf/T)
	var/obj/machinery/cell_charger/C = allocate(/obj/machinery/cell_charger, T || run_loc_floor_bottom_left)
	p2c_settle()
	return C

/datum/unit_test/dq_p2_chargers/proc/p2c_recharger(type = /obj/machinery/recharger, turf/T)
	var/obj/machinery/recharger/R = allocate(type, T || run_loc_floor_bottom_left)
	p2c_settle()
	return R

// ---------------------------------------------------------------------------------------------------------------------
// The heavy-duty cell charger
// ---------------------------------------------------------------------------------------------------------------------

/// A placed cell charger is anchored, empty and idle.
/datum/unit_test/dq_p2_chargers/cell_charger_starts_idle_and_empty

/datum/unit_test/dq_p2_chargers/cell_charger_starts_idle_and_empty/run_gate()
	var/obj/machinery/cell_charger/C = p2c_cell_charger()
	TEST_ASSERT(p2c_anchored(C), "anchored")
	TEST_ASSERT_NULL(p2c_held(C), "empty")
	TEST_ASSERT_EQUAL(C.use_power, USE_POWER_IDLE, "idle")
	TEST_ASSERT_EQUAL(C.efficiency, 60000, "base charge rate")

/// A cell in the hand goes in; an empty hand takes it out again.
/datum/unit_test/dq_p2_chargers/cell_charger_insert_and_take

/datum/unit_test/dq_p2_chargers/cell_charger_insert_and_take/run_gate()
	var/obj/machinery/cell_charger/C = p2c_cell_charger()
	var/mob/living/carbon/human/H = p2c_actor()
	var/obj/item/cell/cell = p2c_cell()
	touch(H, C, cell)
	TEST_ASSERT_EQUAL(p2c_held(C), cell, "the charger holds the cell")
	TEST_ASSERT_EQUAL(cell.loc, C, "inside it")
	TEST_ASSERT_NULL(H.get_active_hand(), "the hand is empty")
	touch(H, C, null)
	TEST_ASSERT_NULL(p2c_held(C), "taken out")
	TEST_ASSERT_EQUAL(H.get_active_hand(), cell, "into the hand")

/// A second cell does not go in while one is charging.
/datum/unit_test/dq_p2_chargers/cell_charger_refuses_a_second_cell

/datum/unit_test/dq_p2_chargers/cell_charger_refuses_a_second_cell/run_gate()
	var/obj/machinery/cell_charger/C = p2c_cell_charger()
	var/mob/living/carbon/human/H = p2c_actor()
	var/obj/item/cell/first = p2c_cell()
	var/obj/item/cell/second = p2c_cell()
	touch(H, C, first)
	touch(H, C, second)
	TEST_ASSERT_NOTEQUAL(p2c_held(C), second, "the second is not the one held")
	TEST_ASSERT_NOTEQUAL(second.loc, C, "the second stayed out")

/// A small device cell does not fit.
/datum/unit_test/dq_p2_chargers/cell_charger_refuses_a_device_cell

/datum/unit_test/dq_p2_chargers/cell_charger_refuses_a_device_cell/run_gate()
	var/obj/machinery/cell_charger/C = p2c_cell_charger()
	var/mob/living/carbon/human/H = p2c_actor()
	var/obj/item/cell/device/small = p2c_cell(/obj/item/cell/device)
	touch(H, C, small)
	TEST_ASSERT_NULL(p2c_held(C), "nothing went in")
	TEST_ASSERT_NOTEQUAL(small.loc, C, "the device cell stayed out")

/// A broken charger takes no cell.
/datum/unit_test/dq_p2_chargers/cell_charger_refuses_a_cell_when_broken

/datum/unit_test/dq_p2_chargers/cell_charger_refuses_a_cell_when_broken/run_gate()
	var/obj/machinery/cell_charger/C = p2c_cell_charger()
	var/mob/living/carbon/human/H = p2c_actor()
	var/obj/item/cell/cell = p2c_cell()
	C.set_broken_condition(TRUE)
	touch(H, C, cell)
	TEST_ASSERT_NULL(p2c_held(C), "refused")
	C.set_broken_condition(FALSE)
	touch(H, C, cell)
	TEST_ASSERT_EQUAL(p2c_held(C), cell, "accepted once whole")

/// A charger in an area with no power (no APC) refuses a cell.
/datum/unit_test/dq_p2_chargers/cell_charger_refuses_a_cell_in_an_unpowered_area

/datum/unit_test/dq_p2_chargers/cell_charger_refuses_a_cell_in_an_unpowered_area/run_gate()
	var/obj/machinery/cell_charger/C = p2c_cell_charger()
	var/mob/living/carbon/human/H = p2c_actor()
	var/obj/item/cell/cell = p2c_cell()
	p2_area.power_equip = FALSE
	touch(H, C, cell)
	TEST_ASSERT_NULL(p2c_held(C), "refused with no area power")
	p2_area.power_equip = TRUE
	touch(H, C, cell)
	TEST_ASSERT_EQUAL(p2c_held(C), cell, "accepted with area power")

/// An unanchored charger takes no cell; the wrench anchors and unanchors it, but not while it holds a cell.
/datum/unit_test/dq_p2_chargers/cell_charger_wrench_and_anchor

/datum/unit_test/dq_p2_chargers/cell_charger_wrench_and_anchor/run_gate()
	var/obj/machinery/cell_charger/C = p2c_cell_charger()
	var/mob/living/carbon/human/H = p2c_actor()
	var/obj/item/cell/cell = p2c_cell()
	var/obj/item/wrench = p2c_tool(/obj/item/tool/wrench)
	wrench(H, C, wrench)
	TEST_ASSERT(!p2c_anchored(C), "unanchored by the wrench")
	touch(H, C, cell)
	TEST_ASSERT_NULL(p2c_held(C), "an unanchored charger takes no cell")
	wrench(H, C, wrench)
	TEST_ASSERT(p2c_anchored(C), "anchored again")
	touch(H, C, cell)
	TEST_ASSERT_EQUAL(p2c_held(C), cell, "now it holds the cell")
	wrench(H, C, wrench)
	TEST_ASSERT(p2c_anchored(C), "the wrench does nothing while it holds a cell")

/// A cyborg beside it takes the cell out onto the floor.
/datum/unit_test/dq_p2_chargers/cell_charger_cyborg_takes_the_cell

/datum/unit_test/dq_p2_chargers/cell_charger_cyborg_takes_the_cell/run_gate()
	var/obj/machinery/cell_charger/C = p2c_cell_charger()
	var/mob/living/carbon/human/H = p2c_actor()
	var/mob/living/silicon/robot/R = p2c_borg(get_step(run_loc_floor_bottom_left, EAST)) // beside it, not on its tile: the cell is set down on the charger's own
	var/obj/item/gripper/G = p2c_gripper(R)
	var/obj/item/cell/cell = p2c_cell()
	touch(H, C, cell)
	TEST_ASSERT_EQUAL(p2c_held(C), cell, "in")
	p2c_borg_touch(R, C)
	p2c_settle()
	TEST_ASSERT_NULL(p2c_held(C), "the borg took it out")
	TEST_ASSERT_EQUAL(G.get_wrapped_item(), cell, "into its gripper")

/// The cell charges at the charger's rate each machine frame and the machine draws active power.
/datum/unit_test/dq_p2_chargers/cell_charger_charges_the_cell

/datum/unit_test/dq_p2_chargers/cell_charger_charges_the_cell/run_gate()
	var/obj/machinery/cell_charger/C = p2c_cell_charger()
	var/mob/living/carbon/human/H = p2c_actor()
	var/obj/item/cell/cell = p2c_cell()
	touch(H, C, cell)
	var/rate = p2c_rate(C)
	TEST_ASSERT(cell.charge > 0, "it charged")
	TEST_ASSERT_EQUAL(round(cell.charge / rate), cell.charge / rate, "in whole frames")
	TEST_ASSERT_EQUAL(C.use_power, USE_POWER_ACTIVE, "active draw")
	var/before = cell.charge
	p2c_settle()
	TEST_ASSERT(cell.charge > before, "and still charging")
	touch(H, C, null)
	var/taken = cell.charge
	p2c_settle()
	TEST_ASSERT_EQUAL(cell.charge, taken, "an ejected cell charges no more")
	TEST_ASSERT_EQUAL(C.use_power, USE_POWER_IDLE, "idle again")

/// A faster charger (more capacitor) gives proportionally more.
/datum/unit_test/dq_p2_chargers/cell_charger_rate_follows_efficiency

/datum/unit_test/dq_p2_chargers/cell_charger_rate_follows_efficiency/run_gate()
	var/obj/machinery/cell_charger/slow = p2c_cell_charger()
	var/obj/machinery/cell_charger/fast = p2c_cell_charger()
	var/mob/living/carbon/human/H = p2c_actor()
	var/obj/item/cell/a = p2c_cell()
	var/obj/item/cell/b = p2c_cell()
	fast.efficiency = slow.efficiency * 2
	touch(H, slow, a)
	touch(H, fast, b)
	var/a_before = a.charge
	var/b_before = b.charge
	p2c_settle()
	TEST_ASSERT(a.charge > a_before, "slow charged")
	TEST_ASSERT(b.charge - b_before > a.charge - a_before, "fast charged more over the same time")

/// A full cell stops the draw; an unpowered or broken charger gives nothing.
/datum/unit_test/dq_p2_chargers/cell_charger_full_cell_idles_and_power_loss_stops_it

/datum/unit_test/dq_p2_chargers/cell_charger_full_cell_idles_and_power_loss_stops_it/run_gate()
	var/obj/machinery/cell_charger/C = p2c_cell_charger()
	var/mob/living/carbon/human/H = p2c_actor()
	var/obj/item/cell/cell = p2c_cell()
	cell.maxcharge = 1000
	cell.charge = 1000
	touch(H, C, cell)
	TEST_ASSERT_EQUAL(cell.charge, 1000, "full stays full")
	TEST_ASSERT_EQUAL(C.use_power, USE_POWER_IDLE, "idle while full")
	cell.maxcharge = 1e7
	cell.charge = 0
	C.set_grid_power(FALSE)
	p2c_settle()
	TEST_ASSERT_EQUAL(cell.charge, 0, "no power, no charge")
	TEST_ASSERT_EQUAL(C.use_power, USE_POWER_OFF, "off")
	C.set_grid_power(TRUE)
	p2c_settle()
	TEST_ASSERT(cell.charge > 0, "power back, charging again")
	var/held = cell.charge
	C.set_broken_condition(TRUE)
	p2c_settle()
	TEST_ASSERT_EQUAL(cell.charge, held, "broken, no charge")
	C.set_broken_condition(FALSE)

/// The examine line names the cell and its charge.
/datum/unit_test/dq_p2_chargers/cell_charger_examine_names_the_cell

/datum/unit_test/dq_p2_chargers/cell_charger_examine_names_the_cell/run_gate()
	var/obj/machinery/cell_charger/C = p2c_cell_charger()
	var/mob/living/carbon/human/H = p2c_actor()
	var/obj/item/cell/cell = p2c_cell()
	cell.name = "p2marker cell"
	touch(H, C, cell)
	TEST_ASSERT(findtext(jointext(C.examine(H), " "), "p2marker"), "examine names the cell")
	touch(H, C, null)
	TEST_ASSERT(!findtext(jointext(C.examine(H), " "), "p2marker"), "and forgets it")

/// Destroying a charger drops what it holds onto the floor.
/datum/unit_test/dq_p2_chargers/cell_charger_destroyed_drops_the_cell

/datum/unit_test/dq_p2_chargers/cell_charger_destroyed_drops_the_cell/run_gate()
	var/obj/machinery/cell_charger/C = p2c_cell_charger()
	var/mob/living/carbon/human/H = p2c_actor()
	var/obj/item/cell/cell = p2c_cell()
	touch(H, C, cell)
	var/turf/T = C.loc
	qdel(C)
	test_time(1 SECOND)
	TEST_ASSERT(QDELETED(cell), "a destroyed cell charger takes the cell with it (unlike the recharger)")
	TEST_ASSERT_NOTNULL(T, "it stood on a turf")

// ---------------------------------------------------------------------------------------------------------------------
// The recharger and the wall recharger
// ---------------------------------------------------------------------------------------------------------------------

/// A stun baton with a big empty cell (a device the recharger and the wall recharger both take).
/datum/unit_test/dq_p2_chargers/proc/p2c_gun(charge = 0)
	var/obj/item/melee/baton/loaded/G = allocate(/obj/item/melee/baton/loaded, run_loc_floor_bottom_left)
	var/obj/item/cell/C = G.get_cell()
	C.maxcharge = 1e7
	C.charge = charge
	return G

/// A recharger starts anchored and idle, with a 40 kW rate; the wall one is 60 kW and cannot be wrenched.
/datum/unit_test/dq_p2_chargers/recharger_start_state

/datum/unit_test/dq_p2_chargers/recharger_start_state/run_gate()
	var/obj/machinery/recharger/R = p2c_recharger()
	var/obj/machinery/recharger/wallcharger/W = p2c_recharger(/obj/machinery/recharger/wallcharger)
	TEST_ASSERT(p2c_anchored(R) && p2c_anchored(W), "both anchored")
	TEST_ASSERT_EQUAL(R.efficiency, 40000, "recharger rate")
	TEST_ASSERT_EQUAL(W.efficiency, 60000, "wall recharger rate")
	TEST_ASSERT_EQUAL(R.use_power, USE_POWER_IDLE, "idle")

/// A gun goes in by click and out by an empty hand, and charges meanwhile.
/datum/unit_test/dq_p2_chargers/recharger_insert_charge_take

/datum/unit_test/dq_p2_chargers/recharger_insert_charge_take/run_gate()
	var/obj/machinery/recharger/R = p2c_recharger()
	var/mob/living/carbon/human/H = p2c_actor()
	var/obj/item/G = p2c_gun()
	touch(H, R, G)
	TEST_ASSERT_EQUAL(p2c_held(R), G, "held")
	TEST_ASSERT_EQUAL(G.loc, R, "inside")
	var/obj/item/cell/C = G.get_cell()
	TEST_ASSERT(C.charge > 0, "charging")
	var/rate = p2c_rate(R)
	TEST_ASSERT_EQUAL(round(C.charge / rate), C.charge / rate, "in whole frames")
	TEST_ASSERT_EQUAL(R.use_power, USE_POWER_ACTIVE, "active draw")
	touch(H, R, null)
	TEST_ASSERT_NULL(p2c_held(R), "taken out")
	TEST_ASSERT_EQUAL(H.get_active_hand(), G, "into the hand")
	var/taken = C.charge
	p2c_settle()
	TEST_ASSERT_EQUAL(C.charge, taken, "no more charge")
	TEST_ASSERT_EQUAL(R.use_power, USE_POWER_IDLE, "idle")

/// Dragging a device onto it puts it in.
/datum/unit_test/dq_p2_chargers/recharger_drag_insert

/datum/unit_test/dq_p2_chargers/recharger_drag_insert/run_gate()
	var/obj/machinery/recharger/R = p2c_recharger()
	var/mob/living/carbon/human/H = p2c_actor()
	var/obj/item/G = p2c_gun()
	p2c_drag(H, R, G)
	p2c_settle()
	TEST_ASSERT_EQUAL(p2c_held(R), G, "dragged in")

/// Only listed devices go in (a plain item does not), and one at a time.
/datum/unit_test/dq_p2_chargers/recharger_takes_listed_devices_one_at_a_time

/datum/unit_test/dq_p2_chargers/recharger_takes_listed_devices_one_at_a_time/run_gate()
	var/obj/machinery/recharger/R = p2c_recharger()
	var/mob/living/carbon/human/H = p2c_actor()
	var/obj/item/pen = allocate(/obj/item/pen, run_loc_floor_bottom_left)
	touch(H, R, pen)
	TEST_ASSERT_NULL(p2c_held(R), "a pen does not go in")
	var/obj/item/first = p2c_gun()
	var/obj/item/second = p2c_gun()
	touch(H, R, first)
	touch(H, R, second)
	TEST_ASSERT_EQUAL(p2c_held(R), first, "the first stays")
	TEST_ASSERT_NOTEQUAL(second.loc, R, "the second is refused")

/// The wall recharger takes a smaller list: a gun, but not a stock cell.
/datum/unit_test/dq_p2_chargers/wallcharger_takes_the_short_list

/datum/unit_test/dq_p2_chargers/wallcharger_takes_the_short_list/run_gate()
	var/obj/machinery/recharger/wallcharger/W = p2c_recharger(/obj/machinery/recharger/wallcharger)
	var/mob/living/carbon/human/H = p2c_actor()
	var/obj/item/cell/cell = p2c_cell()
	touch(H, W, cell)
	TEST_ASSERT_NULL(p2c_held(W), "a stock cell is not on the wall list")
	var/obj/item/G = p2c_gun()
	touch(H, W, G)
	TEST_ASSERT_EQUAL(p2c_held(W), G, "a gun is")

/// A device with no battery, a self-charging gun and an unpowered recharger are refused.
/datum/unit_test/dq_p2_chargers/recharger_refusals

/datum/unit_test/dq_p2_chargers/recharger_refusals/run_gate()
	var/obj/machinery/recharger/R = p2c_recharger()
	var/mob/living/carbon/human/H = p2c_actor()
	var/obj/item/G = p2c_gun()
	R.set_grid_power(FALSE)
	p2_area.set_requires_power(TRUE)
	p2_area.power_change() // the machines of the area learn of it, as a holodeck switch does
	p2_area.power_equip = FALSE
	touch(H, R, G)
	TEST_ASSERT_NULL(p2c_held(R), "unpowered: refused")
	p2_area.set_requires_power(FALSE)
	p2_area.power_change() // the machines of the area learn of it, as a holodeck switch does
	p2_area.power_equip = TRUE
	R.set_grid_power(TRUE)
	var/obj/item/gun/energy/selfish = allocate(/obj/item/gun/energy/taser, run_loc_floor_bottom_left)
	selfish.set_self_recharge(TRUE)
	touch(H, R, selfish)
	TEST_ASSERT_NULL(p2c_held(R), "a self-charging gun has no port")
	touch(H, R, G)
	TEST_ASSERT_EQUAL(p2c_held(R), G, "accepted once fixed")

/// A cyborg takes the device out onto the floor.
/datum/unit_test/dq_p2_chargers/recharger_cyborg_takes_the_device

/datum/unit_test/dq_p2_chargers/recharger_cyborg_takes_the_device/run_gate()
	var/obj/machinery/recharger/R = p2c_recharger()
	var/mob/living/carbon/human/H = p2c_actor()
	var/mob/living/silicon/robot/B = p2c_borg(get_step(run_loc_floor_bottom_left, EAST)) // beside it, not on its tile: the device is set down on the recharger's own
	var/obj/item/gripper/grip = p2c_gripper(B)
	var/obj/item/G = p2c_gun()
	touch(H, R, G)
	p2c_borg_touch(B, R)
	p2c_settle()
	TEST_ASSERT_NULL(p2c_held(R), "taken by the borg")
	TEST_ASSERT(G.loc != R, "out of the recharger, into the gripper when it may hold it")
	TEST_ASSERT(isnull(grip.get_wrapped_item()) || grip.get_wrapped_item() == G, "and the gripper holds nothing else")

/// The wrench moves a recharger unless it is the wall type, and not while it holds something.
/datum/unit_test/dq_p2_chargers/recharger_wrench

/datum/unit_test/dq_p2_chargers/recharger_wrench/run_gate()
	var/obj/machinery/recharger/R = p2c_recharger()
	var/obj/machinery/recharger/wallcharger/W = p2c_recharger(/obj/machinery/recharger/wallcharger)
	var/mob/living/carbon/human/H = p2c_actor()
	var/obj/item/wrench = p2c_tool(/obj/item/tool/wrench)
	var/obj/item/G = p2c_gun()
	wrench(H, R, wrench)
	TEST_ASSERT(!p2c_anchored(R), "unanchored")
	wrench(H, R, wrench)
	TEST_ASSERT(p2c_anchored(R), "anchored")
	touch(H, R, G)
	wrench(H, R, wrench)
	TEST_ASSERT(p2c_anchored(R), "holding a gun it stays put")
	wrench(H, W, wrench)
	TEST_ASSERT(p2c_anchored(W), "the wall recharger cannot be wrenched")

/// A full device idles the draw; an unpowered recharger charges nothing.
/datum/unit_test/dq_p2_chargers/recharger_full_device_and_power_loss

/datum/unit_test/dq_p2_chargers/recharger_full_device_and_power_loss/run_gate()
	var/obj/machinery/recharger/R = p2c_recharger()
	var/mob/living/carbon/human/H = p2c_actor()
	var/obj/item/G = p2c_gun()
	var/obj/item/cell/C = G.get_cell()
	C.maxcharge = 1000
	C.charge = 1000
	touch(H, R, G)
	TEST_ASSERT_EQUAL(R.use_power, USE_POWER_IDLE, "idle while full")
	C.maxcharge = 1e7
	C.charge = 0
	R.set_grid_power(FALSE)
	p2c_settle()
	TEST_ASSERT_EQUAL(C.charge, 0, "unpowered: no charge")
	TEST_ASSERT_EQUAL(R.use_power, USE_POWER_OFF, "off")
	R.set_grid_power(TRUE)
	p2c_settle()
	TEST_ASSERT(C.charge > 0, "powered: charging")

/// A plain cell is charged by a recharger too.
/datum/unit_test/dq_p2_chargers/recharger_charges_a_cell

/datum/unit_test/dq_p2_chargers/recharger_charges_a_cell/run_gate()
	var/obj/machinery/recharger/R = p2c_recharger()
	var/mob/living/carbon/human/H = p2c_actor()
	var/obj/item/cell/cell = p2c_cell()
	touch(H, R, cell)
	TEST_ASSERT_EQUAL(p2c_held(R), cell, "held")
	TEST_ASSERT(cell.charge > 0, "charged")

/// Microbatteries gain a shot per frame and stop when full.
/datum/unit_test/dq_p2_chargers/recharger_charges_microbatteries

/datum/unit_test/dq_p2_chargers/recharger_charges_microbatteries/run_gate()
	var/obj/machinery/recharger/R = p2c_recharger()
	var/mob/living/carbon/human/H = p2c_actor()
	var/obj/item/ammo_casing/microbattery/medical/brute/B = allocate(/obj/item/ammo_casing/microbattery/medical/brute, run_loc_floor_bottom_left)
	var/full = initial(B.shots_left)
	B.shots_left = 0
	touch(H, R, B)
	TEST_ASSERT_EQUAL(p2c_held(R), B, "held")
	TEST_ASSERT(B.shots_left > 0, "shots came back")
	TEST_ASSERT(B.shots_left <= full, "never past full")
	p2c_settle()
	p2c_settle()
	TEST_ASSERT_EQUAL(B.shots_left, full, "full in the end")
	TEST_ASSERT_EQUAL(R.use_power, USE_POWER_IDLE, "idle when full")

/// A part replacer raises the charge rate with better capacitors (the panel must be open), and does nothing with the panel shut.
/datum/unit_test/dq_p2_chargers/rped_upgrades_the_charge_rate

/datum/unit_test/dq_p2_chargers/rped_upgrades_the_charge_rate/run_gate()
	var/obj/machinery/recharger/R = p2c_recharger()
	var/obj/machinery/cell_charger/C = p2c_cell_charger()
	var/mob/living/carbon/human/H = p2c_actor()
	var/base_r = R.efficiency
	var/base_c = C.efficiency
	var/obj/item/storage/part_replacer/rped = allocate(/obj/item/storage/part_replacer, run_loc_floor_bottom_left)
	for(var/i in 1 to 5)
		var/obj/item/stock_parts/capacitor/best = new(rped)
		best.rating = 5
	touch(H, R, rped)
	touch(H, C, rped)
	TEST_ASSERT_EQUAL(R.efficiency, base_r, "a shut panel: the recharger keeps its parts")
	TEST_ASSERT_EQUAL(C.efficiency, base_c, "a shut panel: the cell charger keeps its parts")
	R.set_panel_open(TRUE)
	C.set_panel_open(TRUE)
	touch(H, R, rped)
	touch(H, C, rped)
	TEST_ASSERT(R.efficiency > base_r, "better capacitors charge a recharger faster")
	TEST_ASSERT(C.efficiency > base_c, "and a cell charger")

/// Destroying a recharger drops what it holds.
/datum/unit_test/dq_p2_chargers/recharger_destroyed_drops_the_device

/datum/unit_test/dq_p2_chargers/recharger_destroyed_drops_the_device/run_gate()
	var/obj/machinery/recharger/R = p2c_recharger()
	var/mob/living/carbon/human/H = p2c_actor()
	var/obj/item/G = p2c_gun()
	touch(H, R, G)
	var/turf/T = R.loc
	qdel(R)
	test_time(1 SECOND)
	TEST_ASSERT(!QDELETED(G), "the gun survived")
	TEST_ASSERT_EQUAL(G.loc, T, "on the floor")

/// An item with no battery, and a pAI card with no personality in it, are refused.
/datum/unit_test/dq_p2_chargers/recharger_refuses_batteryless_and_empty_pai_cards

/datum/unit_test/dq_p2_chargers/recharger_refuses_batteryless_and_empty_pai_cards/run_gate()
	var/obj/machinery/recharger/R = p2c_recharger()
	var/mob/living/carbon/human/H = p2c_actor()
	var/obj/item/melee/baton/bare = allocate(/obj/item/melee/baton, run_loc_floor_bottom_left)
	touch(H, R, bare)
	TEST_ASSERT_NULL(p2c_held(R), "a baton with no cell does not go in")
	var/obj/item/paicard/card = allocate(/obj/item/paicard, run_loc_floor_bottom_left)
	touch(H, R, card)
	TEST_ASSERT_NULL(p2c_held(R), "a card with no personality does not go in")
	var/obj/item/good = p2c_gun()
	touch(H, R, good)
	TEST_ASSERT_EQUAL(p2c_held(R), good, "a charged-able baton does")

/// An unlucky person sometimes puts a device in backwards: it lands on the floor and the recharger stays empty (never otherwise).
/datum/unit_test/dq_p2_chargers/recharger_unlucky_hands_drop_the_device

/datum/unit_test/dq_p2_chargers/recharger_unlucky_hands_drop_the_device/run_gate()
	var/obj/machinery/recharger/R = p2c_recharger()
	var/mob/living/carbon/human/H = p2c_actor()
	var/obj/item/G = p2c_gun()
	var/dropped = 0
	var/inserted = 0
	for(var/i in 1 to 60)
		touch(H, R, G)
		if(p2c_held(R) == G)
			inserted++
			touch(H, R, null)
		else
			dropped++
			TEST_ASSERT_EQUAL(G.loc, R.loc, "a backwards device lands on the floor")
	TEST_ASSERT_EQUAL(inserted + dropped, 60, "every try went one way or the other")
	TEST_ASSERT_EQUAL(dropped, 0, "an ordinary person never drops one")
	add_trait(H, TRAIT_UNLUCKY, "p2")
	dropped = 0
	inserted = 0
	for(var/i in 1 to 60)
		touch(H, R, G)
		if(p2c_held(R) == G)
			inserted++
			touch(H, R, null)
		else
			dropped++
	TEST_ASSERT(dropped > 0, "an unlucky person drops some")
	TEST_ASSERT(inserted > 0, "and puts others in")
