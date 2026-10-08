// The draw sweep, items: a cell's charge is tracked, and what draws from it (the cell, the energy gun holding it, a magazine's rounds, a
// robot module's recharge) redraws by itself. Each test moves the state a look reads and checks the look, with no update_icon() call.

/datum/unit_test/dq_draw_items_cell_charge_redraws_cell

/datum/unit_test/dq_draw_items_cell_charge_redraws_cell/Run()
	var/turf/T = test_floor()
	var/obj/item/cell/C = allocate(/obj/item/cell, T)
	refresh_flush()
	TEST_ASSERT(("[initial(C.icon_state)]_100" in C.rx?.look_overlays), "a full cell draws its full level: [json_encode(C.rx?.look_overlays)]")
	var/before = C.rx?.look_key
	C.use(C.charge)
	refresh_flush()
	TEST_ASSERT(C.rx?.look_key != before, "draining the cell redraws it without an update_icon() call")
	TEST_ASSERT(("[initial(C.icon_state)]_0" in C.rx?.look_overlays), "and shows the empty level: [json_encode(C.rx?.look_overlays)]")
	before = C.rx?.look_key
	C.give(C.maxcharge)
	refresh_flush()
	TEST_ASSERT(C.rx?.look_key != before, "charging it redraws it again")

/datum/unit_test/dq_draw_items_cell_charge_redraws_the_gun

/datum/unit_test/dq_draw_items_cell_charge_redraws_the_gun/Run()
	var/turf/T = test_floor()
	var/obj/item/gun/energy/taser/G = allocate(/obj/item/gun/energy/taser, T)
	refresh_flush()
	var/full_state = G.icon_state
	var/before = G.rx?.look_key
	G.power_supply.use(G.power_supply.charge)
	refresh_flush()
	TEST_ASSERT(G.rx?.look_key != before, "draining the gun's cell redraws the gun without an update_icon() call")
	TEST_ASSERT(G.icon_state != full_state, "the charge meter state follows: [full_state] -> [G.icon_state]")

/datum/unit_test/dq_draw_items_firing_redraws_the_gun

/datum/unit_test/dq_draw_items_firing_redraws_the_gun/Run()
	var/turf/T = test_floor()
	var/obj/item/gun/energy/taser/G = allocate(/obj/item/gun/energy/taser, T)
	refresh_flush()
	G.power_supply.set_charge(G.charge_cost)
	refresh_flush()
	var/before = G.rx?.look_key
	var/obj/item/projectile/shot = G.consume_next_projectile()
	qdel(shot)
	refresh_flush()
	TEST_ASSERT(G.power_supply.charge < G.charge_cost, "the shot spent the charge")
	TEST_ASSERT(G.rx?.look_key != before, "a shot redraws the gun's charge meter")

/datum/unit_test/dq_draw_items_firing_redraws_the_ammo_count

/datum/unit_test/dq_draw_items_firing_redraws_the_ammo_count/Run()
	var/turf/T = test_floor()
	var/obj/item/ammo_magazine/m9mm/M = allocate(/obj/item/ammo_magazine/m9mm, T)
	refresh_flush()
	var/before = M.rx?.look_key
	var/obj/item/ammo_casing/round = M.stored_ammo[1]
	own_remove(M, nameof(M.stored_ammo), round)
	refresh_flush()
	TEST_ASSERT(M.rx?.look_key != before, "a magazine that lost a round redraws without an update_icon() call")
	qdel(round)

/datum/unit_test/dq_draw_items_swapping_cells_redraws_the_gun

/datum/unit_test/dq_draw_items_swapping_cells_redraws_the_gun/Run()
	var/turf/T = test_floor()
	var/obj/item/gun/energy/taser/G = allocate(/obj/item/gun/energy/taser, T)
	var/obj/item/cell/device/empty/E = allocate(/obj/item/cell/device/empty, T)
	refresh_flush()
	var/full_state = G.icon_state
	var/obj/item/cell/old = G.power_supply
	rel_clear(G, nameof(G.power_supply))
	refresh_flush()
	TEST_ASSERT(G.icon_state != full_state, "a gun with no cell shows its open state: [G.icon_state]")
	var/open_state = G.icon_state
	rel_set(G, nameof(G.power_supply), E)
	refresh_flush()
	TEST_ASSERT(G.icon_state != open_state, "an empty cell put in redraws the gun: [G.icon_state]")
	var/empty_state = G.icon_state
	rel_set(G, nameof(G.power_supply), old)
	refresh_flush()
	TEST_ASSERT(G.icon_state != empty_state, "swapping the charged cell back redraws it again: [G.icon_state]")
	TEST_ASSERT_EQUAL(G.icon_state, full_state, "and the gun looks as it did")

/datum/unit_test/dq_draw_items_thinktank_recharge_redraws_the_gun

/datum/unit_test/dq_draw_items_thinktank_recharge_redraws_the_gun/Run()
	var/turf/T = test_floor()
	var/obj/item/robot_module/robot/platform/explorer/module = allocate(/obj/item/robot_module/robot/platform/explorer, T)
	var/obj/item/gun/energy/robotic/phasegun/pew
	for(var/obj/item/gun/energy/robotic/phasegun/found in module.modules)
		pew = found
	if(!pew)
		pew = allocate(/obj/item/gun/energy/robotic/phasegun, T)
		rel_add(module, nameof(module.modules), pew)
	pew.power_supply.set_charge(0)
	refresh_flush()
	var/before = pew.rx?.look_key
	module.respawn_consumable(null, 1)
	refresh_flush()
	TEST_ASSERT(pew.power_supply.charge > 0, "the module recharged the gun's cell")
	TEST_ASSERT(pew.rx?.look_key != before, "the recharge redraws the gun without an update_icon() call")
