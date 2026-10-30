/// Code (OBJECTS) in here gets used by the unit tests, but also regular code to test specific things.
/// But because unit_tests are rather late in the loading order, we have to put objects that get shared in here.
/// Else OpenDream gets very angry.

// Used to test distillations without hacking the other machinery's code up
/obj/distilling_tester
	icon = 'icons/obj/weapons.dmi'
	icon_state = "cartridge"
	var/datum/gas_mixture/GM = new()
	var/current_temp = 0

CAPABILITIES(/obj/distilling_tester)
	reagents(5000, holder = /datum/reagents/distilling)
	owns_one(nameof(GM), /datum/gas_mixture)


/obj/distilling_tester/return_air()
	return GM

/// A tester takes no heat from a transformation: the test reads the reagents, not the room.
/obj/distilling_tester/xform_air_sink()
	return null

/// Tests set the temperature directly.
/obj/distilling_tester/get_temperature()
	return current_temp

/obj/distilling_tester/proc/test_distilling(datum/xform/D, temp_prog)
	QDEL_SWAP(GM,new())
	var/list/ambient = xform_cond_ambient(D.holds)
	var/require_gas = ambient[1]
	var/rejects_gas = ambient[2]
	var/minimum_pressure = ambient[3]
	if(require_gas)
		GM.adjust_gas(require_gas, 100) // XGM .gas[id] assign → LINDA adjust
	else
		if(rejects_gas == GAS_N2)
			GM.adjust_gas(GAS_O2, (100) - LINDA_GAS_AMT(GM, GAS_O2))
		else
			GM.adjust_gas(GAS_N2, (100) - LINDA_GAS_AMT(GM, GAS_N2))
	if(minimum_pressure)
		heat_set(GM, (minimum_pressure * CELL_VOLUME) / (LINDA_GAS_AMT(GM, require_gas) * R_IDEAL_GAS_EQUATION)) // XGM .gas[id] → LINDA

	// Try this 10 times, We need to know if something is blocking at multiple temps.
	// If it passes unit test, it might still be awful to make though, gotta find the right gas mix!
	var/list/window = D.bands[1]
	current_temp = LERP(window[1], window[2], temp_prog)
	reagents.handle_reactions()

