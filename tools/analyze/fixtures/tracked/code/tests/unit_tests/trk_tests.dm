// Exempt path: writes are not counted, but a declaration here still tracks the var everywhere.
TRACKED(/obj/machinery/pump, exempt_declared)
SETTER(/obj/machinery/valve, exempt_setter)

/obj/machinery/pump/proc/test_writes(obj/machinery/pump/P)
	target_pressure = 1
	P.open = 1
	exempt_declared = 2
	exempt_setter = 3

/obj/gadget/derived()
	. += derive(nameof(exempt_derived))

/obj/machinery/pump
	var/exempt_declared = 0
	var/exempt_derived = 0
