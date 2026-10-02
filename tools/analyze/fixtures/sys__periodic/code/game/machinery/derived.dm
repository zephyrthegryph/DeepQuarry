OM_DERIVE_FIELD(/obj/machinery/dv, farming, list("operable", "use_power"))
OM_DERIVE_FIELD(/obj/machinery/dv2, other, list(CHANGE_INTEGRITY))
OM_DERIVE_FIELD(/obj/machinery/dv3, third, list(CHANGE_EXPLICIT)) // trailing comment
OM_DERIVE_FIELD(/obj/machinery/dv4, fourth, list("alpha"))
  OM_DERIVE_FIELD(/obj/machinery/dv5, fifth, list("beta"))
OM_DERIVE_FIELD(/obj/machinery/dv, again, list("extra_input"))

/obj/machinery/dv/proc/refresh()
	changed(src, CHANGE_EXPLICIT)
	changed(src, CHANGE_MACHINE_STATE)
	use_power = 3
	changed(src, CHANGE_MACHINE_STATE)

/obj/machinery/dv/proc/refresh2()
	var/a = 1
	var/b = 2
	changed(src, CHANGE_MACHINE_STATE)

/obj/machinery/dv/proc/refresh3()
	extra_input = 4
	var/a = 1
	var/b = 2
	var/c = 3
	changed(src, CHANGE_MACHINE_STATE)

/obj/machinery/dv/proc/refresh4()
	var/a = 1
	var/b = 2
	changed(src, CHANGE_MACHINE_STATE)
	set_operable(TRUE)

/obj/machinery/dv/proc/refresh5()
	// operable = 3
	changed(src, CHANGE_MACHINE_STATE)
	x = 1 // use_power = 3

/obj/machinery/dv/subtype/proc/refresh6()
	operable_add(1)
	changed(src, CHANGE_MACHINE_STATE)

/obj/machinery/dv/subtype/proc/refresh7()
	set_use_power(1)
	changed(src, CHANGE_MACHINE_STATE)

/obj/machinery/dv2/proc/refresh8()
	changed(src, CHANGE_EXPLICIT)
	changed(src, CHANGE_X)

/obj/machinery/dv3/proc/refresh9()
	changed(src, CHANGE_EXPLICIT)
	changed(src, CHANGE_X)
	// changed(src, CHANGE_EXPLICIT)

/obj/machinery/dv3/proc/refresh10()
	// ALLOW(sys_derived_hand_raise): the external write must refresh by hand
	changed(src, CHANGE_EXPLICIT)

/obj/machinery/dv4/proc/refresh11()
	alpha = 3
	changed(src, CHANGE_X)

/obj/machinery/dv4/proc/refresh12()
	changed(src, CHANGE_X)
	beta = 3

/obj/machinery/dv5/proc/refresh13()
	beta = 3
	changed(src, CHANGE_X)

/obj/machinery/dv5/proc/refresh14()
	beta = 3
	changed(other, CHANGE_X)
	changed (src, CHANGE_Y)

/obj/machinery/dv4/refresh15()
	alpha += 3
	changed(src,CHANGE_X)

/obj/machinery/dv4/var/something = 3
	alpha = 4
	changed(src, CHANGE_EXPLICIT)

/obj/machinery/dvother/proc/refresh16()
	changed(src, CHANGE_EXPLICIT)

/obj/machinery/dv4/proc/refresh17()
	alpha = 3
	changed(src, CHANGE_X) // trailing comment
	changed(src, CHANGE_EXPLICIT) // flagged by code part

/proc/free_proc()
	changed(src, CHANGE_EXPLICIT)

/obj/machinery/dv4/verb/refresh18()
	alpha = 3
	changed(src, CHANGE_X)
