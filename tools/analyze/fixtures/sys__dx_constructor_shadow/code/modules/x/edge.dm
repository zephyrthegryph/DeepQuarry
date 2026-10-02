/obj/item/thing/proc/bundle_one()
	return
/obj/item/thing/proc/bundle_two()  // ALLOW(sys_dx_constructor_shadow): fixture
	return
// ALLOW(sys_dx_constructor_shadow): above
/obj/item/thing/proc/cap_lock()
	return
/mob/living/proc/power_channels()
	return
/datum/foo/proc/cap_lock()
	return
/turf/simulated/cap_has(x)
	return
/area/proc/wall_console()
	return
/obj/machinery/proc/helper_only()
	return
// /obj/item/thing/proc/cap_lock()
/obj/item/multi/proc/cap_lock(a,
		b)
	return
/obj/item/verbed/verb/cap_lock()
	set name = "x"
/obj/item/ret/proc/cap_has() as /obj/item
	return
/obj/item/three/proc/bundle_three()
	return
/obj/item/cm/proc/commented_only()
	return
/obj/item/cm/proc/cap_multi()
	return
/client/proc/cap_lock()
	return
/obj/item/oldstyle
	proc/cap_has()
		return
/obj/item/var_line/var/cap_lock
