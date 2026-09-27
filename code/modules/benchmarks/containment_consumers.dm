// Identical fixtures on both sides of a containment-consumer migration.
// Keep this scenario independent of the observer implementation being measured.

/datum/benchmark/containment_consumers
	id = "containment_consumers"
	description = "Storage moves, nested aggregates, inventory reslots and indexed reads"

/datum/benchmark/containment_consumers/Run()
	var/iterations = max(100, min(10000, round(param("iterations", 1000))))
	var/reads = max(100, min(50000, round(param("reads", 10000))))
	var/rounds = max(1, min(10, round(param("rounds", 3))))
	var/turf/T = locate(1, 1, 1)
	if(!T)
		fail("no fixture turf")
	var/obj/item/storage/backpack/pack = new(T)
	var/obj/item/storage/box/first = new(T)
	var/obj/item/storage/box/second = new(T)
	if(!pack.insert_item(first) || !pack.insert_item(second))
		fail("could not build nested storage fixture")
	var/obj/item/pen/stored = new(T)
	if(!first.insert_item(stored))
		fail("could not seed storage item")
	var/mob/living/carbon/human/H = new(T)
	var/obj/item/tool/wrench/held = new(T)
	if(!H.equip_to_slot(held, slot_l_hand))
		fail("could not seed inventory item")
	var/storage_best = INFINITY
	var/storage_open_best = INFINITY
	var/inventory_best = INFINITY
	var/read_best = INFINITY
	for(var/round in 1 to rounds)
		stoplag()
		rustg_time_reset("containment_consumers")
		for(var/i in 1 to iterations)
			if(!second.insert_item(stored) || !first.insert_item(stored))
				fail("nested storage move refused")
		storage_best = min(storage_best, rustg_time_microseconds("containment_consumers") / (2 * iterations))
		if(stored.loc != first || first.slot_used() <= 0 || second.slot_used() != 0 || pack.contents_property(PROP_MASS) <= 0)
			fail("nested storage indexes or aggregates became stale")
		first.hud = new /datum/storage_hud(first)
		var/open_iterations = min(iterations, 200)
		stoplag()
		rustg_time_reset("containment_consumers")
		for(var/i in 1 to open_iterations)
			if(!second.insert_item(stored) || !first.insert_item(stored))
				fail("open nested storage move refused")
		storage_open_best = min(storage_open_best, rustg_time_microseconds("containment_consumers") / (2 * open_iterations))
		if(!(stored in first.hud.shown))
			fail("open storage HUD became stale")
		QDEL_NULL(first.hud)
		stoplag()
		rustg_time_reset("containment_consumers")
		for(var/i in 1 to iterations)
			if(!H.equip_to_slot(held, slot_r_hand) || !H.equip_to_slot(held, slot_l_hand))
				fail("hand reslot refused")
		inventory_best = min(inventory_best, rustg_time_microseconds("containment_consumers") / (2 * iterations))
		if(H.get_left_hand() != held || H.get_right_hand() || H.inventory_slot_id(held) != SLOT_ID_HAND_L)
			fail("inventory index became stale")
		stoplag()
		rustg_time_reset("containment_consumers")
		var/found = 0
		for(var/i in 1 to reads)
			found += first.slot_used() > 0
			found += H.get_left_hand() == held
			found += pack.contents_property(PROP_MASS) > 0
		read_best = min(read_best, rustg_time_microseconds("containment_consumers") / (3 * reads))
		if(found != 3 * reads)
			fail("an indexed read became stale")
	metric("storage_move_us", storage_best, "us/move")
	metric("storage_open_move_us", storage_open_best, "us/move")
	metric("inventory_reslot_us", inventory_best, "us/reslot")
	metric("indexed_read_us", read_best, "us/read")
	metric("moves_per_round", 2 * iterations, "moves", "none")
	metric("open_moves_per_round", 2 * min(iterations, 200), "moves", "none")
	metric("reads_per_round", 3 * reads, "reads", "none")
	qdel(H)
	qdel(pack)
