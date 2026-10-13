// Doors and power: a player walks into a powered airlock and through it; cutting the area's power at its APC stops the door, and
// restoring it brings the door back.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// A walkable floor next to `T` (cardinal), in the same area: no dense thing on it.
/proc/dq_gameplay_free_floor_beside(turf/T)
	for(var/dir in GLOB.cardinal)
		var/turf/simulated/floor/F = get_step(T, dir)
		if(!istype(F) || F.density || get_area(F) != get_area(T))
			continue
		var/blocked = FALSE
		for(var/atom/movable/AM in F)
			if(AM.density)
				blocked = TRUE
				break
		if(!blocked)
			return F
	return null

/// Walks into a powered airlock: it opens, and the player walks through it.
/datum/unit_test/dq_gameplay/walk_through_door

/datum/unit_test/dq_gameplay/walk_through_door/play()
	// Context-take telemetry is cumulative, not an outstanding context lease.
	set_global(nameof(GLOB.act_taken), GLOB.act_taken)
	var/obj/machinery/door/airlock/D = allocate(/obj/machinery/door/airlock, tile(2, 2))
	p2_door_set_autoclose(D, FALSE)
	var/mob/living/carbon/human/H = spawn_player(tile(2, 0))
	TEST_ASSERT(D.density, "the door starts shut")
	TEST_ASSERT(!D.power_lost(), "the door has power: [dq_power_door_state(D)]")
	TEST_ASSERT(stride(H, NORTH), "the player walks up to the door")
	stride(H, NORTH) // into the door: the bump opens it
	pass_time(2)
	TEST_ASSERT(!D.density, "walking into the powered door opened it")
	TEST_ASSERT(stride(H, NORTH), "the player steps into the doorway")
	TEST_ASSERT(stride(H, NORTH), "and through it")
	TEST_ASSERT_EQUAL(H.loc, tile(2, 3), "the player is on the far side")

/// The APC's breaker off: the area's door has no power and stays shut; the breaker on: it opens again.
/datum/unit_test/dq_gameplay/power_cut_stops_doors
	var/obj/machinery/power/apc/apc

/datum/unit_test/dq_gameplay/power_cut_stops_doors/play()
	apc = dq_power_test_apc()
	TEST_ASSERT_NOTNULL(apc, "the test map has a working APC")
	var/turf/door_turf = get_turf(apc)
	var/turf/stand = dq_gameplay_free_floor_beside(door_turf)
	TEST_ASSERT_NOTNULL(stand, "a free floor beside the APC")
	defer_cleanup(src, PROC_REF(restore_apc), apc.operating, lock_locked(apc, null))
	var/obj/machinery/door/airlock/D = allocate(/obj/machinery/door/airlock, door_turf)
	p2_door_set_autoclose(D, FALSE)
	var/mob/living/carbon/human/H = spawn_player(stand, SSaccess.get_all_station_access())
	var/dir_to_door = get_dir(stand, door_turf)
	pass_time(3, power = TRUE)
	TEST_ASSERT(!D.power_lost(), "the door in the APC's area has power: [dq_power_door_state(D)]")
	// Powered: the door opens for the player and shuts on a click.
	stride(H, dir_to_door)
	pass_time(2)
	TEST_ASSERT(!D.density, "the powered door opens when walked into: [dq_power_door_state(D)]")
	click(H, D, wait = 3)
	TEST_ASSERT(D.density, "a click shuts it again")
	// The player opens the APC's lock with their ID and throws the breaker.
	if(lock_locked(apc, null))
		click(H, hud_slot(H, SLOT_ID_ID)) // an empty hand on the ID slot takes the card out
		TEST_ASSERT(istype(H.get_active_hand(), /obj/item/card/id), "the player took their ID in hand from the HUD slot")
		click(H, apc)
		key_equip(H)
	TEST_ASSERT(!lock_locked(apc, null), "the ID swipe unlocked the APC")
	var/datum/op_result/off = press(H, apc, "breaker")
	TEST_ASSERT(test_op_committed(off), "the breaker button works ([off?.outcome])")
	pass_time(3, power = TRUE)
	TEST_ASSERT(!apc.operating, "the breaker is off")
	TEST_ASSERT(D.power_lost(), "with the breaker off the door has no power: [dq_power_door_state(D)]")
	stride(H, dir_to_door)
	pass_time(2)
	TEST_ASSERT(D.density, "the unpowered door stays shut when walked into")
	// Breaker back on: the door works again.
	press(H, apc, "breaker")
	pass_time(3, power = TRUE)
	TEST_ASSERT(apc.operating, "the breaker is on again")
	TEST_ASSERT(!D.power_lost(), "power is back at the door: [dq_power_door_state(D)]")
	click(H, D, wait = 3) // a click: the bump just refused counts toward the door's bump cooldown, which reads world.time (frozen on the test clock)
	TEST_ASSERT(!D.density, "the door opens again once the power is back")

/// Puts the mapped APC back as the scenario found it.
/datum/unit_test/dq_gameplay/power_cut_stops_doors/proc/restore_apc(was_operating, was_locked)
	if(QDELETED(apc))
		return
	if(apc.operating != was_operating)
		apc.set_operating(was_operating)
	key_set(apc, LOCK_LOCKED, was_locked)
	for(var/i in 1 to 3)
		dq_power_test_step()
	refresh_flush()

#endif
