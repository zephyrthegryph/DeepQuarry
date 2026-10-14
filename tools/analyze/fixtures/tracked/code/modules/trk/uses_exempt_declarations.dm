// Writes to vars declared tracked inside an exempt file are still counted here.
/obj/machinery/pump/proc/write_exempt_declared(obj/machinery/pump/P)
	exempt_declared = 1
	P.exempt_declared = 2

/obj/machinery/valve/proc/write_exempt_setter()
	exempt_setter = 1

/obj/gadget/proc/write_exempt_derived()
	exempt_derived = 1
